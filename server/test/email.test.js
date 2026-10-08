// Email tests against the LOCAL Firestore emulator, with a FAKE mailer (nothing is sent):
//   firebase emulators:exec --only firestore --project demo-ccd "npm --prefix server test"

import assert from 'node:assert/strict';
import { beforeEach, describe, test } from 'node:test';

import { Timestamp } from 'firebase-admin/firestore';

import { emailBookingList, formatPeso, renderBookingList, renderEmail, sendStatusEmail } from '../lib/email.js';
import { getDb } from '../lib/firebase.js';
import { settlePayment } from '../lib/payments.js';
import { cancelReservation, createReservation } from '../lib/reservations.js';
import { validateCreateReservation } from '../lib/validate.js';

if (!process.env.FIRESTORE_EMULATOR_HOST) throw new Error('Run inside `firebase emulators:exec` only.');

const db = getDb();
const projectId = process.env.GCLOUD_PROJECT || 'demo-ccd';
const now = new Date('2026-11-20T02:00:00Z'); // 10:00 AM Manila
const start = new Date('2026-11-21T10:00:00Z'); // Sat 6:00 PM Manila

async function reset() {
  await fetch(`http://${process.env.FIRESTORE_EMULATOR_HOST}/emulator/v1/projects/${projectId}/databases/(default)/documents`, { method: 'DELETE' });
  const seats = [];
  for (const row of 'ABCDEFGHIJ') for (let n = 1; n <= 12; n++) seats.push({ label: `${row}${n}`, row, number: n, isActive: true });
  await db.doc('settings/seatLayout').set({ seats });
  for (const [id, type, price] of [['free1', 'free', null], ['paid1', 'paid', 15000]]) {
    await db.doc(`screenings/${id}`).set({
      eventTitle: id === 'paid1' ? 'Himala' : 'Film <Night> & "Talk"',
      movieId: null,
      movie: null,
      startAt: Timestamp.fromDate(start),
      endAt: Timestamp.fromDate(new Date(start.getTime() + 2 * 3600_000)),
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
  const created = await createReservation(db, value, { now });
  return created.reservationId;
}

const reservation = async (id) => (await db.doc(`reservations/${id}`).get()).data();

function fakeMailer({ fail = false } = {}) {
  return {
    sent: [],
    async send(message) {
      if (fail) throw new Error('SMTP down');
      this.sent.push(message);
    },
  };
}

describe('email templates', () => {
  beforeEach(reset);

  test('free + pending: "awaiting approval", not a ticket; HTML-escaped; Manila time; seat 1 marked as booker', async () => {
    const r = await reservation(await book());
    const m = renderEmail('pending', r);
    assert.match(m.subject, /^Reservation received · CCD-[A-Z0-9]{8}$/);
    assert.ok(m.html.includes('Awaiting approval'));
    assert.match(m.text, /not valid for entry/);
    assert.match(m.text, /Date: Saturday, November 21, 2026/);
    assert.match(m.text, /Time: 6:00 PM – 8:00 PM/);
    assert.match(m.text, /Admission: Free/);
    assert.match(m.text, /A1 {2}Maria Dela Cruz \(booker\)/);
    assert.match(m.text, /A2 {2}Jose Dela Cruz$/m);
    assert.ok(m.html.includes('Film &lt;Night&gt; &amp; &quot;Talk&quot;'), 'names and titles are escaped in HTML');
    assert.ok(!m.html.includes('<Night>'));
    assert.ok(!m.text.includes('917'), 'no contact numbers in emails');
  });

  test('paid + pending: pay-by time (15 minutes), amount, and how to pay in the app', async () => {
    const r = await reservation(await book('paid1'));
    const m = renderEmail('pending', r, { status: 'pending', amountCentavos: 30000 });
    assert.match(m.subject, /^Complete your payment · CCD-/);
    assert.ok(m.html.includes('Awaiting payment'));
    assert.match(m.text, /held until 10:15 AM/);
    assert.match(m.text, /Find my booking → CCD-[A-Z0-9]{8} → Pay now/);
    assert.match(m.text, /Amount: ₱300\.00/);
    assert.match(m.text, /Payment: Not yet paid/);
  });

  test('confirmed: the e-ticket stub with ADMIT count and reference, and how it was paid', async () => {
    const r = { ...(await reservation(await book('paid1'))), status: 'confirmed' };
    const m = renderEmail('confirmed', r, {
      status: 'verified',
      amountCentavos: 30000,
      method: 'gcash',
      paidAt: Timestamp.fromDate(new Date('2026-11-20T02:05:00Z')),
    });
    assert.match(m.subject, /^Your e-ticket · CCD-/);
    assert.ok(m.html.includes('Confirmed · paid'));
    assert.ok(m.html.includes('E-TICKET · ADMIT 2'));
    assert.ok(m.html.includes(r.bookingReference));
    assert.match(m.text, /Payment: Paid via GCash, Nov 20, 2026, 10:05 AM/);
  });

  test('cancelled: the reason, and a refund note when money was received', async () => {
    const r = await reservation(await book('paid1'));
    const expired = renderEmail('cancelled', { ...r, status: 'cancelled', cancellationReason: 'payment_expired' }, { status: 'pending', amountCentavos: 30000 });
    assert.match(expired.subject, /^Reservation cancelled · CCD-/);
    assert.match(expired.text, /payment was not completed within 15 minutes/);
    assert.doesNotMatch(expired.text, /refund/);

    const late = renderEmail('cancelled', { ...r, status: 'cancelled', cancellationReason: 'payment_expired' }, { status: 'verified', amountCentavos: 30000 });
    assert.match(late.text, /arrived after the 15-minute window/);
    assert.match(late.text, /contact Cinematheque Centre Davao about your refund/);

    const staff = renderEmail('cancelled', { ...r, status: 'cancelled', cancellationReason: 'staff_cancelled' }, { status: 'verified', amountCentavos: 30000 });
    assert.match(staff.text, /Cinematheque Centre Davao cancelled it/);
    assert.match(staff.text, /about your refund/);
  });

  test('the booking list (Find my booking by email): every upcoming reference', async () => {
    const a = await reservation(await book());
    const b = await reservation(await book('paid1', ['C1']));
    const m = renderBookingList([a, b]);
    assert.equal(m.subject, 'Your upcoming bookings · Cinematheque Centre Davao');
    assert.ok(m.html.includes(a.bookingReference) && m.html.includes(b.bookingReference));
    assert.match(m.text, /Awaiting approval/);
    assert.match(m.text, /Awaiting payment/);
  });

  test('pesos', () => {
    assert.equal(formatPeso(30000), '₱300');
    assert.equal(formatPeso(1234550), '₱12,345.50');
  });
});

describe('booking list by email', () => {
  beforeEach(reset);

  test('sent to the address only when it has upcoming bookings, and not again within 2 minutes', async () => {
    const mailer = fakeMailer();
    await book();
    assert.equal(await emailBookingList(db, 'nobody@example.com', { mailer, now }), 'nothing_sent');
    assert.equal(await emailBookingList(db, ' MARIA@example.com ', { mailer, now }), 'sent');
    assert.equal(mailer.sent[0].to, 'maria@example.com');
    assert.equal(await emailBookingList(db, 'maria@example.com', { mailer, now: new Date(now.getTime() + 60_000) }), 'too_soon');
    assert.equal(await emailBookingList(db, 'maria@example.com', { mailer, now: new Date(now.getTime() + 3 * 60_000) }), 'sent');
    assert.equal(mailer.sent.length, 2);
  });
});

describe('sending once per state', () => {
  beforeEach(reset);

  test('one email per state, to the booker; repeats are skipped; a new state sends its own', async () => {
    const mailer = fakeMailer();
    const id = await book();
    assert.equal(await sendStatusEmail(db, id, { mailer }), 'sent');
    assert.equal(await sendStatusEmail(db, id, { mailer }), 'already_sent');
    assert.equal(mailer.sent.length, 1);
    assert.equal(mailer.sent[0].to, 'maria@example.com');
    assert.equal((await reservation(id)).emails.pending.state, 'sent');

    await cancelReservation(db, { reservationId: id, reason: 'customer_cancelled', now });
    assert.equal(await sendStatusEmail(db, id, { mailer }), 'sent');
    assert.match(mailer.sent[1].subject, /^Reservation cancelled/);
  });

  test('simultaneous triggers (webhook + refresh + cron) still send ONE email', async () => {
    const mailer = fakeMailer();
    const id = await book();
    const results = await Promise.all(Array.from({ length: 6 }, () => sendStatusEmail(db, id, { mailer })));
    assert.equal(results.filter((r) => r === 'sent').length, 1);
    assert.equal(mailer.sent.length, 1);
  });

  test('an old state is never emailed after the booking moved on (no conflicting emails)', async () => {
    const mailer = fakeMailer();
    const id = await book();
    await cancelReservation(db, { reservationId: id, reason: 'customer_cancelled', now }); // pending email never went out
    await sendStatusEmail(db, id, { mailer });
    assert.deepEqual(mailer.sent.map((m) => m.subject.split(' · ')[0]), ['Reservation cancelled']);
  });

  test('SMTP failure: recorded as failed, nothing thrown, not retried automatically', async () => {
    const id = await book();
    assert.equal(await sendStatusEmail(db, id, { mailer: fakeMailer({ fail: true }) }), 'failed');
    assert.equal((await reservation(id)).emails.pending.state, 'failed');
    assert.equal(await sendStatusEmail(db, id, { mailer: fakeMailer() }), 'already_sent');
  });

  test('without Gmail configured nothing is recorded (local work)', async () => {
    const id = await book();
    assert.equal(await sendStatusEmail(db, id, { mailer: null }), 'not_configured');
    assert.equal((await reservation(id)).emails, undefined);
  });

  test('a verified payment sends the e-ticket', async () => {
    const mailer = fakeMailer();
    const id = await book('paid1');
    const session = {
      id: 'cs_1',
      attributes: { payments: [{ id: 'pay_1', attributes: { status: 'paid', amount: 30000, currency: 'PHP', paid_at: Math.floor(now.getTime() / 1000) + 60 } }] },
    };
    assert.equal((await settlePayment(db, { reservationId: id, session, now, mailer })).outcome, 'confirmed');
    assert.equal(mailer.sent.length, 1);
    assert.match(mailer.sent[0].subject, /^Your e-ticket · CCD-/);
  });
});
