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

import nodemailer from 'nodemailer';

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

// ── Templates (the website's emails: dark header, status bar, details, seats, footer) ──

const METHOD_NAMES = { card: 'Card', gcash: 'GCash', paymaya: 'Maya', grab_pay: 'GrabPay', qrph: 'QR Ph' };
const formatDateShort = (t) => fmt({ weekday: 'short', month: 'short', day: 'numeric', year: 'numeric' }).format(toDate(t));
const formatPaidAt = (t) =>
  `${fmt({ month: 'short', day: 'numeric', year: 'numeric' }).format(toDate(t))} ${formatTime(t)}`;
const pesos2 = (centavos) =>
  `₱${(centavos / 100).toLocaleString('en-PH', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;

const STATUS = {
  pendingPaid: { bg: '#fdf1e3', fg: '#7c3a06', label: 'PENDING · AWAITING PAYMENT' },
  pendingFree: { bg: '#fdf1e3', fg: '#7c3a06', label: 'PENDING · AWAITING APPROVAL' },
  confirmed: { bg: '#e6f2ec', fg: '#154c37', label: 'APPROVED · E-TICKET' },
  cancelled: { bg: '#fdecea', fg: '#7a1a12', label: 'CANCELLED' },
};

const CANCEL_REASONS = {
  customer_cancelled: 'you cancelled it',
  payment_expired: 'payment was not completed within 15 minutes',
  staff_cancelled: 'Cinematheque Centre Davao cancelled it',
};

/** The rows of booking details shared by every email (only data the system already stores). */
function details(r, payment) {
  const s = r.screening;
  const rows = [
    ['Booking reference', r.bookingReference, 'font-weight:bold;font-size:17px;letter-spacing:1px;'],
    ['Event', s.eventTitle, 'font-weight:bold;'],
    ['Date', formatDateLong(s.startAt)],
    ['Time', `${formatTime(s.startAt)} – ${formatTime(s.endAt)}`],
    ['Booked by', fullName(r.booker)],
  ];
  if (payment) {
    const method = payment.method ? ` via ${METHOD_NAMES[payment.method] ?? payment.method}` : '';
    const when = payment.paidAt ? ` on ${formatPaidAt(payment.paidAt)}` : '';
    rows.push(['Amount', pesos2(payment.amountCentavos)]);
    rows.push(['Payment', payment.status === 'verified' ? `Paid${method}${when}` : 'Not yet paid']);
  } else {
    rows.push(['Admission', 'Free']);
  }
  return rows;
}

function renderDetailsHtml(r, payment) {
  const row = 'padding:6px 0;border-bottom:1px solid #f0eee9;vertical-align:top;';
  const label = `${row}color:#6b6674;width:40%;font-size:13px;`;
  const seats = r.seats;
  return `<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="margin:0 0 20px;">
${details(r, payment).map(([k, v, extra = '']) => `    <tr><td style="${label}">${esc(k)}</td><td style="${row}${extra}">${esc(v)}</td></tr>`).join('\n')}
</table>
<div style="font-size:13px;color:#6b6674;font-weight:bold;letter-spacing:.5px;margin:0 0 6px;">SEATS (${seats.length})</div>
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="margin:0 0 20px;border:1px solid #ece9e4;border-radius:8px;">
${seats
  .map(
    (x) => `    <tr>
        <td style="padding:8px 12px;border-bottom:1px solid #f0eee9;width:70px;"><span style="display:inline-block;background:#ebbc00;color:#141219;font-weight:bold;border-radius:12px;padding:2px 10px;font-size:13px;">${esc(x.label)}</span></td>
        <td style="padding:8px 12px;border-bottom:1px solid #f0eee9;">${esc(fullName(x.attendee))}${x.isBooker ? ' <span style="color:#6b6674;font-size:12px;">(booker)</span>' : ''}</td>
    </tr>`,
  )
  .join('\n')}
</table>`;
}

