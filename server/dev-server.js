// Local development server: runs the same api/ files Vercel runs, at http://127.0.0.1:3000.
// By default it talks to the LOCAL Firestore emulator — start that first:
//   firebase emulators:start --only auth,firestore --project cinematheque-48a54
//   node server/dev-server.js
// Android emulator: `adb reverse tcp:3000 tcp:3000` so the phone's 127.0.0.1:3000 reaches it.

import { createServer } from 'node:http';
import { existsSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

process.env.FIRESTORE_EMULATOR_HOST ??= '127.0.0.1:8080';
process.env.FIREBASE_AUTH_EMULATOR_HOST ??= '127.0.0.1:9099'; // staff sign-in tokens from the Auth emulator
process.env.GCLOUD_PROJECT ??= 'cinematheque-48a54';
process.env.ALLOWED_ORIGINS ??= 'http://127.0.0.1:5056,http://localhost:5056';

const root = dirname(fileURLToPath(import.meta.url));
const port = Number(process.env.PORT ?? 3000);

createServer(async (req, res) => {
  const path = new URL(req.url, 'http://x').pathname;
  const file = join(root, `${path}.js`);
  if (!/^\/api\/[a-z0-9/-]+$/.test(path) || !existsSync(file)) {
    res.statusCode = 404;
    return res.end('{"error":"not_found"}');
  }
  const { default: handler } = await import(pathToFileURL(file).href);
  const started = Date.now();
  res.on('finish', () => console.log(`${req.method} ${path} → ${res.statusCode} (${Date.now() - started} ms)`));
  return handler(req, res);
}).listen(port, '127.0.0.1', () => {
  console.log(`CCD API (dev) on http://127.0.0.1:${port} — Firestore emulator ${process.env.FIRESTORE_EMULATOR_HOST}`);
});
