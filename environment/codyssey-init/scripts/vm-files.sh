#!/usr/bin/env bash
# The VM payload is an allowlist: never send .env, runtime GOST edits, or host files.
vm_files=(
  .dockerignore .env.example Dockerfile README.md HANDOFF.md docker-compose.yml init.sh
  justfile lib/auth.sh macos-setup.sh enable-korean.swift install.sh tailscale-entrypoint.sh mise.toml next-script.zsh tailnet.sh
  verify-macos-setup.py scripts/check.sh scripts/vm-files.sh
  scripts/create-macos-vm.sh tests/vm-orchestration-test.py tests/vm-guest-test.py
  scripts/prepare-macos-vm.sh scripts/verify-macos-vm.sh
  tests/check.Dockerfile tests/run.sh tests/bootstrap-static.sh
  tests/bootstrap-remote.sh tests/bootstrap-runtime.sh tests/managed-j-runtime.sh tests/macos-fake-tools.py
  tests/macos-setup-test.py tests/fixtures/dockerignore tests/fixtures/gost.yaml
  chrome-extension/manifest.json chrome-extension/background.mjs chrome-extension/proxy.mjs
  chrome-extension/popup.html chrome-extension/popup.css chrome-extension/popup.mjs
  chrome-extension/README.md chrome-extension/startup.json scripts/install-chrome-extension.sh tests/chrome-extension-test.mjs
  scripts/tailnet-browser.sh scripts/browser-version.sh scripts/install-gureum.sh tests/portable-browser-test.py
  scripts/configure-tailnet-browser.py
  scripts/install-tailnet-tools.sh scripts/tailnet-dns.sh
  scripts/verify-tailnet-runtime.py
  tests/tailnet-dns-test.sh
)
