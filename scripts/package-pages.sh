#!/bin/sh
set -eu
test "$#" -le 2 || { printf 'Usage: sh scripts/package-pages.sh [OUTPUT_DIR [B1_2_DIST]]\n' >&2; exit 2; }
if test "${1:-}" = --help; then
  printf 'Usage: sh scripts/package-pages.sh [OUTPUT_DIR [B1_2_DIST]]\nPackages B1-1 and optionally a built B1-2 frontend for GitHub Pages.\n'
  exit 0
fi
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
source=$root/coursework/B1-1
output=${1:-"$root/_site"}
dist=${2:-}
test ! -e "$output" && test ! -L "$output" || {
  printf 'Output already exists; select a fresh directory: %s\n' "$output" >&2
  exit 2
}
if test -n "$dist"; then
  test -f "$dist/index.html" && test ! -L "$dist/index.html" &&
    test -d "$dist/assets" && test ! -L "$dist/assets" || {
    printf 'B1-2 requires a built index.html and assets directory\n' >&2; exit 2;
  }
  rejected=$(find "$dist/assets" ! -type d ! \( -type f \( -name '*.js' -o -name '*.css' \) \))
  test -z "$rejected" || {
    printf 'B1-2 assets must contain only regular JavaScript/CSS files\n' >&2; exit 2;
  }
fi
mkdir -p "$output"
mkdir "$output/B1-1"
cp "$source/index.html" "$output/B1-1/index.html"
cp -R "$source/css" "$source/js" "$source/images" "$output/B1-1/"
{
  printf '%s\n' '<!doctype html>' '<html lang="en">' '<head>' \
    '<meta charset="utf-8">' '<meta name="viewport" content="width=device-width, initial-scale=1">' \
    '<title>Codyssey coursework</title>' '</head>' '<body>' '<main>' \
    '<h1>Codyssey coursework</h1>' '<nav aria-label="Coursework websites"><ul>' \
    '<li><a href="B1-1/">B1-1: Developer portfolio</a></li>'
  if test -n "$dist"; then
    printf '%s\n' '<li><a href="B1-2/">B1-2: Workshop planner</a></li>'
  fi
  printf '%s\n' '</ul></nav>' '</main>' '</body>' '</html>'
} >"$output/index.html"
touch "$output/.nojekyll"
if test -n "$dist"; then
  mkdir "$output/B1-2"
  cp "$dist/index.html" "$output/B1-2/index.html"
  cp -R "$dist/assets" "$output/B1-2/"
fi
printf 'Pages artifact: %s\n' "$output"
