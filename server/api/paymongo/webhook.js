import { getDb } from '../../lib/firebase.js';
import { HttpError, send } from '../../lib/http.js';
import { settlePayment } from '../../lib/payments.js';
import { getPaymongo, verifyWebhookSignature } from '../../lib/paymongo.js';
import { ReservationError } from '../../lib/reservations.js';

// POST /api/paymongo/webhook — PayMongo reports "checkout_session.payment.paid".
// 1. The signature is checked against the RAW body (PAYMONGO_WEBHOOK_SECRET).
// 2. The session is fetched again from PayMongo with our secret key — that answer, not the
//    webhook body, decides. 3. settlePayment() confirms or flags a late payment (idempotent).
// Unknown events get 200 so PayMongo doesn't retry them; real failures get 500 so it does.

const MAX_BODY_BYTES = 256 * 1024;

async function readRaw(req) {
  if (Buffer.isBuffer(req.rawBody)) return req.rawBody;
  const chunks = [];
  let size = 0;
  for await (const chunk of req) {
    size += chunk.length;
    if (size > MAX_BODY_BYTES) throw new HttpError(413, 'body_too_large');
    chunks.push(Buffer.from(chunk));
  }
  return Buffer.concat(chunks);
}

/** [deps] lets tests pass a fake PayMongo; Vercel uses the default export. */
export const createWebhookHandler = (deps) => async function handler(req, res) {
  if (req.method !== 'POST') return send(res, 405, { error: 'method_not_allowed' });
  const secret = process.env.PAYMONGO_WEBHOOK_SECRET?.trim();
  const paymongo = deps.getPaymongo();
  if (!secret || !paymongo) return send(res, 503, { error: 'not_configured' });

  try {
    const raw = await readRaw(req);
    if (!verifyWebhookSignature(raw, req.headers['paymongo-signature'], secret)) {
      return send(res, 401, { error: 'invalid_signature' });
    }
    const event = JSON.parse(raw.toString('utf8'))?.data?.attributes;
    if (event?.type !== 'checkout_session.payment.paid') return send(res, 200, { received: true });

    const sessionId = event.data?.id;
    const reservationId = event.data?.attributes?.metadata?.reservationId;
    if (!sessionId || !reservationId) return send(res, 200, { received: true });

    const session = await paymongo.getCheckoutSession(sessionId);
    if (session.attributes?.metadata?.reservationId !== reservationId) return send(res, 200, { received: true });
    const { outcome } = await settlePayment(deps.getDb(), { reservationId, session });
    return send(res, 200, { received: true, outcome });
  } catch (e) {
    if (e instanceof HttpError) return send(res, e.status, { error: e.code });
    if (e instanceof SyntaxError) return send(res, 400, { error: 'invalid_json' });
    if (e instanceof ReservationError) return send(res, 200, { received: true }); // not one of ours
    console.error('Webhook failed', e);
    return send(res, 500, { error: 'server_error' });
  }
};

export default createWebhookHandler({ getDb, getPaymongo });
