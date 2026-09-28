import { getDb } from '../../lib/firebase.js';
import { HttpError, endpoint } from '../../lib/http.js';
import { ReservationError, lookupBooking } from '../../lib/reservations.js';

// POST /api/bookings/lookup — public. { bookingReference, email } → { bookingReference, accessKey }
// Wrong reference and wrong email give the SAME 404, so the endpoint can't be used to
// discover which references exist or whose email is on a booking.
export default endpoint({ methods: ['POST'] }, async (body) => {
  try {
    return { body: await lookupBooking(getDb(), { bookingReference: body.bookingReference, email: body.email }) };
  } catch (e) {
    if (e instanceof ReservationError) throw new HttpError(404, 'not_found');
    throw e;
  }
});
