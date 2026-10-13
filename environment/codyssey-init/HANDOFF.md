# Codyssey environment handoff

This change reproduces the reference classroom environment. It is not a general-purpose macOS
installer. The delivery patch is relative to the **whole repository root**, `codyssey-public`, at
base commit `464c4d15c1d148402345067cca3dd56888397aea`. All changed paths are in
`environment/codyssey-init/`. The patch includes tracked edits and new source files; it excludes
credentials, `.env`, local GOST configuration, browser profiles, downloaded applications, and logs.

## Current keyboard limitation

**Physical Control-Space switching is not confirmed working on this machine.** Gureum's input modes
were initially absent from the registration database despite the app being installed. Registering
the app exposed its modes. Enabling Hangul succeeds, but selecting it currently returns macOS error
`-50`; the input method's parent still reports disabled and the selected source remains ABC.
The script reports that session limitation rather than reporting a working keyboard.

The latest setup reads back imported shortcut preferences before calling Apple's live-reload helper.
Both Control-Space and Control-Shift-Space were then visible as enabled in Carbon's live symbolic
hotkey list. That verifies shortcut registration, not physical key handling or Hangul composition.
Log out and back in, rerun `bash macos-setup.sh --input-only`, and test a focused text field.
If selection still fails, keep that as an unresolved input-method activation issue; do not substitute
Apple Korean and declare this reference environment reproduced.

## Input method installed on this machine

| Property | Observed value |
| --- | --- |
| Product | Gureum (구름), not the goorm cloud service |
| Version | 1.13.2 |
| Installed app | `/Library/Input Methods/Gureum.app` |
| Executable | `/Library/Input Methods/Gureum.app/Contents/MacOS/Gureum` |
| Executable architectures | x86_64 and arm64, universal binary |
| App bundle identifier | `org.youknowone.inputmethod.Gureum` |
| Parent TIS input-source identifier | `org.youknowone.inputmethod.Korean` |
| Hangul 2-set mode | `org.youknowone.inputmethod.Gureum.han2` |
| Gureum QWERTY mode | `org.youknowone.inputmethod.Gureum.qwerty` |
| Existing Latin input source | `com.apple.keylayout.ABC` |
| Earlier bootstrap's Apple Korean mode | `com.apple.inputmethod.Korean.2SetKorean` |

The parent source ID is a legacy name; it is not the app bundle ID. The setup explicitly uses these
installed identifiers. It enables Gureum's parent and Hangul mode while retaining the existing Latin
layout. Only after Gureum selection succeeds does it disable the Apple Korean sources introduced
by the earlier bootstrap, avoiding duplicate Hangul entries during Control-Space switching.

When Gureum 1.13.2 is absent, `scripts/install-gureum.sh` downloads
`https://github.com/gureum/gureum/releases/download/1.13.2/Gureum-1.13.2.pkg`, verifies SHA-256
`eadbc2904e54885eea08f7c410e2adeec4caf8463c1321706cb3d1a3e42612d1`, and expands its
`org.youknowone.inputmethod.Gureum.pkg/Payload/Gureum.app` payload. It copies the app to
`~/Library/Input Methods/Gureum.app` without invoking the privileged package installer. An existing
matching system or per-user app is reused. A differing per-user installation is preserved and reported.
The official package was downloaded, verified, and expanded here; fresh per-user installation and
post-login activation remain part of the future VM test.

## Reference machine and pinned runtime

| Component | Observed version / configuration |
| --- | --- |
| macOS | 15.7.5 |
| Host architecture | x86_64 |
| OrbStack | 2.0.5 |
| Docker CLI | 28.5.2 |
| Docker Compose | 2.40.3 |
| mise | 2026.10.5, macos-x64 |
| just | 1.43.0 |
| Installed Google Chrome | 146.0.7680.165 |
| Portable Chrome for Testing | 155.0.8059.39, mac-x64 |
| Tailscale container | 1.88.3, persistent `tailscale-state` volume |
| System Python | 3.9.6; too old for the native Python test suites |

Swift/Xcode Command Line Tools are available on the reference machine. They are required by the
Carbon input-source helper. The environment-specific live shortcut helper is
`/System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings -u`.
Its presence and behavior on another macOS version are not assumed.

