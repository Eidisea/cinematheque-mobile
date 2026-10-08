// Booking emails, sent ONLY from this server through Gmail SMTP (GMAIL_USER +
// GMAIL_APP_PASSWORD in Vercel's environment variables — never in an app or in Git).
//
// One email per booking state, to the primary booker (seat 1):
//   pending   → "Reservation received" (free) / "Complete your payment" (paid)
//   confirmed → the e-ticket
//   cancelled → why, and (paid) that refunds are handled by Cinematheque
//
// sendStatusEmail() looks at the booking's CURRENT status and sends that state's email
// once. Before sending it claims reservations/{id}.emails.<state> in a transaction, so a
// webhook + refresh + cron arriving together still send one email, and an old state's
// email is never sent after the booking has moved on (no conflicting emails).

import { createHash } from 'node:crypto';

import { Timestamp } from 'firebase-admin/firestore';
import nodemailer from 'nodemailer';

import { upcomingBookingsFor } from './reservations.js';

export function createMailer({ user, pass, transport }) {
  const t =
    transport ??
    nodemailer.createTransport({
      service: 'gmail',
      auth: { user, pass },
      connectionTimeout: 8_000,
      greetingTimeout: 8_000,
      socketTimeout: 10_000,
    });
  return {
    send: ({ to, subject, html, text }) =>
      t.sendMail({ from: { name: 'Cinematheque Centre Davao', address: user }, to, subject, html, text }),
    /** Signs in to Gmail without sending anything (health check). */
    verify: () => t.verify(),
  };
}

/** The real mailer, or null when Gmail is not configured (local work, tests). */
export function getMailer() {
  const user = process.env.GMAIL_USER?.trim();
  const pass = process.env.GMAIL_APP_PASSWORD?.replace(/\s+/g, ''); // Google shows it in groups of 4
  return user && pass ? createMailer({ user, pass }) : null;
}

// ── Formatting (Manila time, pesos) ──────────────────────────────────────────

const TZ = 'Asia/Manila';
const fmt = (opts) => new Intl.DateTimeFormat('en-US', { timeZone: TZ, ...opts });
const toDate = (t) => (t?.toDate ? t.toDate() : t);
export const formatDateLong = (t) => fmt({ weekday: 'long', month: 'long', day: 'numeric', year: 'numeric' }).format(toDate(t));
export const formatTime = (t) => fmt({ hour: 'numeric', minute: '2-digit' }).format(toDate(t));
export const formatPeso = (centavos) =>
  `₱${(centavos / 100).toLocaleString('en-PH', { minimumFractionDigits: centavos % 100 ? 2 : 0, maximumFractionDigits: 2 })}`;

const esc = (s) =>
  String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]);
const fullName = (p) => [p.firstName, p.middleName, p.lastName].filter(Boolean).join(' ');

// ── Templates ────────────────────────────────────────────────────────────────
// One calm layout for every email: the Cinematheque wordmark on the page, then a single
// white card (status pill, heading, message, details, seats), then a quiet footer.
// Tables + inline styles, because email clients ignore most CSS.

