// Keep this function self-contained and ES5-compatible: Chrome runs its source
// in the PAC interpreter, not in the extension's JavaScript environment.
export function FindProxyForURL(url, host) {
  var name = host.toLowerCase().replace(/\.$/, "").replace(/^\[|\]$/g, "");
  if (name === "localhost" || /\.localhost$|\.local$/.test(name) ||
      /^127\./.test(name) || name === "::1") return "DIRECT";

  var parts = name.split(".");
  var ipv4 = parts.length === 4 && parts.every(function (part) {
    return /^\d{1,3}$/.test(part) && Number(part) <= 255;
  });
  var first = Number(parts[0]);
  var second = Number(parts[1]);
  if (/\.ts\.net$/.test(name) || /^fd7a:115c:a1e0:/.test(name) ||
      (name.indexOf(".") === -1 && name.indexOf(":") === -1) ||
      (ipv4 && (first === 10 || (first === 172 && second >= 16 && second <= 31) ||
        (first === 192 && second === 168) ||
        (first === 100 && second >= 64 && second <= 127)))) {
    return "SOCKS5 127.0.0.1:1055";
  }
  return "DIRECT";
}

export function proxyConfig(mode) {
  if (mode === "tailnet") {
    return {mode: "pac_script", pacScript: {
      // Distinguish an explicit Tailnet-only choice from the old default during
      // the one-time upgrade to All websites, without extra storage permission.
      data: "// codyssey-proxy-explicit-tailnet-v1\n" + FindProxyForURL.toString(), mandatory: true
    }};
  }
  if (mode === "all") {
    return {mode: "fixed_servers", rules: {
      singleProxy: {scheme: "socks5", host: "127.0.0.1", port: 1055},
      bypassList: ["localhost", "*.localhost", "127.0.0.0/8", "[::1]", "*.local"]
    }};
  }
  throw new Error("Choose Tailnet sites or All websites.");
}

export async function migrateLegacyRouting(api) {
  const current = await setting(api, "get", {incognito: false});
  if (current.levelOfControl === "controlled_by_this_extension" &&
      current.value.mode === "pac_script" &&
      !current.value.pacScript?.data?.startsWith("// codyssey-proxy-explicit-tailnet-v1\n")) {
    await changeRouting(api, true, "all");
  }
}

function setting(api, method, details) {
  return new Promise((resolve, reject) => {
    api.proxy.settings[method](details, (result) => {
      const error = api.runtime.lastError;
      if (error) reject(new Error(error.message));
      else resolve(result);
    });
  });
}

export async function readStatus(api) {
  const result = await setting(api, "get", {incognito: false});
  const owned = result.levelOfControl === "controlled_by_this_extension";
  return {
    enabled: owned,
    mode: !owned || result.value.mode === "fixed_servers" ? "all" : "tailnet",
    blocked: !["controllable_by_this_extension", "controlled_by_this_extension"].includes(result.levelOfControl)
  };
}

export async function changeRouting(api, enabled, mode) {
  if (enabled) {
    const config = proxyConfig(mode);
    if ((await readStatus(api)).blocked) {
      throw new Error("Another extension or Chrome policy controls the proxy. Disable that proxy extension or ask your administrator.");
    }
    await setting(api, "set", {value: config, scope: "regular"});
    const status = await readStatus(api);
    if (!status.enabled) throw new Error("Chrome did not apply the Tailnet proxy settings.");
    return status;
  }
  // Clear only our setting so a pre-existing system or extension proxy resumes.
  await setting(api, "clear", {scope: "regular"});
  return readStatus(api);
}
