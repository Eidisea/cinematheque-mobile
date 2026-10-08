import { getDb } from '../../lib/firebase.js';
import { HttpError, endpoint } from '../../lib/http.js';
import { getPaymongo } from '../../lib/paymongo.js';
import { ReservationError } from '../../lib/reservations.js';
import { requireStaff, verifyFirebaseIdToken } from '../../lib/staff-auth.js';
import {
  approveAllPending,
  approveReservation,
  resendStatusEmail,
  staffCancelReservation,
} from '../../lib/staff-reservations.js';

// POST /api/staff/reservations — staff actions on bookings. Needs a staff ID token.
//   { action: 'approve',    reservationId }  → { status: 'confirmed', bookingReference }
//   { action: 'approveAll', screeningId }    → { approved, failed: [references] }
//   { action: 'cancel',     reservationId }  → { status: 'cancelled', … }
//   { action: 'resend',     reservationId }  → { email: 'sent' | 'failed' | 'not_configured' }
// 400 bad_request · 401 unauthenticated · 403 not_staff · 404 not_found · 409 not_approvable / not_cancellable

const id = (v) => (typeof v === 'string' && /^[A-Za-z0-9_-]{1,100}$/.test(v) ? v : null);

/** [deps] lets tests pass fakes; Vercel uses the default export. */
export const createStaffReservationsHandler = (deps) =>
  endpoint({ methods: ['POST'] }, async (body, req) => {
    const db = deps.getDb();
    const staff = await requireStaff(req, db, deps.verify);
    const reservationId = id(body.reservationId);
    const screeningId = id(body.screeningId);
    const args = { reservationId, staffUid: staff.uid, mailer: deps.mailer };

    try {
      switch (body.action) {
        case 'approve':
          if (!reservationId) break;
          return { body: await approveReservation(db, args) };
        case 'approveAll':
          if (!screeningId) break;
          return { body: await approveAllPending(db, { screeningId, staffUid: staff.uid, mailer: deps.mailer }) };
        case 'cancel':
          if (!reservationId) break;
          return { body: await staffCancelReservation(db, deps.getPaymongo(), args) };
        case 'resend':
          if (!reservationId) break;
          return { body: { email: await resendStatusEmail(db, args) } };
      }
    } catch (e) {
      if (e instanceof ReservationError) throw new HttpError(e.code === 'not_found' ? 404 : 409, e.code, { detail: e.message });
      throw e;
    }
    throw new HttpError(400, 'bad_request');
  });

export default createStaffReservationsHandler({ getDb, getPaymongo, verify: verifyFirebaseIdToken });
