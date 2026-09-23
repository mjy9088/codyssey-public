#!/bin/bash
set -Eeuo pipefail
source /workspace/scripts/lib.bash
begin_validation "20-environment-and-docker"
for name in lab-hello lab-ubuntu-once lab-ubuntu; do cleanup_container "$name"; done

trap 'cleanup_container lab-hello; cleanup_container lab-ubuntu-once; cleanup_container lab-ubuntu' EXIT

section "Operating system, shell, and tool versions"
cat /etc/os-release
bash --version
docker --version
docker compose version
git --version

section "Installation and daemon"
docker info

section "hello-world image and container"
docker pull "$HELLO_WORLD_IMAGE"
docker run --name lab-hello "$HELLO_WORLD_IMAGE"
docker logs lab-hello
assert_contains "hello-world output" "$(docker logs lab-hello)" \
  "Hello from Docker!"
assert_eq "hello-world state" "exited" \
  "$(docker inspect --format '{{.State.Status}}' lab-hello)"
assert_eq "hello-world exit code" "0" \
  "$(docker inspect --format '{{.State.ExitCode}}' lab-hello)"
docker images
docker ps
docker ps -a
cleanup_container lab-hello

section "Ubuntu: foreground run versus exec on a running container"
# foreground `docker run`의 주 프로세스가 끝나면 컨테이너도 종료된다.
docker run --name lab-ubuntu-once "$UBUNTU_IMAGE" \
  bash -lc 'echo "foreground process"; ls / | head'
docker ps -a --filter name=lab-ubuntu-once
assert_eq "foreground container state" "exited" \
  "$(docker inspect --format '{{.State.Status}}' lab-ubuntu-once)"
assert_eq "foreground container exit code" "0" \
  "$(docker inspect --format '{{.State.ExitCode}}' lab-ubuntu-once)"
cleanup_container lab-ubuntu-once

# 장기 실행 중인 주 프로세스가 있을 때 exec는 별도 프로세스를 추가한다.
docker run -d --name lab-ubuntu "$UBUNTU_IMAGE" sleep infinity
docker exec lab-ubuntu bash -lc 'echo "exec process"; pwd; ls / | head'
assert_eq "container state after exec" "running" \
  "$(docker inspect --format '{{.State.Status}}' lab-ubuntu)"
docker stats --no-stream lab-ubuntu
docker stop lab-ubuntu
docker ps -a --filter name=lab-ubuntu
assert_eq "stopped container state" "exited" \
  "$(docker inspect --format '{{.State.Status}}' lab-ubuntu)"

end_validation
