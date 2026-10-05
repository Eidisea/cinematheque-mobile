// Payment tests against the LOCAL Firestore emulator, with a FAKE PayMongo (no network):
//   firebase emulators:exec --only firestore --project demo-ccd "npm --prefix server test"

import assert from 'node:assert/strict';
import { createHmac } from 'node:crypto';
import { Readable } from 'node:stream';
import { beforeEach, describe, test } from 'node:test';

import { Timestamp } from 'firebase-admin/firestore';

import { createExpiryHandler } from '../api/cron/expire-unpaid.js';
import { createWebhookHandler } from '../api/paymongo/webhook.js';
import { getDb } from '../lib/firebase.js';
import {
  PaymentError,
  expireReservation,
  findExpiredUnpaid,
  refreshPayment,
  settlePayment,
  startCheckout,
} from '../lib/payments.js';
import { paidPaymentOf, verifyWebhookSignature } from '../lib/paymongo.js';
import { createReservation } from '../lib/reservations.js';
import { validateCreateReservation } from '../lib/validate.js';

if (!process.env.FIRESTORE_EMULATOR_HOST) throw new Error('Run inside `firebase emulators:exec` only.');

const db = getDb();
const projectId = process.env.GCLOUD_PROJECT || 'demo-ccd';
const now = new Date();
const inMinutes = (m) => new Date(now.getTime() + m * 60_000);
const RETURN_URL = 'https://api.test/api/payments/return';

async function reset() {
  await fetch(`http://${process.env.FIRESTORE_EMULATOR_HOST}/emulator/v1/projects/${projectId}/databases/(default)/documents`, { method: 'DELETE' });
  const seats = [];
  for (const row of 'ABCDEFGHIJ') for (let n = 1; n <= 12; n++) seats.push({ label: `${row}${n}`, row, number: n, isActive: true });
  await db.doc('settings/seatLayout').set({ seats });
  for (const [id, type, price] of [['free1', 'free', null], ['paid1', 'paid', 15000]]) {
    await db.doc(`screenings/${id}`).set({
      eventTitle: `Screening ${id}`,
      movieId: null,
      movie: null,
      startAt: Timestamp.fromDate(inMinutes(24 * 60)),
      endAt: Timestamp.fromDate(inMinutes(26 * 60)),
      type,
      priceCentavos: price,
      capacity: 120,
      seatHolds: {},
      hasReservations: false,
    });
  }
}

const attendee = (first) => ({
  firstName: first,
  lastName: 'Dela Cruz',
  age: 30,
  sex: 'M',
  companySchool: 'Ateneo de Davao',
  contactNo: '09171234567',
  email: `${first.toLowerCase()}@example.com`,
  isPwd: false,
});

/** Books [seats] for the paid (or free) screening at [at]; returns { id, accessKey }. */
async function book({ seats = ['A1', 'A2'], screeningId = 'paid1', at = now, expire } = {}) {
  const { value, errors } = validateCreateReservation({
    screeningId,
    seats,
    bookerSeat: seats[0],
    booker: { firstName: 'Juan', lastName: 'Dela Cruz', contactNo: '0917 123 4567', email: 'juan@example.com' },
    attendees: Object.fromEntries(seats.map((s, i) => [s, attendee(`Guest${i}`)])),
  });
  assert.deepEqual(errors, {});
  const created = await createReservation(db, value, { now: at, ...(expire ? { expire } : {}) });
  const snap = await db.collection('reservations').where('accessKey', '==', created.accessKey).get();
  return { id: snap.docs[0].id, accessKey: created.accessKey };
}

