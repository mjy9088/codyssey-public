#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: bash scripts/verify-intel-macos.sh BASE.vmx [--prepare]

Prepare a running disposable base once, then shut it down and run without
--prepare to verify a fresh clone. Set CODYSSEY_FUSION_STORAGE to put clones
and logs on another volume. The guest account defaults to vmuser.
EOF
}
[[ ${1:-} != --help ]] || { usage; exit 0; }
[[ $# == 1 || ( $# == 2 && $2 == --prepare ) ]] || { usage >&2; exit 2; }
[[ $(uname -s) == Darwin && $(uname -m) == x86_64 ]] || {
  printf 'This command requires an Intel Mac with VMware Fusion Pro.\n' >&2
  exit 1
}

root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd -P)
. "$root/scripts/vm-fusion.sh"
fusion_tools
base=$(fusion_source_path "$1")
prepare=${2:-}
umask 077
storage=${CODYSSEY_FUSION_STORAGE:-"$HOME/.local/share/codyssey/fusion"}
mkdir -p "$storage"
storage=$(CDPATH='' cd -- "$storage" && pwd -P)
credentials=${CODYSSEY_FUSION_CREDENTIALS:-"$HOME/.local/share/codyssey/fusion/credentials"}
mkdir -p "$credentials"
chmod 700 "$credentials"
credentials=$(CDPATH='' cd -- "$credentials" && pwd -P)
base_id=$(printf '%s' "$base" | shasum -a 256)
base_id=${base_id%% *}
export CODYSSEY_FUSION_GUEST_USER=${CODYSSEY_FUSION_GUEST_USER:-vmuser}
export CODYSSEY_FUSION_KNOWN_HOSTS=${CODYSSEY_FUSION_KNOWN_HOSTS:-"$credentials/$base_id.known_hosts"}
export CODYSSEY_FUSION_IDENTITY=${CODYSSEY_FUSION_IDENTITY:-"$credentials/id_ed25519"}
identity=$CODYSSEY_FUSION_IDENTITY
pin=$CODYSSEY_FUSION_KNOWN_HOSTS
[[ $identity == /* && $pin == /* ]] || {
  printf 'The identity and known-hosts file must use absolute paths.\n' >&2
  exit 1
}

if [[ -z $prepare && ( ! -r $identity || ! -r $pin ) ]]; then
  printf 'Prepare this base first. With its desktop open, rerun with --prepare.\n' >&2
  exit 1
fi
if [[ ! -e $identity && ! -e $identity.pub && ! -L $identity && ! -L $identity.pub ]]; then
  ssh-keygen -t ed25519 -C codyssey-fusion-lab -f "$identity"
fi
[[ -f $identity && -r $identity ]] || { printf 'Missing private key: %s\n' "$identity" >&2; exit 1; }

# A dedicated agent gives the clone one identity and does not change the user's agent.
if [[ ${codyssey_fusion_agent_pid:-} != "${SSH_AGENT_PID:-unstarted}" ]]; then
  # The shell launched by ssh-agent receives the new agent's environment.
  # shellcheck disable=SC2016
  exec ssh-agent /bin/bash -c '
    set -e
    ssh-add "$CODYSSEY_FUSION_IDENTITY"
    export codyssey_fusion_agent_pid=$SSH_AGENT_PID
    exec /bin/bash "$@"
  ' codyssey-fusion "$root/scripts/verify-intel-macos.sh" "$@"
fi

if [[ -z $prepare ]]; then
  mkdir -p "$storage/runs" "$storage/verification"
  run=$(mktemp -d "$storage/runs/intel-workstation.XXXXXX")
  cd "$storage/verification"
  printf 'Cloning %s\nLog: %s/verify.log\n' "$base" "$run"
  /bin/bash "$root/scripts/create-macos-vm.sh" --image "$base" --name "${run##*/}" --workstation \
    2>&1 | tee "$run/verify.log"
  exit
fi

running=$(fusion list)
fusion_list_contains "$base" "$running" || {
  printf 'Open the disposable base and sign in before preparing it.\n' >&2
  exit 1
}
temp=$(mktemp -d "$credentials/.prepare.XXXXXX")
trap 'rm -rf -- "$temp"' EXIT
if [[ -r $pin ]] && vm_init "$base" prepared-base && vm_ready "$base" 2>/dev/null; then
  printf 'Using the existing pinned guest connection.\n'
else
  public_key=$(ssh-add -L)
  read -r key_type key_blob _ <<< "$public_key"
  [[ $key_type == ssh-ed25519 && $key_blob =~ ^[A-Za-z0-9+/=]+$ ]] || {
    printf 'Base preparation requires an Ed25519 identity.\n' >&2
    exit 1
  }

  printf 'Run these two lines in the base VM Terminal as %s.\n\n' "$CODYSSEY_FUSION_GUEST_USER"
  cat <<EOF
umask 077; mkdir -p ~/.ssh && chmod 700 ~/.ssh && touch ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys && (grep -qxF '$key_type $key_blob' ~/.ssh/authorized_keys || printf '\n%s\n' '$key_type $key_blob' >> ~/.ssh/authorized_keys)
cat /etc/ssh/ssh_host_ed25519_key.pub

EOF
  if [[ ! -e $pin && ! -L $pin ]]; then
    printf 'Paste the public host key printed in the VM console: '
    read -r host_type host_blob _
    [[ $host_type == ssh-ed25519 && $host_blob =~ ^[A-Za-z0-9+/=]+$ ]] || {
      printf 'Expected an Ed25519 public host key.\n' >&2
      exit 1
    }
    printf 'codyssey-fusion %s %s\n' "$host_type" "$host_blob" > "$temp/known_hosts"
    ssh-keygen -lf "$temp/known_hosts" >/dev/null
    export CODYSSEY_FUSION_KNOWN_HOSTS="$temp/known_hosts"
  else
    printf 'Press Enter after installing the public key in the guest: '
    read -r _
  fi

  vm_init "$base" prepared-base
  vm_ready "$base" || {
    printf 'Check VMware Tools, Remote Login, the console user and the public keys, then retry.\n' >&2
    exit 1
  }
  if [[ $fusion_known_hosts == "$temp/known_hosts" ]]; then
    ln "$temp/known_hosts" "$pin"
  fi
fi
guest_root=$(vm_exec /usr/bin/mktemp -d /tmp/codyssey-fusion-base.XXXXXX)
[[ $guest_root =~ ^/tmp/codyssey-fusion-base\.[[:alnum:]]{6}$ ]] || {
  printf 'Unexpected guest working directory.\n' >&2
  exit 1
}
tar -C "$root" -cf "$temp/payload.tar" scripts/prepare-fusion-base.sh scripts/vm-guest-path.sh
vm_transfer "$guest_root" "$temp/payload.tar"
fusion_ssh_terminal=-t fusion_ssh /bin/bash "$guest_root/scripts/prepare-fusion-base.sh"
vm_exec /bin/rm -rf -- "$guest_root"
printf 'Base ready. Eject any installer images and shut down the guest, then run this command without --prepare.\n'