function layout({ title, preheader, status, content }) {
  return `<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <meta name="color-scheme" content="light">
    <title>${esc(title)}</title>
</head>
<body style="margin:0;padding:0;background:#f4f2ef;font-family:Arial,Helvetica,sans-serif;color:#141219;">
<span style="display:none;max-height:0;overflow:hidden;opacity:0;">${esc(preheader)}</span>
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#f4f2ef;">
    <tr>
        <td align="center" style="padding:24px 12px;">
            <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:600px;background:#ffffff;border-radius:12px;overflow:hidden;">
                <tr>
                    <td style="background:#141219;padding:20px 28px;">
                        <div style="color:#ffffff;font-size:18px;font-weight:bold;letter-spacing:1.5px;">CINEMATHEQUE</div>
                        <div style="color:#ebbc00;font-size:11px;font-weight:bold;letter-spacing:3px;">CENTRE DAVAO</div>
                    </td>
                </tr>
                <tr>
                    <td style="background:${status.bg};color:${status.fg};padding:12px 28px;font-size:13px;font-weight:bold;letter-spacing:.5px;">
                        ${esc(status.label)}
                    </td>
                </tr>
                <tr>
                    <td style="padding:28px;font-size:15px;line-height:1.55;">
${content}
                    </td>
                </tr>
                <tr>
                    <td style="padding:18px 28px;background:#faf9f7;border-top:1px solid #ece9e4;font-size:12px;line-height:1.5;color:#6b6674;">
                        Cinematheque Centre Davao · Davao City<br>
                        This email was sent because a reservation was made with this address. Please don't reply to this email.
                    </td>
                </tr>
            </table>
        </td>
    </tr>
</table>
</body>
</html>`;
}

const APP_NOTE =
  'You can check your booking anytime in the Cinematheque app: Find my booking, with your booking reference and this email address.';

/**
 * → { subject, html, text } for [kind] ('pending' | 'confirmed' | 'cancelled').
 * [r] is the reservation document, [payment] its payment document (paid screenings) or null.
 */
