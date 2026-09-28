import { getDb } from '../lib/firebase.js';
import { endpoint } from '../lib/http.js';

// GET /api/health — is the API up, and can it reach Firestore with its credentials?
// Answers only true/false: no configuration, project names or error details.
export default endpoint({ methods: ['GET'] }, async () => {
  let firestore = false;
  try {
    await getDb().collection('settings').doc('seatLayout').get();
    firestore = true;
  } catch (e) {
    console.error('Health check: Firestore unreachable', e);
  }
  return { status: firestore ? 200 : 503, body: { ok: firestore, firestore } };
});
