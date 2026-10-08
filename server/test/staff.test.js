// Staff booking actions against the LOCAL Firestore emulator (fake sign-in, fake mailer):
//   firebase emulators:exec --only firestore --project demo-ccd "npm --prefix server test"

import assert from 'node:assert/strict';
import { Readable } from 'node:stream';
import { beforeEach, describe, test } from 'node:test';

import { Timestamp } from 'firebase-admin/firestore';

import { createStaffReservationsHandler } from '../api/staff/reservations.js';
import { getDb } from '../lib/firebase.js';
import { startCheckout } from '../lib/payments.js';
import { createReservation } from '../lib/reservations.js';
import { validateCreateReservation } from '../lib/validate.js';

if (!process.env.FIRESTORE_EMULATOR_HOST) throw new Error('Run inside `firebase emulators:exec` only.');

const db = getDb();
const projectId = process.env.GCLOUD_PROJECT || 'demo-ccd';
const now = new Date();
const inMinutes = (m) => new Date(now.getTime() + m * 60_000);

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
  await db.doc('staff/s1').set({ firstName: 'Ana', lastName: 'Reyes', email: 'ana@ccd.test', position: 'avt', isActive: true });
  await db.doc('staff/s2').set({ firstName: 'Ben', lastName: 'Santos', email: 'ben@ccd.test', position: 'pdo', isActive: false });
}

const attendee = (first) => ({
  firstName: first,
  lastName: 'Dela Cruz',
  age: 30,
  sex: 'F',
  companySchool: 'UP Mindanao',
  contactNo: '09171234567',
  email: `${first.toLowerCase()}@example.com`,
  isPwd: false,
});

async function book(screeningId = 'free1', seats = ['A1', 'A2']) {
  const { value, errors } = validateCreateReservation({
    screeningId,
    seats,
    bookerSeat: seats[0],
    booker: { firstName: 'Maria', lastName: 'Dela Cruz', contactNo: '0917 123 4567', email: 'maria@example.com' },
    attendees: Object.fromEntries(seats.map((s, i) => [s, attendee(i ? 'Jose' : 'Maria')])),
  });
  assert.deepEqual(errors, {});
  return createReservation(db, value, { now });
}

const tokens = { 'tok-s1': 's1', 'tok-s2': 's2', 'tok-nobody': 'x' };
const verify = async (t) => {
  if (!tokens[t]) throw new Error('bad token');
  return tokens[t];
};

function fakeMailer() {
  return {
    sent: [],
    async send(m) {
      this.sent.push(m);
    },
  };
}

function fakePaymongo() {
  const sessions = new Map();
  return {
    expired: [],
    async createCheckoutSession(attributes) {
      const id = `cs_${sessions.size + 1}`;
      sessions.set(id, { id, attributes: { ...attributes, checkout_url: `https://checkout.test/${id}`, status: 'active', payments: [] } });
      return sessions.get(id);
    },
    async getCheckoutSession(id) {
      return sessions.get(id);
    },
    async expireCheckoutSession(id) {
      this.expired.push(id);
    },
  };
}

async function call(body, { token = 'tok-s1', mailer = fakeMailer(), paymongo = null } = {}) {
  const handler = createStaffReservationsHandler({ getDb: () => db, getPaymongo: () => paymongo, verify, mailer });
  const req = Readable.from([Buffer.from(JSON.stringify(body))]);
  req.method = 'POST';
  req.headers = token ? { authorization: `Bearer ${token}` } : {};
  const res = { statusCode: 200, setHeader() {}, end(chunk) { this.body = chunk ? JSON.parse(chunk) : null; } };
  await handler(req, res);
  return { status: res.statusCode, body: res.body };
}

const idOf = async (accessKey) => (await db.collection('reservations').where('accessKey', '==', accessKey).get()).docs[0].id;
const data = async (path) => (await db.doc(path).get()).data();

describe('staff sign-in', () => {
  beforeEach(reset);

  test('no token or a bad one → 401; a login without an active staff record → 403', async () => {
    assert.equal((await call({ action: 'approve', reservationId: 'x' }, { token: null })).status, 401);
    assert.equal((await call({ action: 'approve', reservationId: 'x' }, { token: 'forged' })).status, 401);
    assert.deepEqual(await call({ action: 'approve', reservationId: 'x' }, { token: 'tok-nobody' }), { status: 403, body: { error: 'not_staff' } });
    assert.equal((await call({ action: 'approve', reservationId: 'x' }, { token: 'tok-s2' })).status, 403, 'deactivated');
  });

  test('unknown action, missing or malformed IDs → 400; unknown booking → 404', async () => {
    assert.equal((await call({ action: 'delete', reservationId: 'x' })).status, 400);
    assert.equal((await call({ action: 'approve' })).status, 400);
    assert.equal((await call({ action: 'approve', reservationId: '../x' })).status, 400);
    assert.equal((await call({ action: 'approve', reservationId: 'nope' })).status, 404);
  });
});

