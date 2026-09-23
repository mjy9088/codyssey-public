#!/bin/bash
set -Eeuo pipefail
source /workspace/scripts/lib.bash
begin_validation "30-custom-image"

# 성공 후 실제 호스트의 http://localhost:8080에서 브라우저 증거를 수집할 수 있도록
# 이 컨테이너는 유지한다. 다음 실행 시작 시 같은 이름의 이전 컨테이너를 정리한다.
cleanup_container workstation-web

section "Build custom NGINX image"
docker build --tag workstation-web:1.0 /workspace/app
docker image inspect workstation-web:1.0 \
  --format 'base-derived image={{.RepoTags}} exposed={{json .Config.ExposedPorts}}'
assert_eq "image title label" "codyssey-workstation-web" \
  "$(docker image inspect workstation-web:1.0 \
    --format '{{index .Config.Labels "org.opencontainers.image.title"}}')"
assert_contains "image healthcheck" \
  "$(docker image inspect workstation-web:1.0 \
    --format '{{json .Config.Healthcheck.Test}}')" \
  "127.0.0.1:80"

section "Run with host-to-container port mapping"
# outer container의 8080은 Compose가 실제 호스트의 8080으로 다시 전달한다.
docker run -d --name workstation-web -p 8080:80 workstation-web:1.0
docker ps --filter name=workstation-web

wait_for_http http://127.0.0.1:8080/
wait_for_container_health workstation-web
response="$(curl --fail --silent --show-error http://127.0.0.1:8080/)"
assert_contains "custom page response" "$response" \
  "It works reproducibly."
assert_contains "published port" "$(docker port workstation-web 80/tcp)" \
  ":8080"
docker logs workstation-web
docker stats --no-stream workstation-web

end_validation
