import { getDb } from '../../lib/firebase.js';
import { HttpError, endpoint } from '../../lib/http.js';
import { PaymentError, startCheckout } from '../../lib/payments.js';
import { PaymongoError, getPaymongo } from '../../lib/paymongo.js';
import { ReservationError } from '../../lib/reservations.js';

// POST /api/payments/checkout — the customer pays a pending PAID booking.
// { accessKey } → { checkoutUrl } (PayMongo hosted page) or { alreadyPaid: true }
// 404 not_found · 409 not_payable / payment_expired · 502 payment_provider_error · 503 payments_unavailable
export default endpoint({ methods: ['POST'] }, async (body, req) => {
  const proto = req.headers['x-forwarded-proto'] ?? 'http';
  const host = req.headers['x-forwarded-host'] ?? req.headers.host;
  try {
    const out = await startCheckout(getDb(), getPaymongo(), {
      accessKey: body.accessKey,
      returnUrl: `${proto}://${host}/api/payments/return`,
    });
    return { body: out };
  } catch (e) {
    if (e instanceof ReservationError) throw new HttpError(404, 'not_found');
    if (e instanceof PaymentError) throw new HttpError(e.code === 'payments_unavailable' ? 503 : 409, e.code);
    if (e instanceof PaymongoError) {
      console.error(e);
      throw new HttpError(502, 'payment_provider_error');
    }
    throw e;
  }
});
