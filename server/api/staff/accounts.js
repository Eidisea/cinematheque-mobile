import { AuthAdminError, getAuthAdmin } from '../../lib/auth-admin.js';
import { getDb } from '../../lib/firebase.js';
import { HttpError, endpoint } from '../../lib/http.js';
import { requireStaff, verifyFirebaseIdToken } from '../../lib/staff-auth.js';
import {
  StaffAccountError,
  createStaffAccount,
  setStaffActive,
  updateStaffAccount,
} from '../../lib/staff-accounts.js';

// POST /api/staff/accounts — manage staff accounts. Needs a staff ID token.
//   { action: 'create', firstName, middleName?, lastName, email, position: 'AVT'|'PDO', password }  → { uid }
//   { action: 'update', uid, …same fields…, password? (blank keeps it) }                            → { uid }
//   { action: 'activate' | 'deactivate', uid }                                                        → { uid, isActive }
// 400 validation (fields) / bad_request · 401 · 403 · 404 not_found · 409 email_exists / self

const uidOf = (v) => (typeof v === 'string' && /^[A-Za-z0-9]{1,128}$/.test(v) ? v : null);

/** [deps] lets tests pass fakes; Vercel uses the default export. */
export const createAccountsHandler = (deps) =>
  endpoint({ methods: ['POST'] }, async (body, req) => {
    const db = deps.getDb();
    const staff = await requireStaff(req, db, deps.verify);
    const auth = deps.getAuthAdmin();
    const uid = uidOf(body.uid);

    try {
      switch (body.action) {
        case 'create':
          return { status: 201, body: await createStaffAccount(db, auth, body) };
        case 'update':
          if (!uid) break;
          return { body: await updateStaffAccount(db, auth, uid, body) };
        case 'activate':
        case 'deactivate':
          if (!uid) break;
          return { body: await setStaffActive(db, auth, uid, body.action === 'activate', { by: staff.uid }) };
      }
    } catch (e) {
      if (e instanceof StaffAccountError) {
        if (e.code === 'validation') throw new HttpError(400, 'validation', { fields: e.fields });
        throw new HttpError(e.code === 'not_found' ? 404 : 409, e.code);
      }
      if (e instanceof AuthAdminError) {
        if (e.code === 'email_exists') throw new HttpError(409, 'email_exists', { fields: { email: 'Another account already uses this email.' } });
        if (e.code === 'weak_password') throw new HttpError(400, 'validation', { fields: { password: 'Choose a stronger password.' } });
        if (e.code === 'invalid_email') throw new HttpError(400, 'validation', { fields: { email: 'Enter a valid email address.' } });
        if (e.code === 'user_not_found') throw new HttpError(404, 'not_found');
        console.error('Staff account change failed', e);
        throw new HttpError(502, 'auth_failed');
      }
      throw e;
    }
    throw new HttpError(400, 'bad_request');
  });

export default createAccountsHandler({ getDb, getAuthAdmin, verify: verifyFirebaseIdToken });
