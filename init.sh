#!/bin/sh

set -eu

docker compose up -d

ui_url="http://localhost:18081/"

printf '\nGOST UI가 준비되기를 기다리는 중입니다.\n'
attempt=0
while [ "$attempt" -lt 30 ]; do
  if curl --silent --fail --output /dev/null "$ui_url"; then
    printf 'GOST UI: %s\n' "$ui_url"

    if command -v open >/dev/null 2>&1; then
      open -a "Google Chrome" "$ui_url" 2>/dev/null || open "$ui_url" 2>/dev/null || true
    fi

    exit 0
  fi

  attempt=$((attempt + 1))
  sleep 1
done

printf 'GOST UI가 아직 준비되지 않았습니다. 잠시 후 %s 을(를) 직접 여세요.\n' "$ui_url"
