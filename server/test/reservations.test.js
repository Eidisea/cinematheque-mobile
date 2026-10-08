// Reservation tests against the LOCAL Firestore emulator:
//   firebase emulators:exec --only firestore --project demo-ccd "npm --prefix server test"

import assert from 'node:assert/strict';
import { Readable } from 'node:stream';
import { beforeEach, describe, test } from 'node:test';

import { Timestamp } from 'firebase-admin/firestore';

import cancelEndpoint from '../api/bookings/cancel.js';
import lookupEndpoint from '../api/bookings/lookup.js';
import createEndpoint from '../api/reservations/create.js';
import { getDb } from '../lib/firebase.js';
import { normalizeBookingReference } from '../lib/ids.js';
import { cancelReservation, createReservation, lookupBooking } from '../lib/reservations.js';
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
}

const booker = { firstName: 'Juan', middleName: '', lastName: 'Dela Cruz', contactNo: '0917 123 4567', email: 'Juan@Example.com' };
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
const request = (over = {}) => ({
  screeningId: 'free1',
  seats: ['A1', 'A2'],
  bookerSeat: 'A1',
  booker,
  attendees: { A1: attendee('Juan'), A2: attendee('Maria') },
  ...over,
});
const valid = (over) => {
  const { value, errors } = validateCreateReservation(request(over));
  assert.deepEqual(errors, {});
  return value;
};

/** Calls an endpoint the way Vercel would, returns { status, body }. */
async function call(endpoint, body) {
  const req = Readable.from([Buffer.from(JSON.stringify(body))]);
  req.method = 'POST';
  req.headers = {};
  let status;
  let payload = '';
  const res = { statusCode: 200, setHeader() {}, end(chunk) { status = this.statusCode; payload = chunk ?? ''; } };
  await endpoint(req, res);
  return { status, body: payload ? JSON.parse(payload) : null };
}

describe('validation (server side)', () => {
  test('a correct request passes and is normalised', () => {
    const v = valid();
    assert.equal(v.booker.middleName, null, 'empty optional text becomes null');
    assert.equal(v.booker.contactNo, '+639171234567', 'stored as +639…');
    assert.equal(v.attendees.A2.firstName, 'Maria');
  });

  test('required fields, formats, limits', () => {
    const { errors } = validateCreateReservation(request({
      booker: { firstName: ' ', lastName: 'X'.repeat(51), contactNo: 'abc', email: 'not-an-email' },
    }));
    assert.equal(errors['booker.firstName'], 'This field is required.');
    assert.match(errors['booker.lastName'], /at most 50/);
    assert.match(errors['booker.contactNo'], /mobile number/);
    assert.match(errors['booker.email'], /email/);
  });

  test('exactly one attendee per selected seat; booker seat must be one of them', () => {
    const { errors } = validateCreateReservation(request({ attendees: { A1: attendee('Juan'), B9: attendee('X') }, bookerSeat: 'C3' }));
    assert.ok(errors.attendees);
    assert.ok(errors['attendees.A2']);
    assert.ok(errors.bookerSeat);
  });

  test('seat list: required, max 10, no duplicates, valid labels', () => {
    assert.ok(validateCreateReservation(request({ seats: [] })).errors.seats);
    assert.ok(validateCreateReservation(request({ seats: Array.from({ length: 11 }, (_, i) => `B${i + 1}`) })).errors.seats);
    assert.ok(validateCreateReservation(request({ seats: ['A1', 'A1'] })).errors.seats);
    assert.ok(validateCreateReservation(request({ seats: ['<script>'] })).errors.seats);
  });

  test('attendee extras: age range, sex values', () => {
    const bad = { ...attendee('Ana'), age: 300, sex: 'X' };
    const { errors } = validateCreateReservation(request({ attendees: { A1: attendee('Juan'), A2: bad } }));
    assert.ok(errors['attendees.A2.age']);
    assert.ok(errors['attendees.A2.sex']);
  });

  test('every moviegoer gives age, sex, school/company, mobile and email; senior card and PWD stay optional', () => {
    const bare = { firstName: 'Ana', lastName: 'Reyes' };
    const { errors } = validateCreateReservation(request({ attendees: { A1: attendee('Juan'), A2: bare } }));
    for (const f of ['age', 'sex', 'companySchool', 'contactNo', 'email']) assert.ok(errors[`attendees.A2.${f}`], f);
    assert.equal(errors['attendees.A2.middleName'], undefined);
    assert.equal(errors['attendees.A2.seniorCardNo'], undefined);
    assert.equal(errors['attendees.A2.isPwd'], undefined);
    assert.deepEqual(Object.keys(validateCreateReservation(request()).errors), []);
  });

  test('booking references are read forgivingly', () => {
    assert.equal(normalizeBookingReference(' ccd-7kq2m9xa '), 'CCD-7KQ2M9XA');
    assert.equal(normalizeBookingReference('CCD 7KQ2M9XA'), 'CCD-7KQ2M9XA');
    assert.equal(normalizeBookingReference('7KQ2M9XA'), 'CCD-7KQ2M9XA');
    assert.equal(normalizeBookingReference('CCD-123'), null);
  });
});