const METHOD_NAMES = { card: 'Card', gcash: 'GCash', paymaya: 'Maya', grab_pay: 'GrabPay', qrph: 'QR Ph' };
const formatDateShort = (t) => fmt({ weekday: 'short', month: 'short', day: 'numeric', year: 'numeric' }).format(toDate(t));
const formatPaidAt = (t) => `${fmt({ month: 'short', day: 'numeric', year: 'numeric' }).format(toDate(t))}, ${formatTime(t)}`;
const pesos2 = (centavos) =>
  `₱${(centavos / 100).toLocaleString('en-PH', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;

const INK = '#141219';
const MUTED = '#6b6674';
const LINE = '#ece9e4';
const FONT = "Helvetica,Arial,sans-serif";

const TONES = {
  pending: { bg: '#fdf1e3', fg: '#8a4b0f' },
  confirmed: { bg: '#e6f2ec', fg: '#1f6f50' },
  cancelled: { bg: '#f3f1ee', fg: '#6b6674' },
};

const CANCEL_REASONS = {
  customer_cancelled: 'you cancelled it',
  payment_expired: 'payment was not completed within 15 minutes',
  staff_cancelled: 'Cinematheque Centre Davao cancelled it',
};

const APP_NOTE =
  'To see this booking any time, open the Cinematheque app → Find my booking and enter your booking reference.';

/** Label → value rows shared by the booking emails (only data the system already stores). */
function details(r, payment) {
  const s = r.screening;
  const rows = [
    ['Screening', s.eventTitle],
    ['Date', formatDateLong(s.startAt)],
    ['Time', `${formatTime(s.startAt)} – ${formatTime(s.endAt)}`],
    ['Venue', 'Cinematheque Centre Davao, Palma Gil St.'],
    ['Booked by', fullName(r.booker)],
  ];
  if (payment) {
    const method = payment.method ? ` via ${METHOD_NAMES[payment.method] ?? payment.method}` : '';
    const when = payment.paidAt ? `, ${formatPaidAt(payment.paidAt)}` : '';
    rows.push(['Amount', pesos2(payment.amountCentavos)]);
    rows.push(['Payment', payment.status === 'verified' ? `Paid${method}${when}` : 'Not yet paid']);
  } else {
    rows.push(['Admission', 'Free']);
  }
  return rows;
}

const pill = (label, tone) =>
  `<span style="display:inline-block;padding:4px 10px;border-radius:999px;background:${tone.bg};color:${tone.fg};font-size:12px;font-weight:bold;letter-spacing:.3px;">${esc(label)}</span>`;

const para = (html, extra = '') => `<p style="margin:0 0 16px;font-size:15px;line-height:1.6;color:${INK};${extra}">${html}</p>`;

function detailsHtml(r, payment) {
  const rows = details(r, payment)
    .map(
      ([k, v]) => `<tr>
        <td style="padding:7px 0;width:120px;vertical-align:top;font-size:13px;color:${MUTED};">${esc(k)}</td>
        <td style="padding:7px 0;vertical-align:top;font-size:14px;color:${INK};">${esc(v)}</td>
      </tr>`,
    )
    .join('');
  const seats = r.seats
    .map(
      (x) => `<tr>
        <td style="padding:7px 0;width:56px;vertical-align:top;font-size:14px;font-weight:bold;color:${INK};font-family:'Courier New',monospace;">${esc(x.label)}</td>
        <td style="padding:7px 0;vertical-align:top;font-size:14px;color:${INK};">${esc(fullName(x.attendee))}${x.isBooker ? ` <span style="font-size:12px;color:${MUTED};">· booker</span>` : ''}</td>
      </tr>`,
    )
    .join('');
  return `<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="margin:8px 0 0;border-top:1px solid ${LINE};">
  <tr><td style="padding:16px 0 4px;">
    <table role="presentation" width="100%" cellpadding="0" cellspacing="0">${rows}</table>
  </td></tr>
  <tr><td style="padding:12px 0 4px;border-top:1px solid ${LINE};">
    <div style="font-size:11px;letter-spacing:1.5px;color:${MUTED};font-weight:bold;margin:4px 0 2px;">SEATS (${r.seats.length})</div>
    <table role="presentation" width="100%" cellpadding="0" cellspacing="0">${seats}</table>
  </td></tr>
</table>`;
}

/** The e-ticket stub: reference large, ADMIT n, the screening — with a dashed tear line. */
function stubHtml(r) {
  const s = r.screening;
  return `<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="margin:4px 0 22px;background:#fff7e1;border-radius:12px;">
  <tr><td style="padding:18px 20px 14px;">
    <div style="font-size:11px;letter-spacing:2px;color:#8a5a00;font-weight:bold;">E-TICKET · ADMIT ${r.seats.length}</div>
    <div style="font-size:15px;font-weight:bold;color:${INK};margin-top:6px;">${esc(s.eventTitle)}</div>
    <div style="font-size:13px;color:${MUTED};margin-top:2px;">${esc(formatDateShort(s.startAt))} · ${esc(formatTime(s.startAt))}</div>
  </td></tr>
  <tr><td style="padding:0 20px;"><div style="border-top:2px dashed #e9c766;height:0;line-height:0;font-size:0;">&nbsp;</div></td></tr>
  <tr><td style="padding:14px 20px 18px;">
    <div style="font-size:11px;letter-spacing:1.5px;color:${MUTED};font-weight:bold;">BOOKING REFERENCE</div>
    <div style="font-size:26px;font-weight:bold;letter-spacing:2px;color:${INK};font-family:'Courier New',monospace;margin-top:4px;">${esc(r.bookingReference)}</div>
  </td></tr>
</table>`;
}

/** A plain reference box for emails that are not tickets. */
function referenceHtml(ref) {
  return `<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="margin:4px 0 20px;border:1px solid ${LINE};border-radius:12px;">
  <tr><td style="padding:14px 18px;">
    <div style="font-size:11px;letter-spacing:1.5px;color:${MUTED};font-weight:bold;">BOOKING REFERENCE</div>
    <div style="font-size:22px;font-weight:bold;letter-spacing:2px;color:${INK};font-family:'Courier New',monospace;margin-top:4px;">${esc(ref)}</div>
  </td></tr>
