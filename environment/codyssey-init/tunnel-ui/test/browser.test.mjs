import assert from 'node:assert/strict';
import { spawn, execFileSync } from 'node:child_process';
import { randomBytes } from 'node:crypto';
import { once } from 'node:events';
import { mkdir, mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { createServer as httpServer, request } from 'node:http';
import { connect, createServer as tcpServer } from 'node:net';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import test from 'node:test';
import { setTimeout as delay } from 'node:timers/promises';
import { chromium } from 'playwright';
import { gostClient } from '../server/gost.mjs';
import { createTunnelServer } from '../server/http.mjs';
import { tunnelService } from '../server/tunnels.mjs';

const payload = 'disposable TCP destination';
const artifacts = new URL('../test-artifacts/', import.meta.url);

async function bind(server, port = 0) {
  server.listen(port, '127.0.0.1');
  await once(server, 'listening');
  return server.address().port;
}

async function expectEventually(operation) {
  for (let attempt = 0; ; attempt++) {
    try { return await operation(); }
    catch (error) {
      if (attempt === 60) throw error;
      await delay(50);
    }
  }
}

async function stop(child) {
  if (child?.exitCode === null && child.signalCode === null) {
    const exited = once(child, 'exit');
    child.kill();
    await exited;
  }
}


async function requestStatus(url, headers) {
  return new Promise((resolve, reject) => {
    const req = request(url, { headers }, (res) => {
      res.resume();
      resolve(res.statusCode);
    });
    req.on('error', reject);
    req.end();
  });
}

async function fill(page, name, listenPort, destinationPort, route = 'loopback') {
  await page.getByLabel('Tunnel name').fill(name);
  await page.getByLabel('Local port').fill(String(listenPort));
  await page.getByLabel('Destination', { exact: true }).selectOption(route);
  await page.getByLabel('Destination port').fill(String(destinationPort));
}

test('owner adds local and Tailnet forwards in the real UI, without replacing legacy config', { timeout: 45_000 }, async (t) => {
  const binary = process.env.GOST_BIN;
  assert.ok(binary, 'Use sh ../tests/tunnel-ui-check.sh to supply the pinned GOST binary.');
  assert.match(execFileSync(binary, ['-V'], { encoding: 'utf8' }), /^gost 3\.2\.6\b/);
  const work = await mkdtemp(join(tmpdir(), 'codyssey-ui-'));
  t.after(() => rm(work, { recursive: true, force: true }));
  const config = join(work, 'gost.yaml');
  const socket = join(work, 'control.sock');
  const target = httpServer((_, res) => res.end(payload));
  t.after(() => target.close());
  const targetPort = await bind(target);
  // A real SOCKS5 listener maps the synthetic peer to loopback inside the network sandbox.
  const socks = spawn(binary, ['-L', 'socks5://127.0.0.1:1055?notls=true&hosts=100.64.0.42:127.0.0.1'], {
    cwd: work, env: {}, stdio: 'ignore',
  });
  t.after(() => stop(socks));
  await expectEventually(async () => {
    const probe = connect(1055, '127.0.0.1');
    try { await once(probe, 'connect'); } finally { probe.destroy(); }
  });
  const allocated = [];
  for (let i = 0; i < 4; i++) {
    const reservation = tcpServer();
    t.after(() => reservation.close());
    allocated.push({ reservation, port: await bind(reservation) });
  }
  const [localPort, tailnetPort, reservedLegacyApi, conflict] = allocated.map(({ port }) => port);
  for (const { reservation } of allocated.slice(0, -1)) await new Promise((resolve) => reservation.close(resolve));
  const fixture = await readFile(new URL('../../tests/fixtures/gost.yaml', import.meta.url), 'utf8');
  const original = `${fixture}# Existing owner configuration\nfutureField: {format: 0777}\napi: {addr: '127.0.0.1:${reservedLegacyApi}'}\n`;
  await writeFile(config, original);
  let gost;
  const gostApi = gostClient(socket);
  async function startGost() {
    await rm(socket, { force: true });
    gost = spawn(binary, ['-C', config], { cwd: work, env: { GOST_API: `unix://${socket}` }, stdio: 'ignore' });
    await expectEventually(() => gostApi.list());
  }
  const stopGost = () => stop(gost);
  t.after(stopGost);
  await startGost();
  await assert.rejects(fetch(`http://127.0.0.1:${reservedLegacyApi}/config`));

  const assets = new Map();
  for (const [url, file, type] of [
    ['/', '../index.html', 'text/html'], ['/App.js', '../dist/App.js', 'text/javascript'], ['/App.css', '../dist/App.css', 'text/css'],
  ]) assets.set(url, { type, body: await readFile(new URL(file, import.meta.url)) });
  const key = randomBytes(32).toString('base64url');
  const app = createTunnelServer({ key, assets, service: tunnelService(gostApi, config) });
  t.after(() => app.close());
  const origin = `http://127.0.0.1:${await bind(app)}`;
  assert.equal((await fetch(`${origin}/health`)).status, 200);
  assert.equal((await fetch(`${origin}/api/tunnels`)).status, 401);
  assert.equal((await fetch(`${origin}/config`)).status, 404);
  assert.equal(await requestStatus(`${origin}/api/tunnels`, { Host: 'not-loopback.invalid' }), 403);
  assert.equal((await fetch(`${origin}/api/tunnels`, {
    method: 'POST', headers: { Origin: 'http://another-origin.invalid', Authorization: `Bearer ${key}` },
  })).status, 403);

  const browser = await chromium.launch();
  t.after(() => browser.close());
  const page = await browser.newPage({ viewport: { width: 1280, height: 840 }, colorScheme: 'light' });
  const pageErrors = [];
  page.on('pageerror', (error) => pageErrors.push(error.message));
  await mkdir(artifacts, { recursive: true });
  const shot = (name) => page.screenshot({ path: new URL(name, artifacts).pathname, fullPage: true });
  await page.goto(origin);
  await page.getByRole('heading', { name: 'Unlock tunnel management' }).waitFor();
  await shot('locked.png');
  await page.getByLabel('Owner key').fill('synthetic-invalid-key');
  await page.getByLabel('Owner key').press('Enter');
  await page.getByRole('alert').getByText('Enter the owner key from this installation.').waitFor();
  await page.getByLabel('Owner key').fill(key);
  await page.getByLabel('Owner key').press('Enter');
  await page.getByText('No tunnels yet.', { exact: false }).waitFor();
  await shot('empty.png');

  await fill(page, 'preview', conflict, targetPort);
  await page.getByRole('button', { name: 'Add tunnel' }).click();
  await page.getByRole('alert').getByText('That local port is already in use.', { exact: false }).waitFor();
  assert.equal(await page.evaluate(() => document.activeElement?.id), 'listenPort');
  assert.equal(await readFile(config, 'utf8'), original);
  await shot('error.png');
  await page.getByLabel('Local port').fill(String(localPort));
  await page.getByLabel('Destination port').press('Enter');
  await page.getByRole('heading', { name: 'preview', exact: true }).waitFor();
  assert.equal(await (await fetch(`http://127.0.0.1:${localPort}`)).text(), payload);

  await fill(page, 'tailnet-preview', tailnetPort, targetPort, 'tailnet');
  await page.getByLabel('Tailscale IP address').fill('100.64.0.42');
  // Delay dispatch, not the response, so the actual save and forwarding are exercised.
  const release = Promise.withResolvers();
  await page.route('**/api/tunnels', async (route) => { await release.promise; await route.continue(); }, { times: 1 });
  await page.getByRole('button', { name: 'Add tunnel' }).click();
  try {
    await page.getByRole('button', { name: 'Adding tunnel…' }).waitFor();
    assert.equal(await page.getByLabel('Tunnel name').isDisabled(), true);
  } finally {
    release.resolve();
  }
  await page.getByRole('heading', { name: 'tailnet-preview', exact: true }).waitFor();
  assert.equal(await (await fetch(`http://127.0.0.1:${tailnetPort}`)).text(), payload);
  const updated = await readFile(config, 'utf8');
  assert.equal(updated.replace(/services: \[[^\n]*\]/, 'services: []'), original);
  await stopGost();
  await startGost();
  await page.reload();
  await page.getByRole('heading', { name: 'tailnet-preview', exact: true }).waitFor();
  await page.getByText(`100.64.0.42:${targetPort}`, { exact: true }).waitFor();
  assert.equal(await (await fetch(`http://127.0.0.1:${tailnetPort}`)).text(), payload);
  await shot('desktop.png');
  await page.setViewportSize({ width: 390, height: 844 });
  assert.equal(await page.evaluate(() => document.documentElement.scrollWidth), 390);
  await shot('mobile.png');
  await page.getByRole('button', { name: 'Lock' }).click();
  await page.reload();
  await page.getByRole('heading', { name: 'Unlock tunnel management' }).waitFor();
  assert.deepEqual(pageErrors, []);
});
