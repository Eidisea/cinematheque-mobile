import { sendStatusEmail } from '../../lib/email.js';
import { getDb } from '../../lib/firebase.js';
import { HttpError, endpoint } from '../../lib/http.js';
import { ReservationError, cancelReservation, findReservationIdByAccessKey } from '../../lib/reservations.js';

// POST /api/bookings/cancel — the customer cancels their own PENDING booking.
// { accessKey } → { status: 'cancelled', cancellationReason, bookingReference }
// Confirmed (paid / approved) bookings can only be cancelled by staff → 409.
export default endpoint({ methods: ['POST'] }, async (body) => {
  const db = getDb();
  const reservationId = await findReservationIdByAccessKey(db, body.accessKey);
  if (!reservationId) throw new HttpError(404, 'not_found');
  try {
    const outcome = await cancelReservation(db, { reservationId, reason: 'customer_cancelled' });
    await sendStatusEmail(db, reservationId);
    return { body: outcome };
  } catch (e) {
    if (e instanceof ReservationError) throw new HttpError(e.code === 'not_found' ? 404 : 409, e.code);
    throw e;
  }
});
