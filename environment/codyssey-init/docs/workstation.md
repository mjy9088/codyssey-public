# macOS workstation settings

Run the [bootstrap](../README.md) to choose workstation settings. Run maintenance commands from the installed or checked-out `environment/codyssey-init` directory.

## iTerm2

iTerm2 is part of the default macOS application setup. A valid existing system or per-user
iTerm2 is reused; otherwise the checksum-pinned universal iTerm2 3.7.7 ZIP is installed
under `~/Applications` without sudo or launching it. The complete bundle is staged before
publication, so failed installs can be retried. See the [checksum source](https://formulae.brew.sh/api/cask/iterm2.json).
The default profile sets **Left Option = Esc+** and enables **Apps can change how keys are reported**,
using user preferences without Accessibility or Automation permission. Other profiles and
Right Option remain unchanged. Existing preferences are backed up privately under
`~/Library/Application Support/codyssey-init/iterm2-backups`. Quit a running iTerm2 and rerun
the same init command from Terminal to apply the settings; custom preference-folder configurations are
preserved and reported for manual setup. See [iTerm2 keyboard settings](https://iterm2.com/documentation-preferences-profiles-keys.html).

## macOS preferences

When personal macOS preferences are selected, this environment disables text automation and configures **Gureum Hangul 2-set**
with **Control-Space for input switching and Command-Space for Spotlight**.
Control-Space is applied automatically without a switching-key prompt. Interactive setup
asks whether to clean up Dock pins and stacks. Enter declines and preserves existing pins
and stacks; explicit Yes keeps Terminal and Chrome. The j terminal launcher is added only
when `j` is separately selected.
Caps Lock remains unsupported. Independent preference groups continue after a failure and
report a nonzero summary status; the bootstrap continues container and browser setup.
To provide choices without prompting:

```sh
CODYSSEY_MACOS_SETUP=1 CODYSSEY_INPUT_SWITCH=control-space CODYSSEY_DOCK_SETUP=1 sh init.sh
```

`macos-setup.sh` refuses non-Darwin systems and never uses `sudo`. Before each independent preference
group, it creates a private per-run backup under
`~/Library/Application Support/codyssey-init/macos-backups/`. It then:

- disables macOS text automation;
- when Dock cleanup is accepted and both Terminal and Google Chrome exist, replaces Dock app pins with those two apps,
  hides recent items and removes folder stacks;
  the `Codyssey j.command` launcher is added only when explicitly selected, and declining cleanup preserves existing pins;
- preserves unrelated input sources while adding Gureum Hangul 2-set once;
- configures Control-Space and Control-Shift-Space for input switching, Command-Space for Spotlight,
  and Option-Command-Space for the Spotlight window, and disables Caps Lock switching; and
- restarts only the current user's Dock process when pins change.

`CODYSSEY_INPUT_SWITCH` accepts `control-space` or `caps-lock`; `CODYSSEY_DOCK_SETUP` accepts `0` or `1`.
Within selected macOS setup, Control-Space is used and existing Dock pins/stacks are preserved
unless `CODYSSEY_DOCK_SETUP=1` is supplied. The standalone maintenance script adds the launcher
only with `CODYSSEY_DOCK_LAUNCHER=1`; the root bootstrap sets that flag from the `j` choice.
`CODYSSEY_MACOS_SETUP=0` explicitly skips all macOS preferences during bootstrap.
`macos-setup.sh --input-only` changes input settings only; `--no-dock` also disables text automation.
`macos-setup.sh --shortcuts-only` applies and verifies the shortcut bindings without changing input sources.
The helper applies shortcuts even when System Settings is open, registers the live WindowServer
bindings directly, and verifies them in a fresh process as well as the writer.
No Screen Recording, Accessibility, administrator privileges, or logout are needed for shortcut setup.

macOS, CPU architecture, Swift/Command Line Tools, Docker, browsers, and apps can differ between
workstations and guests. For a failure, see [how to compare environments](bootstrap.md#comparing-environments).

## Gureum installation and approval

When Gureum is absent, `scripts/install-gureum.sh` verifies the SHA-256 of the pinned 1.13.2
package and extracts it into `~/Library/Input Methods/Gureum.app` without sudo. An existing
bundle with the expected identifier and an executable is reused at its installed version. A
per-user bundle takes precedence over a system-wide bundle. Swift and the Xcode Command Line
Tools are required for Carbon registration and selection.

`enable-korean.swift` registers the installed app, enables its parent source
`org.youknowone.inputmethod.Korean` and Hangul mode `org.youknowone.inputmethod.Gureum.han2`, and attempts
to select Hangul. The legacy parent ID differs from the app's bundle ID,
`org.youknowone.inputmethod.Gureum`. After successful Gureum selection, it disables the Apple Korean
sources added by the earlier bootstrap. Choose Allow if macOS prompts. For up to 120 seconds the
helper services its run loop and attempts activation once the Hangul mode is enable-capable.
Gureum's QWERTY source uses `org.youknowone.inputmethod.Gureum.qwerty`. A stock ABC layout
uses `com.apple.keylayout.ABC`.
If the parent remains unavailable for 15 seconds or macOS rejects automatic selection with status
-50, the helper asks you to finish any pending Allow dialog. You can select Gureum Hangul 2-set
in the Input menu while the same run watches the current desktop input source. Add it under
**System Settings → Keyboard → Text Input → Edit** if needed. If it is listed but will not switch,
switch to a working source and try removing and re-adding just Gureum. If the installed input
method still does not appear in the picker, save your work and follow the
[Gureum installation instructions](https://github.com/gureum/gureum#수동-설치).

Carbon requires both the parent input source and the Hangul mode to be enabled before selecting
the mode. An accepted enable request can still be waiting for Allow. The helper re-reads live
state, treats a missing Carbon lookup as unavailable, and retries failed parent requests at
intervals. It leaves an accepted request pending to avoid reopening the approval dialog.

Even after both sources are enabled, Carbon may return -50. The helper shows the desktop recovery instructions once and retries at a slower
cadence for the rest of the activation window. This lets a pending approval finish or a manual
selection take effect. Completion requires Gureum to be the current input source. The desktop
typing check separately verifies that the active source actually composes Hangul.

Timeouts report observed TIS state and status codes while the remaining preference groups
continue. Keep a working Latin layout and Apple Korean available until Gureum is usable. To
retry in the same session after selecting Gureum:

```sh
bash macos-setup.sh --input-only
```

## Diagnosing stalled Gureum approval

On registration failure or timeout, the helper writes a timestamped trace to stderr. It includes
changes in the live parent and Hangul mode flags, membership in the enabled-only list, the
current source, and Carbon return codes. Carbon does not identify the time of an Allow click
in this trace. Record that time separately to correlate it with the observed state changes.

For a stalled approval, run the following from the installed setup directory in a second
Terminal window on the affected desktop. Compile the helper before reproducing so Swift startup
does not delay the snapshot. Use the same probe after signing back in.

```sh
probe_dir=$(mktemp -d)
printf 'Probe and log directory: %s\n' "$probe_dir"
/usr/bin/swiftc enable-korean.swift -o "$probe_dir/gureum-probe"

# While Allow is visible
"$probe_dir/gureum-probe" --diagnose-gureum snapshot 2>&1 | tee "$probe_dir/before-allow.log"

# Immediately after clicking Allow
"$probe_dir/gureum-probe" --diagnose-gureum snapshot 2>&1 | tee "$probe_dir/after-allow.log"

# If the parent stays disabled after approval and setup exits
"$probe_dir/gureum-probe" --diagnose-gureum retry-parent 2>&1 | tee "$probe_dir/retry-parent.log"

# If it still stays disabled, log out and back in and set probe_dir to the printed path.
"$probe_dir/gureum-probe" --diagnose-gureum snapshot 2>&1 | tee "$probe_dir/after-login.log"
```

The snapshot reads live state without changing settings. The explicit retry can trigger an
approval prompt and samples state for five seconds after its single enable request. Neither
diagnostic selects an input source or removes Apple Korean.

## Verifying shortcuts

Control-Space uses symbolic hotkey 60 with parameters `[65535, 49, 262144]`; Control-Shift-Space uses 61
with `[65535, 49, 393216]`. The old value `786432` was Control-Option-Space. After synchronizing preferences through CFPreferences,
the setup registers and enables the live bindings through SkyLight, waits for asynchronous application,
and verifies their values and enabled state. These private APIs target the reference macOS version;
missing symbols produce an error for this group while other setup groups continue.
Loaded shortcut registration does not prove physical key handling; test both Korean and English in a
focused text field. The setup does not automatically replace Gureum with Apple Korean when Caps Lock fails.
For a live check, type `gksrmf` in an editable document and verify that it composes `한글`.
Use Control-Space to switch in both directions and Command-Space to open Spotlight. If a focused
app switches input sources automatically, select Gureum again in that app before checking.
In Terminal, `/usr/bin/swift enable-korean.swift --current-source` prints the active source ID.

## Restoring a preference backup

Every successful domain export is retained as `text.plist`, `dock.plist`,
`input-sources.plist`, or `hotkeys.plist` in the backup directory printed by the script. To restore a
particular run manually, set `backup` to that printed directory and import the snapshots that exist:

```sh
backup="$HOME/Library/Application Support/codyssey-init/macos-backups/run.REPLACE_ME"
defaults import NSGlobalDomain "$backup/text.plist"
defaults import com.apple.dock "$backup/dock.plist"
defaults import com.apple.HIToolbox "$backup/input-sources.plist"
defaults import com.apple.symbolichotkeys "$backup/hotkeys.plist"
killall -u "$USER" Dock
```

If a group has a `.missing` marker instead of a plist, that domain was confirmed absent before the
write. Restore that state with `defaults delete DOMAIN` rather than importing a file. Run only the
commands corresponding to files or markers in that backup directory. `NSGlobalDomain` is never
classified as absent.
Restoring a whole domain also reverts later changes in that domain. Restart affected applications;
input-source and shortcut changes may require logging out and back in.

## Dock launcher

Opting into `j` pins `Codyssey j.command` in the document area of the Dock. Clicking it opens
Terminal in this installation and runs `just`, with the user-local mise tools on PATH. It does not
require the optional global `j` wrapper. An unowned launcher is preserved. Declining Dock cleanup keeps existing pins, stacks and recent-app settings, and, when explicitly selected, adds only the j launcher without duplicates. Run
`CODYSSEY_DOCK_LAUNCHER=1 bash macos-setup.sh --desktop-only` to explicitly add the launcher.
Dock tiles use typed XML plist values: URL type 15 and file types are integers, not OpenStep
strings. This setup targets fresh installations; it does not migrate malformed tiles from older installs.

Notification dismissal is not automated: controlling Notification Center requires separate
Accessibility permission. Clear existing notifications manually. To suppress future banners,
enable Do Not Disturb in Control Center or disable unwanted apps in System Settings > Notifications.
Those are per-user settings and require no administrator password.
