// Paid screenings: PayMongo checkout, payment verification, and expiry of unpaid holds.
//
// A paid booking is confirmed ONLY here, and only when PayMongo itself (asked with our
// secret key) reports a payment of exactly the booking's amount. The webhook, the app's
// "refresh" and the expiry job all end in settlePayment(), so it is safe to run more than
// once for the same payment.
//
// Late payments (paid after the 15-minute window, or after the seats went to someone else)
// are recorded as verified + needsRefund; the booking stays / becomes cancelled and staff
// refund it outside the system.

import { Timestamp } from 'firebase-admin/firestore';

import { sendStatusEmail } from './email.js';
import { paidPaymentOf } from './paymongo.js';
import { ReservationError, bookingViewOf, cancelReservation, findReservationIdByAccessKey } from './reservations.js';
import { confirmSeats } from './seat-holds.js';

/** Payment methods offered on PayMongo's hosted page (all available in test mode). */
export const PAYMENT_METHOD_TYPES = ['gcash', 'paymaya', 'card'];

export class PaymentError extends Error {
  /** @param {'not_payable'|'payment_expired'|'payments_unavailable'} code */
  constructor(code) {
    super(code);
    this.name = 'PaymentError';
    this.code = code;
  }
}

const refs = (db, reservationId) => ({
  reservation: db.collection('reservations').doc(reservationId),
  payment: db.collection('payments').doc(reservationId),
});

/**
 * The customer wants to pay: returns { checkoutUrl } of a PayMongo hosted checkout for the
 * booking's exact amount, reusing the open one if there is one. { alreadyPaid: true } if
 * PayMongo already has the payment (it is recorded now).
 */
export async function startCheckout(db, paymongo, { accessKey, returnUrl, now = new Date() }) {
  if (!paymongo) throw new PaymentError('payments_unavailable');
  const reservationId = await findReservationIdByAccessKey(db, accessKey);
  if (!reservationId) throw new ReservationError('not_found');
  const ref = refs(db, reservationId);
  const [resSnap, paySnap] = await Promise.all([ref.reservation.get(), ref.payment.get()]);
  const r = resSnap.data();
  const payment = paySnap.exists ? paySnap.data() : null;

  if (!payment || r.status !== 'pending' || payment.status === 'verified') throw new PaymentError('not_payable');
  if (r.expiresAt && r.expiresAt.toMillis() <= now.getTime()) throw new PaymentError('payment_expired');

  if (payment.checkoutSessionId) {
    const existing = await paymongo.getCheckoutSession(payment.checkoutSessionId);
    if (paidPaymentOf(existing)) {
      await settlePayment(db, { reservationId, session: existing, now });
      return { alreadyPaid: true };
    }
    if (existing.attributes?.status === 'active') return { checkoutUrl: existing.attributes.checkout_url };
  }

  const seats = r.seatLabels.length;
  const perSeat = payment.amountCentavos / seats;
  const name = `${r.screening.eventTitle} · admission`;
  const b = r.booker;
  const session = await paymongo.createCheckoutSession({
    // Fills in PayMongo's billing fields with the booker's details (it always asks for them).
    billing: {
      name: [b.firstName, b.middleName, b.lastName].filter(Boolean).join(' '),
      email: b.email,
      phone: b.contactNo,
    },
    line_items: Number.isInteger(perSeat)
      ? [{ name, amount: perSeat, currency: 'PHP', quantity: seats }]
      : [{ name, amount: payment.amountCentavos, currency: 'PHP', quantity: 1 }],
    payment_method_types: PAYMENT_METHOD_TYPES,
    description: `Cinematheque Centre Davao · ${r.bookingReference} · Seats ${r.seatLabels.join(', ')}`,
    reference_number: r.bookingReference,
    metadata: { reservationId },
    success_url: `${returnUrl}?result=paid`,
    cancel_url: `${returnUrl}?result=cancelled`,
    send_email_receipt: false,
    show_description: true,
    show_line_items: true,
  });
  await ref.payment.update({ checkoutSessionId: session.id });
  return { checkoutUrl: session.attributes.checkout_url };
}

/**
 * Records what PayMongo reports for [session] (already fetched from PayMongo with our key).
 * Outcomes: unpaid · confirmed · late_needs_refund · already_recorded · amount_mismatch · not_paid_booking
 */
