import { POSTER_FOLDER, getCloudinary } from '../../lib/cloudinary.js';
import { getDb } from '../../lib/firebase.js';
import { HttpError, endpoint } from '../../lib/http.js';
import { requireStaff, verifyFirebaseIdToken } from '../../lib/staff-auth.js';

// POST /api/staff/poster — film posters on Cloudinary. Needs a staff ID token.
//   { action: 'sign' }               → { uploadUrl, apiKey, folder, allowed_formats, timestamp, signature }
//                                       (the browser uploads the image to Cloudinary with exactly these)
//   { action: 'delete', publicId }   → { deleted: true|false }  (only posters in ccd/posters/)
// 400 bad_request · 401 · 403 · 503 not_configured

/** [deps] lets tests pass fakes; Vercel uses the default export. */
export const createPosterHandler = (deps) =>
  endpoint({ methods: ['POST'] }, async (body, req) => {
    await requireStaff(req, deps.getDb(), deps.verify);
    const cloudinary = deps.getCloudinary();
    if (!cloudinary) throw new HttpError(503, 'not_configured');

    switch (body.action) {
      case 'sign':
        return { body: cloudinary.signPosterUpload() };
      case 'delete': {
        const publicId = body.publicId;
        if (typeof publicId !== 'string' || !publicId.startsWith(`${POSTER_FOLDER}/`) || publicId.length > 300 || publicId.includes('..')) {
          throw new HttpError(400, 'bad_request');
        }
        return { body: { deleted: await cloudinary.deletePoster(publicId) } };
      }
      default:
        throw new HttpError(400, 'bad_request');
    }
  });

export default createPosterHandler({ getDb, getCloudinary, verify: verifyFirebaseIdToken });
