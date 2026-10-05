import { getDb } from '../../lib/firebase.js';
import { HttpError, endpoint } from '../../lib/http.js';
import { expireReservation } from '../../lib/payments.js';
import { getPaymongo } from '../../lib/paymongo.js';
import { createReservation } from '../../lib/reservations.js';
import { BookingNotAllowedError, SeatConflictError } from '../../lib/seat-holds.js';
import { validateCreateReservation } from '../../lib/validate.js';

// POST /api/reservations/create — public (customers have no accounts).
// 201 { bookingReference, accessKey, status, requiresPayment, totalCentavos, expiresAt }
// 400 validation · 404 screening_not_found · 409 seats_taken / screening_started
export default endpoint({ methods: ['POST'] }, async (body) => {
  const { value, errors } = validateCreateReservation(body);
  if (Object.keys(errors).length) throw new HttpError(400, 'validation', { fields: errors });

  try {
    const db = getDb();
    const paymongo = getPaymongo();
    const created = await createReservation(db, value, { expire: (id) => expireReservation(db, paymongo, id) });
    return { status: 201, body: { ...created, expiresAt: created.expiresAt?.toISOString() ?? null } };
  } catch (e) {
    if (e instanceof SeatConflictError) throw new HttpError(409, 'seats_taken', { seats: e.labels });
    if (e instanceof BookingNotAllowedError) {
      if (e.reason === 'screening_not_found') throw new HttpError(404, 'screening_not_found');
      if (e.reason === 'screening_started') throw new HttpError(409, 'screening_started');
      throw new HttpError(400, e.reason);
    }
    throw e;
  }
});