</table>`;
}

function layout({ title, preheader, status, heading, content }) {
  return `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="color-scheme" content="light">
<title>${esc(title)}</title>
</head>
<body style="margin:0;padding:0;background:#f4f2ef;font-family:${FONT};color:${INK};">
<span style="display:none;max-height:0;overflow:hidden;opacity:0;">${esc(preheader)}</span>
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#f4f2ef;">
  <tr><td align="center" style="padding:28px 14px 36px;">
    <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:560px;">
      <tr><td style="padding:0 4px 16px;">
        <div style="font-size:16px;font-weight:bold;letter-spacing:3px;color:${INK};">CINEMATHEQUE</div>
        <div style="font-size:10px;font-weight:bold;letter-spacing:3.5px;color:#8a5a00;margin-top:2px;">CENTRE DAVAO</div>
      </td></tr>
      <tr><td style="background:#ffffff;border-radius:16px;padding:28px 28px 24px;">
        ${status ? `<div style="margin:0 0 14px;">${pill(status.label, status.tone)}</div>` : ''}
        <h1 style="margin:0 0 16px;font-size:22px;line-height:1.3;color:${INK};font-weight:bold;">${esc(heading)}</h1>
        ${content}
      </td></tr>
      <tr><td style="padding:16px 4px 0;font-size:12px;line-height:1.6;color:${MUTED};">
        Cinematheque Centre Davao · Palma Gil St., Davao City · An FDCP Cinematheque Centre<br>
        This email was sent because a booking was made with this address. Please don't reply to it.
      </td></tr>
    </table>
  </td></tr>
</table>
</body>
</html>`;
}

/**
 * → { subject, html, text } for [kind] ('pending' | 'confirmed' | 'cancelled').
 * [r] is the reservation document, [payment] its payment document (paid screenings) or null.
 */
export function renderEmail(kind, r, payment = null) {
  const s = r.screening;
  const paidScreening = s.type === 'paid';
  const ref = r.bookingReference;
  const hi = para(`Hi ${esc(r.booker.firstName)},`);
  const note = `<p style="margin:16px 0 0;font-size:13px;line-height:1.6;color:${MUTED};">${esc(APP_NOTE)}</p>`;
  let subject;
  let preheader;
  let status;
  let heading;
  let body; // HTML before the details
  let after = note; // HTML after the details
  let textIntro;

  switch (kind) {
    case 'pending':
      if (paidScreening) {
        const by = formatTime(r.expiresAt);
        subject = `Complete your payment · ${ref}`;
        preheader = `Your seats are held until ${by}. Pay in the Cinematheque app to get your e-ticket.`;
        status = { label: 'Awaiting payment', tone: TONES.pending };
        heading = 'Complete your payment';
        textIntro = [
          `We've received your reservation. Your seats are held until ${by}. Your booking is confirmed once payment is completed; unpaid bookings are released after 15 minutes. We'll email your e-ticket as soon as the payment goes through.`,
          `Amount due: ${pesos2(r.totalCentavos)}. To pay, open the Cinematheque app → Find my booking → ${ref} → Pay now.`,
        ];
        body = `${hi}${para(`We've received your reservation. Your seats are held until <strong>${esc(by)}</strong>; your booking is confirmed once payment is completed. Unpaid bookings are released after 15 minutes.`)}
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="margin:4px 0 20px;background:#fff7e1;border-radius:12px;">
  <tr><td style="padding:14px 18px;font-size:14px;line-height:1.55;color:${INK};">
    <strong>Amount due: ${esc(pesos2(r.totalCentavos))}</strong><br>
    <span style="color:${MUTED};">Open the Cinematheque app → Find my booking → <strong style="color:${INK};font-family:'Courier New',monospace;">${esc(ref)}</strong> → Pay now.</span>
  </td></tr>
