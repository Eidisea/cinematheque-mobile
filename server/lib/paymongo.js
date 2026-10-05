// PayMongo (test mode): hosted Checkout Sessions. Only this server talks to PayMongo — the
// secret key lives in the PAYMONGO_SECRET_KEY environment variable and never reaches an app.
//
// The rest of the server uses the small interface returned by createPaymongo(), so tests
// can pass a fake instead of calling PayMongo.

import { createHmac, timingSafeEqual } from 'node:crypto';

const API = 'https://api.paymongo.com/v1';

export class PaymongoError extends Error {
  constructor(status, detail) {
    super(`PayMongo answered ${status}: ${detail}`);
    this.name = 'PaymongoError';
    this.status = status;
  }
}

export function createPaymongo({ secretKey, fetchImpl = fetch }) {
  const auth = `Basic ${Buffer.from(`${secretKey}:`).toString('base64')}`;

  async function call(method, path, body) {
    const res = await fetchImpl(`${API}${path}`, {
      method,
      headers: { Authorization: auth, 'Content-Type': 'application/json', Accept: 'application/json' },
      body: body ? JSON.stringify(body) : undefined,
      signal: AbortSignal.timeout(10_000),
    });
    const json = await res.json().catch(() => null);
    if (!res.ok) throw new PaymongoError(res.status, JSON.stringify(json?.errors ?? json));
    return json.data;
  }

  return {
    /** → { id: 'cs_…', attributes: { checkout_url, status, payments, … } } */
    createCheckoutSession: (attributes) => call('POST', '/checkout_sessions', { data: { attributes } }),
    getCheckoutSession: (id) => call('GET', `/checkout_sessions/${encodeURIComponent(id)}`),
    expireCheckoutSession: (id) => call('POST', `/checkout_sessions/${encodeURIComponent(id)}/expire`),
  };
}

/** The real client, or null when PAYMONGO_SECRET_KEY is not set (local emulator work). */
export function getPaymongo() {
  const secretKey = process.env.PAYMONGO_SECRET_KEY?.trim(); // a pasted value may end in a line break
  return secretKey ? createPaymongo({ secretKey }) : null;
}

/**
 * The successful payment of a checkout session, or null if it is not paid.
 * → { id: 'pay_…', amountCentavos, currency, paidAt: Date, method }
 */
export function paidPaymentOf(session) {
  const a = session?.attributes ?? {};
  const payments = [...(a.payments ?? []), ...(a.payment_intent?.attributes?.payments ?? [])];
  const paid = payments.find((p) => p?.attributes?.status === 'paid');
  if (!paid) return null;
  const p = paid.attributes;
  return {
    id: paid.id,
    amountCentavos: p.amount,
    currency: p.currency,
    paidAt: new Date((p.paid_at ?? a.paid_at) * 1000),
    method: a.payment_method_used ?? p.source?.type ?? null,
  };
}

const sameHex = (a, b) => {
  const x = Buffer.from(String(a ?? ''), 'utf8');
  const y = Buffer.from(String(b ?? ''), 'utf8');
  return x.length === y.length && timingSafeEqual(x, y);
};

/**
 * Checks the Paymongo-Signature header against the RAW request body (HMAC-SHA256 with the
 * webhook's secret). PayMongo documents two shapes, both accepted:
 *   "t=<unix>,te=<test sig>,li=<live sig>"  → signs "<t>.<body>"
 *   "<hex>"                                   → signs "<body>"
 */
export function verifyWebhookSignature(rawBody, header, secret) {
  if (!secret || typeof header !== 'string' || !header) return false;
  const hmac = (data) => createHmac('sha256', secret).update(data).digest('hex');

  if (header.includes('t=')) {
    const parts = Object.fromEntries(header.split(',').map((kv) => kv.trim().split('=')));
    if (!parts.t) return false;
    const expected = hmac(Buffer.concat([Buffer.from(`${parts.t}.`), Buffer.from(rawBody)]));
    return sameHex(expected, parts.te) || sameHex(expected, parts.li);
  }
  return sameHex(hmac(Buffer.from(rawBody)), header.trim());
}
