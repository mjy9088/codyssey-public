# Reproduce workstation verification on an Intel Mac

Use this guide to create or move a disposable Intel macOS VM in Fusion, register it with the host, and run the workstation check.

Install Fusion Pro on the Intel host and open this repository's `environment/codyssey-init`
directory in Terminal. Use a Fusion release with `vmrun` and `vmcli` in
`/Applications/VMware Fusion.app/Contents/Library`. If you have a verified base, copy its
complete powered-off `.vmwarevm` bundle to the new Mac and skip to
[Run the verification](#run-the-verification). Check the host and guest releases against
[Broadcom's macOS guest support policy](https://knowledge.broadcom.com/external/article/301109/vmware-discontinuation-of-latest-macos-a.html).

## Create the base once

1. Choose where to keep VM files. The default is `~/.local/share/codyssey/fusion`. To keep VM
   files on an external APFS volume, set the following in the host Terminal:

   ```sh
   export CODYSSEY_FUSION_STORAGE="/Volumes/Codyssey VM/Codyssey-Fusion"
   ```

2. Download a compatible full macOS installer from Apple and build the Fusion disk image.
   This example uses Sequoia 15.8.3 if Apple still offers it. Use
   `softwareupdate --list-full-installers` to see the versions offered to this host.
   Skip the download if the full installer app is already in Applications.

   ```sh
   softwareupdate --fetch-full-installer --full-installer-version 15.8.3
   storage="${CODYSSEY_FUSION_STORAGE:-$HOME/.local/share/codyssey/fusion}"
   bash scripts/create-fusion-installer.sh "/Applications/Install macOS Sequoia.app" \
     "$storage/installers/Sequoia-15.8.3.dmg"
   ```

   The script asks for host administrator authorization and builds the installer on a
   temporary disk image. [Apple bootable installer instructions](https://support.apple.com/en-us/101578).
   [Fusion installer-image procedure](https://community.broadcom.com/vmware-cloud-foundation/question/installer-app-not-accepted-for-installing-macos-vm).

3. In Fusion, choose **File > New > Install from disc or image** and select the DMG.
   Save the base bundle on the chosen volume, for example under `bases/`. Use NAT, turn
   off shared folders and folder mirroring, and give the VM four vCPUs, 8 GiB RAM and
   an 80 GiB growable SATA disk. In the macOS installer, use Disk Utility to erase the
   **new virtual SATA disk** as APFS with a GUID partition map, then install macOS there.
   If media validation fails, see [Installer recovery](#installer-recovery).

4. Complete Setup Assistant with a disposable local administrator named `vmuser` and a
   unique password stored in your password manager. At the first desktop, eject the
   installer and take a Fusion snapshot if you want a checkpoint before installing tools.
   Install VMware Tools from Fusion's **Virtual Machine** menu. Approve its signed extension
   and restart the guest if macOS asks.

5. In the guest, enable **System Settings > General > Sharing > Remote Login** for the
   lab account. Install Command Line Tools with `xcode-select --install`,
   [MacPorts](https://www.macports.org/install.php), and
   [Google Chrome](https://www.google.com/chrome/) from their official installers.
   Leave the guest signed in, then run the preparation command below on the host.
   [Apple Remote Login settings](https://support.apple.com/guide/mac-help/allow-a-remote-computer-to-access-your-mac-mchlp1066/mac).

## Run the verification

From `environment/codyssey-init` on the host, set `base` to the VMX inside the disposable
base bundle. If the VM was moved, open it in Fusion and choose **I moved it** if prompted.
With the base running and signed in, register this host and check the guest once:

```sh
base="/path/to/bases/Sequoia.vmwarevm/Sequoia.vmx"
bash scripts/verify-intel-macos.sh "$base" --prepare
```

The script prepares a dedicated host SSH key, prints two commands to run in the
guest Terminal, and asks for the public host key displayed in the Fusion console.
After the pinned connection succeeds, it installs missing Python and Node through
MacPorts and checks the guest prerequisites. Enter the guest administrator
password if `sudo` asks. The key and base-specific host pin are stored on the host under
`~/.local/share/codyssey/fusion/credentials`. For a different lab account, set
`CODYSSEY_FUSION_GUEST_USER` before both commands.

Shut down the prepared base, then start a verification run:

```sh
bash scripts/verify-intel-macos.sh "$base"
```

See [what the VM checks cover](verification.md#vm-check-scope-and-cleanup).

The command writes a private log in `runs/`, creates the full clone in `verification/`,
and runs the workstation checks without Docker. The checks cover preference reapplication,
the saved Dock pins, the launcher's `--list` output, and live shortcut settings.
The clone is stopped and retained so
you can inspect it or open the separate [Terminal typing check](verification.md#terminal-typing-check).
Sign in if the clone waits at the login window, and approve Gureum on its first activation.
For unattended reruns, use a reviewed base with lab auto-login and Gureum approval
already configured.

If you already have the lab identity and verified host pin, set
`CODYSSEY_FUSION_IDENTITY` and `CODYSSEY_FUSION_KNOWN_HOSTS` to their absolute paths to
reuse them. Keep the private key on the host. Use `create-macos-vm.sh` directly for the
optional combined Docker route or to select a clone name and cleanup policy. The combined
Intel route also requires `lima +additional_guestagents`, `colima`, `docker`,
`docker-compose-plugin`, and `docker-buildx-plugin` in the base. Set
`CODYSSEY_FUSION_VMRUN` for a nonstandard Fusion installation.

## Installer recovery

If the installer offers the volume and then reports that the installer is damaged,
open **Window > Installer Log** and record the failed operation. If the log reports
`OSISVerifyBaseSystemOperation` or `pkgdmg validation has failed`, keep the guest disk
and investigate the installer media. On the host, mount the installer image read-only and use
`hdiutil verify` on `BaseSystem/BaseSystem.dmg` and the installer app's
`Contents/SharedSupport/SharedSupport.dmg`. These checks validate image checksums.
The guest installer performs its own package validation.

If the attached installer fails package validation, standalone Apple Recovery offers
**Reinstall macOS**, which downloads the installation assets through the guest's NAT
connection. Use a compatible Apple `BaseSystem.dmg` from the host Recovery volume
and keep the formatted SATA target disk. Use `diskutil apfs list` to identify the
volume with the Recovery role and `diskutil mount readOnly <recovery-volume-id>`
to access it if it is unmounted. Find `BaseSystem.dmg` in the volume's system
directory and select the image for the intended macOS release.

Power off the disposable VM and run this from `environment/codyssey-init`, using the path
to the base bundle that already has the SATA target disk:

```sh
bash scripts/create-fusion-installer.sh --recovery /path/to/BaseSystem.dmg \
  "/path/to/Sequoia.vmwarevm/RecoveryMedia.vmdk"
```

In the powered-off lab VM's VMX, keep the existing target disk on `sata0:0`, replace
the CD/DVD device's `sata0:1.*` entries with the settings below, and connect the existing
NAT adapter. Start the VM with Fusion or the CLI.

```text
sata0:1.present = "TRUE"
sata0:1.fileName = "RecoveryMedia.vmdk"
sata0:1.startConnected = "TRUE"
sata0:1.mode = "independent-nonpersistent"
bios.hddOrder = "sata0:1,sata0:0"
```

To start the VM from a terminal, use:

```sh
"/Applications/VMware Fusion.app/Contents/Library/vmrun" -T fusion \
  start "/path/to/guest.vmx" gui
```

In the console, select **Reinstall macOS** and choose the guest's `Macintosh HD`.
If the installer reboots into the standalone Recovery menu, shut down from the
guest's Apple menu. With the VM powered off, set `sata0:1.present = "FALSE"` and
`bios.hddOrder = "sata0:0"` in the VMX, then restart to continue from the staged
installation on the target disk. Leave the Recovery disk disconnected when using
the installed guest as a base.

To monitor a running installation from a terminal, use `uv` and Fusion's `vmcli`:

```sh
storage="${CODYSSEY_FUSION_STORAGE:-$HOME/.local/share/codyssey/fusion}"
mkdir -p "$storage/runs"
run=$(mktemp -d "$storage/runs/watch.XXXXXX")
uv run --no-build scripts/watch-fusion-installer.py \
  --vmx "/absolute/path/to/base.vmx" --output-dir "$run"
```

The watcher defaults to one capture per minute for up to one hour. Use `--interval` and
`--timeout` to change those values in seconds. It keeps the latest `screen.png` and
`status.json` in the chosen directory. A `menu-candidate` means enough of the frame has changed from
the black boot background to inspect for the installer menu. Check the screenshot before interacting with it.
Once installation starts, use a new output directory and add
`--monitor --interval 180 --timeout 14400` to capture every three minutes for up to four hours.
In monitor mode, a `menu-candidate` is recorded and capture continues. Check the screenshot
for Setup Assistant or an installer error, then stop the watcher with Ctrl-C.
If screen capture fails and Fusion's inventory omits the VM, the watcher emits `not-listed`
and returns status 1. Confirm the actual power state before restarting or editing the VM.
A timeout returns 124. Store the watch directory outside
the repository and use a separate directory for each watcher.

If Fusion lacks the macOS Tools image, attach Broadcom's
[Darwin Tools ISO](https://packages-prod.broadcom.com/tools/frozen/darwin/darwin.iso)
as the guest CD/DVD and install the VMware-signed package inside the guest.
Check from the host that VMware Tools reports an address:

```sh
"/Applications/VMware Fusion.app/Contents/Library/vmrun" -T fusion \
  getGuestIPAddress "/path/to/base.vmx"
```

Eject temporary images before shutting down the base.