Tailscale's upstream container startup wrapper timed out during browser authentication and
invalidated login URLs by restarting. The replacement entry point waits without that timeout and
persists identity and login state in a named volume. The bootstrap uses the current `AuthURL` from
status before falling back to the latest logged URL. Container restarts reuse the existing identity;
the old memory-only setup needs one login when migrating to persistent state.

The portable browser downloads a pinned, SHA-256-verified Google archive, extracts it into the user
cache, and uses a separate user profile. `just browser` loads the extension automatically. Tailnet
routing enables on first installation; later launches preserve the user's choice. Its SOCKS5 endpoint
is `127.0.0.1:1055`. Public sites stay direct in Tailnet mode; All websites uses the container's egress.
The current OrbStack installation exposes the listener to macOS. Another Docker VM may require
additional forwarding; that is a fresh-VM compatibility check, not a proven portable networking claim.

## Apply and test on a fresh VM later

1. Prepare a disposable macOS VM with a logged-in desktop user, Xcode Command Line Tools, and a
   working Docker Engine with Compose. For the closest reproduction use x86_64 macOS 15.7.5 and
   OrbStack 2.0.5. Installing Docker and command-line tools is outside the bootstrap.
2. Check out the base repository commit. From the repository root, apply the delivered patch:

   ```sh
   git apply --check /path/to/codyssey-public.patch
   git apply /path/to/codyssey-public.patch
   cd environment/codyssey-init
   ```

3. Run `sh scripts/check.sh`. Use the container checks on this reference machine; its Python 3.9.6
   cannot run the native suites, which require Python 3.10 or newer.
4. Run `bash init.sh`. Leave the auth-key prompt blank for browser login. The script installs/reuses
   the pinned Gureum package and portable browser, starts the services, and opens authentication.
   For an initial unattended pass use `CODYSSEY_OPEN_BROWSER=0 bash init.sh`, then `just browser`.
5. If the keyboard step reports pending activation, log out of macOS and back in. Rerun
   `bash macos-setup.sh --input-only`. Do not reboot or log out through automation without coordinating
   the interactive VM session.
6. In a text field, confirm the menu shows Gureum Hangul 2-set and ABC. Press Control-Space in each
   direction and verify actual Hangul composition. Check Control-Shift-Space separately. If the UI
   intercepts the keys, distinguish VM-client forwarding from guest shortcut registration.
7. Confirm `mise` and `just` are available in the setup's final zsh. Run `just bash`, type a command,
   then exit. Run `just browser` and test an authorized Tailnet website. Toggle routing off and on.
8. Run `bash init.sh` again to check reuse and idempotence. Verify a container restart reconnects
   with the same node identity and that short MagicDNS names resolve in `just`. Check `mise --version`
   and `zellij --version` in that shell. Keep private VM evidence outside the public repository.

Shortcut 60 must be enabled with `[32, 49, 262144]`. Shortcut 61 must use `[32, 49, 393216]`.
The previous `786432` value meant Control-Option-Space, not Control-Shift-Space.

The existing `scripts/verify-macos-vm.sh --disposable` workflow remains available for destructive
preference/VM verification, but it does not test a physical Control-Space event or authenticated
Tailnet browsing. A successful automated VM preference check does not establish physical keyboard
handling or resolve input-method selection in every login session. Follow the interactive steps
above, and keep any VM execution evidence in ignored storage.

## Verification and delivery boundaries

The rerunnable checks cover synthetic bootstrap/authentication, macOS plist changes and rollback,
VM orchestration, extension proxy boundaries/precedence, portable-browser download failures,
architecture selection, and browser-launch arguments. A real isolated x86_64 Chrome for Testing
session verified automatic extension loading, initial Tailnet routing, SOCKS5 browsing, and disabling
routing. The arm64 archive was checksum-verified, but its browser was not executed on this x86_64 host.

This authored handoff and the patch were explicitly requested deliverables. The patch is generated
outside the repository and should not be committed back into it. Execution logs, profiles, traces,
and generated results are excluded: they become stale, grow the repository, and can disclose private
machine or Tailnet data. No repository-owned source/output checksum manifest is added; the SHA-256
values here and in download scripts protect external release downloads only.
