#!/usr/bin/env bash
# The VM payload is an allowlist: never send .env, runtime GOST edits, or host files.
vm_files=(
  .dockerignore .env.example Dockerfile README.md docker-compose.yml init.sh
  justfile lib/auth.sh macos-setup.sh mise.toml next-script.zsh tailnet.sh
  verify-macos-setup.py scripts/check.sh scripts/vm-files.sh
  scripts/create-macos-vm.sh tests/vm-orchestration-test.py
  scripts/prepare-macos-vm.sh scripts/verify-macos-vm.sh
  tests/check.Dockerfile tests/run.sh tests/bootstrap-static.sh
  tests/bootstrap-remote.sh tests/bootstrap-runtime.sh tests/macos-fake-tools.py
  tests/macos-setup-test.py tests/fixtures/dockerignore tests/fixtures/gost.yaml
)