export function renderEmail(kind, r, payment = null) {
  const s = r.screening;
  const paidScreening = s.type === 'paid';
  const ref = r.bookingReference;
  const hi = `<p style="margin:0 0 16px;">Hi ${esc(r.booker.firstName)},</p>`;
  const note = `<p style="margin:0;font-size:13px;color:#6b6674;">${esc(APP_NOTE)}</p>`;
  let subject;
  let preheader;
  let status;
  let body; // HTML paragraphs before the details
  let after = ''; // HTML after the details
  let textIntro; // plain-text version of the message

  switch (kind) {
    case 'pending':
      if (paidScreening) {
        const by = formatTime(r.expiresAt);
        subject = `Complete your payment · ${ref}`;
        preheader = 'Complete your payment to receive your e-ticket.';
        status = STATUS.pendingPaid;
        textIntro = [
          `We've received your reservation. Your seats are held until ${by}, but your booking is only confirmed once payment is completed; unpaid bookings expire after 15 minutes. We'll email your e-ticket as soon as the payment goes through.`,
          `To pay: open the Cinematheque app → Find my booking → ${ref} → Pay now.`,
        ];
        body = `<p style="margin:0 0 20px;">We've received your reservation. Your seats are held until <strong>${esc(by)}</strong>, but <strong>your booking is only confirmed once payment is completed</strong>; unpaid bookings expire after 15 minutes. Pay securely through PayMongo in the Cinematheque app. We'll email your e-ticket as soon as the payment goes through.</p>
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="margin:0 0 24px;background:#fff7e1;border:1px solid #e9c766;border-radius:10px;">
    <tr><td style="padding:14px 16px;font-size:14px;line-height:1.5;">
        <strong>Amount due: ${esc(pesos2(r.totalCentavos))}</strong><br>
        <span style="color:#6b6674;">To pay, open the Cinematheque app → Find my booking → ${esc(ref)} → Pay now.</span>
    </td></tr>
</table>`;
      } else {
        subject = `Reservation received · ${ref}`;
        preheader = 'We received your reservation. Your e-ticket follows once it is approved.';
        status = STATUS.pendingFree;
        textIntro = [
          "We've received your reservation for a free screening. Cinematheque staff will review it, and your e-ticket will be emailed to you once it's approved. This email is not valid for entry.",
        ];
        body = `<p style="margin:0 0 20px;">We've received your reservation for a free screening. Cinematheque staff will review it, and <strong>your e-ticket will be emailed to you once it's approved</strong>. This email is not valid for entry.</p>`;
      }
      after = note;
      break;

    case 'confirmed':
      subject = `Your e-ticket · ${ref}`;
      preheader = 'Your reservation is confirmed. Show this e-ticket at the entrance.';
      status = STATUS.confirmed;
      textIntro = [
        'Your reservation is confirmed. This email is your e-ticket: show it, or just the booking reference, at the entrance.',
        `E-TICKET · ADMIT ${r.seats.length} · ${ref}`,
      ];
      body = `<p style="margin:0 0 20px;">Your reservation is <strong>confirmed</strong>. This email is your <strong>e-ticket</strong>: show it, or just the booking reference, at the entrance.</p>
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="margin:0 0 24px;border:2px dashed #ebbc00;border-radius:12px;">
    <tr>
        <td align="center" style="padding:18px 12px;">
            <div style="font-size:11px;letter-spacing:3px;color:#6b6674;font-weight:bold;">E-TICKET · ADMIT ${r.seats.length}</div>
            <div style="font-size:30px;font-weight:bold;letter-spacing:3px;margin:6px 0;color:#141219;">${esc(ref)}</div>
            <div style="font-size:14px;font-weight:bold;">${esc(s.eventTitle)}</div>
            <div style="font-size:13px;color:#6b6674;">${esc(formatDateShort(s.startAt))} · ${esc(formatTime(s.startAt))}</div>
        </td>
    </tr>
</table>`;
      after = `<div style="background:#faf9f7;border-radius:8px;padding:14px 16px;font-size:13px;line-height:1.55;margin:0 0 16px;">
    <strong>At the venue</strong><br>
    Each attendee listed above is admitted individually by Cinematheque staff, who check names against this booking. Please arrive before the start time.
</div>
${note}`;
      break;

    case 'cancelled': {
      subject = `Reservation cancelled · ${ref}`;
      preheader = `Your reservation ${ref} has been cancelled.`;
      status = STATUS.cancelled;
      const reason = CANCEL_REASONS[r.cancellationReason];
      const late = payment?.status === 'verified' && r.cancellationReason === 'payment_expired';
      const intro = late
        ? 'Your reservation below has been cancelled because your payment arrived after the 15-minute window, and it is no longer valid for admission.'
        : `Your reservation below has been cancelled${reason ? ` (${reason})` : ''} and is no longer valid for admission.`;
      const refund =
        payment?.status === 'verified'
          ? 'A payment was recorded for this booking. Please contact Cinematheque Centre Davao about your refund, quoting your booking reference.'
          : null;
      textIntro = [intro, ...(refund ? [refund] : [])];
      body = `<p style="margin:0 0 20px;">${esc(intro).replace('cancelled', '<strong>cancelled</strong>')}</p>`;
      after = `${refund ? `<p style="margin:0 0 16px;">${esc(refund)}</p>\n` : ''}<p style="margin:0;font-size:13px;color:#6b6674;">If you think this is a mistake, please contact Cinematheque Centre Davao and quote your booking reference.</p>`;
      break;
    }
    default:
      throw new Error(`Unknown email kind: ${kind}`);
  }

  const content = `${hi}\n${body}\n${renderDetailsHtml(r, payment)}\n${after}`;
  const text = [
    'CINEMATHEQUE CENTRE DAVAO',
    status.label,
    '',
    `Hi ${r.booker.firstName},`,
    ...textIntro.flatMap((l) => ['', l]),
    '',
    ...details(r, payment).map(([k, v]) => `${k}: ${v}`),
    '',
    `Seats (${r.seats.length}):`,
    ...r.seats.map((x) => `  ${x.label}  ${fullName(x.attendee)}${x.isBooker ? ' (booker)' : ''}`),
    '',
    kind === 'cancelled' ? 'If you think this is a mistake, please contact Cinematheque Centre Davao and quote your booking reference.' : APP_NOTE,
    '',
    '— Cinematheque Centre Davao · Davao City',
  ].join('\n');

  return { subject, html: layout({ title: subject, preheader, status, content }), text };
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
