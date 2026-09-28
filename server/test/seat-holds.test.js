// Seat-hold tests against the LOCAL Firestore emulator:
//   firebase emulators:exec --only firestore --project demo-ccd "npm --prefix server test"

import assert from 'node:assert/strict';
import { beforeEach, describe, test } from 'node:test';

import { Timestamp } from 'firebase-admin/firestore';

import { getDb } from '../lib/firebase.js';
import {
  BookingNotAllowedError,
  SeatConflictError,
  claimSeats,
  confirmSeats,
  releaseSeats,
} from '../lib/seat-holds.js';

if (!process.env.FIRESTORE_EMULATOR_HOST) {
  throw new Error('Run these tests inside `firebase emulators:exec` — never against the real database.');
}

const db = getDb();
const projectId = process.env.GCLOUD_PROJECT || 'demo-ccd';
const now = new Date();
const inMinutes = (m) => new Date(now.getTime() + m * 60_000);

async function reset({ startsInMinutes = 120, holds = {} } = {}) {
  const res = await fetch(
    `http://${process.env.FIRESTORE_EMULATOR_HOST}/emulator/v1/projects/${projectId}/databases/(default)/documents`,
    { method: 'DELETE' },
  );
  assert.equal(res.status, 200);

  const seats = [];
  for (const row of 'ABCDEFGHIJ') for (let n = 1; n <= 12; n++) seats.push({ label: `${row}${n}`, row, number: n, isActive: true });
  seats.find((s) => s.label === 'J12').isActive = false; // one switched-off seat
  await db.doc('settings/seatLayout').set({ seats });

  await db.doc('screenings/s1').set({
    eventTitle: 'Test Screening',
    startAt: Timestamp.fromDate(inMinutes(startsInMinutes)),
    endAt: Timestamp.fromDate(inMinutes(startsInMinutes + 120)),
    type: 'paid',
    priceCentavos: 15000,
    capacity: 119,
    seatHolds: holds,
    hasReservations: Object.keys(holds).length > 0,
  });
}

const holdsNow = async () => (await db.doc('screenings/s1').get()).data().seatHolds;
const claim = (seatLabels, reservationId, extra = {}) =>
  claimSeats(db, { screeningId: 's1', seatLabels, reservationId, now, ...extra });

describe('claiming seats', () => {
  beforeEach(() => reset());

  test('free seats are held for the reservation', async () => {
    await claim(['A1', 'A2'], 'r1', { expiresAt: inMinutes(15) });
    const holds = await holdsNow();
    assert.equal(holds.A1.reservationId, 'r1');
    assert.equal(holds.A1.state, 'held');
    assert.ok(holds.A2.expiresAt.toMillis() > now.getTime());
    assert.equal((await db.doc('screenings/s1').get()).data().hasReservations, true);
  });

  test('a free-screening hold has no expiry', async () => {
    await claim(['B1'], 'r1');
    assert.equal((await holdsNow()).B1.expiresAt, null);
  });

  test('taken seats are refused and NOTHING is claimed (all-or-nothing)', async () => {
    await claim(['C1'], 'first');
    await assert.rejects(claim(['C2', 'C1', 'C3'], 'second'), (e) => {
      assert.ok(e instanceof SeatConflictError);
      assert.deepEqual(e.labels, ['C1']);
      return true;
    });
    const holds = await holdsNow();
    assert.equal(holds.C2, undefined);
    assert.equal(holds.C3, undefined);
  });

  test('confirmed, free-pending and unexpired unpaid holds all block the seat', async () => {
    await reset({
      holds: {
        D1: { reservationId: 'paid', state: 'confirmed', expiresAt: null },
        D2: { reservationId: 'freePending', state: 'held', expiresAt: null },
        D3: { reservationId: 'unpaid', state: 'held', expiresAt: Timestamp.fromDate(inMinutes(5)) },
      },
    });
    for (const seat of ['D1', 'D2', 'D3']) {
      await assert.rejects(claim([seat], 'x'), SeatConflictError, seat);
    }
  });

  test('an EXPIRED unpaid hold can be taken, and its reservation is reported for cancellation', async () => {
    await reset({ holds: { E1: { reservationId: 'late', state: 'held', expiresAt: Timestamp.fromDate(inMinutes(-1)) } } });
    const result = await claim(['E1', 'E2'], 'fresh');
    assert.deepEqual(result.replacedReservationIds, ['late']);
    assert.equal((await holdsNow()).E1.reservationId, 'fresh');
  });

  test('booking closes when the screening starts', async () => {
    await reset({ startsInMinutes: -1 });
    await assert.rejects(claim(['A1'], 'r1'), (e) => e instanceof BookingNotAllowedError && e.reason === 'screening_started');
  });

  test('unknown screening', async () => {
    await assert.rejects(
      claimSeats(db, { screeningId: 'nope', seatLabels: ['A1'], reservationId: 'r1', now }),
      (e) => e.reason === 'screening_not_found',
    );
  });

  test('invalid requests: no seats, >10 seats, duplicates, unknown or switched-off seats', async () => {
    const reason = (r) => (e) => e instanceof BookingNotAllowedError && e.reason === r;
    await assert.rejects(claim([], 'r'), reason('invalid_seats'));
    await assert.rejects(claim(['A1', 'A2', 'A3', 'A4', 'A5', 'A6', 'A7', 'A8', 'A9', 'A10', 'A11'], 'r'), reason('too_many_seats'));
    await assert.rejects(claim(['A1', 'A1'], 'r'), reason('invalid_seats'));
    await assert.rejects(claim(['Z99'], 'r'), reason('invalid_seats'));
    await assert.rejects(claim(['J12'], 'r'), reason('invalid_seats'), 'switched off in the layout');
    await assert.rejects(claim(['a1; drop'], 'r'), reason('invalid_seats'));
    assert.deepEqual(await holdsNow(), {});
  });

  test('if the rest of the booking fails, the seats are NOT kept (same transaction)', async () => {
    await assert.rejects(
      claim(['F1'], 'r1', {
        inTransaction: () => {
          throw new Error('reservation write failed');
        },
      }),
      /reservation write failed/,
    );
    assert.equal((await holdsNow()).F1, undefined);
  });
});

