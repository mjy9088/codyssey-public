import { isIP } from 'node:net';

const namePattern = /^[a-zA-Z0-9][a-zA-Z0-9_-]{0,39}$/;
const reserved = new Set([1055, 18080, 18081]);

export class TunnelError extends Error {
  constructor(status, message, field) {
    super(message);
    this.status = status;
    this.field = field;
  }
}

function port(value, field, min = 1) {
  if (typeof value !== 'string' || !/^\d{1,5}$/.test(value) || +value < min || +value > 65535) {
    throw new TunnelError(400, `Enter a port from ${min} to 65535.`, field);
  }
  return +value;
}

function tailnetIP(host) {
  if (isIP(host) === 4) {
    const [a, b] = host.split('.').map(Number);
    return a === 100 && b >= 64 && b <= 127;
  }
  return isIP(host) === 6 && /^fd7a:115c:a1e0:/i.test(host) && !host.includes('%');
}

export function tunnelFromInput(input) {
  const keys = ['name', 'listenPort', 'route', 'destinationHost', 'destinationPort'];
  if (!input || typeof input !== 'object' || Object.keys(input).length !== keys.length ||
      keys.some((key) => !Object.hasOwn(input, key) || typeof input[key] !== 'string')) {
    throw new TunnelError(400, 'Send only the tunnel form fields.');
  }

  const name = input.name.trim();
  if (!namePattern.test(name)) {
    throw new TunnelError(400, 'Use 1–40 letters, digits, hyphens or underscores; start with a letter or digit.', 'name');
  }
  const listenPort = port(input.listenPort, 'listenPort', 1024);
  if (reserved.has(listenPort)) {
    throw new TunnelError(400, 'Codyssey reserves this port. Choose a different local port.', 'listenPort');
  }
  if (input.route !== 'loopback' && input.route !== 'tailnet') {
    throw new TunnelError(400, 'Choose This machine or Tailnet.', 'route');
  }
  const host = input.destinationHost.trim().toLowerCase();
  const isTailnet = input.route === 'tailnet';
  if (isTailnet ? !tailnetIP(host) : host !== '127.0.0.1') {
    throw new TunnelError(400, isTailnet ? 'Enter the peer’s Tailscale IPv4 or IPv6 address.' : 'Use 127.0.0.1 for a local destination.', 'destinationHost');
  }
  const destinationPort = port(input.destinationPort, 'destinationPort');
  if (!isTailnet && (destinationPort === listenPort || reserved.has(destinationPort))) {
    throw new TunnelError(400, 'Choose a different destination; this would forward to itself or a Codyssey control port.', 'destinationPort');
  }
  const addr = `${isIP(host) === 6 ? `[${host}]` : host}:${destinationPort}`;
  return {
    name,
    addr: `127.0.0.1:${listenPort}`,
    handler: isTailnet ? { type: 'tcp', chain: 'tailnet' } : { type: 'tcp' },
    listener: { type: 'tcp' },
    forwarder: { nodes: [{ name: 'destination', addr }] },
  };
}

// Expose only the simple shape this UI understands, never the raw GOST config.
export function summarize(service, saved) {
  const { name, addr, handler, listener, forwarder } = service;
  const target = forwarder?.nodes?.[0];
  const only = (value, keys) => Object.keys(value ?? {}).every((key) => keys.includes(key));
  const simple = saved && typeof name === 'string' && namePattern.test(name) &&
    only(service, ['name', 'addr', 'handler', 'listener', 'forwarder']) &&
    only(handler, ['type', 'chain']) && only(listener, ['type']) && only(forwarder, ['nodes']) &&
    handler?.type === 'tcp' && listener?.type === 'tcp' && /^127\.0\.0\.1:\d+$/.test(addr) &&
    forwarder?.nodes?.length === 1 && only(target, ['name', 'addr']);
  if (simple) {
    const parts = /^(?:\[([^\]]+)\]|([^:]+)):(\d+)$/.exec(target?.addr ?? '');
    const host = parts?.[1] ?? parts?.[2];
    if (parts && ((!handler.chain && host === '127.0.0.1') || (handler.chain === 'tailnet' && tailnetIP(host)))) {
      return { name, listen: addr, destination: target.addr, route: handler.chain ? 'tailnet' : 'loopback' };
    }
  }
  return { name: typeof name === 'string' ? name.slice(0, 160) : 'Unnamed GOST service', route: saved ? 'advanced' : 'runtime' };
}
