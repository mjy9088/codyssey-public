#!/bin/sh
set -eu

root=${1:?candidate root is required}
readme="$root/README.md"
guide="$root/docs/CONTRIBUTING.md"
conflicts="$root/docs/conflict-resolution.md"

require_pattern() {
  tr '\n' ' ' < "$2" | tr -s '[:space:]' ' ' | grep -Eiq -- "$1" || {
    printf 'Missing documented contract in %s: %s\n' "$2" "$1" >&2
    exit 1
  }
}

require_pattern 'main branch releasable' "$guide"
require_pattern 'feature/<person-or-team>/<purpose>' "$guide"
require_pattern 'meaningful.*feat:.*fix:.*test:.*docs:' "$guide"
require_pattern 'what changed, why, and how.*verify' "$guide"
require_pattern 'independent approval.*successful checks.*merge' "$guide"
require_pattern 'prohibit direct main.*branch protection' "$guide"
require_pattern 'concrete lines, behavior, failure modes and alternatives' "$guide"
require_pattern 'author should answer.*requested change' "$guide"
require_pattern 'conflicting changes.*preserve intended behavior.*rerun tests' "$guide"
require_pattern 'never force-push a shared branch' "$guide"

require_pattern 'not.*claim.*multiple people.*reviewed or merged' "$readme"
require_pattern 'real team membership.*separately authorized shared' "$readme"
require_pattern 'synthetic history is not acceptable as evidence of human collaboration' "$readme"
require_pattern 'not a record of.*people resolving a GitHub conflict' "$conflicts"
require_pattern 'never replace real participation with synthetic fixture output' "$conflicts"

printf 'PASS: documented GitHub Flow, review, conflict-safety, and collaboration-limit contracts\n'