/** Stands in for PayMongo: sessions live in memory; pay() marks one paid. */
function fakePaymongo() {
  const sessions = new Map();
  let n = 0;
  return {
    created: [],
    expired: [],
    async createCheckoutSession(attributes) {
      const id = `cs_test_${++n}`;
      this.created.push(attributes);
      sessions.set(id, { id, attributes: { ...attributes, checkout_url: `https://checkout.test/${id}`, status: 'active', payments: [] } });
      return structuredClone(sessions.get(id));
    },
    async getCheckoutSession(id) {
      return structuredClone(sessions.get(id));
    },
    async expireCheckoutSession(id) {
      sessions.get(id).attributes.status = 'expired';
      this.expired.push(id);
    },
    pay(id, { at = now, amount } = {}) {
      const s = sessions.get(id).attributes;
      s.status = 'active';
      s.payments = [{
        id: `pay_${id}`,
        type: 'payment',
        attributes: {
          amount: amount ?? s.line_items.reduce((t, l) => t + l.amount * l.quantity, 0),
          currency: 'PHP',
          status: 'paid',
          paid_at: Math.floor(at.getTime() / 1000),
          source: { type: 'gcash' },
        },
      }];
    },
  };
}

const docs = async (id, accessKey) => {
  const [r, p, v, s] = await Promise.all([
    db.doc(`reservations/${id}`).get(),
    db.doc(`payments/${id}`).get(),
    db.doc(`bookingViews/${accessKey}`).get(),
    db.doc('screenings/paid1').get(),
  ]);
  return { reservation: r.data(), payment: p.data(), view: v.data(), holds: s.data().seatHolds };
};

describe('checkout', () => {
  beforeEach(reset);

  test('a hosted checkout for exactly price × seats, labelled with the booking; reused while open', async () => {
    const pm = fakePaymongo();
    const { id, accessKey } = await book();
    const first = await startCheckout(db, pm, { accessKey, returnUrl: RETURN_URL });
    assert.equal(first.checkoutUrl, 'https://checkout.test/cs_test_1');

    const attrs = pm.created[0];
    assert.deepEqual(attrs.line_items, [{ name: 'Screening paid1 · admission', amount: 15000, currency: 'PHP', quantity: 2 }]);
    assert.deepEqual(attrs.metadata, { reservationId: id });
    assert.match(attrs.reference_number, /^CCD-/);
    assert.equal(attrs.success_url, `${RETURN_URL}?result=paid`);
    assert.equal((await db.doc(`payments/${id}`).get()).data().checkoutSessionId, 'cs_test_1');

    const again = await startCheckout(db, pm, { accessKey, returnUrl: RETURN_URL });
    assert.equal(again.checkoutUrl, first.checkoutUrl);
    assert.equal(pm.created.length, 1, 'no second session while the first is open');
  });

  test('free bookings, expired holds and a missing PayMongo key are refused', async () => {
    const pm = fakePaymongo();
    const free = await book({ screeningId: 'free1' });
    await assert.rejects(startCheckout(db, pm, { accessKey: free.accessKey, returnUrl: RETURN_URL }), { code: 'not_payable' });

    const old = await book({ seats: ['B1'], at: inMinutes(-20) });
    await assert.rejects(startCheckout(db, pm, { accessKey: old.accessKey, returnUrl: RETURN_URL }), { code: 'payment_expired' });

    const ok = await book({ seats: ['C1'] });
    await assert.rejects(startCheckout(db, null, { accessKey: ok.accessKey, returnUrl: RETURN_URL }), PaymentError);
    await assert.rejects(startCheckout(db, pm, { accessKey: 'x'.repeat(43), returnUrl: RETURN_URL }), { code: 'not_found' });
  });

  test('already paid on PayMongo → recorded instead of a new checkout', async () => {
    const pm = fakePaymongo();
    const { id, accessKey } = await book();
    await startCheckout(db, pm, { accessKey, returnUrl: RETURN_URL });
    pm.pay('cs_test_1');
    assert.deepEqual(await startCheckout(db, pm, { accessKey, returnUrl: RETURN_URL }), { alreadyPaid: true });
    assert.equal((await docs(id, accessKey)).reservation.status, 'confirmed');
  });
});