export async function settlePayment(db, { reservationId, session, now = new Date(), mailer }) {
  const paid = paidPaymentOf(session);
  if (!paid) return { outcome: 'unpaid' };

  const ref = refs(db, reservationId);
  const first = await ref.reservation.get();
  if (!first.exists) throw new ReservationError('not_found');
  const { screeningId, seatLabels } = first.data();
  let outcome;
  let cancelAfter = false;

  await confirmSeats(db, {
    screeningId,
    reservationId,
    seatLabels,
    inTransaction: async (tx, { lost }) => {
      cancelAfter = false; // reset on every attempt — a retried transaction starts over
      const [resSnap, paySnap] = await Promise.all([tx.get(ref.reservation), tx.get(ref.payment)]);
      const r = resSnap.data();
      const payment = paySnap.exists ? paySnap.data() : null;

      if (!payment) {
        outcome = 'not_paid_booking';
        return false;
      }
      if (payment.status === 'verified') {
        if (payment.paymongoPaymentId !== paid.id) {
          console.error(`Second payment ${paid.id} for reservation ${reservationId}: refund it in the PayMongo dashboard.`);
        }
        outcome = 'already_recorded';
        return false;
      }
      if (paid.currency !== 'PHP' || paid.amountCentavos !== payment.amountCentavos) {
        console.error(`Payment ${paid.id} for ${reservationId}: ${paid.amountCentavos} ${paid.currency} ≠ ${payment.amountCentavos} PHP`);
        outcome = 'amount_mismatch';
        return false;
      }

      // Paid within the window (by PayMongo's clock), and every seat is still this booking's.
      const inTime = !r.expiresAt || paid.paidAt.getTime() <= r.expiresAt.toMillis();
      const confirm = r.status === 'pending' && inTime && lost.length === 0;
      const paymentUpdate = {
        status: 'verified',
        checkoutSessionId: session.id,
        paymongoPaymentId: paid.id,
        method: paid.method,
        paidAt: Timestamp.fromDate(paid.paidAt),
        needsRefund: !confirm,
      };
      tx.update(ref.payment, paymentUpdate);
      const view = db.collection('bookingViews').doc(r.accessKey);

      if (confirm) {
        const update = { status: 'confirmed', confirmedAt: Timestamp.fromDate(now), expiresAt: null };
        tx.update(ref.reservation, update);
        tx.set(view, bookingViewOf({ ...r, ...update }, { ...payment, ...paymentUpdate }));
        outcome = 'confirmed';
        return true;
      }
      tx.set(view, bookingViewOf(r, { ...payment, ...paymentUpdate }));
      cancelAfter = r.status === 'pending';
      outcome = 'late_needs_refund';
      return false;
    },
  });

  if (cancelAfter) await cancelExpired(db, reservationId, now);
  if (outcome === 'confirmed' || outcome === 'late_needs_refund') {
    await sendStatusEmail(db, reservationId, { mailer, now }); // e-ticket, or cancelled + refund note
  }
  return { outcome };
}

/** The app asks "has my payment gone through?" (e.g. back from the PayMongo page). */
export async function refreshPayment(db, paymongo, { accessKey, now = new Date() }) {
  const reservationId = await findReservationIdByAccessKey(db, accessKey);
  if (!reservationId) throw new ReservationError('not_found');
  const paySnap = await refs(db, reservationId).payment.get();
  const payment = paySnap.exists ? paySnap.data() : null;
  if (!paymongo || !payment?.checkoutSessionId || payment.status === 'verified') return { outcome: 'unchanged' };
  const session = await paymongo.getCheckoutSession(payment.checkoutSessionId);
  return settlePayment(db, { reservationId, session, now });
}

/**
 * Ends an unpaid booking whose 15 minutes are over — but asks PayMongo first, so a payment
 * made in time (webhook not arrived yet) still confirms, and a late one is flagged for refund.
 */
export async function expireReservation(db, paymongo, reservationId, now = new Date(), { mailer } = {}) {
  const paySnap = await refs(db, reservationId).payment.get();
  const payment = paySnap.exists ? paySnap.data() : null;

  if (payment?.checkoutSessionId && payment.status !== 'verified') {
    if (!paymongo) throw new PaymentError('payments_unavailable'); // never drop a possible payment unchecked
    const session = await paymongo.getCheckoutSession(payment.checkoutSessionId);
    if (paidPaymentOf(session)) return settlePayment(db, { reservationId, session, now, mailer });
    if (session.attributes?.status === 'active') {
      await paymongo.expireCheckoutSession(payment.checkoutSessionId).catch((e) =>
        console.error('Could not expire checkout session', payment.checkoutSessionId, e),
      );
    }
  }
  if (!(await cancelExpired(db, reservationId, now))) return { outcome: 'unchanged' };
  await sendStatusEmail(db, reservationId, { mailer, now });
  return { outcome: 'expired' };
}

async function cancelExpired(db, reservationId, now) {
  try {
    await cancelReservation(db, { reservationId, reason: 'payment_expired', now });
    return true;
  } catch (e) {
    if (e instanceof ReservationError) return false; // already cancelled / not expired yet
    throw e;
  }
}

/** Pending paid bookings whose payment window is over (uses the status + expiresAt index). */
export async function findExpiredUnpaid(db, now = new Date(), limit = 50) {
  const snap = await db
    .collection('reservations')
    .where('status', '==', 'pending')
    .where('expiresAt', '<=', Timestamp.fromDate(now))
    .orderBy('expiresAt')
    .limit(limit)
    .get();
  return snap.docs.map((d) => d.id);
}
