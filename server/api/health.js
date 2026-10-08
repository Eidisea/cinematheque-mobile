import { getCloudinary } from '../lib/cloudinary.js';
import { getMailer } from '../lib/email.js';
import { getDb } from '../lib/firebase.js';
import { endpoint } from '../lib/http.js';

// GET /api/health — is the API up, can it reach Firestore, can it sign in to Gmail and
// Cloudinary? Answers only true/false (null when a service is not configured): no configuration,
// addresses or error details. "ok" depends on Firestore only — email problems never stop
// bookings.
export default endpoint({ methods: ['GET'] }, async () => {
  let firestore = false;
  try {
    await getDb().collection('settings').doc('seatLayout').get();
    firestore = true;
  } catch (e) {
    console.error('Health check: Firestore unreachable', e);
  }

  let email = null;
  const mailer = getMailer();
  if (mailer) {
    try {
      await mailer.verify();
      email = true;
    } catch (e) {
      console.error('Health check: Gmail sign-in failed', e.message);
      email = false;
    }
  }

  let posters = null;
  const cloudinary = getCloudinary();
  if (cloudinary) {
    posters = await cloudinary.ping().catch((e) => {
      console.error('Health check: Cloudinary unreachable', e.message);
      return false;
    });
  }
  return { status: firestore ? 200 : 503, body: { ok: firestore, firestore, email, posters } };
});
