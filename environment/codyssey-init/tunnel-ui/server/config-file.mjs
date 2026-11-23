import { constants } from 'node:fs';
import { open, rename, rm } from 'node:fs/promises';
import { dirname, join } from 'node:path';
import { randomUUID } from 'node:crypto';
import { isMap, isScalar, isSeq, parseAllDocuments } from 'yaml';
import { TunnelError } from './policy.mjs';

function incompatible() {
  return new TunnelError(409, 'The GOST file uses a configuration this form cannot safely update. No changes were made.');
}

function inspect(source) {
  const [doc, extra] = parseAllDocuments(source, { version: '1.1' });
  if (!doc || extra || doc.errors.length || !isMap(doc.contents)) throw incompatible();
  const root = doc.contents;
  // Viper folds keys and can consume YAML merge keys. Do not guess which list it uses.
  if (root.items.some(({ key }) => !isScalar(key) || key.value === '<<' ||
      (typeof key.value === 'string' && key.value.toLowerCase() === 'services' && key.value !== 'services'))) {
    throw incompatible();
  }
  const services = root.get('services', true);
  if (root.has('services') && (!isSeq(services) || services.tag)) throw incompatible();
  if (services?.items.some((item) => !isMap(item) || item.items.some(({ key }) => !isScalar(key) || key.value === '<<'))) {
    throw incompatible();
  }
  const names = (services?.items ?? []).map((item) => item.items.find(({ key }) =>
    typeof key.value === 'string' && key.value.toLowerCase() === 'name')?.value?.value);
  if (names.some((name) => typeof name !== 'string')) throw incompatible();
  return { root, services, names };
}

export function appendService(source, service) {
  const { root, services, names } = inspect(source);
  if (names.includes(service.name)) throw new TunnelError(409, 'A tunnel already uses this name.', 'name');
  const encoded = JSON.stringify(service);
  const insert = (at, text) => source.slice(0, at) + text + source.slice(at);
  const newline = source.includes('\r\n') ? '\r\n' : '\n';
  let result;
  if (services?.flow) {
    result = insert(services.range[0] + 1, encoded + (names.length ? ', ' : ''));
  } else if (services) {
    const at = services.range[0];
    const indent = source.slice(source.lastIndexOf('\n', at - 1) + 1, at);
    if (!/^ *$/.test(indent) || source[at] !== '-') throw incompatible();
    result = insert(at, `- ${encoded}${newline}${indent}`);
  } else if (root.flow) {
    result = insert(root.range[0] + 1, `"services": [${encoded}]` + (root.items.length ? ', ' : ''));
  } else {
    const at = root.items[0]?.key.range[0];
    if (at === undefined || (at > 0 && source[at - 1] !== '\n')) throw incompatible();
    result = insert(at, `services:${newline}  - ${encoded}${newline}`);
  }
  const updated = inspect(result).names;
  if (updated.length !== names.length + 1 || updated[0] !== service.name ||
      names.some((name, index) => updated[index + 1] !== name)) throw incompatible();
  return result;
}

async function snapshot(path) {
  const file = await open(path, constants.O_RDONLY | constants.O_NOFOLLOW | constants.O_NONBLOCK);
  try {
    const info = await file.stat({ bigint: true });
    if (!info.isFile() || info.nlink !== 1n || info.size > 4_194_304n) throw incompatible();
    const source = new TextDecoder('utf-8', { fatal: true, ignoreBOM: true }).decode(await file.readFile());
    return { info, source };
  } finally {
    await file.close();
  }
}

export async function savedNames(path) {
  return new Set(inspect((await snapshot(path)).source).names);
}

export async function stageService(path, service) {
  const { info, source } = await snapshot(path);
  const next = appendService(source, service);
  const temp = join(dirname(path), `.tunnel-${randomUUID()}.tmp`);
  try {
    const file = await open(temp, 'wx', 0o600);
    try {
      const owner = await file.stat({ bigint: true });
      if (owner.uid !== info.uid || owner.gid !== info.gid) await file.chown(Number(info.uid), Number(info.gid));
      // Even if the input had broader permissions, the replacement can contain credentials.
      await file.writeFile(next);
      await file.sync();
    } finally {
      await file.close();
    }
  } catch (error) {
    await rm(temp, { force: true });
    throw error;
  }
  return {
    async commit() {
      const current = await snapshot(path);
      if (current.info.ino !== info.ino || current.info.dev !== info.dev || current.info.ctimeNs !== info.ctimeNs ||
          current.source !== source) throw new TunnelError(409, 'The GOST file changed during this save. Reload before retrying.');
      await rename(temp, path);
    },
    async discard() {
      await rm(temp, { force: true });
    },
  };
}
