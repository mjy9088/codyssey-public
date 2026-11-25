import { randomBytes } from 'node:crypto';
import { readFile, writeFile } from 'node:fs/promises';
import { gostClient } from './gost.mjs';
import { createTunnelServer } from './http.mjs';
import { tunnelService } from './tunnels.mjs';

const key = randomBytes(32).toString('base64url');
await writeFile('/run/tunnel-owner/key', `${key}\n`, { mode: 0o600, flag: 'wx' });
const assets = new Map();
for (const [path, file, type] of [
  ['/', '../index.html', 'text/html'],
  ['/App.js', '../dist/App.js', 'text/javascript'],
  ['/App.css', '../dist/App.css', 'text/css'],
]) {
  assets.set(path, { type: `${type}; charset=utf-8`, body: await readFile(new URL(file, import.meta.url)) });
}
const service = tunnelService(gostClient('/run/gost/control.sock'), '/etc/gost/gost.yaml');
createTunnelServer({ key, assets, service }).listen(18081, '0.0.0.0');
