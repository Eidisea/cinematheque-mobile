// Cloudinary (film posters). The API secret lives only in Vercel's environment variables
// (CLOUDINARY_CLOUD_NAME, CLOUDINARY_API_KEY, CLOUDINARY_API_SECRET). The staff app never
// sees it: it asks this server for a SIGNED upload and sends the image straight to
// Cloudinary, which accepts only what was signed (folder, formats, time).

import { createHash } from 'node:crypto';

export const POSTER_FOLDER = 'ccd/posters';
export const POSTER_FORMATS = 'jpg,jpeg,png,webp';

/** Cloudinary's signature: SHA-1 of the sorted "key=value" pairs joined by "&", plus the secret. */
export function signParams(params, secret) {
  const payload = Object.keys(params)
    .filter((k) => params[k] !== undefined && params[k] !== null && params[k] !== '')
    .sort()
    .map((k) => `${k}=${params[k]}`)
    .join('&');
  return createHash('sha1').update(payload + secret).digest('hex');
}

export function createCloudinary({ cloudName, apiKey, apiSecret, fetchImpl = fetch }) {
  const api = `https://api.cloudinary.com/v1_1/${encodeURIComponent(cloudName)}`;

  return {
    cloudName,

    /** What the browser needs to upload ONE poster into the poster folder. Valid ~1 hour. */
    signPosterUpload(now = new Date()) {
      const params = { allowed_formats: POSTER_FORMATS, folder: POSTER_FOLDER, timestamp: Math.floor(now.getTime() / 1000) };
      return {
        uploadUrl: `${api}/image/upload`,
        apiKey,
        ...params,
        signature: signParams(params, apiSecret),
      };
    },

    /** Removes a poster (only ones in the poster folder). → true when Cloudinary removed it or it was already gone. */
    async deletePoster(publicId, now = new Date()) {
      const params = { public_id: publicId, timestamp: Math.floor(now.getTime() / 1000) };
      const body = new URLSearchParams({ ...params, api_key: apiKey, signature: signParams(params, apiSecret) });
      const res = await fetchImpl(`${api}/image/destroy`, { method: 'POST', body, signal: AbortSignal.timeout(10_000) });
      const json = await res.json().catch(() => ({}));
      return res.ok && (json.result === 'ok' || json.result === 'not found');
    },

    /** Checks the keys (Admin API ping) without changing anything. */
    async ping() {
      const auth = `Basic ${Buffer.from(`${apiKey}:${apiSecret}`).toString('base64')}`;
      const res = await fetchImpl(`${api}/ping`, { headers: { Authorization: auth }, signal: AbortSignal.timeout(8_000) });
      return res.ok;
    },
  };
}

/** The real client, or null when Cloudinary is not configured. */
export function getCloudinary() {
  const cloudName = process.env.CLOUDINARY_CLOUD_NAME?.trim();
  const apiKey = process.env.CLOUDINARY_API_KEY?.trim();
  const apiSecret = process.env.CLOUDINARY_API_SECRET?.trim();
  return cloudName && apiKey && apiSecret ? createCloudinary({ cloudName, apiKey, apiSecret }) : null;
}

/** A Cloudinary poster as stored on a film: https://res.cloudinary.com/<our cloud>/…/ccd/posters/… */
export function isOurPoster(cloudName, { url, publicId }) {
  return (
    typeof url === 'string' &&
    typeof publicId === 'string' &&
    publicId.startsWith(`${POSTER_FOLDER}/`) &&
    url.startsWith(`https://res.cloudinary.com/${cloudName}/image/upload/`)
  );
}
