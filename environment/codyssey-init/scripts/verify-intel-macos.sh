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
storage=$(fusion_storage_path)
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
CODYSSEY_FUSION_IDENTITY=$(fusion_guest_identity)
export CODYSSEY_FUSION_IDENTITY
identity=$CODYSSEY_FUSION_IDENTITY
pin=$CODYSSEY_FUSION_KNOWN_HOSTS
[[ $identity == /* && $pin == /* ]] || {
  printf 'The identity and known-hosts file must use absolute paths.\n' >&2
  exit 1
}

if [[ -z $prepare && ( ! -r $identity || ! -r $pin ) ]]; then
  printf 'Prepare this base first with scripts/intel-macos-vm/04-checkpoint-and-mount-tools.sh.\n' >&2
  exit 1
fi
fusion_ensure_guest_identity "$identity"

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
  CODYSSEY_FUSION_START_MODE=${CODYSSEY_FUSION_START_MODE:-nogui} \
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
timeout=${CODYSSEY_FUSION_PREPARE_TIMEOUT:-1800}
[[ $timeout =~ ^[1-9][0-9]{0,4}$ ]] || { printf 'Use a positive preparation timeout in seconds.\n' >&2; exit 1; }
deadline=$((SECONDS + timeout))
new_pin=0
if [[ ! -e $pin && ! -L $pin ]]; then
  new_pin=1
  export CODYSSEY_FUSION_KNOWN_HOSTS="$temp/known_hosts"
elif [[ ! -s $pin ]]; then
  printf 'The saved SSH host key file is empty or missing: %s\n' "$pin" >&2
  exit 1
fi
printf 'Keep this host command running while you prepare the guest (up to %s seconds).\n' "$timeout"
previous_status=
while :; do
  if (( new_pin )) && [[ ! -s $temp/known_hosts ]]; then
    # This variable is scoped to the selected VMX through Fusion's guest channel.
    guest_key=$(fusion readVariable "$base" guestVar codyssey.ssh-host-key 2>/dev/null) || guest_key=
    if [[ -n $guest_key ]]; then
      read -r host_type host_blob extra <<< "$guest_key"
      [[ $guest_key != *$'\n'* && $host_type == ssh-ed25519 &&
         $host_blob =~ ^[A-Za-z0-9+/=]+$ && -z $extra ]] || {
        printf 'Invalid Ed25519 host key from the selected VM.\n' >&2
        exit 1
      }
      printf 'codyssey-fusion %s %s\n' "$host_type" "$host_blob" > "$temp/known_hosts"
      ssh-keygen -lf "$temp/known_hosts" >/dev/null
    fi
  fi
  if [[ ! -s $CODYSSEY_FUSION_KNOWN_HOSTS ]]; then
    status='Waiting for the guest SSH key. Open the VM console and run: bash /Volumes/Codyssey/setup.sh'
  else
    vm_init "$base" prepared-base
    if ! fusion_address=$(fusion_guest_address "$base" 2>/dev/null); then
      status='Fusion has not reported a guest IPv4 address. Finish VMware Tools setup and check the guest network.'
    elif fusion_console_ready >/dev/null 2>&1; then
      if vm_exec /usr/bin/xcode-select -p >/dev/null 2>&1; then
        break
      fi
      status='SSH is connected. Finish the Command Line Tools installation in the guest.'
    elif [[ $? == 255 ]]; then
      status="SSH could not connect with the pinned key. Check Remote Login and access for $fusion_user in the guest."
    else
      status="SSH is connected. Sign in to the guest desktop as $fusion_user and leave that session open."
    fi
  fi
  if [[ $status != "$previous_status" ]]; then
    printf '%s\n' "$status"
    previous_status=$status
  fi
  remaining=$((deadline - SECONDS))
  if (( remaining <= 0 )); then
    printf 'Guest preparation timed out. Resolve the condition above, then resume with step 05.\n' >&2
    exit 1
  fi
  if (( remaining > 15 )); then remaining=15; fi
  sleep "$remaining"
done
if (( new_pin )); then
  ln "$temp/known_hosts" "$pin"
  printf 'Verified the SSH host key through Fusion and pinned the connection.\n'
else
  printf 'Using the existing pinned guest connection.\n'
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
printf 'Guest tools are ready.\n'
