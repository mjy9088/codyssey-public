#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT INT TERM
site=$work/site
sh "$root/scripts/package-pages.sh" "$site"
test -f "$site/index.html"
test -f "$site/css/style.css"
test -f "$site/js/app.js"
test -f "$site/images/profile-notes.svg"
test -f "$site/.nojekyll"
entries=$(find "$site" ! -path "$site" -prune -exec basename {} \; | LC_ALL=C sort)
test "$entries" = '.nojekyll
css
images
index.html
js'
cmp "$root/coursework/B1-1/index.html" "$site/index.html"
if sh "$root/scripts/package-pages.sh" "$site" >"$work/repeat.log" 2>&1; then
  printf 'Packaging must not overwrite an existing directory\n' >&2
  exit 1
fi
sh "$root/scripts/package-pages.sh" --help >/dev/null
printf 'Pages package checks passed: only B1-1 runtime assets, unchanged HTML, no overwrite\n'