describe('approving free bookings', () => {
  beforeEach(reset);

  test('pending free → confirmed: seats confirmed, customer copy updated, e-ticket emailed, who approved recorded', async () => {
    const created = await book();
    const id = await idOf(created.accessKey);
    const mailer = fakeMailer();
    const out = await call({ action: 'approve', reservationId: id }, { mailer });
    assert.deepEqual(out, { status: 200, body: { status: 'confirmed', bookingReference: created.bookingReference } });

    const r = await data(`reservations/${id}`);
    assert.equal(r.status, 'confirmed');
    assert.equal(r.confirmedBy, 's1');
    assert.equal((await data('screenings/free1')).seatHolds.A1.state, 'confirmed');
    assert.equal((await data(`bookingViews/${created.accessKey}`)).status, 'confirmed');
    assert.equal(mailer.sent.length, 1);
    assert.match(mailer.sent[0].subject, /^Your e-ticket · CCD-/);
  });

  test('paid bookings are never approved by staff; approving twice is refused', async () => {
    const paid = await idOf((await book('paid1', ['B1'])).accessKey);
    const out = await call({ action: 'approve', reservationId: paid });
    assert.equal(out.status, 409);
    assert.equal(out.body.error, 'not_approvable');
    assert.equal((await data(`reservations/${paid}`)).status, 'pending');

    const free = await idOf((await book()).accessKey);
    assert.equal((await call({ action: 'approve', reservationId: free })).status, 200);
    assert.equal((await call({ action: 'approve', reservationId: free })).status, 409);
  });

  test('"approve all" confirms every pending free booking of the screening, nothing else', async () => {
    const a = await idOf((await book('free1', ['A1'])).accessKey);
    const b = await idOf((await book('free1', ['A2', 'A3'])).accessKey);
    const paid = await idOf((await book('paid1', ['C1'])).accessKey);
    const out = await call({ action: 'approveAll', screeningId: 'free1' });
    assert.deepEqual(out, { status: 200, body: { approved: 2, failed: [] } });
    assert.equal((await data(`reservations/${a}`)).status, 'confirmed');
    assert.equal((await data(`reservations/${b}`)).status, 'confirmed');
    assert.equal((await data(`reservations/${paid}`)).status, 'pending');
  });
});

describe('cancelling and resending', () => {
  beforeEach(reset);

  test('staff cancel a confirmed booking: seats released, who cancelled recorded, email sent', async () => {
    const created = await book();
    const id = await idOf(created.accessKey);
    await call({ action: 'approve', reservationId: id });
    const mailer = fakeMailer();
    const out = await call({ action: 'cancel', reservationId: id }, { mailer });
    assert.equal(out.status, 200);
    assert.equal(out.body.cancellationReason, 'staff_cancelled');

    const r = await data(`reservations/${id}`);
    assert.equal(r.status, 'cancelled');
    assert.equal(r.cancelledBy, 's1');
    assert.equal((await data('screenings/free1')).seatHolds.A1, undefined);
    assert.match(mailer.sent[0].subject, /^Reservation cancelled/);
    assert.equal((await call({ action: 'cancel', reservationId: id })).status, 409, 'already cancelled');
  });

  test("cancelling an unpaid booking closes its PayMongo checkout so nobody pays for it", async () => {
    const created = await book('paid1', ['D1']);
    const id = await idOf(created.accessKey);
    const paymongo = fakePaymongo();
    await startCheckout(db, paymongo, { accessKey: created.accessKey, returnUrl: 'https://x.test/r' });
    await call({ action: 'cancel', reservationId: id }, { paymongo });
    assert.deepEqual(paymongo.expired, ['cs_1']);
  });

  test('cancelling a PAID confirmed booking flags its payment for refund', async () => {
    const created = await book('paid1', ['E1']);
    const id = await idOf(created.accessKey);
    await db.doc(`reservations/${id}`).update({ status: 'confirmed', expiresAt: null });
    await db.doc(`payments/${id}`).update({ status: 'verified', paidAt: Timestamp.fromDate(now) });
    assert.equal((await call({ action: 'cancel', reservationId: id })).status, 200);
    assert.equal((await data(`payments/${id}`)).needsRefund, true);
  });

  test('resend sends the current email again', async () => {
    const id = await idOf((await book()).accessKey);
    const mailer = fakeMailer();
    await call({ action: 'approve', reservationId: id }, { mailer });
    const out = await call({ action: 'resend', reservationId: id }, { mailer });
    assert.deepEqual(out.body, { email: 'sent' });
    assert.equal(mailer.sent.length, 2);
    assert.match(mailer.sent[1].subject, /^Your e-ticket/);
  });
});
