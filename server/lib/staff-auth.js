// Staff-only API routes: the staff web app sends the signed-in user's Firebase ID token
// ("Authorization: Bearer <token>"). A Firebase login alone is not enough — the account
// must also have an ACTIVE staff/{uid} document (same rule as firestore.rules isStaff()).

import { createRemoteJWKSet, decodeJwt, jwtVerify } from 'jose';

import { getProjectId } from './firebase.js';
import { HttpError } from './http.js';

// Google's public keys for Firebase ID tokens (cached and rotated by jose).
const firebaseKeys = createRemoteJWKSet(
  new URL('https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com'),
);

/**
 * Checks a Firebase ID token the way Firebase documents for third-party servers: signed by
 * Google (RS256), issued for THIS project, not expired → the uid. (firebase-admin/auth is
 * not used: it fails to load on Vercel's Node runtime.) Deactivated staff are still refused
 * on every request by requireStaff's staff-record check.
 */
export async function verifyFirebaseIdToken(token) {
  const projectId = getProjectId();
  // Local development only: the Auth emulator issues unsigned tokens. This variable is set
  // by dev-server.js / the Firebase CLI on this computer and never on Vercel.
  if (process.env.FIREBASE_AUTH_EMULATOR_HOST) {
    const payload = decodeJwt(token);
    if (payload.aud !== projectId || typeof payload.sub !== 'string' || !payload.sub) throw new Error('bad emulator token');
    return payload.sub;
  }
  const { payload } = await jwtVerify(token, firebaseKeys, {
    issuer: `https://securetoken.google.com/${projectId}`,
    audience: projectId,
    algorithms: ['RS256'],
  });
  if (typeof payload.sub !== 'string' || !payload.sub) throw new Error('token without a user');
  return payload.sub;
}

/**
 * → { uid, firstName, lastName, position } of the active staff member making the request.
 * 401 unauthenticated (no / bad token) · 403 not_staff (no record, or deactivated)
 */
export async function requireStaff(req, db, verify = verifyFirebaseIdToken) {
  const match = /^Bearer (\S+)$/.exec(req.headers.authorization ?? '');
  if (!match) throw new HttpError(401, 'unauthenticated');

  let uid;
  try {
    uid = await verify(match[1]);
  } catch {
    throw new HttpError(401, 'unauthenticated');
  }

  const snap = await db.collection('staff').doc(uid).get();
  if (!snap.exists || snap.data().isActive !== true) throw new HttpError(403, 'not_staff');
  const { firstName, lastName, position } = snap.data();
  return { uid, firstName, lastName, position };
}