describe('verifying payments', () => {
  beforeEach(reset);

  test('paid in time, exact amount → confirmed; seats confirmed with no expiry; customer copy updated', async () => {
    const pm = fakePaymongo();
    const { id, accessKey } = await book();
    await startCheckout(db, pm, { accessKey, returnUrl: RETURN_URL });
    pm.pay('cs_test_1');

    assert.deepEqual(await refreshPayment(db, pm, { accessKey }), { outcome: 'confirmed' });
    const d = await docs(id, accessKey);
    assert.equal(d.reservation.status, 'confirmed');
    assert.equal(d.reservation.expiresAt, null);
    assert.equal(d.payment.status, 'verified');
    assert.equal(d.payment.paymongoPaymentId, 'pay_cs_test_1');
    assert.equal(d.payment.method, 'gcash');
    assert.equal(d.payment.needsRefund, false);
    assert.deepEqual(d.holds.A1, { reservationId: id, state: 'confirmed', expiresAt: null });
    assert.equal(d.view.status, 'confirmed');
    assert.equal(d.view.paymentStatus, 'verified');
    assert.equal(d.view.expiresAt, null);
  });

  test('settling twice changes nothing (webhook + refresh can both arrive)', async () => {
    const pm = fakePaymongo();
    const { id, accessKey } = await book();
    await startCheckout(db, pm, { accessKey, returnUrl: RETURN_URL });
    pm.pay('cs_test_1');
    const session = await pm.getCheckoutSession('cs_test_1');
    assert.equal((await settlePayment(db, { reservationId: id, session })).outcome, 'confirmed');
    assert.equal((await settlePayment(db, { reservationId: id, session })).outcome, 'already_recorded');
    assert.deepEqual(await refreshPayment(db, pm, { accessKey }), { outcome: 'unchanged' });
  });

  test('a wrong amount never confirms', async () => {
    const pm = fakePaymongo();
    const { id, accessKey } = await book();
    await startCheckout(db, pm, { accessKey, returnUrl: RETURN_URL });
    pm.pay('cs_test_1', { amount: 100 });
    assert.equal((await refreshPayment(db, pm, { accessKey })).outcome, 'amount_mismatch');
    const d = await docs(id, accessKey);
    assert.equal(d.reservation.status, 'pending');
    assert.equal(d.payment.status, 'pending');
  });

  test('not paid yet → nothing changes', async () => {
    const pm = fakePaymongo();
    const { id, accessKey } = await book();
    await startCheckout(db, pm, { accessKey, returnUrl: RETURN_URL });
    assert.equal((await refreshPayment(db, pm, { accessKey })).outcome, 'unpaid');
    assert.equal((await docs(id, accessKey)).reservation.status, 'pending');
  });

  test('LATE payment (after the 15 minutes) → recorded, flagged for refund, booking cancelled, seats released', async () => {
    const pm = fakePaymongo();
    const { id, accessKey } = await book({ at: inMinutes(-20) }); // deadline was 5 minutes ago
    await startCheckout(db, pm, { accessKey, returnUrl: RETURN_URL, now: inMinutes(-19) });
    pm.pay('cs_test_1', { at: now });

    assert.equal((await refreshPayment(db, pm, { accessKey })).outcome, 'late_needs_refund');
    const d = await docs(id, accessKey);
    assert.equal(d.reservation.status, 'cancelled');
    assert.equal(d.reservation.cancellationReason, 'payment_expired');
    assert.equal(d.payment.status, 'verified');
    assert.equal(d.payment.needsRefund, true);
    assert.equal(d.holds.A1, undefined);
    assert.equal(d.view.status, 'cancelled');
    assert.equal(d.view.paymentStatus, 'verified', 'the app can tell the customer a refund is due');
  });

  test('paid in time but the webhook came after someone took an expired seat → refund flag, not a double booking', async () => {
    const pm = fakePaymongo();
    const a = await book({ at: inMinutes(-20) });
    await startCheckout(db, pm, { accessKey: a.accessKey, returnUrl: RETURN_URL, now: inMinutes(-19) });
    pm.pay('cs_test_1', { at: inMinutes(-6) }); // inside the window, but nobody has recorded it yet

    const b = await book({ seats: ['A1'], expire: (id) => expireReservation(db, pm, id, now) });
    const d = await docs(a.id, a.accessKey);
    assert.equal(d.reservation.status, 'cancelled');
    assert.equal(d.payment.needsRefund, true);
    assert.equal(d.holds.A1.reservationId, b.id, 'A1 belongs to the new booking');
    assert.equal(d.holds.A2, undefined, "the late booking's other seat is released");
  });
});

