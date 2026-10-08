// Staff accounts against the LOCAL Firestore emulator (fake sign-in, fake Firebase Auth):
//   firebase emulators:exec --only firestore --project demo-ccd "npm --prefix server test"
// With the Auth emulator too (--only firestore,auth) the real Identity Toolkit calls are tested as well.

import assert from 'node:assert/strict';
import { Readable } from 'node:stream';
import { beforeEach, describe, test } from 'node:test';

import { createAccountsHandler } from '../api/staff/accounts.js';
import { AuthAdminError, createAuthAdmin } from '../lib/auth-admin.js';
import { getDb } from '../lib/firebase.js';

if (!process.env.FIRESTORE_EMULATOR_HOST) throw new Error('Run inside `firebase emulators:exec` only.');

const db = getDb();
const projectId = process.env.GCLOUD_PROJECT || 'demo-ccd';

async function reset() {
  await fetch(`http://${process.env.FIRESTORE_EMULATOR_HOST}/emulator/v1/projects/${projectId}/databases/(default)/documents`, { method: 'DELETE' });
  await db.doc('staff/s1').set({ firstName: 'Ana', lastName: 'Reyes', email: 'ana@ccd.test', position: 'AVT', isActive: true });
}

const verify = async (t) => {
  if (t !== 'tok-s1') throw new Error('bad token');
  return 's1';
};

function fakeAuth() {
  const users = new Map([['s1', { email: 'ana@ccd.test', disabled: false }]]);
  return {
    users,
    async createUser({ email, password, displayName }) {
      if ([...users.values()].some((u) => u.email === email)) throw new AuthAdminError('email_exists');
      const uid = `u${users.size + 1}`;
      users.set(uid, { email, password, displayName, disabled: false });
      return uid;
    },
    async updateUser(uid, changes) {
      if (!users.has(uid)) throw new AuthAdminError('user_not_found');
      Object.assign(users.get(uid), changes);
    },
  };
}

async function call(body, { token = 'tok-s1', auth = fakeAuth() } = {}) {
  const handler = createAccountsHandler({ getDb: () => db, getAuthAdmin: () => auth, verify });
  const req = Readable.from([Buffer.from(JSON.stringify(body))]);
  req.method = 'POST';
  req.headers = token ? { authorization: `Bearer ${token}` } : {};
  const res = { statusCode: 200, setHeader() {}, end(chunk) { this.body = chunk ? JSON.parse(chunk) : null; } };
  await handler(req, res);
  return { status: res.statusCode, body: res.body };
}

const ben = { firstName: 'Ben', lastName: 'Santos', email: 'Ben@CCD.test', position: 'pdo', password: 'long-enough-1' };

describe('staff accounts', () => {
  beforeEach(reset);

  test('staff only', async () => {
    assert.equal((await call({ action: 'create', ...ben }, { token: null })).status, 401);
  });

  test('create: a Firebase account + an active staff record (email lower-cased, position AVT/PDO)', async () => {
    const auth = fakeAuth();
    const out = await call({ action: 'create', ...ben }, { auth });
    assert.equal(out.status, 201);
    const record = (await db.doc(`staff/${out.body.uid}`).get()).data();
    assert.equal(record.email, 'ben@ccd.test');
    assert.equal(record.position, 'PDO');
    assert.equal(record.isActive, true);
    assert.equal(auth.users.get(out.body.uid).displayName, 'Ben Santos');
  });

  test('form errors come back per field; a used email is refused', async () => {
    const bad = await call({ action: 'create', firstName: '', lastName: 'X', email: 'nope', position: 'boss', password: 'short' });
    assert.equal(bad.status, 400);
    assert.deepEqual(Object.keys(bad.body.fields).sort(), ['email', 'firstName', 'password', 'position']);

    const taken = await call({ action: 'create', ...ben, email: 'ana@ccd.test' });
    assert.equal(taken.status, 409);
    assert.equal(taken.body.fields.email, 'Another account already uses this email.');
  });

  test('update: details change; a blank password keeps the old one', async () => {
    const auth = fakeAuth();
    const { body } = await call({ action: 'create', ...ben }, { auth });
    const out = await call({ action: 'update', uid: body.uid, ...ben, lastName: 'Santos-Cruz', password: '' }, { auth });
    assert.equal(out.status, 200);
    assert.equal((await db.doc(`staff/${body.uid}`).get()).data().lastName, 'Santos-Cruz');
    assert.equal(auth.users.get(body.uid).password, 'long-enough-1');
  });

  test('deactivate turns off both sign-in and the record; nobody can deactivate themselves', async () => {
    const auth = fakeAuth();
    const { body } = await call({ action: 'create', ...ben }, { auth });
    assert.deepEqual((await call({ action: 'deactivate', uid: body.uid }, { auth })).body, { uid: body.uid, isActive: false });
    assert.equal(auth.users.get(body.uid).disabled, true);
    assert.equal((await db.doc(`staff/${body.uid}`).get()).data().isActive, false);

    assert.deepEqual(await call({ action: 'deactivate', uid: 's1' }, { auth }), { status: 409, body: { error: 'self' } });
    assert.equal((await call({ action: 'activate', uid: body.uid }, { auth })).body.isActive, true);
  });
});

describe('Firebase accounts (Auth emulator)', { skip: !process.env.FIREBASE_AUTH_EMULATOR_HOST && 'Auth emulator not running' }, () => {
  test('create, update, disable through the Identity Toolkit API', async () => {
    const auth = createAuthAdmin({ projectId, emulatorHost: process.env.FIREBASE_AUTH_EMULATOR_HOST });
    const email = `staff${Date.now()}@ccd.test`;
    const uid = await auth.createUser({ email, password: 'long-enough-1', displayName: 'Test Staff' });
    assert.ok(uid);
    await auth.updateUser(uid, { displayName: 'Renamed', disabled: true });
    await assert.rejects(auth.createUser({ email, password: 'long-enough-1' }), { code: 'email_exists' });
  });
});
