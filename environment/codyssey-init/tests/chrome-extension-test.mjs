import assert from "node:assert/strict";
import {readFileSync, existsSync} from "node:fs";
import {test} from "node:test";
import {runInNewContext} from "node:vm";
import {proxyConfig, changeRouting, readStatus} from "../chrome-extension/proxy.mjs";

test("PAC routes Tailnet destinations without DNS lookup or a direct fallback", () => {
  const context = {};
  runInNewContext(proxyConfig("tailnet").pacScript.data, context);
  for (const host of ["server", "server.example.ts.net", "SERVER.EXAMPLE.TS.NET.",
    "100.64.0.1", "100.127.255.254", "10.2.3.4", "172.16.0.1", "172.31.255.254",
    "192.168.2.3", "[fd7a:115c:a1e0::1]"]) {
    assert.equal(context.FindProxyForURL(`https://${host}/`, host), "SOCKS5 127.0.0.1:1055", host);
  }
  for (const host of ["example.com", "100.63.255.254", "100.128.0.1", "172.15.0.1",
    "172.32.0.1", "192.169.0.1", "100.64.999.1", "localhost", "127.0.0.2",
    "server.localhost", "printer.local", "[::1]", "2001:db8::1", "fake.ts.net.example.com"]) {
    assert.equal(context.FindProxyForURL(`https://${host}/`, host), "DIRECT", host);
  }
  assert.equal(proxyConfig("tailnet").pacScript.mandatory, true);
});

function fakeChrome(level = "controllable_by_this_extension") {
  const previous = {mode: "system"};
  const state = {levelOfControl: level, value: previous};
  const calls = [];
  const api = {runtime: {}, proxy: {settings: {
    get(details, callback) { callback({...state}); },
    set(details, callback) {
      calls.push(["set", details]);
      if (api.runtime.lastError) return callback();
      state.value = details.value;
      state.levelOfControl = "controlled_by_this_extension";
      callback();
    },
    clear(details, callback) {
      calls.push(["clear", details]);
      state.value = previous;
      state.levelOfControl = "controllable_by_this_extension";
      callback();
    }
  }}};
  return {api, calls, state, previous};
}

test("enabling both modes and disabling restores the previous effective proxy", async () => {
  const {api, calls, state, previous} = fakeChrome();
  assert.equal((await readStatus(api)).enabled, false);
  assert.deepEqual(await changeRouting(api, true, "tailnet"), {enabled: true, mode: "tailnet", blocked: false});
  assert.equal((await changeRouting(api, true, "all")).mode, "all");
  assert.deepEqual(state.value.rules.singleProxy, {scheme: "socks5", host: "127.0.0.1", port: 1055});
  assert.equal((await changeRouting(api, false)).enabled, false);
  assert.equal(state.value, previous);
  assert.deepEqual(calls.at(-1), ["clear", {scope: "regular"}]);
});

test("managed and competing proxy settings are not overwritten", async () => {
  for (const level of ["not_controllable", "controlled_by_other_extensions"]) {
    const {api, calls} = fakeChrome(level);
    await assert.rejects(changeRouting(api, true, "tailnet"), /controls the proxy/);
    assert.deepEqual(calls, []);
  }
});

test("invalid modes and Chrome API failures are surfaced", async () => {
  const {api, calls} = fakeChrome();
  await assert.rejects(changeRouting(api, true, "unexpected"), /Choose/);
  assert.deepEqual(calls, []);
  api.runtime.lastError = {message: "Chrome rejected the setting"};
  await assert.rejects(changeRouting(api, true, "tailnet"), /Chrome rejected/);
});

test("manifest uses only the proxy permission and references bundled assets", () => {
  const directory = new URL("../chrome-extension/", import.meta.url);
  const manifest = JSON.parse(readFileSync(new URL("manifest.json", directory)));
  assert.equal(manifest.manifest_version, 3);
  assert.deepEqual(manifest.permissions, ["proxy"]);
  assert.equal(manifest.host_permissions, undefined);
  for (const file of [manifest.background.service_worker, manifest.action.default_popup,
    "proxy.mjs", "popup.mjs", "popup.css", "startup.json"]) assert.ok(existsSync(new URL(file, directory)), file);
});

test("portable startup enables Tailnet once; ordinary installs and updates preserve opt-in", async () => {
  const previousChrome = globalThis.chrome;
  const previousFetch = globalThis.fetch;
  try {
    for (const [enableOnInstall, reason, expected] of [[true, "install", true], [false, "install", false], [true, "update", false]]) {
      const {api} = fakeChrome();
      const handlers = {};
      const event = (name) => ({addListener(callback) { handlers[name] = callback; }});
      let badge;
      api.runtime = {id: "synthetic", getURL: (path) => path, onMessage: event("message"), onInstalled: event("installed"), onStartup: event("startup")};
      api.proxy.settings.onChange = event("change");
      api.proxy.onProxyError = event("error");
      api.action = {async setBadgeText(details) { badge = details.text; }, async setBadgeBackgroundColor() {}, async setTitle() {}};
      globalThis.chrome = api;
      globalThis.fetch = async () => ({json: async () => ({enableOnInstall})});
      await import(`../chrome-extension/background.mjs?startup=${enableOnInstall}-${reason}`);
      handlers.installed({reason});
      for (let attempt = 0; attempt < 20 && badge === undefined; attempt++) {
        await new Promise((resolve) => setImmediate(resolve));
      }
      assert.equal((await readStatus(api)).enabled, expected);
      assert.equal(badge, expected ? "ON" : "");
    }
  } finally {
    globalThis.chrome = previousChrome;
    globalThis.fetch = previousFetch;
  }
});
