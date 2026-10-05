// GET /api/payments/return?result=paid|cancelled — where PayMongo's hosted page sends the
// customer afterwards. Nothing is decided here (anyone can open this URL): the booking is
// confirmed only by the webhook / refresh after PayMongo is asked directly.

const PAGES = {
  paid: ['Payment sent', 'Go back to the Cinematheque app. Your booking updates there once the payment is confirmed.'],
  cancelled: ['Payment not completed', 'Go back to the Cinematheque app. You can try again while your seats are still held.'],
};

const page = ([title, message]) => `<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>${title} · Cinematheque Centre Davao</title>
<style>
  body{margin:0;min-height:100vh;display:grid;place-items:center;background:#FAF9F7;color:#141219;
       font:16px/1.5 system-ui,-apple-system,"Segoe UI",Roboto,sans-serif;padding:24px;box-sizing:border-box}
  main{max-width:380px;text-align:center}
  p.eyebrow{font-size:12px;letter-spacing:.14em;text-transform:uppercase;color:#7a6a3a;margin:0 0 12px}
  h1{font-size:24px;margin:0 0 12px}
  p{margin:0;color:#4a4652}
</style></head>
<body><main><p class="eyebrow">Cinematheque Centre Davao</p><h1>${title}</h1><p>${message}</p></main></body></html>`;

export default function handler(req, res) {
  const result = new URL(req.url, 'http://x').searchParams.get('result');
  res.statusCode = req.method === 'GET' ? 200 : 405;
  res.setHeader('Content-Type', 'text/html; charset=utf-8');
  res.setHeader('Cache-Control', 'no-store');
  res.end(page(PAGES[result] ?? PAGES.cancelled));
}
