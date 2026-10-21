#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT INT TERM
site=$work/site
sh "$root/scripts/package-pages.sh" "$site"
test -f "$site/index.html"
test -f "$site/B1-1/css/style.css"
test -f "$site/B1-1/js/app.js"
test -f "$site/B1-1/images/profile-notes.svg"
test -f "$site/.nojekyll"
entries=$(find "$site" ! -path "$site" -prune -exec basename {} \; | LC_ALL=C sort)
test "$entries" = '.nojekyll
B1-1
index.html'
cmp "$root/coursework/B1-1/index.html" "$site/B1-1/index.html"
grep -q 'href="B1-1/"' "$site/index.html"
! grep -q 'href="B1-2/"' "$site/index.html"
if sh "$root/scripts/package-pages.sh" "$site" >"$work/repeat.log" 2>&1; then
  printf 'Packaging must not overwrite an existing directory\n' >&2
  exit 1
fi
sh "$root/scripts/package-pages.sh" --help >/dev/null
dist=$work/dist
mkdir -p "$dist/assets"
printf '<html>synthetic built frontend</html>\n' >"$dist/index.html"
printf 'console.log("synthetic");\n' >"$dist/assets/app.js"
printf 'body { color: black; }\n' >"$dist/assets/app.css"
printf 'must not publish\n' >"$dist/.env"
printf 'must not publish\n' >"$dist/source.ts"
sh "$root/scripts/package-pages.sh" "$work/combined" "$dist"
grep -q 'href="B1-2/"' "$work/combined/index.html"
cmp "$dist/index.html" "$work/combined/B1-2/index.html"
cmp "$dist/assets/app.js" "$work/combined/B1-2/assets/app.js"
test ! -e "$work/combined/B1-2/.env"
test ! -e "$work/combined/B1-2/source.ts"
printf 'must not publish\n' >"$dist/assets/app.js.map"
if sh "$root/scripts/package-pages.sh" "$work/rejected-map" "$dist"; then
  printf 'Packaging must reject non-runtime assets\n' >&2; exit 1
fi
rm "$dist/assets/app.js.map"
ln -s "$dist/.env" "$dist/assets/link.js"
if sh "$root/scripts/package-pages.sh" "$work/rejected-link" "$dist"; then
  printf 'Packaging must reject symlink assets\n' >&2; exit 1
fi
printf 'Pages package checks passed: runtime allowlist, optional B1-2, no secrets/maps/symlinks/overwrite\n'
