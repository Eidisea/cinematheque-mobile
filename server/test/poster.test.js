// Poster signing (Cloudinary) — fake sign-in and a fake Cloudinary; Firestore emulator for staff records.
//   firebase emulators:exec --only firestore --project demo-ccd "npm --prefix server test"

import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { Readable } from 'node:stream';
import { beforeEach, describe, test } from 'node:test';

import { createPosterHandler } from '../api/staff/poster.js';
import { POSTER_FOLDER, createCloudinary, isOurPoster, signParams } from '../lib/cloudinary.js';
import { getDb } from '../lib/firebase.js';

if (!process.env.FIRESTORE_EMULATOR_HOST) throw new Error('Run inside `firebase emulators:exec` only.');

const db = getDb();
const projectId = process.env.GCLOUD_PROJECT || 'demo-ccd';

async function reset() {
  await fetch(`http://${process.env.FIRESTORE_EMULATOR_HOST}/emulator/v1/projects/${projectId}/databases/(default)/documents`, { method: 'DELETE' });
  await db.doc('staff/s1').set({ firstName: 'Ana', lastName: 'Reyes', email: 'ana@ccd.test', position: 'avt', isActive: true });
}

const verify = async (t) => {
  if (t !== 'tok-s1') throw new Error('bad token');
  return 's1';
};

async function call(body, { token = 'tok-s1', cloudinary } = {}) {
  const handler = createPosterHandler({ getDb: () => db, getCloudinary: () => cloudinary, verify });
  const req = Readable.from([Buffer.from(JSON.stringify(body))]);
  req.method = 'POST';
  req.headers = token ? { authorization: `Bearer ${token}` } : {};
  const res = { statusCode: 200, setHeader() {}, end(chunk) { this.body = chunk ? JSON.parse(chunk) : null; } };
  await handler(req, res);
  return { status: res.statusCode, body: res.body };
}

describe('Cloudinary signing', () => {
  test('signature = SHA-1 of the sorted key=value pairs + the secret (empty values left out)', () => {
    const expected = createHash('sha1').update('folder=ccd/posters&timestamp=1700000000secret').digest('hex');
    assert.equal(signParams({ timestamp: 1700000000, folder: 'ccd/posters', empty: '' }, 'secret'), expected);
  });

  test('an upload ticket signs exactly the folder, formats and time', () => {
    const c = createCloudinary({ cloudName: 'tjdy4j9n', apiKey: 'key', apiSecret: 'sec' });
    const t = c.signPosterUpload(new Date(1_700_000_000_000));
    assert.equal(t.uploadUrl, 'https://api.cloudinary.com/v1_1/tjdy4j9n/image/upload');
    assert.equal(t.folder, POSTER_FOLDER);
    assert.equal(t.timestamp, 1_700_000_000);
    assert.equal(t.signature, signParams({ allowed_formats: t.allowed_formats, folder: t.folder, timestamp: t.timestamp }, 'sec'));
    assert.ok(!JSON.stringify(t).includes('sec"'), 'the secret is never handed out');
  });

  test('only our own poster folder on our cloud counts as a poster', () => {
    const url = 'https://res.cloudinary.com/tjdy4j9n/image/upload/v1/ccd/posters/abc.jpg';
    assert.equal(isOurPoster('tjdy4j9n', { url, publicId: 'ccd/posters/abc' }), true);
    assert.equal(isOurPoster('tjdy4j9n', { url, publicId: 'other/abc' }), false);
    assert.equal(isOurPoster('tjdy4j9n', { url: 'https://evil.test/x.jpg', publicId: 'ccd/posters/abc' }), false);
  });
});

describe('poster route', () => {
  beforeEach(reset);

  const fakeCloudinary = () => ({
    deleted: [],
    signPosterUpload: () => ({ uploadUrl: 'https://api.cloudinary.com/v1_1/x/image/upload', signature: 'sig' }),
    async deletePoster(id) {
      this.deleted.push(id);
      return true;
    },
  });

  test('staff only', async () => {
    assert.equal((await call({ action: 'sign' }, { token: null, cloudinary: fakeCloudinary() })).status, 401);
  });

  test('sign → an upload ticket; not configured → 503', async () => {
    assert.deepEqual((await call({ action: 'sign' }, { cloudinary: fakeCloudinary() })).body.signature, 'sig');
    assert.deepEqual(await call({ action: 'sign' }, { cloudinary: null }), { status: 503, body: { error: 'not_configured' } });
  });

  test('delete removes posters in our folder only', async () => {
    const c = fakeCloudinary();
    assert.deepEqual((await call({ action: 'delete', publicId: 'ccd/posters/abc' }, { cloudinary: c })).body, { deleted: true });
    assert.equal((await call({ action: 'delete', publicId: 'someone/else' }, { cloudinary: c })).status, 400);
    assert.equal((await call({ action: 'delete', publicId: 'ccd/posters/../x' }, { cloudinary: c })).status, 400);
    assert.deepEqual(c.deleted, ['ccd/posters/abc']);
  });
});
