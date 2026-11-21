#!/usr/bin/env bash
set -euo pipefail
umask 077

media=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P)
expected_user=$(cat "$media/guest-user")
[[ $(uname -s) == Darwin && $(id -u) != 0 && $(id -un) == "$expected_user" ]] || {
  printf 'Run this in the disposable macOS guest as %s.\n' "$expected_user" >&2
  exit 1
}
read -r type blob _ < "$media/host.pub"
[[ $type == ssh-ed25519 && $blob =~ ^[A-Za-z0-9+/=]+$ ]] || {
  printf 'The setup media is missing a valid public key.\n' >&2
  exit 1
}
/usr/bin/ssh-keygen -lf "$media/host.pub" >/dev/null
mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"
authorized="$HOME/.ssh/authorized_keys"
touch "$authorized"
chmod 600 "$authorized"
if ! awk -v type="$type" -v blob="$blob" '$1 == type && $2 == blob { found=1 } END { exit !found }' "$authorized"; then
  printf '\n%s %s\n' "$type" "$blob" >> "$authorized"
fi

tools_dir='/Library/Application Support/VMware Tools'
tools_running=0
remote_login=0
if /usr/bin/pgrep -f "^$tools_dir/vmware-tools-daemon( |$)" >/dev/null; then tools_running=1; fi
if /usr/bin/nc -z -G 2 127.0.0.1 22; then remote_login=1; fi
if (( ! tools_running || ! remote_login )) || [[ ! -r /etc/ssh/ssh_host_ed25519_key.pub ]]; then
  prompt_id=$(cat "$media/prompt-id")
  [[ $prompt_id =~ ^[0-9a-f]{8}$ ]]
  sudo -v -p "Codyssey $prompt_id password: "
fi

if (( ! tools_running )); then
  pkg="$media/VMware Tools.pkg"
  signature=$(/usr/sbin/pkgutil --check-signature "$pkg")
  grep -qF '(EG7KH642X6)' <<< "$signature" || {
    printf 'Expected the VMware-signed Tools package.\n' >&2
    exit 1
  }
  if ! sudo /usr/sbin/installer -pkg "$pkg" -target /; then
    services="$tools_dir/services.sh"
    if [[ ! -x $services ]] || ! sudo "$services" --start; then
      printf 'Review the VMware Tools approval, then run this command again.\n' >&2
      exit 1
    fi
  fi
fi
if [[ ! -r /etc/ssh/ssh_host_ed25519_key.pub ]]; then
  sudo /usr/bin/ssh-keygen -A
fi
read -r type blob _ < /etc/ssh/ssh_host_ed25519_key.pub
"$tools_dir/vmware-tools-daemon" --cmd "info-set guestinfo.codyssey.ssh-host-key $type $blob"
if [[ ! -e $media/automatic-setup ]] && ! /usr/bin/xcode-select -p >/dev/null 2>&1; then
  /usr/bin/xcode-select --install || printf 'Check the Command Line Tools installer in the guest.\n'
fi
if (( ! remote_login )); then
  # Set the Remote Login access list before enabling the system service.
  if ! /usr/bin/dscl . -read /Groups/com.apple.access_ssh >/dev/null 2>&1; then
    sudo /usr/sbin/dseditgroup -o create com.apple.access_ssh
  fi
  sudo /usr/sbin/dseditgroup -o edit -a "$expected_user" -t user com.apple.access_ssh
  sudo /usr/sbin/systemsetup -setremotelogin on || :
  if ! /usr/bin/nc -z -G 2 127.0.0.1 22; then
    # Terminal may lack Full Disk Access. Enable the same system SSH job
    # through launchd and retain the account restriction set above.
    if sudo /bin/launchctl enable system/com.openssh.sshd &&
       ! sudo /bin/launchctl print system/com.openssh.sshd >/dev/null 2>&1; then
      sudo /bin/launchctl bootstrap system /System/Library/LaunchDaemons/ssh.plist || :
    fi
  fi
  if ! /usr/bin/nc -z -G 2 127.0.0.1 22; then
    printf '\nEnable Remote Login for %s in System Settings.\n' "$expected_user"
  fi
fi
if /usr/bin/nc -z -G 2 127.0.0.1 22; then
  "$tools_dir/vmware-tools-daemon" --cmd 'info-set guestinfo.codyssey.setup-state ready'
fi
printf '\nLeave this desktop signed in. The host continues automatically.\n'
