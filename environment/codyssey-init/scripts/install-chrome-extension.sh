#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
printf 'In Chrome, enable Developer mode, click Load unpacked, and select:\n%s/chrome-extension\n' "$root"
printf 'Then open Codyssey Tailnet and click Enable routing.\n'
if [ "$(uname -s)" = Darwin ] && [ -d '/Applications/Google Chrome.app' ]; then
  open -a 'Google Chrome' 'chrome://extensions/'
  open "$root/chrome-extension"
fi