describe('expiry job', () => {
  beforeEach(reset);
  const CRON_SECRET = 'test-cron-secret';
  const run = async (pm, auth = `Bearer ${CRON_SECRET}`, saved = CRON_SECRET) => {
    process.env.CRON_SECRET = saved;
    const handler = createExpiryHandler({ getDb: () => db, getPaymongo: () => pm });
    const res = { statusCode: 200, setHeader() {}, end(chunk) { this.body = JSON.parse(chunk); } };
    await handler({ method: 'GET', headers: auth ? { authorization: auth } : {} }, res);
    return { status: res.statusCode, body: res.body };
  };

  test('only bookings whose 15 minutes are over are found (free and paid-in-time ones are not)', async () => {
    await book({ screeningId: 'free1', at: inMinutes(-60) });
    await book({ seats: ['B1'] });
    const old = await book({ seats: ['C1'], at: inMinutes(-20) });
    assert.deepEqual(await findExpiredUnpaid(db, now), [old.id]);
  });

  test('needs the cron secret', async () => {
    assert.equal((await run(fakePaymongo(), null)).status, 401);
    assert.equal((await run(fakePaymongo(), 'Bearer wrong')).status, 401);
  });

  test('a secret saved in Vercel with a trailing line break (pasted from PowerShell) still matches', async () => {
    assert.equal((await run(fakePaymongo(), `Bearer ${CRON_SECRET}`, `${CRON_SECRET}\r\n`)).status, 200);
  });

  test('expires unpaid holds (closing their checkout), but confirms one PayMongo says was paid in time', async () => {
    const pm = fakePaymongo();
    const unpaid = await book({ seats: ['A1'], at: inMinutes(-20) });
    const paid = await book({ seats: ['B1'], at: inMinutes(-20) });
    await startCheckout(db, pm, { accessKey: unpaid.accessKey, returnUrl: RETURN_URL, now: inMinutes(-19) }); // cs_test_1
    await startCheckout(db, pm, { accessKey: paid.accessKey, returnUrl: RETURN_URL, now: inMinutes(-19) }); // cs_test_2
    pm.pay('cs_test_2', { at: inMinutes(-10) });

    const { status, body } = await run(pm);
    assert.equal(status, 200);
    assert.deepEqual(body, { checked: 2, outcomes: { expired: 1, confirmed: 1 }, failed: 0 });
    assert.deepEqual(pm.expired, ['cs_test_1']);
    assert.equal((await docs(unpaid.id, unpaid.accessKey)).reservation.cancellationReason, 'payment_expired');
    assert.equal((await docs(paid.id, paid.accessKey)).reservation.status, 'confirmed');
  });

  test('without PayMongo configured, a booking that has a checkout is never dropped unchecked', async () => {
    const pm = fakePaymongo();
    const b = await book({ seats: ['A1'], at: inMinutes(-20) });
    await startCheckout(db, pm, { accessKey: b.accessKey, returnUrl: RETURN_URL, now: inMinutes(-19) });
    const { body } = await run(null);
    assert.deepEqual(body, { checked: 1, outcomes: {}, failed: 1 });
    assert.equal((await docs(b.id, b.accessKey)).reservation.status, 'pending');
  });
});

