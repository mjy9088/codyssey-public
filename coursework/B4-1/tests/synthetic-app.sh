#!/usr/bin/env bash
set -eu
echo "SYNTHETIC-TARGET: not the supplied application"
exec -a agent-app-synthetic nc -lk -p "${AGENT_PORT:-15034}"
