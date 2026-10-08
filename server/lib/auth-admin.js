// Firebase Authentication accounts, managed through Google's Identity Toolkit REST API with
// the server's service account — the same API firebase-admin uses internally. (Importing
// firebase-admin/auth fails on Vercel's Node runtime, so it is not used.)
//
// Locally (FIREBASE_AUTH_EMULATOR_HOST set) the calls go to the Auth emulator instead.

import { getApp } from 'firebase-admin/app';

import { getDb, getProjectId } from './firebase.js';

export class AuthAdminError extends Error {
  /** @param {'email_exists'|'weak_password'|'invalid_email'|'user_not_found'|'auth_failed'} code */
  constructor(code, detail = '') {
    super(`${code}${detail ? `: ${detail}` : ''}`);
    this.name = 'AuthAdminError';
    this.code = code;
  }
}

const CODES = {
  EMAIL_EXISTS: 'email_exists',
  DUPLICATE_EMAIL: 'email_exists',
  INVALID_EMAIL: 'invalid_email',
  USER_NOT_FOUND: 'user_not_found',
};

export function createAuthAdmin({ projectId, accessToken, emulatorHost, fetchImpl = fetch }) {
  const base = emulatorHost
    ? `http://${emulatorHost}/identitytoolkit.googleapis.com/v1/projects/${projectId}`
    : `https://identitytoolkit.googleapis.com/v1/projects/${projectId}`;

  async function call(path, body) {
    const token = emulatorHost ? 'owner' : await accessToken();
    const res = await fetchImpl(`${base}${path}`, {
      method: 'POST',
      headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
      signal: AbortSignal.timeout(10_000),
    });
    const json = await res.json().catch(() => ({}));
    if (!res.ok) {
      const message = String(json?.error?.message ?? res.status);
      if (message.startsWith('WEAK_PASSWORD')) throw new AuthAdminError('weak_password');
      throw new AuthAdminError(CODES[message.split(' ')[0]] ?? 'auth_failed', message);
    }
    return json;
  }

  return {
    /** → the new account's uid. */
    async createUser({ email, password, displayName }) {
      return (await call('/accounts', { email, password, displayName })).localId;
    },
    /** Changes only what is given; disabled accounts cannot sign in. */
    async updateUser(uid, { email, password, displayName, disabled }) {
      const body = { localId: uid };
      if (email !== undefined) body.email = email;
      if (password !== undefined) body.password = password;
      if (displayName !== undefined) body.displayName = displayName;
      if (disabled !== undefined) body.disableUser = disabled;
      await call('/accounts:update', body);
    },
  };
}

/** The real client, signed in as the server's service account. */
export function getAuthAdmin() {
  getDb(); // initialises the Firebase app
  const emulatorHost = process.env.FIREBASE_AUTH_EMULATOR_HOST;
  return createAuthAdmin({
    projectId: getProjectId(),
    emulatorHost,
    accessToken: async () => (await getApp().options.credential.getAccessToken()).access_token,
  });
}
