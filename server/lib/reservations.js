// Reservations: create, look up (reference + email), cancel.
//
// Documents written together (always in ONE transaction with the seat holds):
//   reservations/{id}      full record — staff only
//   payments/{id}          paid screenings only — staff only
//   bookingViews/{key}     the customer's copy without sensitive details — readable by
//                          whoever holds the long random access key (the customer's phone)

import { FieldValue, Timestamp } from 'firebase-admin/firestore';

import { PAYMENT_WINDOW_MS } from './booking-rules.js';
import { newAccessKey, newBookingReference, normalizeBookingReference } from './ids.js';
import { claimSeats, releaseSeats } from './seat-holds.js';

export class ReservationError extends Error {
  /** @param {'not_found'|'not_cancellable'|'not_approvable'} code */
  constructor(code, detail = '') {
    super(`${code}${detail ? `: ${detail}` : ''}`);
    this.name = 'ReservationError';
    this.code = code;
  }
}

const fullName = (p) => [p.firstName, p.middleName, p.lastName].filter(Boolean).join(' ');

/** The customer's copy. Only what the booking screen / e-ticket needs. */
export function bookingViewOf(reservation, payment) {
  return {
    bookingReference: reservation.bookingReference,
    status: reservation.status,
    cancellationReason: reservation.cancellationReason ?? null,
    screening: reservation.screening,
    posterUrl: reservation.posterUrl ?? null,
    seats: reservation.seats.map((s) => ({ label: s.label, attendeeName: fullName(s.attendee) })),
    totalCentavos: reservation.totalCentavos,
    paymentStatus: payment ? payment.status : null,
    expiresAt: reservation.status === 'pending' ? (reservation.expiresAt ?? null) : null,
    updatedAt: FieldValue.serverTimestamp(),
  };
}

/**
 * Creates a PENDING reservation and holds its seats (all-or-nothing).
 * Paid screenings: a pending payment + a 15-minute payment deadline.
 * Free screenings: no deadline — staff approve them.
 * [input] must already be validated (validateCreateReservation).
 * [expire] ends a reservation whose expired seats were just taken over (the API passes
 * payments.expireReservation, which asks PayMongo first so a payment is never lost).
 */
export async function createReservation(
  db,
  input,
  { now = new Date(), expire = (id) => cancelReservation(db, { reservationId: id, reason: 'payment_expired', now }) } = {},
) {
  const reservationRef = db.collection('reservations').doc();
  const accessKey = newAccessKey();
  const deadlineFor = (screening) => (screening.type === 'paid' ? new Date(now.getTime() + PAYMENT_WINDOW_MS) : null);
  let created;

  const { replacedReservationIds } = await claimSeats(db, {
    screeningId: input.screeningId,
    seatLabels: input.seats,
    reservationId: reservationRef.id,
    expiresAt: deadlineFor,
    now,
    inTransaction: async (tx, _plan, screening) => {
      // A new reference, checked against existing ones inside the same transaction.
      let bookingReference;
      for (let attempt = 0; attempt < 5 && !bookingReference; attempt++) {
        const candidate = newBookingReference();
        const clash = await tx.get(db.collection('reservations').where('bookingReference', '==', candidate).limit(1));
        if (clash.empty) bookingReference = candidate;
      }
      if (!bookingReference) throw new Error('Could not generate a unique booking reference');

      const paid = screening.type === 'paid';
      const deadline = deadlineFor(screening);
      const totalCentavos = paid ? screening.priceCentavos * input.seats.length : 0;

      const reservation = {
        bookingReference,
        screeningId: input.screeningId,
        screening: {
          eventTitle: screening.eventTitle,
          startAt: screening.startAt,
          endAt: screening.endAt,
          type: screening.type,
        },
        posterUrl: screening.movie?.posterUrl ?? null,
        status: 'pending',
        cancellationReason: null,
        booker: input.booker,
        bookerEmailLower: input.booker.email.toLowerCase(),
        seats: input.seats.map((label) => ({ label, isBooker: label === input.bookerSeat, attendee: input.attendees[label] })),
        seatLabels: input.seats,
        totalCentavos,
        accessKey,
        createdAt: Timestamp.fromDate(now),
        expiresAt: deadline ? Timestamp.fromDate(deadline) : null,
        confirmedAt: null,
        cancelledAt: null,
      };
      const payment = paid
        ? {
            bookingReference,
            amountCentavos: totalCentavos,
            currency: 'PHP',
            status: 'pending',
            checkoutSessionId: null,
            paymongoPaymentId: null,
            method: null,
            paidAt: null,
            needsRefund: false,
            createdAt: Timestamp.fromDate(now),
          }
        : null;

      tx.create(reservationRef, reservation);
      if (payment) tx.create(db.collection('payments').doc(reservationRef.id), payment);
      tx.create(db.collection('bookingViews').doc(accessKey), bookingViewOf(reservation, payment));
      created = {
        reservationId: reservationRef.id, // for the server only — the API does not return it
        bookingReference,
        accessKey,
        status: 'pending',
        requiresPayment: paid,
        totalCentavos,
        expiresAt: deadline,
      };
    },
  });

  // Seats taken over from EXPIRED unpaid reservations: those reservations end now.
  for (const id of replacedReservationIds) {
    await expire(id).catch((e) => console.error('Could not expire replaced reservation', id, e));
  }

  return created;
}

