import { emailBookingList } from '../../lib/email.js';
import { getDb } from '../../lib/firebase.js';
import { HttpError, endpoint } from '../../lib/http.js';
import { ReservationError, lookupBooking } from '../../lib/reservations.js';

// POST /api/bookings/lookup — public ("Find my booking"), by reference OR email:
//   { bookingReference } → { bookingReference, accessKey }        404 not_found
//   { email }            → { emailed: true }  The booker is emailed their upcoming booking
//                          references. The answer is the same whether or not the address has
//                          bookings, so this can't be used to learn who booked what.
export default endpoint({ methods: ['POST'] }, async (body) => {
  const db = getDb();
  if (typeof body.bookingReference === 'string' && body.bookingReference.trim()) {
    try {
      return { body: await lookupBooking(db, { bookingReference: body.bookingReference }) };
    } catch (e) {
      if (e instanceof ReservationError) throw new HttpError(404, 'not_found');
      throw e;
    }
  }
  const email = typeof body.email === 'string' ? body.email.trim() : '';
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(email) || email.length > 100) {
    throw new HttpError(400, 'validation', { fields: { email: 'Enter your booking reference or a valid email.' } });
  }
  await emailBookingList(db, email);
  return { body: { emailed: true } };
});
