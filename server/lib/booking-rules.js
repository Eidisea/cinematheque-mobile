// Business rules enforced by the server. The Flutter apps use the same values only to
// guide customers (lib/core/booking_rules.dart) — the server is what actually decides.

export const MAX_SEATS_PER_RESERVATION = 10;

/** A paid reservation holds its seats this long while the customer pays. */
export const PAYMENT_WINDOW_MS = 15 * 60 * 1000;

/** Seat labels look like "A1" … "J12": row letters then a number. */
export const SEAT_LABEL_PATTERN = /^[A-Z]{1,2}[0-9]{1,3}$/;
