# Reproduce workstation verification on an Intel Mac

Install [VMware Fusion 26H1](https://support.broadcom.com/group/ecx/productfiles?subFamily=VMware%20Fusion&displayGroup=VMware%20Fusion%2026H1&release=26H1&os=&servicePk=543219&language=EN&freeDownloads=true) on the Intel host. Sign in to Broadcom if the download page asks. Check the host and guest releases against [Broadcom's macOS guest support policy](https://knowledge.broadcom.com/external/article/301109/vmware-discontinuation-of-latest-macos-a.html).

## Single-command verification

The host needs Fusion Pro, Python 3, Apple Command Line Tools, and about
100 GiB of free space on the VM storage volume. After reviewing the
[macOS license](https://www.apple.com/legal/sla/),
run from `environment/codyssey-init`.

```sh
bash scripts/intel-macos-vm/run-unattended.sh --accept-license
```

When it needs a new base, the script requests Sequoia 15.8.3, formats the new virtual disk, installs
macOS, creates `vmuser` through Setup Assistant with the preset password
`vm user password`, and prepares the base for workstation verification.
Use this preset only for disposable lab VMs. The host drives guest login,
setup, and approval dialogs through the English guest console over Fusion's
loopback interface.
The script saves the `macOS - initial setup complete` snapshot before
installing guest tools and verifies a full clone of the prepared base. On
success, it closes Fusion if no other VMs are running, removes the verification
clone, and retains the stopped base, snapshot, and logs.

Every invocation creates a fresh `runs/unattended.*` directory for verification
and logs, and records the current `HEAD` in `git-commit`. If the last invocation
passed and its prepared base belongs to that commit, the script reuses the base
and starts at step 06. Uncommitted changes do not affect the comparison.

- `--invalidate` forces a new base. Use it to rebuild after uncommitted changes
  or to use different installer media.
- `--no-invalidate` reuses the last prepared base even after a failed run or a
  commit change. It still builds a new base if the saved VM, snapshot, or SSH
  credentials are missing. Forced reuse retains the base's original commit.

The optional installer argument is used when building a new base. The default
installer is cached separately by macOS version and can be reused when rebuilding
the base.
The script leaves older base VMs and logs on disk for inspection.

A rebuilt run writes `01-media.log`, `02-create.log`, `03-installer.log`, `04-prepare.log`
(including step 05), `06-verify.log`, and `07-cleanup.log`. A reused run writes
`base-reuse.log` in place of steps 01–05.

Apple’s `createinstallmedia` requires host administrator privileges when
building an ISO. Authenticate when the host prompts.
[Apple's installer instructions](https://support.apple.com/en-us/101578).

To build a base from an Apple-generated ISO, pass `--invalidate` and append
the ISO path. The script stages it for the new VM.
Set `CODYSSEY_FUSION_HOST_AUTH=dialog` to use the macOS host authorization
dialog.

Step 01 asks the host's Install macOS app to quit after the download, or
before using a supplied installer or cached copy. If the app refuses to quit,
use Command-Q in the host installer window and confirm Quit if prompted. The
script leaves the installer available for the next run. [Apple's installer download instructions](https://support.apple.com/en-us/102662).

The terminal shows native percentages for disk-image conversion and download
progress when the tool reports a total. Full Fusion clones report the bytes
written and elapsed time about every ten seconds. Steps that cannot estimate
completion, such as waiting for SSH or checking signatures, report elapsed
time. Follow the guest installer window for the macOS installation itself.

### Store VMs on an external disk

The scripts use `~/.local/share/codyssey/fusion` by default. To use an external
APFS volume, save the location once from the host Terminal. Subsequent runs
reuse it.

```sh
bash scripts/intel-macos-vm/01-create-install-media.sh --set-storage "/Volumes/Codyssey VM/Codyssey-Fusion"
```

## Numbered recovery steps

Use these steps from `environment/codyssey-init` to diagnose a failed run or
to prepare a base interactively.

If the single command created a run before failing, use its printed directory
as storage when resuming. For a reused base, `base-reuse.log` points to the
original run whose `credentials` directory step 06 uses. If the base uses the
preset `vmuser` password, enable unattended mode to resume its automatic setup.

```sh
export CODYSSEY_FUSION_STORAGE="/path/to/runs/unattended.XXXXXX"
export CODYSSEY_FUSION_CREDENTIALS="/path/to/the/base-run/credentials"
export CODYSSEY_FUSION_KNOWN_HOSTS="$CODYSSEY_FUSION_CREDENTIALS/known_hosts"
export CODYSSEY_FUSION_UNATTENDED=1
```

### 01–02. Build the installer and start the VM

```sh
bash scripts/intel-macos-vm/01-create-install-media.sh
bash scripts/intel-macos-vm/02-create-base-vm.sh
```

Step 01 requests **Sequoia 15.8.3** from Apple, reuses an ISO already produced for
that version, and prompts for host administrator authorization when building the
media. Step 01 remembers the resulting ISO. Step 02 reads that selection and creates and boots a Fusion VM with NAT, no shared folders, four
vCPUs, 8 GiB RAM, and a growable 80 GiB SATA disk. It saves the selected VMX in
`current-base` under the storage directory. The later steps read that file.

In the guest, open Disk Utility, erase the **new virtual SATA disk** (about 86 GB) as
APFS with a GUID partition map, and install macOS there. Complete Setup Assistant
with a disposable local administrator named `vmuser`. Use the preset password
`vm user password` to enable unattended preparation for this base.
During long installs, use the [installer watcher](#watch-a-long-installation).

#### Format the target from the guest Terminal

In the guest installer or Recovery, open **Utilities > Terminal**. List the disks
and inspect the whole disk corresponding to the new VMware virtual SATA disk
(about 86 GB). Replace `diskN` with that disk's identifier.

```sh
diskutil list
diskutil info diskN
```

After confirming the new target, erase only that disk as APFS with a GUID
partition map:

```sh
diskutil eraseDisk APFS "Macintosh HD" GPT diskN
```

Close Terminal and select **Macintosh HD** in the installer. The Recovery Terminal
runs this command before guest SSH and VMware Tools are available.
[Apple's Intel Recovery guide](https://support.apple.com/guide/mac-help/use-macos-recovery-on-an-intel-based-mac-mchl338cf9a8/mac).

#### If the automatic installer path fails

Try the numbered scripts first. If Apple no longer offers the pinned release,
list the host's available installers with `--list` and pass an offered Sequoia
version to step 01. If the download still fails, obtain the full installer from
Apple and pass its path. Step 02 uses the ISO saved by the successful step 01.

```sh
bash scripts/intel-macos-vm/01-create-install-media.sh --list
bash scripts/intel-macos-vm/01-create-install-media.sh VERSION_FROM_LIST
bash scripts/intel-macos-vm/01-create-install-media.sh --app "/Applications/Install macOS Sequoia.app"
```

[Apple installer guidance](https://support.apple.com/en-us/101578) describes the
full installer. If Fusion rejects the generated VM or media, use **File > New >
Install from disc or image** with the printed ISO and create the same 80 GB SATA
disk. [Broadcom's installer-image procedure](https://community.broadcom.com/vmware-cloud-foundation/question/installer-app-not-accepted-for-installing-macos-vm)
also describes attaching a bootable DMG.

If the installer reports package validation errors, try the scripted Recovery
route in [Installer recovery](#installer-recovery).

### 03. Boot the staged installation if needed

If the guest restarts into the installer again after staging macOS on the target
disk, shut down the guest and run:

```sh
bash scripts/intel-macos-vm/03-boot-target-disk.sh
```

This disconnects the installer and starts from the target disk. If Setup
Assistant already opens, continue directly to step 04.

### 04. Prepare the installed base

Shut down the guest from its first desktop after Setup Assistant.

```sh
bash scripts/intel-macos-vm/04-checkpoint-and-mount-tools.sh
```

Step 04 saves the initial desktop checkpoint, disconnects the installer, and
boots the guest with a setup disc containing its VMware Tools package and the
host's public SSH key.

For a disposable `vmuser` account with the preset password, set
`CODYSSEY_FUSION_UNATTENDED=1` when running step 04. With English Finder labels,
Python 3.8 or newer, and host Apple Command Line Tools, step 04 can sign in,
open the setup disc, and handle recognized VMware dialogs. Step 05 uses the
preset for guest package installation over pinned SSH. The lab account
`vmuser` uses public-key SSH in both unattended and manual preparation.
When step 04 starts Fusion itself, it closes Fusion after the guest has stopped.

For manual recovery or a guest with a custom password, clear
`CODYSSEY_FUSION_UNATTENDED` and open
**Start Setup.command** on the **Codyssey** disc, or run
`bash /Volumes/Codyssey/setup.sh` after signing in. Approve any remaining
VMware Tools or Command Line Tools prompts. If SSH is still unavailable, enable
**System Settings > General > Sharing > Remote Login** for the lab
account only, then leave that user signed in. [Apple Remote Login](https://support.apple.com/guide/mac-help/allow-a-remote-computer-to-access-your-mac-mchlp1066/mac).

The host waits for the guest for up to 30 minutes. It reads the SSH host key
directly from the selected VM through VMware Tools and pins it after a strict
SSH connection succeeds. The host prints the current prerequisite as it
progresses. If it is waiting for the guest SSH key, run the setup command in the
guest Terminal and finish any VMware Tools prompts. If it is waiting for SSH or
Command Line Tools, check Remote Login or finish the Apple installer in the
guest. It installs Python from the pinned macOS installer if the harness
needs it. It prepares Google Chrome, OrbStack, Gureum, and iTerm2 in the guest
before shutting down the base and disconnecting the setup disc. Existing valid
bundles are reused. OrbStack is installed without onboarding or starting its
virtualization engine, and Gureum is activated during verification. Step 06 runs
`init.sh`, which installs Node.js through mise when needed. In
manual mode, enter the guest administrator password when prompted. Close the
installer or setup console with Command-W once the base has shut down.

If the host wait is interrupted or an automatic package install fails, leave the
guest running. If needed, install the missing tool using the
[Python installer](https://www.python.org/downloads/release/python-31410/) or
[Google Chrome installer](https://www.google.com/chrome/), then resume on the host.

```sh
bash scripts/intel-macos-vm/05-prepare-base.sh
```

Pass the VMX when resuming an imported base that has yet to be saved.
Set `CODYSSEY_FUSION_PREPARE_TIMEOUT` in seconds for a longer wait.

If step 04 cannot download the Tools image, place Broadcom's published
[`darwin.iso`](https://packages-prod.broadcom.com/tools/frozen/darwin/darwin.iso) in
the VM storage directory under `tools/darwin.iso` and rerun step 04. The host
stores its SSH identity and guest fingerprint pin under
`~/.local/share/codyssey/fusion/credentials`. For another lab account, set
`CODYSSEY_FUSION_GUEST_USER` for steps 04–06.

### 06. Run the workstation verification

```sh
bash scripts/intel-macos-vm/06-verify-workstation.sh
```

Step 06 creates a full clone under `verification/`, writes a private log under
`runs/`, and stops and retains the clone. It checks the installed application
bundles and OrbStack's bundled CLI versions, then runs workstation setup
without starting an engine. In the clone's Terminal, the host sends actual
key events over a temporary loopback Fusion console. The guest must compose
`한`, switch to Latin with Control-Space and enter `abc`, then switch back
with Control-Space and compose `한` again. It also checks the active input
source, macOS preferences, and Dock launcher.

Keep any Fusion window opened by the script available while verification runs.
The lab path uses auto-login and handles the known Gureum approval. A custom
guest account may need a sign-in before verification can start. If reusing
an older base that lacks the apps, run step 05 on the running base first.
The [manual Terminal typing check](verification.md#terminal-typing-check)
is available for troubleshooting.

To reuse a prepared base, copy its complete powered-off `.vmwarevm` bundle.
If prompted in Fusion, choose **I moved it**. With the lab identity and verified
host pin already available, set `CODYSSEY_FUSION_IDENTITY` and
`CODYSSEY_FUSION_KNOWN_HOSTS` to their absolute paths and give step 06 the VMX
once. Otherwise give step 04 the powered-off VMX and run the short guest setup
command when the desktop opens.

```sh
bash scripts/intel-macos-vm/04-checkpoint-and-mount-tools.sh "/path/to/Sequoia.vmwarevm/Sequoia.vmx"
```

A successful explicit run of step 04, 05, or 06 remembers that VMX. Subsequent steps
can run without arguments.

See [VM check scope and cleanup](verification.md#vm-check-scope-and-cleanup) for
the combined service route and cleanup behavior. Set `CODYSSEY_FUSION_VMRUN` if
Fusion is installed in another location.

### 07. Close Fusion after verification

```sh
bash scripts/intel-macos-vm/07-close-fusion.sh
```

This closes Fusion and its consoles once no guest is running.

## Installer recovery

Open **Window > Installer Log** if macOS reports that the installer is damaged.
For `OSISVerifyBaseSystemOperation` or `pkgdmg validation has failed`, inspect the
source media. `hdiutil verify` can check the installer DMGs' image checksums.
The guest still verifies the macOS packages independently.

On a Sequoia host, step 02 looks for the current system's `BaseSystem.dmg` and
tries mounting its Recovery volume read-only if needed. It converts the image and boots a fresh VM with a
separate 80 GB target. Use a new base name to keep the earlier VM for diagnosis.

```sh
bash scripts/intel-macos-vm/02-create-base-vm.sh --recovery
```

If discovery fails, use `diskutil apfs list` to find the Recovery volume and
`diskutil mount readOnly <recovery-volume-id>` to mount it. Locate the compatible
`BaseSystem.dmg` and pass its path after `--recovery`.

In the guest Recovery menu, choose **Reinstall macOS** and install onto the APFS
target disk. If the restart returns to the Recovery menu, use
[step 03](#03-boot-the-staged-installation-if-needed). Continue to step 04 after Setup Assistant.

### Watch a long installation

With `uv` installed on the host, run the watcher for the saved base. It saves the last
screenshot and status JSON in a private run directory, taking one screenshot
every three minutes for up to four hours. A menu candidate indicates a screen
worth inspecting. A timeout exits with status 124.

```sh
bash scripts/intel-macos-vm/02-watch-installation.sh
```
