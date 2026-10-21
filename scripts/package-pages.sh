#!/bin/sh
set -eu
test "$#" -le 1 || { printf 'Usage: sh scripts/package-pages.sh [OUTPUT_DIR]\n' >&2; exit 2; }
if test "${1:-}" = --help; then
  printf 'Usage: sh scripts/package-pages.sh [OUTPUT_DIR]\nPackages only B1-1 runtime assets for GitHub Pages.\n'
  exit 0
fi
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
source=$root/coursework/B1-1
output=${1:-"$root/_site"}
test ! -e "$output" && test ! -L "$output" || {
  printf 'Output already exists; select a fresh directory: %s\n' "$output" >&2
  exit 2
}
mkdir -p "$output"
cp "$source/index.html" "$output/index.html"
cp -R "$source/css" "$source/js" "$source/images" "$output/"
touch "$output/.nojekyll"
printf 'B1-1 Pages artifact: %s\n' "$output"
