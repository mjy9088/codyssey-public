import { useEffect, useRef, useState, type FormEvent } from 'react';
import { createRoot } from 'react-dom/client';
import './styles.css';

type Input = { name: string; listenPort: string; route: string; destinationHost: string; destinationPort: string };
type Tunnel = { name: string; route: 'loopback' | 'tailnet'; listen: string; destination: string }
  | { name: string; route: 'advanced' | 'runtime' };
type Listing = { tunnels: Tunnel[]; notice?: string };
const storageKey = 'codyssey.tunnel-owner.v1';
const emptyInput: Input = { name: '', listenPort: '', route: 'loopback', destinationHost: '127.0.0.1', destinationPort: '' };

class RequestError extends Error {
  constructor(message: string, readonly status: number, readonly field?: string) {
    super(message);
  }
}

async function request<T>(key: string, input?: Input): Promise<T> {
  const headers: Record<string, string> = { Authorization: `Bearer ${key}` };
  if (input) headers['Content-Type'] = 'application/json';
  const response = await fetch('/api/tunnels', {
    method: input ? 'POST' : 'GET', headers, body: input && JSON.stringify(input),
    signal: AbortSignal.timeout(12_000),
  });
  const data = await response.json();
  if (!response.ok) throw new RequestError(data.error, response.status, data.field);
  return data;
}

function issue(error: unknown) {
  return error instanceof RequestError ? error.message : 'Could not reach the tunnel manager. Try again.';
}

function TunnelList({ listing }: { listing: Listing }) {
  return <section aria-labelledby="tunnel-list">
    <h2 id="tunnel-list">Configured tunnels <span className="count">{listing.tunnels.length}</span></h2>
    {listing.tunnels.length === 0
      ? <p className="empty">No tunnels yet. Add one to forward a local port to a TCP service.</p>
      : <ul className="tunnels">{listing.tunnels.map((tunnel, index) => <li key={`${index}:${tunnel.name}`}>
        <h3>{tunnel.name}</h3>
        {'listen' in tunnel ? <dl className="endpoints">
          <div><dt>Listen on</dt><dd><code>{tunnel.listen}</code></dd></div>
          <div><dt>{tunnel.route === 'tailnet' ? 'Tailnet destination' : 'Local destination'}</dt><dd><code>{tunnel.destination}</code></dd></div>
        </dl> : <p className="hint">{tunnel.route === 'advanced' ? 'Managed in GOST configuration' : 'Running in GOST · not saved to the configuration file'}</p>}
      </li>)}</ul>}
  </section>;
}

function TunnelForm({ add, disabled }: { add: (input: Input) => Promise<void>; disabled: boolean }) {
  const [input, setInput] = useState(emptyInput);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<{ message: string; field?: string }>();
  const [status, setStatus] = useState('');
  const form = useRef<HTMLFormElement>(null);
  const set = (field: keyof Input, value: string) => setInput({ ...input, [field]: value });
  const fieldProps = (field: keyof Input) => ({
    id: field, name: field, value: input[field],
    'aria-invalid': error?.field === field || undefined,
    'aria-describedby': error?.field === field ? 'save-error' : undefined,
  });

  useEffect(() => {
    if (error?.field) form.current?.querySelector<HTMLElement>(`[name="${error.field}"]`)?.focus();
  }, [error]);

  async function submit(event: FormEvent) {
    event.preventDefault();
    if (saving || disabled) return;
    setSaving(true);
    setError(undefined);
    setStatus('Adding tunnel…');
    try {
      await add(input);
      setStatus(`Tunnel ${input.name.trim()} added.`);
      setInput(emptyInput);
    } catch (error) {
      setError({ message: issue(error), field: error instanceof RequestError ? error.field : undefined });
      setStatus('');
    } finally {
      setSaving(false);
    }
  }

  return <section aria-labelledby="add-tunnel">
    <h2 id="add-tunnel">Add a tunnel</h2>
    <form ref={form} onSubmit={submit}>
      <fieldset disabled={disabled || saving} aria-busy={saving}>
        <legend className="sr-only">Tunnel settings</legend>
        <div className="form-grid">
          <label htmlFor="name">Tunnel name<input {...fieldProps('name')} required maxLength={40} placeholder="e.g. dev-preview" onChange={(e) => set('name', e.target.value)} /></label>
          <div>
            <label htmlFor="listenPort">Local port</label>
            <div className="listen-field">
              <span aria-hidden="true">127.0.0.1 :</span>
              <input {...fieldProps('listenPort')} required inputMode="numeric" maxLength={5} placeholder="8080" onChange={(e) => set('listenPort', e.target.value)} />
            </div>
          </div>
          <div className="full">
            <label htmlFor="route">Destination</label>
            <select {...fieldProps('route')} onChange={(e) => {
              const route = e.target.value;
              setInput({ ...input, route, destinationHost: route === 'loopback' ? '127.0.0.1' : '' });
            }}>
              <option value="loopback">This machine</option>
              <option value="tailnet">Tailnet</option>
            </select>
          </div>
          <label htmlFor="destinationHost">{input.route === 'tailnet' ? 'Tailscale IP address' : 'Destination address'}
            <input {...fieldProps('destinationHost')} required readOnly={input.route === 'loopback'} maxLength={45}
              spellCheck={false} autoComplete="off" placeholder="100.64.0.42" onChange={(e) => set('destinationHost', e.target.value)} />
          </label>
          <label htmlFor="destinationPort">Destination port<input {...fieldProps('destinationPort')} required inputMode="numeric" maxLength={5}
            placeholder="3000" onChange={(e) => set('destinationPort', e.target.value)} /></label>
        </div>
        <p className="hint route-hint">{input.route === 'tailnet'
          ? 'Use the peer’s Tailscale IPv4 or IPv6 address. Tailnet access rules still apply.'
          : 'Use a TCP service on the same machine as GOST.'}</p>
        {error && <p id="save-error" role="alert" className="error">{error.message}</p>}
        <button type="submit">{saving ? 'Adding tunnel…' : 'Add tunnel'}</button>
      </fieldset>
      <p role="status" className="status">{status}</p>
    </form>
  </section>;
}

