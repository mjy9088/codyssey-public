#!/bin/sh
set -eu

if test "${1:-}" = --help && test "$#" -eq 1; then
  printf '%s\n' 'Usage: sh scripts/setup-pstack.sh' \
    'Installs the pinned pstack architecture, review, TDD and principle skills for OpenCode.' \
    'Requires Git, Node.js and npm; writes user-level agent skills, not application files.'
  exit 0
fi
test "$#" -eq 0 || { printf 'Unexpected arguments; use --help\n' >&2; exit 2; }

revision=f51fdeba3d803ef90e4eaa4a95ffb4e76008ab37
temporary=$(mktemp -d)
trap 'rm -rf "$temporary"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

git -c core.hooksPath=/dev/null -c init.templateDir= clone --quiet --no-checkout \
  https://github.com/backnotprop/pstack.git "$temporary/source"
git -c core.hooksPath=/dev/null -C "$temporary/source" checkout --quiet --detach "$revision"

set -- architect how why arena interrogate tdd
for directory in "$temporary/source"/skills/principle-*; do
  set -- "$@" "${directory##*/}"
done
DISABLE_TELEMETRY=1 DO_NOT_TRACK=1 npx --yes skills@1.7.4 add "$temporary/source" \
  --global --agent opencode --copy --yes --skill "$@"
cp "$temporary/source/LICENSE" "$HOME/.agents/skills/pstack.LICENSE"
printf 'Installed pstack 0.15.32 at %s; restart OpenCode to discover the new skills.\n' "$revision"
