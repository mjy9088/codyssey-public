#!/bin/sh
set -eu

root=${1:?candidate root is required}
readme="$root/README.md"
cli="$root/src/ai_git_review/cli.py"

require_fixed() {
  tr '\n' ' ' < "$2" | tr -s '[:space:]' ' ' | grep -Fq -- "$1" || {
    printf 'Missing source contract in %s: %s\n' "$2" "$1" >&2
    exit 1
  }
}

require_pattern() {
  tr '\n' ' ' < "$2" | tr -s '[:space:]' ' ' | grep -Eiq -- "$1" || {
    printf 'Missing documented contract in %s: %s\n' "$2" "$1" >&2
    exit 1
  }
}

require_fixed 'docker compose run --rm reviewer commit' "$readme"
require_fixed 'docker compose run --rm reviewer pr' "$readme"
require_fixed 'docker run --rm -v "$PWD:/repo:ro" -w /repo ai-git-review commit' "$readme"
require_fixed 'OPENAI_API_KEY' "$readme"
require_fixed '--backend api --allow-network' "$readme"
require_pattern 'requires both the API backend and a separate opt-in flag' "$readme"
require_pattern 'safe mode is on by default' "$readme"
require_fixed '--unsafe-include-sensitive' "$readme"
require_pattern 'heuristics cannot identify every secret.*inspect the diff first' "$readme"
require_pattern 'require credentials, incur cost.*confirm current model availability and pricing' "$readme"
require_pattern 'output is a draft only.*never commits, pushes, opens a PR, or changes repository files' "$readme"
require_fixed '--- END DRAFT: review before applying ---' "$cli"
require_pattern 'reminder to review before applying' "$readme"
require_pattern 'does not prove model quality.*live service behavior' "$readme"

printf 'PASS: documented run, API opt-in, safety, cost, and draft-review contracts\n'