describe('creating reservations', () => {
  beforeEach(reset);

  test('free screening: pending, no deadline, seats held, customer copy without sensitive details', async () => {
    const created = await createReservation(db, valid(), { now });
    assert.match(created.bookingReference, /^CCD-[A-Z2-9]{8}$/);
    assert.equal(created.status, 'pending');
    assert.equal(created.requiresPayment, false);
    assert.equal(created.expiresAt, null);

    const res = (await db.collection('reservations').where('bookingReference', '==', created.bookingReference).get()).docs[0];
    const r = res.data();
    assert.equal(r.bookerEmailLower, 'juan@example.com');
    assert.deepEqual(r.seatLabels, ['A1', 'A2']);
    assert.equal(r.seats[0].isBooker, true);
    assert.equal(r.totalCentavos, 0);
    assert.equal((await db.doc(`payments/${res.id}`).get()).exists, false, 'free → no payment record');

    const holds = (await db.doc('screenings/free1').get()).data().seatHolds;
    assert.equal(holds.A1.reservationId, res.id);
    assert.equal(holds.A1.expiresAt, null);

    const view = (await db.doc(`bookingViews/${created.accessKey}`).get()).data();
    assert.equal(view.status, 'pending');
    assert.deepEqual(view.seats, [{ label: 'A1', attendeeName: 'Juan Dela Cruz' }, { label: 'A2', attendeeName: 'Maria Dela Cruz' }]);
    const text = JSON.stringify(view);
    assert.ok(!text.includes('0917') && !text.includes('example.com') && !text.includes('"age"'), 'no contact/age data in the customer copy');
  });

  test('paid screening: pending payment for price × seats, 15-minute deadline on seats', async () => {
    const created = await createReservation(db, valid({ screeningId: 'paid1' }), { now });
    assert.equal(created.requiresPayment, true);
    assert.equal(created.totalCentavos, 30000);
    assert.equal(created.expiresAt.getTime(), now.getTime() + 15 * 60_000);

    const id = (await db.collection('reservations').where('bookingReference', '==', created.bookingReference).get()).docs[0].id;
    const payment = (await db.doc(`payments/${id}`).get()).data();
    assert.equal(payment.status, 'pending');
    assert.equal(payment.amountCentavos, 30000);
    const holds = (await db.doc('screenings/paid1').get()).data().seatHolds;
    assert.equal(holds.A2.expiresAt.toMillis(), now.getTime() + 15 * 60_000);
  });

  test('taking over an EXPIRED unpaid booking cancels it as payment_expired', async () => {
    const old = await createReservation(db, valid({ screeningId: 'paid1', seats: ['C1'], bookerSeat: null, attendees: { C1: attendee('Old') } }), {
      now: inMinutes(-20),
    });
    const fresh = await createReservation(db, valid({ screeningId: 'paid1', seats: ['C1'], bookerSeat: null, attendees: { C1: attendee('New') } }), { now });
    assert.ok(fresh.bookingReference);
    const oldView = (await db.doc(`bookingViews/${old.accessKey}`).get()).data();
    assert.equal(oldView.status, 'cancelled');
    assert.equal(oldView.cancellationReason, 'payment_expired');
  });
});

describe('lookup by reference + email', () => {
  beforeEach(reset);

  test('a reference alone opens the booking; case and spacing do not matter', async () => {
    const created = await createReservation(db, valid(), { now });
    const found = await lookupBooking(db, { bookingReference: ` ${created.bookingReference.toLowerCase()} ` });
    assert.equal(found.accessKey, created.accessKey);
    const viaApi = await call(lookupEndpoint, { bookingReference: created.bookingReference });
    assert.equal(viaApi.body.accessKey, created.accessKey);
  });

  test('unknown or malformed references → 404', async () => {
    for (const ref of ['CCD-AAAAAAAA', 'nonsense']) {
      assert.deepEqual(await call(lookupEndpoint, { bookingReference: ref }), { status: 404, body: { error: 'not_found' } });
    }
  });

  test('an email alone answers the same whether or not it has bookings (the list goes to that inbox)', async () => {
    await createReservation(db, valid(), { now });
    const known = await call(lookupEndpoint, { email: 'juan@example.com' });
    const unknown = await call(lookupEndpoint, { email: 'nobody@example.com' });
    assert.deepEqual(known, { status: 200, body: { emailed: true } });
    assert.deepEqual(unknown, known);
    assert.equal((await call(lookupEndpoint, { email: 'not-an-email' })).status, 400);
    assert.equal((await call(lookupEndpoint, {})).status, 400);
  });
});

