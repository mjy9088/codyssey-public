#!/bin/bash
set -Eeuo pipefail
source /workspace/scripts/lib.bash
begin_validation "40-storage"

readonly HOST_BIND_DIR="/mnt/host-bind-mount-volume"

trap 'cleanup_container bind-web; cleanup_container volume-before; cleanup_container volume-after' EXIT
for name in bind-web volume-before volume-after; do cleanup_container "$name"; done

section "Two-hop bind mount reflects a real host-side change"
# 실제 호스트 ./volumes/bind-mount
#   -> outer DinD /mnt/host-bind-mount-volume
#   -> nested NGINX /usr/share/nginx/html
# 세 경로는 같은 파일을 바라본다. index.html은 실행 산출물이라 Git에서 제외한다.
test -d "$HOST_BIND_DIR"
cp /workspace/app/index.html "$HOST_BIND_DIR/index.html"
stat -c '%i %s %n' "$HOST_BIND_DIR/index.html"
docker run -d --name bind-web -p 8081:80 \
  --mount "type=bind,source=$HOST_BIND_DIR,target=/usr/share/nginx/html,readonly" "$NGINX_IMAGE"
wait_for_http http://127.0.0.1:8081/
before_response="$(curl --fail --silent http://127.0.0.1:8081/)"
assert_contains "bind response before change" "$before_response" \
  "It works reproducibly."
docker inspect bind-web --format '{{json .Mounts}}'
assert_eq "bind mount type" "bind" \
  "$(docker inspect bind-web --format '{{(index .Mounts 0).Type}}')"
assert_eq "bind mount writable" "false" \
  "$(docker inspect bind-web --format '{{(index .Mounts 0).RW}}')"
sh -c 'printf "<h1>Changed through the host bind mount</h1>\n" > "$1"' _ \
  "$HOST_BIND_DIR/index.html"
after_response="$(curl --fail --silent http://127.0.0.1:8081/)"
assert_eq "bind response after change" \
  "<h1>Changed through the host bind mount</h1>" "$after_response"

section "Named volume survives container deletion"
docker volume rm workstation-data >/dev/null 2>&1 || true
docker volume create workstation-data
docker run -d --name volume-before \
  --mount type=volume,source=workstation-data,target=/data "$UBUNTU_IMAGE" sleep infinity
docker exec volume-before sh -c 'printf "persistent-data\n" > /data/result.txt'
docker exec volume-before cat /data/result.txt
docker inspect volume-before --format '{{json .Mounts}}'
assert_eq "named volume type" "volume" \
  "$(docker inspect volume-before --format '{{(index .Mounts 0).Type}}')"
assert_eq "named volume name" "workstation-data" \
  "$(docker inspect volume-before --format '{{(index .Mounts 0).Name}}')"
assert_eq "data before deletion" "persistent-data" \
  "$(docker exec volume-before cat /data/result.txt)"
docker rm -f volume-before
docker run -d --name volume-after \
  --mount type=volume,source=workstation-data,target=/data "$UBUNTU_IMAGE" sleep infinity
docker exec volume-after cat /data/result.txt
assert_eq "data after recreation" "persistent-data" \
  "$(docker exec volume-after cat /data/result.txt)"

end_validation