describe('PayMongo webhook', () => {
  beforeEach(reset);
  const SECRET = 'whsk_test_secret';
  const sign = (raw, t = 1700000000) => `t=${t},te=${createHmac('sha256', SECRET).update(`${t}.${raw}`).digest('hex')},li=`;
  const deliver = async (pm, event, signature) => {
    process.env.PAYMONGO_WEBHOOK_SECRET = SECRET;
    const raw = JSON.stringify(event);
    const req = Readable.from([Buffer.from(raw)]);
    req.method = 'POST';
    req.headers = { 'paymongo-signature': signature ?? sign(raw) };
    const res = { statusCode: 200, setHeader() {}, end(chunk) { this.body = JSON.parse(chunk); } };
    await createWebhookHandler({ getDb: () => db, getPaymongo: () => pm })(req, res);
    return { status: res.statusCode, body: res.body };
  };
  const paidEvent = (session) => ({ data: { id: 'evt_1', attributes: { type: 'checkout_session.payment.paid', data: session } } });

  test('a signed "payment.paid" confirms the booking — after asking PayMongo again', async () => {
    const pm = fakePaymongo();
    const { id, accessKey } = await book();
    await startCheckout(db, pm, { accessKey, returnUrl: RETURN_URL });
    pm.pay('cs_test_1');
    const { status, body } = await deliver(pm, paidEvent(await pm.getCheckoutSession('cs_test_1')));
    assert.equal(status, 200);
    assert.equal(body.outcome, 'confirmed');
    assert.equal((await docs(id, accessKey)).reservation.status, 'confirmed');
  });

  test('bad signature → 401 and nothing changes', async () => {
    const pm = fakePaymongo();
    const { id, accessKey } = await book();
    await startCheckout(db, pm, { accessKey, returnUrl: RETURN_URL });
    pm.pay('cs_test_1');
    const { status } = await deliver(pm, paidEvent(await pm.getCheckoutSession('cs_test_1')), 't=1,te=deadbeef,li=');
    assert.equal(status, 401);
    assert.equal((await docs(id, accessKey)).reservation.status, 'pending');
  });

  test('a forged "paid" body for an unpaid session confirms nothing (PayMongo is asked)', async () => {
    const pm = fakePaymongo();
    const { id, accessKey } = await book();
    await startCheckout(db, pm, { accessKey, returnUrl: RETURN_URL });
    const forged = await pm.getCheckoutSession('cs_test_1');
    forged.attributes.payments = [{ id: 'pay_x', attributes: { status: 'paid', amount: 30000, currency: 'PHP', paid_at: 1 } }];
    const { body } = await deliver(pm, paidEvent(forged));
    assert.equal(body.outcome, 'unpaid');
    assert.equal((await docs(id, accessKey)).reservation.status, 'pending');
  });

  test('other events are acknowledged and ignored', async () => {
    const { status, body } = await deliver(fakePaymongo(), { data: { attributes: { type: 'payment.refunded', data: {} } } });
    assert.equal(status, 200);
    assert.deepEqual(body, { received: true });
  });
});

describe('PayMongo helpers', () => {
  test('signature: both documented header shapes; wrong secret or tampered body fails', () => {
    const raw = Buffer.from('{"a":1}');
    const hex = createHmac('sha256', 's').update(raw).digest('hex');
    assert.equal(verifyWebhookSignature(raw, hex, 's'), true);
    const t = createHmac('sha256', 's').update(`9.${raw}`).digest('hex');
    assert.equal(verifyWebhookSignature(raw, `t=9,te=,li=${t}`, 's'), true);
    assert.equal(verifyWebhookSignature(raw, hex, 'other'), false);
    assert.equal(verifyWebhookSignature(Buffer.from('{"a":2}'), hex, 's'), false);
    assert.equal(verifyWebhookSignature(raw, undefined, 's'), false);
    assert.equal(verifyWebhookSignature(raw, hex, undefined), false);
  });

  test('a session counts as paid only with a payment whose status is "paid"', () => {
    assert.equal(paidPaymentOf({ attributes: { payments: [] } }), null);
    assert.equal(paidPaymentOf({ attributes: { payments: [{ id: 'p', attributes: { status: 'failed' } }] } }), null);
    const p = paidPaymentOf({
      attributes: { payment_method_used: 'gcash', payment_intent: { attributes: { payments: [{ id: 'p', attributes: { status: 'paid', amount: 5, currency: 'PHP', paid_at: 10 } }] } } },
    });
    assert.deepEqual(p, { id: 'p', amountCentavos: 5, currency: 'PHP', paidAt: new Date(10_000), method: 'gcash' });
  });
});
