#!/bin/bash
set -Eeuo pipefail

readonly SERVICE="workstation"
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
  reset   Remove the workstation and its Docker data (destructive)
EOF
}

wait_until_ready() {
  printf 'Waiting for the Docker daemon'
  until docker compose exec -T "$SERVICE" docker info >/dev/null 2>&1; do
    printf '.'
    sleep 1
  done
  printf ' ready\n'
}

prepare_runtime() {
  mkdir -p volumes/bind-mount .local/evidence
}

command="${1:-}"
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
    printf 'This removes all lab containers, images, and volume data. Type RESET: '
    read -r confirmation
    [[ "$confirmation" == "RESET" ]] || { echo "Cancelled"; exit 1; }
    docker compose down --volumes --remove-orphans
    ;;
  *)
    usage
    exit 1
    ;;
esac