</table>`;
      } else {
        subject = `Reservation received · ${ref}`;
        preheader = 'We received your reservation. Your e-ticket follows once it is approved.';
        status = { label: 'Awaiting approval', tone: TONES.pending };
        heading = 'Reservation received';
        textIntro = [
          "We've received your reservation for a free screening. Cinematheque staff will review it, and your e-ticket will be emailed to you once it's approved. This email is not valid for entry.",
        ];
        body = `${hi}${para("We've received your reservation for a free screening. Cinematheque staff will review it, and <strong>your e-ticket will be emailed to you once it's approved</strong>.")}${para('This email is not valid for entry.', `color:${MUTED};font-size:14px;`)}${referenceHtml(ref)}`;
      }
      break;

    case 'confirmed':
      subject = `Your e-ticket · ${ref}`;
      preheader = 'Your booking is confirmed. Show this e-ticket at the entrance.';
      status = { label: paidScreening ? 'Confirmed · paid' : 'Approved', tone: TONES.confirmed };
      heading = 'Your e-ticket';
      textIntro = [
        'Your booking is confirmed. This email is your e-ticket: show it, or just the booking reference, at the entrance.',
        `E-TICKET · ADMIT ${r.seats.length} · ${ref}`,
      ];
      body = `${hi}${para('Your booking is confirmed. <strong>This email is your e-ticket</strong>: show it, or just the booking reference, at the entrance.')}${stubHtml(r)}`;
      after = `<p style="margin:16px 0 0;font-size:13px;line-height:1.6;color:${MUTED};">Each person listed above is admitted by Cinematheque staff, who check names against this booking. Please arrive before the screening starts.</p>${note}`;
      break;

    case 'cancelled': {
      subject = `Reservation cancelled · ${ref}`;
      preheader = `Your booking ${ref} has been cancelled.`;
      status = { label: 'Cancelled', tone: TONES.cancelled };
      heading = 'Booking cancelled';
      const reason = CANCEL_REASONS[r.cancellationReason];
      const late = payment?.status === 'verified' && r.cancellationReason === 'payment_expired';
      const intro = late
        ? 'Your booking has been cancelled because your payment arrived after the 15-minute window. It is no longer valid for entry.'
        : `Your booking has been cancelled${reason ? ` (${reason})` : ''}. It is no longer valid for entry.`;
      const refund =
        payment?.status === 'verified'
          ? 'A payment was recorded for this booking. Please contact Cinematheque Centre Davao about your refund, quoting your booking reference.'
          : null;
      textIntro = [intro, ...(refund ? [refund] : [])];
      body = `${hi}${para(esc(intro))}${refund ? `<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="margin:0 0 20px;background:#fdecea;border-radius:12px;"><tr><td style="padding:14px 18px;font-size:14px;line-height:1.55;color:#7a1a12;">${esc(refund)}</td></tr></table>` : ''}${referenceHtml(ref)}`;
      after = `<p style="margin:16px 0 0;font-size:13px;line-height:1.6;color:${MUTED};">If you think this is a mistake, please contact Cinematheque Centre Davao and quote your booking reference.</p>`;
      break;
    }
    default:
      throw new Error(`Unknown email kind: ${kind}`);
  }

  const content = `${body}${detailsHtml(r, payment)}${after}`;
  const text = [
    'CINEMATHEQUE CENTRE DAVAO',
    '',
    `${heading.toUpperCase()} · ${status.label}`,
    '',
    `Hi ${r.booker.firstName},`,
    ...textIntro.flatMap((l) => ['', l]),
    '',
    `Booking reference: ${ref}`,
    ...details(r, payment).map(([k, v]) => `${k}: ${v}`),
    '',
    `Seats (${r.seats.length}):`,
    ...r.seats.map((x) => `  ${x.label}  ${fullName(x.attendee)}${x.isBooker ? ' (booker)' : ''}`),
    '',
    kind === 'cancelled' ? 'If you think this is a mistake, please contact Cinematheque Centre Davao and quote your booking reference.' : APP_NOTE,
    '',
    '— Cinematheque Centre Davao · Palma Gil St., Davao City',
  ].join('\n');

  return { subject, html: layout({ title: subject, preheader, status, heading, content }), text };
}

const STATUS_WORDS = {
  pending: (r) => (r.screening.type === 'paid' ? 'Awaiting payment' : 'Awaiting approval'),
  confirmed: () => 'Confirmed',
  cancelled: () => 'Cancelled',
};

const statusWord = (r) => STATUS_WORDS[r.status]?.(r) ?? '';

/** "Your upcoming bookings": what Find my booking sends when someone enters only an email. */
export function renderBookingList(reservations) {
  const first = reservations[0]?.booker?.firstName;
  const items = reservations
    .map(
      (r) => `<tr><td style="padding:14px 0;border-top:1px solid ${LINE};">
        <div style="font-size:15px;font-weight:bold;color:${INK};">${esc(r.screening.eventTitle)}</div>
        <div style="font-size:13px;color:${MUTED};margin-top:2px;">${esc(formatDateShort(r.screening.startAt))} · ${esc(formatTime(r.screening.startAt))} · ${r.seats.length} ${r.seats.length === 1 ? 'seat' : 'seats'} · ${esc(statusWord(r))}</div>
        <div style="font-size:17px;font-weight:bold;letter-spacing:1.5px;color:${INK};font-family:'Courier New',monospace;margin-top:6px;">${esc(r.bookingReference)}</div>
      </td></tr>`,
    )
    .join('');
  const subject = 'Your upcoming bookings · Cinematheque Centre Davao';
  const content = `${para(`Hi${first ? ` ${esc(first)}` : ''},`)}${para('Someone (hopefully you) asked for the bookings made with this email address. Here are the upcoming ones:')}
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="margin:4px 0 0;border-bottom:1px solid ${LINE};">${items}</table>
<p style="margin:16px 0 0;font-size:13px;line-height:1.6;color:${MUTED};">To open one, go to the Cinematheque app → Find my booking and enter its reference. If you didn't ask for this, you can ignore this email.</p>`;
  const text = [
    'CINEMATHEQUE CENTRE DAVAO',
    '',
    'YOUR UPCOMING BOOKINGS',
    '',
    ...reservations.map(
      (r) => `${r.screening.eventTitle} — ${formatDateShort(r.screening.startAt)} ${formatTime(r.screening.startAt)} — ${statusWord(r)}\n  Reference: ${r.bookingReference}`,
    ),
    '',
    'To open one: Cinematheque app → Find my booking → enter the reference.',
  ].join('\n');
  return { subject, html: layout({ title: subject, preheader: 'The booking references for your upcoming screenings.', status: null, heading: 'Your upcoming bookings', content }), text };
}

