#!/usr/bin/env bash
set -euo pipefail

if [[ ${1:-} == --help ]]; then
  printf 'Usage: bash scripts/prepare-macos-vm.sh --disposable\nInstalls guest tools and starts a dedicated software-emulated Docker VM.\n'
  exit 0
fi
[[ $# == 1 && $1 == --disposable ]] || { printf 'Use --disposable inside a disposable macOS VM.\n' >&2; exit 1; }
[[ $(uname -s) == Darwin && $(uname -m) == arm64 ]] || {
  printf 'Automatic guest provisioning requires Apple Silicon macOS.\n' >&2; exit 1;
}
export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:$HOME/.local/bin:$PATH"
[[ $(id -u) != 0 ]] || { printf 'Run as the VM desktop user, not root.\n' >&2; exit 1; }
command -v brew >/dev/null || { printf 'The guest image must include Homebrew.\n' >&2; exit 1; }

colima_owned=0
cleanup() {
  result=$?
  trap - EXIT
  if (( colima_owned )) && ! colima stop --profile codyssey-verify; then
    printf 'Could not stop the partially prepared Colima profile.\n' >&2
    (( result != 0 )) || result=1
  fi
  exit "$result"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# Host and guest dependencies are intentionally separate. No nested hypervisor is used.
brew install colima lima-additional-guestagents docker docker-compose docker-buildx qemu python@3.13
if [[ ! -d '/Applications/Google Chrome.app' && ! -d "$HOME/Applications/Google Chrome.app" ]]; then
  brew install --cask google-chrome
fi
mkdir -p "$HOME/.docker/cli-plugins"
for plugin_name in docker-compose docker-buildx; do
  plugin="$HOME/.docker/cli-plugins/$plugin_name"
  if [[ ! -e $plugin && ! -L $plugin ]]; then
    ln -s "$(brew --prefix "$plugin_name")/bin/$plugin_name" "$plugin"
  fi
done
# Cross-architecture x86_64 on arm64 forces QEMU TCG rather than Apple's hypervisor.
colima_owned=1
colima start --profile codyssey-verify --vm-type qemu --arch x86_64 \
  --cpu-type max --cpus 2 --memory 4 --disk 30 --runtime docker
docker --context colima-codyssey-verify info >/dev/null
docker --context colima-codyssey-verify compose version
colima_owned=0
trap - EXIT
printf 'Docker ready. Run: DOCKER_CONTEXT=colima-codyssey-verify bash scripts/verify-macos-vm.sh --disposable\n'
