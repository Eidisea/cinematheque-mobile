import { timingSafeEqual } from 'node:crypto';

import { getDb } from '../../lib/firebase.js';
import { HttpError, endpoint } from '../../lib/http.js';
import { expireReservation, findExpiredUnpaid } from '../../lib/payments.js';
import { getPaymongo } from '../../lib/paymongo.js';

// GET|POST /api/cron/expire-unpaid — called by cron-job.org every 5 minutes with
// "Authorization: Bearer <CRON_SECRET>". Ends unpaid bookings whose 15 minutes are over,
// asking PayMongo first about each one (see expireReservation).
// → { checked, outcomes: { expired, confirmed, late_needs_refund, … }, failed }

function authorized(req) {
  // trim(): a value pasted into Vercel may carry a trailing line break.
  const secret = process.env.CRON_SECRET?.trim();
  const given = (req.headers.authorization ?? '').trim();
  if (!secret) return false;
  const a = Buffer.from(given);
  const b = Buffer.from(`Bearer ${secret}`);
  return a.length === b.length && timingSafeEqual(a, b);
}

/** [deps] lets tests pass a fake PayMongo; Vercel uses the default export. */
export const createExpiryHandler = (deps) => endpoint({ methods: ['GET', 'POST'] }, async (_body, req) => {
  if (!authorized(req)) throw new HttpError(401, 'unauthorized');

  const db = deps.getDb();
  const paymongo = deps.getPaymongo();
  const now = new Date();
  const ids = await findExpiredUnpaid(db, now);
  const outcomes = {};
  let failed = 0;
  for (const id of ids) {
    try {
      const { outcome } = await expireReservation(db, paymongo, id, now);
      outcomes[outcome] = (outcomes[outcome] ?? 0) + 1;
    } catch (e) {
      failed++;
      console.error('Could not expire reservation', id, e);
    }
  }
  return { body: { checked: ids.length, outcomes, failed } };
});

export default createExpiryHandler({ getDb, getPaymongo });
