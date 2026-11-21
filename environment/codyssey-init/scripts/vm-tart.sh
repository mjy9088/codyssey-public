#!/usr/bin/env bash
# Tart VM lifecycle and Guest Agent transport.
vm_init() {
  tart_image=$1 tart_name=$2 tart_root=$3
  if [[ $tart_image == */* && ! $tart_image =~ @sha256:[0-9a-f]{64}$ ]]; then
    printf 'Registry VM images must be pinned with @sha256:<64 lowercase hex digits>.\n' >&2; return 1
  fi
  [[ $(sw_vers -productVersion | cut -d . -f 1) -ge 14 ]] || { printf 'tart exec requires macOS 14+.\n' >&2; return 1; }
  command -v mise >/dev/null || { printf 'Install mise on the host first.\n' >&2; return 1; }
  # Name only Tart so unrelated configured tools are not installed. An explicit
  # install also works when mise's automatic installation setting is disabled.
  MISE_QUIET=1 mise -C "$tart_root" -E vm install tart
  export TART_NO_AUTO_PRUNE=1
  tart --version >/dev/null
}

tart() { MISE_QUIET=1 mise -C "$tart_root" -E vm exec tart -- tart "$@"; }
vm_clone() { tart clone "$tart_image" "$tart_name"; }
vm_start() {
  tart set "$tart_name" --cpu 4 --memory 8192
  tart_log=$(mktemp "${TMPDIR:-/tmp}/codyssey-tart.XXXXXX")
  MISE_QUIET=1 mise -C "$tart_root" -E vm exec tart -- tart run --no-graphics "$tart_name" \
    </dev/null >"$tart_log" 2>&1 &
  tart_runner=$!
}
vm_running() {
  if kill -0 "$tart_runner" 2>/dev/null; then
    return 0
  fi
  tail -n 12 "$tart_log" >&2
  return 1
}
vm_ready() { vm_exec /usr/bin/true; }
vm_exec() { tart exec "$tart_name" "$@"; }
vm_transfer() { tart exec -i "$tart_name" /usr/bin/tar -xf - -C "$1" <"$2"; }
vm_stop() {
  local status=0
  tart stop "$tart_name" || status=$?
  if [[ -n ${tart_runner:-} ]]; then
    kill "$tart_runner" 2>/dev/null || true
    wait "$tart_runner" 2>/dev/null || true
  fi
  if [[ -n ${tart_log:-} ]]; then
    rm -f "$tart_log"
  fi
  return "$status"
}
vm_delete() { tart delete "$tart_name"; }
vm_recovery() {
  printf 'Tart log: %s\n' "$tart_log" >&2
}
vm_retained() {
  printf 'Open: mise -C %q -E vm exec tart -- tart run %q\n' "$tart_root" "$tart_name"
  printf 'Delete: mise -C %q -E vm exec tart -- tart delete %q\n' "$tart_root" "$tart_name"
}

vm_desktop_preflight() { :; }
vm_desktop_exec() {
  shift 2 # Tart Guest Agent already runs in the desktop session.
  vm_exec "$@"
}
