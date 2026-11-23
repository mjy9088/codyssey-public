#!/usr/bin/env bash
# Headless guest commands do not inherit the desktop user's package-manager PATH.
case $(uname -m) in
  arm64) vm_brew_prefix=/opt/homebrew ;;
  x86_64) vm_brew_prefix=/usr/local ;;
  *) printf 'Unsupported macOS guest architecture.\n' >&2; return 1 ;;
esac
export PATH="$vm_brew_prefix/opt/python@3.13/libexec/bin:$vm_brew_prefix/bin:$vm_brew_prefix/sbin:$HOME/.local/bin:$PATH"
if [[ $vm_brew_prefix == /usr/local ]]; then
  export PATH="/opt/local/bin:/opt/local/sbin:$PATH"
fi
unset vm_brew_prefix

vm_guest_python_ready() {
  local check='import sys; sys.exit(sys.version_info < (3, 10))'
  if python3 -c "$check" >/dev/null 2>&1; then
    return 0
  fi
  if /usr/local/bin/python3 -c "$check" >/dev/null 2>&1; then
    export PATH="/usr/local/bin:$PATH"
    return 0
  fi
  return 1
}
