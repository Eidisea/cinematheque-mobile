// Seat holds: which seats of a screening are taken, and by which reservation.
//
// They live in the screening document as a map:  seatHolds.<label> = { reservationId, state, expiresAt }
//   held + expiresAt  → paid reservation waiting for payment (15-minute window)
//   held, no expiry   → free reservation waiting for staff approval
//   confirmed         → approved / paid
//
// Every change happens inside a Firestore TRANSACTION on the screening document. If two
// customers try to take the same seat at the same moment, Firestore runs one transaction
// first; the other one is retried, sees the seat is taken, and fails with SeatConflictError.
// That is what prevents double-booking.

import { FieldValue, Timestamp } from 'firebase-admin/firestore';

import { MAX_SEATS_PER_RESERVATION, SEAT_LABEL_PATTERN } from './booking-rules.js';

export class SeatConflictError extends Error {
  constructor(labels) {
    super(`Seat${labels.length > 1 ? 's' : ''} already taken: ${labels.join(', ')}`);
    this.name = 'SeatConflictError';
    this.labels = labels;
  }
}

export class BookingNotAllowedError extends Error {
  /** @param {'screening_not_found'|'screening_started'|'invalid_seats'|'too_many_seats'|'no_seat_layout'} reason */
  constructor(reason, detail = '') {
    super(`${reason}${detail ? `: ${detail}` : ''}`);
    this.name = 'BookingNotAllowedError';
    this.reason = reason;
  }
}

/** Same rule as the app: an unpaid hold stops blocking the seat once its window is over. */
export function isHoldActive(hold, now) {
  if (!hold) return false;
  if (hold.state === 'confirmed' || !hold.expiresAt) return true;
  return hold.expiresAt.toMillis() > now.getTime();
}

/**
 * Pure decision (no database): may these seats be claimed for this screening right now?
 * Returns the Firestore update to apply, plus reservations whose EXPIRED holds get replaced
 * (those reservations must be cancelled as payment_expired by the caller).
 */
export function planSeatClaim({ screening, layout, seatLabels, reservationId, expiresAt = null, now }) {
  if (!screening) throw new BookingNotAllowedError('screening_not_found');
  if (screening.startAt.toMillis() <= now.getTime()) throw new BookingNotAllowedError('screening_started');

  const labels = [...seatLabels];
  if (labels.length === 0) throw new BookingNotAllowedError('invalid_seats', 'no seats chosen');
  if (labels.length > MAX_SEATS_PER_RESERVATION) throw new BookingNotAllowedError('too_many_seats');
  if (new Set(labels).size !== labels.length) throw new BookingNotAllowedError('invalid_seats', 'duplicate seats');

  const activeSeats = new Set((layout?.seats ?? []).filter((s) => s.isActive !== false).map((s) => s.label));
  if (activeSeats.size === 0) throw new BookingNotAllowedError('no_seat_layout');
  const invalid = labels.filter((l) => !SEAT_LABEL_PATTERN.test(l) || !activeSeats.has(l));
  if (invalid.length) throw new BookingNotAllowedError('invalid_seats', invalid.join(', '));

  const holds = screening.seatHolds ?? {};
  const conflicts = labels.filter((l) => isHoldActive(holds[l], now));
  if (conflicts.length) throw new SeatConflictError(conflicts);

  const replacedReservationIds = [
    ...new Set(labels.filter((l) => holds[l]).map((l) => holds[l].reservationId)),
  ];

  const update = { hasReservations: true };
  for (const label of labels) {
    update[`seatHolds.${label}`] = {
      reservationId,
      state: 'held',
      expiresAt: expiresAt ? Timestamp.fromDate(expiresAt) : null,
    };
  }
  return { update, replacedReservationIds };
}

/**
 * Claims seats in a transaction. [inTransaction] lets the caller write more documents in
 * the SAME transaction (the reservation itself), so seats and reservation are saved
 * together or not at all. [expiresAt] may be a Date, null, or a function of the screening
 * (paid screenings get a payment deadline, free ones don't).
 */
export async function claimSeats(db, { screeningId, seatLabels, reservationId, expiresAt = null, now = new Date(), inTransaction }) {
  const screeningRef = db.collection('screenings').doc(screeningId);
  const layoutRef = db.doc('settings/seatLayout');

  return db.runTransaction(
    async (tx) => {
      const [screeningSnap, layoutSnap] = await Promise.all([tx.get(screeningRef), tx.get(layoutRef)]);
      const screening = screeningSnap.exists ? screeningSnap.data() : null;
      const plan = planSeatClaim({
        screening,
        layout: layoutSnap.exists ? layoutSnap.data() : null,
        seatLabels,
        reservationId,
        expiresAt: typeof expiresAt === 'function' ? (screening ? expiresAt(screening) : null) : expiresAt,
        now,
      });
      if (inTransaction) await inTransaction(tx, plan, screeningSnap.data());
      tx.update(screeningRef, plan.update);
      return { replacedReservationIds: plan.replacedReservationIds };
    },
    { maxAttempts: 10 },
  );
}

/**
 * Releases a reservation's seats (cancelled / expired). Only removes holds that still
 * belong to THIS reservation — if an expired seat was already re-claimed by someone
 * else, that newer hold is left alone. Returns the labels actually released.
 */
export async function releaseSeats(db, { screeningId, reservationId, seatLabels, inTransaction }) {
  const screeningRef = db.collection('screenings').doc(screeningId);
  return db.runTransaction(
    async (tx) => {
      const snap = await tx.get(screeningRef);
      const holds = snap.exists ? (snap.data().seatHolds ?? {}) : {};
      const released = seatLabels.filter((l) => holds[l]?.reservationId === reservationId);
      if (inTransaction) await inTransaction(tx, released);
      if (released.length) {
        const update = {};
        for (const l of released) update[`seatHolds.${l}`] = FieldValue.delete();
        tx.update(screeningRef, update);
      }
      return released;
    },
    { maxAttempts: 10 },
  );
}

/**
 * Marks a reservation's seats as confirmed (paid / approved) and removes the expiry.
 * Returns labels that no longer belong to this reservation (e.g. payment arrived after
 * the hold expired and someone else took the seat) so the caller can flag it.
 * If [inTransaction] returns false, the holds are left unchanged (e.g. a late payment).
 */
export async function confirmSeats(db, { screeningId, reservationId, seatLabels, inTransaction }) {
  const screeningRef = db.collection('screenings').doc(screeningId);
  return db.runTransaction(
    async (tx) => {
      const snap = await tx.get(screeningRef);
      const holds = snap.exists ? (snap.data().seatHolds ?? {}) : {};
      const kept = seatLabels.filter((l) => holds[l]?.reservationId === reservationId);
      const lost = seatLabels.filter((l) => !kept.includes(l));
      const proceed = inTransaction ? await inTransaction(tx, { kept, lost }) : true;
      if (proceed !== false && kept.length) {
        const update = {};
        for (const l of kept) update[`seatHolds.${l}`] = { reservationId, state: 'confirmed', expiresAt: null };
        tx.update(screeningRef, update);
      }
      return { kept, lost };
    },
    { maxAttempts: 10 },
  );
}
