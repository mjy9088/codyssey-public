#!/bin/bash
set -Eeuo pipefail

readonly SERVICE="workstation"
readonly SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly READY_ATTEMPTS="${LAB_READY_ATTEMPTS:-30}"
readonly -a STEPS=(
  scripts/10-cli-and-permissions.bash
  scripts/20-environment-and-docker.bash
  scripts/30-custom-image.bash
  scripts/40-storage.bash
  scripts/50-git.bash
  scripts/60-browser-evidence.bash
)

usage() {
  cat <<'EOF'
Usage: bash lab.bash <command>

  up      Build and start the DinD workstation
  run     Run every documented lab step
  shell   Open an interactive shell in the workstation
  status  Show the outer container status
  down    Stop the workstation while preserving Docker data
  reset   Remove workstation containers and nested Docker data (destructive)
EOF
}

wait_until_ready() {
  local attempt

  printf 'Waiting for the Docker daemon'
  for ((attempt = 1; attempt <= READY_ATTEMPTS; attempt++)); do
    if docker compose exec -T "$SERVICE" docker info >/dev/null 2>&1; then
      printf ' ready\n'
      return 0
    fi
    printf '.'
    ((attempt < READY_ATTEMPTS)) && sleep 1
  done

  printf '\nDocker daemon did not become ready after %d attempts.\n' "$READY_ATTEMPTS" >&2
  docker compose ps >&2 || true
  return 1
}

prepare_runtime() {
  mkdir -p volumes/bind-mount .local/evidence
}

if ! [[ "$READY_ATTEMPTS" =~ ^[1-9][0-9]*$ ]]; then
  printf 'LAB_READY_ATTEMPTS must be a positive integer.\n' >&2
  exit 2
fi

if (($# != 1)); then
  usage >&2
  exit 2
fi

cd "$SCRIPT_DIR"
command="$1"
case "$command" in
  up)
    prepare_runtime
    docker compose up -d --build
    wait_until_ready
    ;;
  run)
    prepare_runtime
    docker compose up -d --build
    wait_until_ready
    for step in "${STEPS[@]}"; do
      printf '\n===== %s =====\n' "$step"
      docker compose exec -T "$SERVICE" bash "$step"
    done
    printf '\nAll automated checks passed. Runtime artifacts are in .local/evidence/.\n'
    ;;
  shell)
    docker compose exec "$SERVICE" bash
    ;;
  status)
    docker compose ps
    ;;
  down)
    docker compose down
    ;;
  reset)
    printf 'This removes lab containers and nested Docker daemon data; host images and caches remain. Type RESET: '
    read -r confirmation
    [[ "$confirmation" == "RESET" ]] || { echo "Cancelled"; exit 1; }
    docker compose down --volumes --remove-orphans
    ;;
  *)
    usage
    exit 1
    ;;
esac
