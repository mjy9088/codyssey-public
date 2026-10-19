#!/bin/bash
set -Eeuo pipefail
source /workspace/scripts/lib.bash
begin_validation "20-environment-and-docker"
for name in lab-hello lab-ubuntu-once lab-ubuntu; do cleanup_container "$name"; done

trap 'cleanup_container lab-hello; cleanup_container lab-ubuntu-once; cleanup_container lab-ubuntu' EXIT

section "Operating system, shell, and tool versions"
cat /etc/os-release
bash --version
docker_version="$(docker --version)"
printf '%s\n' "$docker_version"
assert_contains "Docker CLI version" "$docker_version" "Docker version"
compose_version="$(docker compose version)"
printf '%s\n' "$compose_version"
assert_contains "Docker Compose version" "$compose_version" "Docker Compose version"
git_version="$(git --version)"
printf '%s\n' "$git_version"
assert_contains "Git version" "$git_version" "git version"

section "Installation and daemon"
docker info
assert_not_empty "Docker daemon version" \
  "$(docker info --format '{{.ServerVersion}}')"

section "hello-world image and container"
docker pull "$HELLO_WORLD_IMAGE"
assert_not_empty "pulled hello-world image ID" \
  "$(docker image inspect --format '{{.Id}}' "$HELLO_WORLD_IMAGE")"
hello_run_output="$(docker run --name lab-hello "$HELLO_WORLD_IMAGE")"
printf '%s\n' "$hello_run_output"
assert_contains "hello-world run output" "$hello_run_output" "Hello from Docker!"
hello_logs="$(docker logs lab-hello)"
printf '%s\n' "$hello_logs"
assert_contains "hello-world logs" "$hello_logs" \
  "Hello from Docker!"
assert_eq "hello-world state" "exited" \
  "$(docker inspect --format '{{.State.Status}}' lab-hello)"
assert_eq "hello-world exit code" "0" \
  "$(docker inspect --format '{{.State.ExitCode}}' lab-hello)"
docker_images="$(docker images --format '{{.Repository}}')"
printf '%s\n' "$docker_images"
assert_contains "image listing" "$docker_images" "hello-world"
assert_eq "exited container absent from running list" "" \
  "$(docker ps --filter name=^/lab-hello$ --quiet)"
assert_not_empty "exited container present in all list" \
  "$(docker ps -a --filter name=^/lab-hello$ --quiet)"
cleanup_container lab-hello

section "Ubuntu: foreground run versus exec on a running container"
# foreground `docker run`의 주 프로세스가 끝나면 컨테이너도 종료된다.
foreground_output="$(docker run --name lab-ubuntu-once "$UBUNTU_IMAGE" \
  bash -lc 'echo "foreground process"; ls / | head')"
printf '%s\n' "$foreground_output"
assert_contains "foreground run output" "$foreground_output" "foreground process"
assert_contains "foreground root listing" "$foreground_output" "bin"
assert_not_empty "foreground container listed" \
  "$(docker ps -a --filter name=^/lab-ubuntu-once$ --quiet)"
assert_eq "foreground container state" "exited" \
  "$(docker inspect --format '{{.State.Status}}' lab-ubuntu-once)"
assert_eq "foreground container exit code" "0" \
  "$(docker inspect --format '{{.State.ExitCode}}' lab-ubuntu-once)"
cleanup_container lab-ubuntu-once

# 장기 실행 중인 주 프로세스가 있을 때 exec는 별도 프로세스를 추가한다.
ubuntu_container_id="$(docker run -d --name lab-ubuntu "$UBUNTU_IMAGE" sleep infinity)"
printf '%s\n' "$ubuntu_container_id"
assert_eq "detached run container ID" \
  "$(docker inspect --format '{{.Id}}' lab-ubuntu)" "$ubuntu_container_id"
exec_output="$(docker exec lab-ubuntu bash -lc 'echo "exec process"; pwd; ls / | head')"
printf '%s\n' "$exec_output"
assert_contains "exec output" "$exec_output" "exec process"
assert_contains "exec working directory" "$exec_output" $'exec process\n/'
assert_eq "container state after exec" "running" \
  "$(docker inspect --format '{{.State.Status}}' lab-ubuntu)"
stats_name="$(docker stats --no-stream --format '{{.Name}}' lab-ubuntu)"
printf '%s\n' "$stats_name"
assert_eq "stats container name" "lab-ubuntu" "$stats_name"
stop_output="$(docker stop lab-ubuntu)"
printf '%s\n' "$stop_output"
assert_eq "stop result" "lab-ubuntu" "$stop_output"
assert_not_empty "stopped container listed" \
  "$(docker ps -a --filter name=^/lab-ubuntu$ --quiet)"
assert_eq "stopped container state" "exited" \
  "$(docker inspect --format '{{.State.Status}}' lab-ubuntu)"

end_validation
