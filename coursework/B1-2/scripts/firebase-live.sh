#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
image=benchbook-firebase-operator:15.35.0
mode=${1:---help}

case "$mode" in
  --help|help)
    printf '%s\n' 'Usage: sh scripts/firebase-live.sh build|version|login|logout|plan|apply [OPTIONS]' \
      'plan/apply: --project ID --create-location LOCATION' \
      'apply also: --confirm-project ID --accept-shared-demo-policy' \
      'plan is offline, not a cloud diff. Location is used only when creating (default).' \
      'apply replaces rules with shared signed-in CRUD; dedicated disposable projects only.' \
      'Billing is not inspected or capped; no billing changes are requested.' \
      'login/logout/apply: BENCHBOOK_FIREBASE_CREDENTIALS must name an existing mode-0700' \
      'directory outside the checkout. See docs/FIREBASE_PROVISIONING.md.'
    test "$#" -le 1 || exit 2
    exit 0 ;;
  build)
    test "$#" -eq 1 || { printf 'build accepts no options\n' >&2; exit 2; }
    exec docker build -f "$root/ops/firebase/Dockerfile" -t "$image" "$root" ;;
  version|plan)
    case "$root" in *,*) printf 'Checkout path cannot contain commas\n' >&2; exit 2 ;; esac
    exec docker run --rm --init --network none --read-only --tmpfs /tmp \
      --cap-drop ALL --security-opt no-new-privileges:true \
      --mount "type=bind,source=$root/ops/firebase/main.mjs,target=/app/ops/firebase/main.mjs,readonly" \
      --mount "type=bind,source=$root/ops/firebase/request.mjs,target=/app/ops/firebase/request.mjs,readonly" \
      --mount "type=bind,source=$root/ops/firebase/provision.mjs,target=/app/ops/firebase/provision.mjs,readonly" \
      --mount "type=bind,source=$root/ops/firebase/credentials.mjs,target=/app/ops/firebase/credentials.mjs,readonly" \
      --mount "type=bind,source=$root/firestore.rules,target=/app/firestore.rules,readonly" \
      "$image" "$@" ;;
  login|logout)
    test "$#" -eq 1 || { printf '%s accepts no options\n' "$mode" >&2; exit 2; } ;;
  apply) ;;
  *) printf 'Unknown command: %s\n' "$mode" >&2; exit 2 ;;
esac

credentials=${BENCHBOOK_FIREBASE_CREDENTIALS:?Set a dedicated existing credential directory outside the checkout}
case "$credentials" in /*) ;; *) printf 'Credential path must be absolute\n' >&2; exit 2 ;; esac
test -d "$credentials" || { printf 'Create a dedicated mode-0700 credential directory first\n' >&2; exit 2; }
credentials=$(CDPATH= cd -- "$credentials" && pwd -P)
test "$credentials" != / || { printf 'Credential directory cannot be filesystem root\n' >&2; exit 2; }
checkout=$root
candidate=$root
while [ "$candidate" != / ]; do
  if [ -e "$candidate/.git" ]; then checkout=$candidate; break; fi
  candidate=$(dirname -- "$candidate")
done
case "$credentials/" in "$checkout/"*) printf 'Credentials must stay outside the checkout\n' >&2; exit 2 ;; esac
case "$checkout/" in "$credentials/"*) printf 'Credential directory cannot contain the checkout\n' >&2; exit 2 ;; esac
case "$credentials" in *,*) printf 'Credential path cannot contain commas (Docker mount syntax)\n' >&2; exit 2 ;; esac

# Capture this build's immutable image ID, not a mutable tag another checkout can replace.
image=$(docker build --quiet -f "$root/ops/firebase/Dockerfile" -t "$image" "$root")
case "$image" in sha256:*) ;; *) printf 'Docker did not return an image ID\n' >&2; exit 1 ;; esac

# Do not forward host environment, ADC files, cloud keys, or a Docker socket.
# The directory is writable because the CLI can refresh its OAuth login.
if [ "$mode" = login ]; then
  exec docker run --rm --init -it --name "benchbook-firebase-operator-$(id -u)" --read-only --tmpfs /tmp \
    --user "$(id -u):$(id -g)" --cap-drop ALL --security-opt no-new-privileges:true \
    --mount "type=bind,source=$credentials,target=/credentials" \
    -e XDG_CONFIG_HOME=/credentials "$image" login
fi
exec docker run --rm --init --name "benchbook-firebase-operator-$(id -u)" --read-only --tmpfs /tmp \
  --user "$(id -u):$(id -g)" --cap-drop ALL --security-opt no-new-privileges:true \
  --mount "type=bind,source=$credentials,target=/credentials" \
  -e XDG_CONFIG_HOME=/credentials "$image" "$@"