describe('concurrency — no double booking', () => {
  beforeEach(() => reset());

  test('25 customers grab the same seat at the same moment → exactly one gets it', async () => {
    const results = await Promise.allSettled(
      Array.from({ length: 25 }, (_, i) => claim(['G5'], `customer-${i}`, { expiresAt: inMinutes(15) })),
    );
    const winners = results.map((r, i) => (r.status === 'fulfilled' ? `customer-${i}` : null)).filter(Boolean);
    assert.equal(winners.length, 1, `winners: ${winners}`);

    const losers = results.filter((r) => r.status === 'rejected');
    for (const l of losers) assert.ok(l.reason instanceof SeatConflictError, `unexpected error: ${l.reason}`);

    assert.equal((await holdsNow()).G5.reservationId, winners[0]);
  });

  test('overlapping seat groups at the same moment never share a seat', async () => {
    const groups = [['H1', 'H2'], ['H2', 'H3'], ['H3', 'H4'], ['H4', 'H5'], ['H5', 'H1'], ['H6']];
    const results = await Promise.allSettled(groups.map((g, i) => claim(g, `group-${i}`)));
    const holds = await holdsNow();

    const won = groups.filter((_, i) => results[i].status === 'fulfilled');
    const seatsWon = won.flat();
    assert.equal(new Set(seatsWon).size, seatsWon.length, 'a seat was given to two reservations');
    for (const [i, g] of groups.entries()) {
      if (results[i].status !== 'fulfilled') {
        assert.ok(results[i].reason instanceof SeatConflictError, String(results[i].reason));
        continue;
      }
      for (const seat of g) assert.equal(holds[seat].reservationId, `group-${i}`);
    }
    assert.ok(won.length >= 3, 'at least the non-overlapping groups succeed');
  });
});

describe('releasing and confirming', () => {
  beforeEach(() => reset());

  test('cancelling releases the seats, which can then be booked again', async () => {
    await claim(['A5', 'A6'], 'r1');
    const released = await releaseSeats(db, { screeningId: 's1', reservationId: 'r1', seatLabels: ['A5', 'A6'] });
    assert.deepEqual(released, ['A5', 'A6']);
    assert.deepEqual(await holdsNow(), {});
    await claim(['A5'], 'r2');
    assert.equal((await holdsNow()).A5.reservationId, 'r2');
  });

  test('releasing never removes another reservation’s hold', async () => {
    await claim(['B7'], 'owner');
    const released = await releaseSeats(db, { screeningId: 's1', reservationId: 'someone-else', seatLabels: ['B7'] });
    assert.deepEqual(released, []);
    assert.equal((await holdsNow()).B7.reservationId, 'owner');
  });

  test('confirming turns holds into confirmed seats with no expiry', async () => {
    await claim(['C8', 'C9'], 'r1', { expiresAt: inMinutes(15) });
    const { kept, lost } = await confirmSeats(db, { screeningId: 's1', reservationId: 'r1', seatLabels: ['C8', 'C9'] });
    assert.deepEqual(kept, ['C8', 'C9']);
    assert.deepEqual(lost, []);
    const holds = await holdsNow();
    assert.equal(holds.C8.state, 'confirmed');
    assert.equal(holds.C8.expiresAt, null);
  });

  test('a late payment for seats someone else already took is reported (needs refund)', async () => {
    await reset({ holds: { D9: { reservationId: 'late', state: 'held', expiresAt: Timestamp.fromDate(inMinutes(-1)) } } });
    await claim(['D9'], 'newcomer'); // expired hold replaced
    const { kept, lost } = await confirmSeats(db, { screeningId: 's1', reservationId: 'late', seatLabels: ['D9'] });
    assert.deepEqual(kept, []);
    assert.deepEqual(lost, ['D9']);
    assert.equal((await holdsNow()).D9.reservationId, 'newcomer');
  });
});
