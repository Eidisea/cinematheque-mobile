// What staff may do to bookings (Phase 9). Everything runs here on the server; the staff
// app only asks. Rules (handoff §5):
//   - FREE bookings are confirmed by staff approval (one, or all pending for a screening).
//   - PAID bookings are confirmed only by a verified payment — staff can never approve them.
//   - Staff may cancel pending or confirmed bookings; refunds happen outside the system.
//   - Each state change sends its email once; staff may resend the current one.

import { FieldValue, Timestamp } from 'firebase-admin/firestore';

import { sendStatusEmail } from './email.js';
import { ReservationError, bookingViewOf, cancelReservation } from './reservations.js';
import { confirmSeats } from './seat-holds.js';

/** Approves one pending FREE booking: seats confirmed, booking confirmed, e-ticket emailed. */
export async function approveReservation(db, { reservationId, staffUid, now = new Date(), mailer }) {
  const ref = db.collection('reservations').doc(reservationId);
  const first = await ref.get();
  if (!first.exists) throw new ReservationError('not_found');
  const { screeningId, seatLabels } = first.data();
  let bookingReference;

  await confirmSeats(db, {
    screeningId,
    reservationId,
    seatLabels,
    inTransaction: async (tx, { lost }) => {
      const r = (await tx.get(ref)).data();
      if (r.screening.type !== 'free') throw new ReservationError('not_approvable', 'paid bookings are confirmed by payment');
      if (r.status !== 'pending') throw new ReservationError('not_approvable', `already ${r.status}`);
      if (r.screening.startAt.toMillis() <= now.getTime()) throw new ReservationError('not_approvable', 'screening started');
      if (lost.length) throw new ReservationError('not_approvable', `seats no longer held: ${lost.join(', ')}`);

      const update = { status: 'confirmed', confirmedAt: Timestamp.fromDate(now), confirmedBy: staffUid };
      tx.update(ref, update);
      tx.set(db.collection('bookingViews').doc(r.accessKey), bookingViewOf({ ...r, ...update }, null));
      bookingReference = r.bookingReference;
      return true;
    },
  });

  await sendStatusEmail(db, reservationId, { mailer, now }); // the e-ticket
  return { status: 'confirmed', bookingReference };
}

/** Approves every pending free booking of a screening. → { approved, failed } */
export async function approveAllPending(db, { screeningId, staffUid, now = new Date(), mailer }) {
  const snap = await db
    .collection('reservations')
    .where('screeningId', '==', screeningId)
    .where('status', '==', 'pending')
    .get();
  const free = snap.docs.filter((d) => d.data().screening?.type === 'free');
  let approved = 0;
  const failed = [];
  for (const doc of free) {
    try {
      await approveReservation(db, { reservationId: doc.id, staffUid, now, mailer });
      approved++;
    } catch (e) {
      if (!(e instanceof ReservationError)) throw e;
      failed.push(doc.data().bookingReference);
    }
  }
  return { approved, failed };
}

/**
 * Staff cancel a pending or confirmed booking: seats released, booking cancelled, email
 * sent. An open PayMongo checkout is closed first so no one pays for a cancelled booking;
 * a booking that was already paid is flagged for refund.
 */
export async function staffCancelReservation(db, paymongo, { reservationId, staffUid, now = new Date(), mailer }) {
  const paySnap = await db.collection('payments').doc(reservationId).get();
  const payment = paySnap.exists ? paySnap.data() : null;
  if (paymongo && payment?.checkoutSessionId && payment.status !== 'verified') {
    await paymongo.expireCheckoutSession(payment.checkoutSessionId).catch((e) =>
      console.error('Could not expire checkout session', payment.checkoutSessionId, e),
    );
  }
  const outcome = await cancelReservation(db, { reservationId, reason: 'staff_cancelled', now, by: staffUid });
  // Money already received for a booking that no longer happens → refund outside the system.
  if (payment?.status === 'verified') await paySnap.ref.update({ needsRefund: true });
  await sendStatusEmail(db, reservationId, { mailer, now });
  return outcome;
}

/**
 * Sends the email for the booking's current state again (e.g. it failed, or the customer
 * lost it). → 'sent' | 'failed' | 'not_configured'
 */
export async function resendStatusEmail(db, { reservationId, now = new Date(), mailer }) {
  const ref = db.collection('reservations').doc(reservationId);
  const snap = await ref.get();
  if (!snap.exists) throw new ReservationError('not_found');
  await ref.update({ [`emails.${snap.data().status}`]: FieldValue.delete() });
  return sendStatusEmail(db, reservationId, { mailer, now });
}