function App() {
  const [key, setKey] = useState(() => sessionStorage.getItem(storageKey) ?? '');
  const [ownerInput, setOwnerInput] = useState('');
  const [listing, setListing] = useState<Listing>();
  const [busy, setBusy] = useState(Boolean(key));
  const [error, setError] = useState('');
  const title = useRef<HTMLHeadingElement>(null);
  const ownerField = useRef<HTMLInputElement>(null);

  function lock() {
    sessionStorage.removeItem(storageKey);
    setKey('');
    setListing(undefined);
    setOwnerInput('');
    setError('');
    requestAnimationFrame(() => ownerField.current?.focus());
  }

  async function load(candidate: string, fromForm = false) {
    setBusy(true);
    setError('');
    try {
      setListing(await request<Listing>(candidate));
      sessionStorage.setItem(storageKey, candidate);
      setKey(candidate);
      setOwnerInput('');
      if (fromForm) requestAnimationFrame(() => title.current?.focus());
    } catch (error) {
      if (error instanceof RequestError && error.status === 401) lock();
      setError(issue(error));
    } finally {
      setBusy(false);
    }
  }

  useEffect(() => { if (key) void load(key); }, []);

  return <main>
    <header className="page-header">
      <div>
        <h1 ref={title} tabIndex={-1}>Codyssey tunnels</h1>
        <p>Forward a local port to a TCP service on this machine or your Tailnet.</p>
      </div>
      {key && listing && <button className="secondary" onClick={lock}>Lock</button>}
    </header>
    {!key ? <section className="unlock" aria-labelledby="unlock">
      <h2 id="unlock">Unlock tunnel management</h2>
      <p>In the Codyssey installation directory, run <code>just tunnel-key</code> and paste the owner key here.</p>
      <form onSubmit={(event) => { event.preventDefault(); if (!busy) void load(ownerInput.trim(), true); }}>
        <label htmlFor="owner-key">Owner key<input ref={ownerField} id="owner-key" type="password" value={ownerInput} maxLength={64}
          autoComplete="off" required onChange={(event) => setOwnerInput(event.target.value)} /></label>
        {error && <p className="error" role="alert">{error}</p>}
        <button disabled={busy}>{busy ? 'Unlocking…' : 'Unlock'}</button>
      </form>
    </section> : !listing ? <section className="unlock" aria-label="Tunnel list status">
      {busy ? <><p role="status">Loading tunnels…</p><div className="loading-lines" aria-hidden="true" /></>
        : <><p className="error" role="alert">{error}</p><button onClick={() => void load(key)}>Retry</button> <button className="secondary" onClick={lock}>Lock</button></>}
    </section> : <>
      {listing.notice && <p className="error" role="status">{listing.notice}</p>}
      <div className="workspace">
        <TunnelForm disabled={Boolean(listing.notice)} add={async (input) => {
          try {
            const tunnel = await request<Tunnel>(key, input);
            setListing((current) => current && { ...current, tunnels: [...current.tunnels, tunnel] });
          } catch (error) {
            if (error instanceof RequestError && error.status === 401) {
              lock();
              setError('The owner key changed. Unlock again with the current key.');
            }
            throw error;
          }
        }} />
        <TunnelList listing={listing} />
      </div>
      <footer>New tunnels listen on <code>127.0.0.1</code> only.</footer>
    </>}
  </main>;
}

createRoot(document.getElementById('root')!).render(<App />);
