import { timingSafeEqual } from 'node:crypto';
import { createServer } from 'node:http';
import { TunnelError } from './policy.mjs';

const headers = {
  'Cache-Control': 'no-store',
  'Content-Security-Policy': "default-src 'none'; script-src 'self'; style-src 'self'; connect-src 'self'; form-action 'none'; frame-ancestors 'none'; base-uri 'none'",
  'Cross-Origin-Resource-Policy': 'same-origin',
  'Referrer-Policy': 'no-referrer',
  'X-Content-Type-Options': 'nosniff',
};

function json(res, status, value) {
  res.writeHead(status, { ...headers, 'Content-Type': 'application/json; charset=utf-8' });
  res.end(JSON.stringify(value));
}

async function readForm(req) {
  if (req.headers['content-type'] !== 'application/json') throw new TunnelError(415, 'Use JSON.');
  // Do not let chunked uploads or large bodies occupy the control server.
  const length = req.headers['content-length'];
  if (!/^\d{1,4}$/.test(length ?? '') || +length > 2048) {
    throw new TunnelError(413, 'The tunnel form is too large.');
  }
  const chunks = [];
  for await (const chunk of req) chunks.push(chunk);
  try {
    return JSON.parse(Buffer.concat(chunks));
  } catch {
    throw new TunnelError(400, 'The tunnel form could not be read.');
  }
}

export function createTunnelServer({ key, assets, service }) {
  const secret = Buffer.from(`Bearer ${key}`);
  const server = createServer({ requestTimeout: 10_000, headersTimeout: 5000, maxHeaderSize: 8192 }, async (req, res) => {
    try {
      const host = `127.0.0.1:${server.address().port}`;
      const origin = `http://${host}`;
      if (req.headers.host !== host) return json(res, 403, { error: 'Use the local Codyssey address.' });
      if (req.method === 'GET' && req.url === '/health') {
        await service.ready();
        return json(res, 200, { ready: true });
      }
      const asset = req.method === 'GET' && assets.get(req.url);
      if (asset) {
        res.writeHead(200, { ...headers, 'Content-Type': asset.type });
        return res.end(asset.body);
      }
      if (req.url !== '/api/tunnels') return json(res, 404, { error: 'Not found.' });
      if ((req.headers.origin && req.headers.origin !== origin) ||
          (req.headers['sec-fetch-site'] && req.headers['sec-fetch-site'] !== 'same-origin') ||
          (req.method === 'POST' && req.headers.origin !== origin)) {
        return json(res, 403, { error: 'Open the local Codyssey page to manage tunnels.' });
      }
      const auth = Buffer.from(req.headers.authorization ?? '');
      if (auth.length !== secret.length || !timingSafeEqual(auth, secret)) {
        return json(res, 401, { error: 'Enter the owner key from this installation.' });
      }
      if (req.method === 'GET') return json(res, 200, await service.list());
      if (req.method === 'POST') return json(res, 201, await service.add(await readForm(req)));
      return json(res, 405, { error: 'Only listing and adding tunnels are supported.' });
    } catch (error) {
      if (error instanceof TunnelError) return json(res, error.status, { error: error.message, field: error.field });
      return json(res, 503, { error: 'Tunnel services are unavailable. Check GOST and try again.' });
    }
  });
  return server;
}
