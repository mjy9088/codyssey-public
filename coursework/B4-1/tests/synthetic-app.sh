#!/usr/bin/env bash
set -eu
echo "SYNTHETIC-TARGET: not the supplied application"
exec -a agent-app-synthetic nc -s 127.0.0.1 -lk -p "${AGENT_PORT:-15034}"