/**
 * Find my booking, by reference: the reference (random, printed on the ticket and in the
 * emails) opens the booking → its access key. Unknown or malformed → not_found.
 */
export async function lookupBooking(db, { bookingReference }) {
  const ref = normalizeBookingReference(bookingReference);
  if (!ref) throw new ReservationError('not_found');
  const snap = await db.collection('reservations').where('bookingReference', '==', ref).limit(1).get();
  const doc = snap.docs[0];
  if (!doc) throw new ReservationError('not_found');
  return { bookingReference: ref, accessKey: doc.data().accessKey };
}

/** The booker's bookings for screenings that have not started yet, soonest first. */
export async function upcomingBookingsFor(db, email, now = new Date()) {
  const emailLower = typeof email === 'string' ? email.trim().toLowerCase() : '';
  if (!emailLower) return [];
  const snap = await db.collection('reservations').where('bookerEmailLower', '==', emailLower).get();
  return snap.docs
    .map((d) => d.data())
    .filter((r) => r.screening.startAt.toMillis() > now.getTime())
    .sort((a, b) => a.screening.startAt.toMillis() - b.screening.startAt.toMillis());
}

export async function findReservationIdByAccessKey(db, accessKey) {
  if (typeof accessKey !== 'string' || accessKey.length < 20 || accessKey.length > 100) return null;
  const snap = await db.collection('reservations').where('accessKey', '==', accessKey).limit(1).get();
  return snap.docs[0]?.id ?? null;
}

/**
 * Cancels a reservation and releases its seats — all in one transaction.
 * reason: 'customer_cancelled' | 'staff_cancelled' | 'payment_expired'
 *
 * Who may cancel what:
 *  - customer: only PENDING bookings (unpaid paid ones, or free ones awaiting approval)
 *  - staff:    pending or confirmed (Phase 9)
 *  - expiry:   only pending paid bookings whose payment deadline has passed
 */
export async function cancelReservation(db, { reservationId, reason, now = new Date(), by = null }) {
  const reservationRef = db.collection('reservations').doc(reservationId);
  const first = await reservationRef.get();
  if (!first.exists) throw new ReservationError('not_found');
  const { screeningId, seatLabels } = first.data();
  let outcome;

  await releaseSeats(db, {
    screeningId,
    reservationId,
    seatLabels,
    inTransaction: async (tx) => {
      const [resSnap, paySnap] = await Promise.all([
        tx.get(reservationRef),
        tx.get(db.collection('payments').doc(reservationId)),
      ]);
      const r = resSnap.data();
      const payment = paySnap.exists ? paySnap.data() : null;

      if (r.status === 'cancelled') throw new ReservationError('not_cancellable', 'already cancelled');
      const expired = r.status === 'pending' && r.expiresAt && r.expiresAt.toMillis() <= now.getTime();
      if (reason === 'customer_cancelled' && r.status !== 'pending') {
        throw new ReservationError('not_cancellable', 'confirmed bookings are cancelled by staff');
      }
      if (reason === 'payment_expired' && !expired) throw new ReservationError('not_cancellable', 'not expired');

      // A customer cancelling after the deadline is recorded as an expiry.
      const finalReason = reason === 'customer_cancelled' && expired ? 'payment_expired' : reason;
      const update = {
        status: 'cancelled',
        cancellationReason: finalReason,
        cancelledAt: Timestamp.fromDate(now),
        ...(by ? { cancelledBy: by } : {}), // the staff member, for staff cancellations
      };
      tx.update(reservationRef, update);
      tx.set(db.collection('bookingViews').doc(r.accessKey), bookingViewOf({ ...r, ...update }, payment));
      outcome = { status: 'cancelled', cancellationReason: finalReason, bookingReference: r.bookingReference };
    },
  });

  return outcome;
}
