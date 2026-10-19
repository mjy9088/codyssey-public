#!/bin/sh
set -eu
installer=$(mktemp)
trap 'rm -f "$installer"' 0
trap 'exit 1' HUP INT TERM
curl -fsSL https://raw.githubusercontent.com/mjy9088/codyssey-public/main/environment/codyssey-init/init.sh -o "$installer"
bash "$installer"
