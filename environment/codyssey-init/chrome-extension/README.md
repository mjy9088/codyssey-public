# Codyssey Tailnet for Chrome

This Manifest V3 extension routes Chrome web requests through the bootstrap's SOCKS5 listener at
`127.0.0.1:1055`. It uses only the `proxy` permission, with no content scripts, host permissions,
credentials, remote code, telemetry, or dependencies. Ordinary unpacked installation starts with routing off. The portable launcher uses a private copy
whose first installation enables Tailnet routing automatically.

## Portable browser

Run `just browser` in the bootstrap directory. It downloads a pinned Chrome for Testing archive,
verifies it, and automatically loads a private extension copy in a separate profile. No manual
extension installation is needed. Tailnet routing enables on the first launch; subsequent launches
preserve the user's choice. See [the bootstrap README](../README.md#portable-tailnet-browser).

## Install in ordinary Chrome

1. Start the bootstrap and complete Tailscale browser login.
2. Open `chrome://extensions` in Google Chrome and enable **Developer mode**.
3. Click **Load unpacked** and select this `chrome-extension` directory.
4. Pin **Codyssey Tailnet** using Chrome's Extensions menu. Open it and click **Enable routing**.

The bootstrap prints this directory's absolute path. Installation persists for that Chrome profile;
keep the directory in place. After updating the files, use **Reload** on the Extensions page.
Chrome's supported local installation procedure is documented in its
[extension tutorial](https://developer.chrome.com/docs/extensions/get-started/tutorial/hello-world).

## Routing

**Tailnet sites and private addresses** sends `.ts.net` names, single-label MagicDNS names,
`100.64.0.0/10`, Tailscale IPv6 (`fd7a:115c:a1e0::/48`), and private IPv4 destinations through SOCKS5.
Private IPv4 ranges are `10.0.0.0/8`, `172.16.0.0/12`, and `192.168.0.0/16`; their actual reachability
depends on the container's routes and Tailnet permissions. Public websites stay direct.
Use **All websites** for services at other domain names. Localhost, IPv4 loopback, IPv6 loopback,
and `.local` names stay direct in both modes, including the local GOST dashboard.

The extension does not authenticate Tailscale, install routes on macOS, select an exit node, or
provide a system-wide VPN. SOCKS5 carries browser web connections; WebRTC and other non-web traffic
are outside its scope. Public websites in All websites mode use the container's normal egress unless
an exit node is separately configured. Chrome incognito inherits regular proxy settings.

**Disable routing** clears this extension's override and restores Chrome's previous effective
settings. A conflicting extension or managed proxy policy is reported instead of silently overwritten.
The badge indicates routing configuration, not verified Tailnet connectivity. If the container stops,
matching sites fail until it is restarted and authenticated or routing is disabled; there is no direct
fallback for destinations routed through SOCKS5. A `!` badge means Chrome reported a proxy error.

See the [Chrome proxy API](https://developer.chrome.com/docs/extensions/reference/api/proxy)
for proxy precedence, PAC configuration, and permission details.