describe('cancelling', () => {
  beforeEach(reset);

  test('customer cancels a pending booking → seats released, their copy says cancelled', async () => {
    const created = await createReservation(db, valid(), { now });
    const out = await call(cancelEndpoint, { accessKey: created.accessKey });
    assert.deepEqual(out.body, { status: 'cancelled', cancellationReason: 'customer_cancelled', bookingReference: created.bookingReference });
    assert.deepEqual((await db.doc('screenings/free1').get()).data().seatHolds, {});
    assert.equal((await db.doc(`bookingViews/${created.accessKey}`).get()).data().status, 'cancelled');

    // …and the seats can be booked again.
    assert.ok(await createReservation(db, valid(), { now }));
  });

  test('cancelling twice is refused', async () => {
    const created = await createReservation(db, valid(), { now });
    await call(cancelEndpoint, { accessKey: created.accessKey });
    const again = await call(cancelEndpoint, { accessKey: created.accessKey });
    assert.equal(again.status, 409);
  });

  test('customers cannot cancel a CONFIRMED booking (staff do that)', async () => {
    const created = await createReservation(db, valid(), { now });
    const id = (await db.collection('reservations').where('bookingReference', '==', created.bookingReference).get()).docs[0].id;
    await db.doc(`reservations/${id}`).update({ status: 'confirmed' });
    const out = await call(cancelEndpoint, { accessKey: created.accessKey });
    assert.equal(out.status, 409);
    assert.equal((await db.doc('screenings/free1').get()).data().seatHolds.A1.reservationId, id, 'seats kept');
  });

  test('staff cancellation of a confirmed booking releases its seats', async () => {
    const created = await createReservation(db, valid(), { now });
    const id = (await db.collection('reservations').where('bookingReference', '==', created.bookingReference).get()).docs[0].id;
    await db.doc(`reservations/${id}`).update({ status: 'confirmed' });
    const out = await cancelReservation(db, { reservationId: id, reason: 'staff_cancelled', now });
    assert.equal(out.cancellationReason, 'staff_cancelled');
    assert.deepEqual((await db.doc('screenings/free1').get()).data().seatHolds, {});
  });

  test('an expired unpaid booking cancelled by the customer is recorded as payment_expired', async () => {
    const created = await createReservation(db, valid({ screeningId: 'paid1' }), { now: inMinutes(-16) });
    const out = await call(cancelEndpoint, { accessKey: created.accessKey });
    assert.equal(out.body.cancellationReason, 'payment_expired');
  });

  test('unknown or malformed access keys → 404', async () => {
    assert.equal((await call(cancelEndpoint, { accessKey: 'x'.repeat(43) })).status, 404);
    assert.equal((await call(cancelEndpoint, { accessKey: 7 })).status, 404);
  });
});

describe('create endpoint (HTTP behaviour)', () => {
  beforeEach(reset);

  test('201 with reference and access key', async () => {
    const out = await call(createEndpoint, request());
    assert.equal(out.status, 201);
    assert.match(out.body.bookingReference, /^CCD-/);
    assert.ok(out.body.accessKey.length >= 40);
  });

  test('400 with per-field messages', async () => {
    const out = await call(createEndpoint, request({ booker: { ...booker, email: 'nope' } }));
    assert.equal(out.status, 400);
    assert.equal(out.body.error, 'validation');
    assert.ok(out.body.fields['booker.email']);
  });

  test('409 seats_taken names the seats', async () => {
    await call(createEndpoint, request());
    const out = await call(createEndpoint, request({ seats: ['A2', 'A3'], bookerSeat: null, attendees: { A2: attendee('X'), A3: attendee('Y') } }));
    assert.deepEqual(out, { status: 409, body: { error: 'seats_taken', seats: ['A2'] } });
  });

  test('404 unknown screening, 409 screening already started', async () => {
    assert.equal((await call(createEndpoint, request({ screeningId: 'nope' }))).status, 404);
    await db.doc('screenings/free1').update({ startAt: Timestamp.fromDate(inMinutes(-1)) });
    assert.deepEqual(await call(createEndpoint, request()), { status: 409, body: { error: 'screening_started' } });
  });

  test('broken JSON → 400, not a crash', async () => {
    const req = Readable.from([Buffer.from('{not json')]);
    req.method = 'POST';
    req.headers = {};
    let status;
    await createEndpoint(req, { statusCode: 200, setHeader() {}, end() { status = this.statusCode; } });
    assert.equal(status, 400);
  });
});
