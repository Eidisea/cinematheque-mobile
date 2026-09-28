// Firebase Admin SDK connection. The Admin SDK bypasses Firestore security rules —
// that is why only this server (never the Flutter apps) may use it.
//
// - Local tests: set FIRESTORE_EMULATOR_HOST (the Firebase CLI does this automatically
//   inside `firebase emulators:exec`) — no credentials needed, nothing leaves this computer.
// - Vercel: set FIREBASE_SERVICE_ACCOUNT to the service-account JSON, base64-encoded,
//   as a Vercel environment variable. Never commit it.

import { cert, getApps, initializeApp } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';

let db;

export function getDb() {
  if (db) return db;

  if (!getApps().length) {
    if (process.env.FIRESTORE_EMULATOR_HOST) {
      // Local only: don't wait for a Google Cloud metadata server that isn't there
      // (otherwise the first request stalls for seconds before timing out).
      process.env.METADATA_SERVER_DETECTION ??= 'none';
      initializeApp({ projectId: process.env.GCLOUD_PROJECT || 'demo-ccd' });
    } else {
      const encoded = process.env.FIREBASE_SERVICE_ACCOUNT;
      if (!encoded) throw new Error('FIREBASE_SERVICE_ACCOUNT is not set.');
      const serviceAccount = JSON.parse(Buffer.from(encoded, 'base64').toString('utf8'));
      initializeApp({ credential: cert(serviceAccount) });
    }
  }

  db = getFirestore();
  return db;
}
