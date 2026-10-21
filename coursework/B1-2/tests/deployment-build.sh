#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
cd "$root"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
export VITE_USE_EMULATORS=false VITE_ROUTER_MODE=hash
export VITE_FIREBASE_API_KEY=synthetic-deployment-key
export VITE_FIREBASE_AUTH_DOMAIN=synthetic-deployment.firebaseapp.com
export VITE_FIREBASE_PROJECT_ID=synthetic-deployment
for name in VITE_FIREBASE_API_KEY VITE_FIREBASE_AUTH_DOMAIN VITE_FIREBASE_PROJECT_ID; do
  if env "$name=" node node_modules/vite/bin/vite.js build --outDir "$work/rejected" >"$work/build.log" 2>&1; then
    printf 'Remote Firebase build accepted missing %s\n' "$name" >&2
    exit 1
  fi
  grep -q "$name" "$work/build.log"
done
node node_modules/vite/bin/vite.js build --base /codyssey-public/B1-2/ --outDir "$work/site"
grep -q '"/codyssey-public/B1-2/assets/' "$work/site/index.html"
printf 'Remote Firebase builds require all three settings and support the Pages asset prefix\n'
