# Reproduce workstation verification on an Intel Mac

Install [VMware Fusion 26H1](https://support.broadcom.com/group/ecx/productfiles?subFamily=VMware%20Fusion&displayGroup=VMware%20Fusion%2026H1&release=26H1&os=&servicePk=543219&language=EN&freeDownloads=true) on the Intel host. Sign in to Broadcom if the download page asks. Check the host and guest releases against [Broadcom's macOS guest support policy](https://knowledge.broadcom.com/external/article/301109/vmware-discontinuation-of-latest-macos-a.html).

Run the numbered scripts from `environment/codyssey-init` in a host Terminal.
They use `~/.local/share/codyssey/fusion` by default. To select an external APFS
volume, run this once before step 01. The choice is stored on the host and reused
in later Terminal sessions.

```sh
bash scripts/intel-macos-vm/01-create-install-media.sh --set-storage "/Volumes/Codyssey VM/Codyssey-Fusion"
```

## 01–02. Build the installer and start the VM

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
with a disposable local administrator named `vmuser`. Save its unique password
in your password manager. During long installs, use the [installer watcher](#watch-a-long-installation).

### If the automatic installer path fails

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

## 03. Boot the staged installation if needed

If the guest restarts into the installer again after staging macOS on the target
disk, shut down the guest and run:

```sh
bash scripts/intel-macos-vm/03-boot-target-disk.sh
```

This disconnects the installer and starts from the target disk. If Setup
Assistant already opens, continue directly to step 04.

## 04–05. Prepare the installed base

Shut down the guest from its first desktop after Setup Assistant.

```sh
bash scripts/intel-macos-vm/04-checkpoint-and-mount-tools.sh
```

Step 04 saves the initial desktop checkpoint, disconnects the installer, attaches
the checksum-verified VMware Tools image, boots the guest, and prints the guest
Terminal commands for VMware Tools and Command Line Tools.

Paste those commands into the guest Terminal. Approve any macOS dialogs and
restart if prompted. Enable **System Settings > General > Sharing > Remote Login**
for the lab account only, then leave that user signed in. [Apple Remote Login](https://support.apple.com/guide/mac-help/allow-a-remote-computer-to-access-your-mac-mchlp1066/mac).

```sh
bash scripts/intel-macos-vm/05-prepare-base.sh
```

Step 05 prints the one-time guest Terminal commands for SSH registration. Paste the
public host key displayed in the guest console back into the host prompt. The
script then installs any missing MacPorts, Python, Node.js, and Google Chrome in
the guest. Enter the guest administrator password when prompted. Existing tools
are reused. The script shuts down the base and disconnects its VMware Tools image.

If an automatic package install fails, install the missing tool using the
[MacPorts installer](https://www.macports.org/install.php) or
[Google Chrome installer](https://www.google.com/chrome/) and rerun step 05.
If step 04 cannot attach the Tools image, use **Virtual Machine > Install VMware
Tools** in Fusion or attach Broadcom's
[Darwin Tools ISO](https://packages-prod.broadcom.com/tools/frozen/darwin/darwin.iso).
The host key is stored under `~/.local/share/codyssey/fusion/credentials`.
For another lab account, set `CODYSSEY_FUSION_GUEST_USER` before steps 05 and 06.

## 06. Run the workstation verification

```sh
bash scripts/intel-macos-vm/06-verify-workstation.sh
```

Step 06 creates a full clone under `verification/`, writes a private log under
`runs/`, and stops and retains the clone. It checks macOS preferences, the Dock
launcher, and live shortcut settings without Docker. Sign in if the clone waits
at login, and approve Gureum on its first activation. A base with lab auto-login
and prior Gureum approval supports unattended runs. Use the separate
[Terminal typing check](verification.md#terminal-typing-check) to test actual
Hangul and Latin input.

To reuse a prepared base, copy its complete powered-off `.vmwarevm` bundle.
If prompted in Fusion, choose **I moved it**. With the lab identity and verified
host pin already available, set `CODYSSEY_FUSION_IDENTITY` and
`CODYSSEY_FUSION_KNOWN_HOSTS` to their absolute paths and give step 06 the VMX
once. Otherwise start the base and give step 05 the VMX once.

```sh
bash scripts/intel-macos-vm/05-prepare-base.sh "/path/to/Sequoia.vmwarevm/Sequoia.vmx"
```

A successful explicit run of step 05 or 06 remembers that VMX. Subsequent steps
can run without arguments.

See [VM check scope and cleanup](verification.md#vm-check-scope-and-cleanup) for
the combined service route and cleanup behavior. Set `CODYSSEY_FUSION_VMRUN` if
Fusion is installed in another location.

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