// ── Sending (once per state) ─────────────────────────────────────────────────

/**
 * Sends the email for the booking's current status, unless it was already sent (or is
 * being sent). Never throws because of email problems: a failure is recorded on the
 * reservation (emails.<state>.state = 'failed') so staff can resend it later.
 * → 'sent' | 'already_sent' | 'failed' | 'not_configured'
 */
export async function sendStatusEmail(db, reservationId, { mailer = getMailer(), now = new Date() } = {}) {
  if (!mailer) return 'not_configured';
  const ref = db.collection('reservations').doc(reservationId);

  // The claim is the transaction's RESULT: an attempt that lost a race and was retried
  // must not count as having claimed the email.
  const claim = await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) return null;
    const r = snap.data();
    const kind = r.status;
    if (r.emails?.[kind]) return null; // sent, being sent, or failed (staff resend) — never twice
    tx.update(ref, { [`emails.${kind}`]: { state: 'sending', at: now } });
    return { kind, r };
  });
  if (!claim) return 'already_sent';

  const { kind, r } = claim;
  try {
    const paySnap = await db.collection('payments').doc(reservationId).get();
    const message = renderEmail(kind, r, paySnap.exists ? paySnap.data() : null);
    await mailer.send({ to: r.booker.email, ...message });
    await ref.update({ [`emails.${kind}`]: { state: 'sent', at: new Date() } });
    return 'sent';
  } catch (e) {
    console.error(`Could not send the ${kind} email for ${reservationId}`, e);
    await ref.update({ [`emails.${kind}`]: { state: 'failed', at: new Date() } }).catch(() => {});
    return 'failed';
  }
}

/**
 * Find my booking by email: sends the booker the references of their upcoming bookings.
 * Nothing is sent when there are none, and at most once every 2 minutes per address, so the
 * form can't be used to flood someone's inbox. The caller answers the same either way.
 */
export async function emailBookingList(db, email, { mailer = getMailer(), now = new Date() } = {}) {
  const emailLower = email.trim().toLowerCase();
  const bookings = await upcomingBookingsFor(db, emailLower, now);
  if (!bookings.length || !mailer) return 'nothing_sent';

  const ref = db.collection('lookupEmails').doc(createHash('sha256').update(emailLower).digest('hex'));
  const allowed = await db.runTransaction(async (tx) => {
    const last = (await tx.get(ref)).data()?.sentAt?.toMillis() ?? 0;
    if (now.getTime() - last < 2 * 60_000) return false;
    tx.set(ref, { sentAt: Timestamp.fromDate(now) });
    return true;
  });
  if (!allowed) return 'too_soon';

  try {
    await mailer.send({ to: emailLower, ...renderBookingList(bookings) });
    return 'sent';
  } catch (e) {
    console.error('Could not send the booking list', e);
    return 'failed';
  }
}
