import assert from 'node:assert/strict';
import { mkdtemp, readFile, rm, stat, symlink, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';
import { parse } from 'yaml';
import { appendService, stageService } from '../server/config-file.mjs';
import { tunnelFromInput } from '../server/policy.mjs';

const input = { name: 'preview', listenPort: '18100', route: 'loopback', destinationHost: '127.0.0.1', destinationPort: '3000' };

test('accepts only fixed loopback listeners and validated private destinations', () => {
  for (const patch of [
    { address: '0.0.0.0' }, { name: 'a/b' }, { listenPort: '0' }, { listenPort: '18081' },
    { listenPort: '65536' }, { destinationPort: '1e4' }, { destinationPort: '18080' },
    { destinationPort: '18100' }, { destinationHost: 'localhost' }, { route: 'reverse' },
    { route: 'tailnet', destinationHost: '100.128.0.1' }, { route: 'tailnet', destinationHost: '1.1.1.1' },
    { route: 'tailnet', destinationHost: 'peer.ts.net' }, { route: 'tailnet', destinationHost: 'fd7a:115c:a1e1::2' },
  ]) assert.throws(() => tunnelFromInput({ ...input, ...patch }), { status: 400 });
  const v6 = tunnelFromInput({ ...input, route: 'tailnet', destinationHost: 'fd7a:115c:a1e0::42' });
  assert.equal(v6.addr, '127.0.0.1:18100');
  assert.equal(v6.handler.chain, 'tailnet');
  assert.equal(v6.forwarder.nodes[0].addr, '[fd7a:115c:a1e0::42]:3000');
});

test('appends without rewriting legacy config values, comments, aliases or unknown fields', () => {
  const service = tunnelFromInput(input);
  const legacy = 'future: &item {mode: 0777, hex: 0xff}\nservices:\n  # owner note\n  - name: custom\n    metadata: *item\n    handler: {type: udp, auth: {password: synthetic}}\n';
  const added = appendService(legacy, service);
  assert.equal(added.replace(`- ${JSON.stringify(service)}\n  `, ''), legacy);
  for (const source of [legacy, 'services: [ # current\n {name: custom, future: true}, ]\n', '{"services":[]}', 'chains: []\n', '{}']) {
    const original = parse(source);
    const next = parse(appendService(source, service));
    assert.deepEqual(next.services.shift(), service);
    if (!original.services) delete next.services;
    assert.deepEqual(next, original);
  }
  for (const unsupported of ['Services: []', 'services: {}', 'services:\n  - name: null\n', 'services: []\n---\na: 1']) {
    assert.throws(() => appendService(unsupported, service), { status: 409 });
  }
  assert.throws(() => appendService(added, service), { status: 409, field: 'name' });
});

test('refuses symlinks and refuses to overwrite changed configuration', async (t) => {
  const directory = await mkdtemp(join(tmpdir(), 'codyssey-config-'));
  t.after(() => rm(directory, { force: true, recursive: true }));
  const path = join(directory, 'gost.yaml');
  const target = join(directory, 'link.yaml');
  const service = tunnelFromInput(input);
  await writeFile(path, 'services: []\n');
  await symlink(path, target);
  await assert.rejects(stageService(target, service), { code: 'ELOOP' });
  const staged = await stageService(path, service);
  await writeFile(path, '# external edit\nservices: []\n');
  await assert.rejects(staged.commit(), { status: 409 });
  await staged.discard();
  assert.equal(await readFile(path, 'utf8'), '# external edit\nservices: []\n');
  const fresh = await stageService(path, service);
  await fresh.commit();
  assert.equal((await stat(path)).mode & 0o777, 0o600);
});
