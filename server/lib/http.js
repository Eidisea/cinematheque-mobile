// Small helpers so every endpoint handles requests, errors and CORS the same way.
// Works both on Vercel (Node runtime) and with the local dev server (plain node:http).

export class HttpError extends Error {
  constructor(status, code, extra = {}) {
    super(code);
    this.status = status;
    this.code = code;
    this.extra = extra;
  }
}

const MAX_BODY_BYTES = 64 * 1024;

export async function readJson(req) {
  if (req.body && typeof req.body === 'object') return req.body; // Vercel already parsed it
  const chunks = [];
  let size = 0;
  for await (const chunk of req) {
    size += chunk.length;
    if (size > MAX_BODY_BYTES) throw new HttpError(413, 'body_too_large');
    chunks.push(chunk);
  }
  if (!size) return {};
  try {
    return JSON.parse(Buffer.concat(chunks).toString('utf8'));
  } catch {
    throw new HttpError(400, 'invalid_json');
  }
}

export function send(res, status, body) {
  res.statusCode = status;
  res.setHeader('Content-Type', 'application/json; charset=utf-8');
  res.setHeader('Cache-Control', 'no-store');
  res.end(JSON.stringify(body));
}

/** Browsers (the staff web app) may call the API only from origins listed in ALLOWED_ORIGINS.
 *  The Android app is not a browser and sends no Origin header. */
function applyCors(req, res) {
  const origin = req.headers.origin;
  const allowed = (process.env.ALLOWED_ORIGINS ?? '').split(',').map((s) => s.trim()).filter(Boolean);
  if (origin && allowed.includes(origin)) {
    res.setHeader('Access-Control-Allow-Origin', origin);
    res.setHeader('Vary', 'Origin');
    res.setHeader('Access-Control-Allow-Methods', 'POST, GET, OPTIONS');
    res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization');
    res.setHeader('Access-Control-Max-Age', '600');
  }
}

/**
 * Wraps an endpoint: CORS, allowed methods, JSON errors. [fn] receives the parsed JSON
 * body and returns { status?, body }. Unexpected errors are logged and answered with a
 * generic 500 — internal details never reach the client.
 */
export function endpoint({ methods = ['POST'] }, fn) {
  return async function handler(req, res) {
    applyCors(req, res);
    if (req.method === 'OPTIONS') {
      res.statusCode = 204;
      return res.end();
    }
    if (!methods.includes(req.method)) return send(res, 405, { error: 'method_not_allowed' });
    try {
      const body = req.method === 'GET' ? {} : await readJson(req);
      const out = await fn(body, req);
      return send(res, out.status ?? 200, out.body);
    } catch (e) {
      if (e instanceof HttpError) return send(res, e.status, { error: e.code, ...e.extra });
      console.error('Unhandled API error', e);
      return send(res, 500, { error: 'server_error' });
    }
  };
}
