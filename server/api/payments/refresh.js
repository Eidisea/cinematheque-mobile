import { getDb } from '../../lib/firebase.js';
import { HttpError, endpoint } from '../../lib/http.js';
import { refreshPayment } from '../../lib/payments.js';
import { PaymongoError, getPaymongo } from '../../lib/paymongo.js';
import { ReservationError } from '../../lib/reservations.js';

// POST /api/payments/refresh — "has my payment gone through?" Asks PayMongo directly, so a
// booking is confirmed even if the webhook is late. The app then sees the change in its
// booking view. { accessKey } → { outcome }
export default endpoint({ methods: ['POST'] }, async (body) => {
  try {
    return { body: await refreshPayment(getDb(), getPaymongo(), { accessKey: body.accessKey }) };
  } catch (e) {
    if (e instanceof ReservationError) throw new HttpError(404, 'not_found');
    if (e instanceof PaymongoError) {
      console.error(e);
      throw new HttpError(502, 'payment_provider_error');
    }
    throw e;
  }
});
