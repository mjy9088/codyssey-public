# Exercise file operations and Unix permissions without Docker.
demo:
    bash scripts/10-cli-and-permissions.bash

# Check shell syntax and lab dispatch without a Docker daemon.
check: demo
    for script in lab.bash scripts/*.bash; do bash -n "$script" || exit; done
    sh -n scripts/verify.sh
    sh tests/lab-cli-test.sh
