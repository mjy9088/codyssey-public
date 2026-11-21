# Portable Tailnet browser

Select Tailnet in the [bootstrap](../README.md), or run the browser commands below from the installed or checked-out `environment/codyssey-init` directory.

## Launch the browser

On macOS the bootstrap now opens a portable **Chrome for Testing 155.0.8059.39** with the Tailnet
extension loaded automatically. No browser installation, Web Store visit, Developer mode toggle, or Load unpacked step is
needed. The launcher chooses `mac-x64` on x86_64 and `mac-arm64` on Apple Silicon, downloads from
Google's versioned archive, verifies its pinned SHA-256, and extracts into
`~/Library/Caches/codyssey-init/`. It reuses the browser on later runs. Failed downloads, checksums,
or extraction leave no installed browser and remove staging files.

```sh
just browser
# Or open a particular website:
bash scripts/tailnet-browser.sh https://server.example.ts.net
# Download and prepare without opening a window:
bash scripts/tailnet-browser.sh --prepare
```

On the first launch and whenever the bundled extension changes, the launcher configures the dedicated
profile automatically: it enables Chrome Developer mode, reloads the unpacked extension, and verifies
that its worker responds. It uses Python 3 from Xcode Command Line Tools and a temporary DevTools
endpoint bound to loopback. Only the dedicated profile is restarted, with tabs restored. The setup
browser and debugging endpoint close before normal Chrome starts. Managed policy or another
extension controlling the proxy produces an error; no macOS permissions or administrator rights
are granted. An unchanged, configured profile opens without this extra restart.

## Profile and routing

The browser uses its own profile and extension copy under
`~/Library/Application Support/codyssey-init/`. All websites routing enables automatically on the first
launch; later launches preserve the user's routing choice. Browser web connections use the local
SOCKS5 listener, with DNS resolution and routing in the container. Custom domain names and advertised
subnet destinations work without a browser allowlist. Localhost, loopback, and `.local` stay direct.
Its popup can select the narrower Tailnet-only mode or disable routing. The 1.1.0 upgrade migrates
an enabled 1.0.0 Tailnet-only configuration to All websites once; disabled routing stays disabled. It needs only the `proxy` permission, and does not
authenticate Tailscale or provide a system-wide VPN. Keep the Tailscale container running and logged in.

The version and archive integrity pins live in `scripts/browser-version.sh`. The browser does not
auto-update; update those pins deliberately to adopt another release. Synthetic tests cover both architecture selections. The disposable browser verifier exercises the
real executable and fresh profile on the guest architecture. The launcher can override its private locations with
`CODYSSEY_BROWSER_CACHE_DIR` and `CODYSSEY_BROWSER_SUPPORT_DIR`.

## Additional extensions

Additional local unpacked extensions can be registered in
`~/Library/Application Support/codyssey-init/unpacked-extension-paths`, one canonical absolute
directory per line. Each directory must contain a regular `manifest.json`. The launcher preserves
registration order and loads each unique valid directory after the built-in Tailnet extension.
The registry itself must be a readable regular file. Relative, stale, non-canonical,
comma-containing, empty, unreadable, and duplicate entries, failed path canonicalization, and
non-regular registry objects are reported and ignored; they never prevent the built-in extension or
browser from launching. Override the parent directory with `CODYSSEY_BROWSER_SUPPORT_DIR` when using
a private test location.

## Installed browser

Use `CODYSSEY_BROWSER=system` to keep the installed-browser behavior. `CODYSSEY_OPEN_BROWSER=0`
skips browser downloads and launches during bootstrap. To install the extension into ordinary Chrome,
run `just chrome-extension`, enable Developer mode, click Load unpacked, and select the printed
`chrome-extension` directory. That ordinary installation starts with routing off.

Chrome for Testing supports [automatic extension loading](https://groups.google.com/a/chromium.org/g/chromium-extensions/c/1-g8EFx2BBY/m/S0ET5wPjCAAJ).
The browser archives come from [Google's Chrome for Testing project](https://github.com/GoogleChromeLabs/chrome-for-testing).
See [the extension documentation](../chrome-extension/README.md) for routing details and troubleshooting.
The SOCKS proxy must be reachable from macOS at `127.0.0.1:1055`; this has been verified on the current
OrbStack installation. Other Docker engines may need port forwarding from their Linux VM.
