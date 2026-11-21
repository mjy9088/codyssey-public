#!/usr/bin/env bash
set -euo pipefail

if [[ ${1:-} == --help ]]; then
  printf 'Usage: bash scripts/prepare-macos-vm.sh --disposable\nInstalls guest tools and starts a dedicated software-emulated Docker VM.\n'
  exit 0
fi
mode=${2:-}
[[ ${1:-} == --disposable && ( $# == 1 || ( $# == 2 && ( $mode == --managed || $mode == --stop ) ) ) ]] || {
  printf 'Use --disposable inside a disposable macOS VM.\n' >&2; exit 1
}
[[ $(uname -s) == Darwin ]] || { printf 'Guest provisioning requires macOS.\n' >&2; exit 1; }
case $(uname -m) in
  arm64) linux_arch=x86_64 ;;
  x86_64) linux_arch=aarch64 ;;
  *) printf 'Unsupported macOS guest architecture.\n' >&2; exit 1 ;;
esac
root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd -P)
. "$root/scripts/vm-guest-path.sh"
[[ $(id -u) != 0 ]] || { printf 'Run as the VM desktop user, not root.\n' >&2; exit 1; }
profile=codyssey-verify
ownership="$HOME/.codyssey-verify-colima"
cancelled="$root/.colima-cancelled"
check_cancelled() {
  if [[ $mode == --managed && -e $cancelled ]]; then
    printf 'Guest Colima preparation was cancelled.\n' >&2
    exit 1
  fi
}
release_profile_lock() {
  rm -f "$ownership/owner" "$ownership/preparing" "$ownership/acquired" && rmdir "$ownership"
}
release_profile() {
  colima stop --profile "$profile" || return
  release_profile_lock
}
if [[ $mode == --stop ]]; then
  : > "$cancelled"
  [[ -f $ownership/owner && $(cat "$ownership/owner") == "$root" ]] || exit 0
  if [[ -f $ownership/preparing ]]; then
    preparing_pid=''
    if ! read -r preparing_pid < "$ownership/preparing"; then
      [[ ! -e $ownership/preparing ]] || exit 1
    fi
    [[ -z $preparing_pid || $preparing_pid =~ ^[1-9][0-9]*$ ]] || exit 1
    deadline=$((SECONDS + 60))
    while kill -0 "$preparing_pid" 2>/dev/null; do
      if (( SECONDS >= deadline )); then
        printf 'Guest Colima preparation is still running.\n' >&2
        exit 1
      fi
      sleep 2
    done
    [[ -f $ownership/owner && $(cat "$ownership/owner") == "$root" ]] || exit 0
  fi
  if [[ -f $ownership/acquired ]]; then
    release_profile
  else
    release_profile_lock
  fi
  exit
fi
if [[ $linux_arch == aarch64 ]] && command -v port >/dev/null; then
  for tool in colima limactl docker qemu-system-aarch64 python3 node; do
    command -v "$tool" >/dev/null || { printf 'Missing preinstalled Intel guest tool: %s\n' "$tool" >&2; exit 1; }
  done
  docker compose version >/dev/null
  docker buildx version >/dev/null
  [[ -d '/Applications/Google Chrome.app' || -d "$HOME/Applications/Google Chrome.app" ]] || {
    printf 'Install Google Chrome in the Intel guest before verification.\n' >&2; exit 1
  }
  install_with_brew=0
elif command -v brew >/dev/null; then
  install_with_brew=1
else
  printf 'Prepare guest tools with Homebrew or the documented Intel MacPorts procedure.\n' >&2
  exit 1
fi

. "$root/lib/preparation.sh"
printf 'Preparing software-emulated test Docker…\n'

colima_owned=0 lock_owned=0
cleanup() {
  result=$?
  trap - EXIT
  if (( colima_owned )); then
    if ! release_profile; then
      printf 'Could not stop the partially prepared Colima profile.\n' >&2
      (( result != 0 )) || result=1
    fi
  elif (( lock_owned )); then
    release_profile_lock || {
      (( result != 0 )) || result=1
    }
  fi
  exit "$result"
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

if ! (umask 077; mkdir "$ownership"); then
  printf 'A guest Colima verification already owns this profile.\n' >&2
  exit 1
fi
lock_owned=1
printf '%s\n' "$$" > "$ownership/preparing"
printf '%s\n' "$root" > "$ownership/owner"
check_cancelled

# Host and guest dependencies are intentionally separate. No nested hypervisor is used.
if (( install_with_brew )); then
  run_quiet_step 'Installing guest tools' brew install colima lima-additional-guestagents docker docker-compose docker-buildx qemu python@3.13 node
  # Base-image preparation deliberately unlinks Docker. brew install alone can
  # leave an already installed formula unlinked.
  if ! command -v docker >/dev/null; then
    run_quiet_step 'Linking test Docker CLI' brew link docker
  fi
  if [[ ! -d '/Applications/Google Chrome.app' && ! -d "$HOME/Applications/Google Chrome.app" ]]; then
    run_quiet_step 'Installing Chrome' brew install --cask google-chrome
  fi
  mkdir -p "$HOME/.docker/cli-plugins"
  for plugin_name in docker-compose docker-buildx; do
    plugin="$HOME/.docker/cli-plugins/$plugin_name"
    if [[ ! -e $plugin && ! -L $plugin ]]; then
      ln -s "$(brew --prefix "$plugin_name")/bin/$plugin_name" "$plugin"
    fi
  done
fi
# Reuse only a stopped, same-architecture verification profile. Colima can
# return success without starting a new VM when the profile is already running.
colima list --json | python3 -c '
import json, sys
for line in sys.stdin:
    profile = json.loads(line)
    if profile["name"] != sys.argv[2]:
        continue
    if profile["status"] != "Stopped" or profile["arch"] != sys.argv[1]:
        sys.exit("The existing verification profile must be stopped and match the Linux architecture.")
' "$linux_arch" "$profile"
# A foreign Linux architecture forces QEMU software emulation on either host.
check_cancelled
: > "$ownership/acquired"
colima_owned=1
# On Intel Fusion, the emulated ARM guest can reach DHCP after Lima's
# default two-minute address-resolution deadline.
if [[ $linux_arch == aarch64 ]]; then
  export LIMA_USERNET_RESOLVE_IP_ADDRESS_TIMEOUT="${LIMA_USERNET_RESOLVE_IP_ADDRESS_TIMEOUT:-10}"
fi
run_quiet_step 'Starting test Docker' colima start --profile "$profile" --vm-type qemu --arch "$linux_arch" \
  --cpu-type max --cpus 2 --memory 4 --disk 30 --runtime docker
colima status --profile "$profile" --json | python3 -c '
import json, sys
status = json.load(sys.stdin)
if (status["driver"], status["arch"], status["runtime"]) != ("QEMU", sys.argv[1], "docker"):
    sys.exit("The running verification profile must use QEMU, the expected Linux architecture, and Docker.")
' "$linux_arch"
docker --context "colima-$profile" info >/dev/null
docker --context "colima-$profile" compose version >/dev/null
if [[ $mode == --managed ]]; then
  # Keep the ownership marker until host cleanup, even if SSH drops the result.
  rm "$ownership/preparing"
  lock_owned=0
fi
colima_owned=0
printf 'Docker ready. Run: DOCKER_CONTEXT=colima-codyssey-verify bash scripts/verify-macos-vm.sh --disposable\n'
