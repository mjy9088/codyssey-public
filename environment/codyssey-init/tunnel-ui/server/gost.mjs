import { request } from 'node:http';
import { TunnelError } from './policy.mjs';

export function gostClient(socketPath) {
  const call = (method, path, value) => new Promise((resolve, reject) => {
    const body = value === undefined ? undefined : JSON.stringify(value);
    const req = request({ socketPath, method, path, headers: body && {
      'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(body),
    }, signal: AbortSignal.timeout(3000) }, (res) => {
      const chunks = [];
      let size = 0;
      res.on('error', reject);
      res.on('data', (chunk) => {
        size += chunk.length;
        if (size > 4_194_304) req.destroy(new Error('Large GOST response'));
        else chunks.push(chunk);
      });
      res.on('end', () => {
        try {
          resolve({ status: res.statusCode, body: JSON.parse(Buffer.concat(chunks)) });
        } catch (error) {
          reject(error);
        }
      });
    });
    req.on('error', reject);
    req.end(body);
  });

  return {
    async list() {
      const { status, body } = await call('GET', '/config/services');
      if (status !== 200 || !body?.data || (body.data.list !== null && !Array.isArray(body.data.list))) {
        throw new Error('Unexpected GOST list');
      }
      return (body.data.list ?? []).filter(Boolean);
    },
    async checkTailnet() {
      const { status, body } = await call('GET', '/config/chains/tailnet');
      const chain = body?.data;
      const hop = chain?.hops?.[0];
      const node = hop?.nodes?.[0];
      const only = (obj, keys) => Object.keys(obj ?? {}).every((key) => keys.includes(key));
      if (status !== 200 || chain?.name !== 'tailnet' || chain.hops?.length !== 1 || hop?.nodes?.length !== 1 ||
          node?.addr !== '127.0.0.1:1055' || node.connector?.type !== 'socks5' || node.dialer?.type !== 'tcp' ||
          !only(chain, ['name', 'hops']) || !only(hop, ['name', 'nodes']) ||
          !only(node, ['name', 'addr', 'connector', 'dialer']) ||
          !only(node.connector, ['type']) || !only(node.dialer, ['type'])) {
        throw new TunnelError(409, 'The default Tailnet route is unavailable. Check the tailnet chain in GOST.');
      }
    },
    async create(service) {
      const { status, body } = await call('POST', '/config/services', service);
      if (status === 200 && body?.msg === 'OK') return;
      if (status === 400 || status === 500) {
        if (typeof body?.msg === 'string' && body.msg.includes('address already in use')) {
          throw new TunnelError(409, 'That local port is already in use. Choose a different port.', 'listenPort');
        }
        throw new TunnelError(409, 'GOST refused the tunnel. Check that the name and local port are unused.');
      }
      throw new Error('Unexpected GOST create response');
    },
    async remove(name) {
      const { status, body } = await call('DELETE', `/config/services/${encodeURIComponent(name)}`);
      if (status !== 200 || body?.msg !== 'OK') throw new Error('GOST rollback failed');
    },
  };
}
