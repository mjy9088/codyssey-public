#!/usr/bin/env bash
# The VM payload is an allowlist: never send .env, runtime GOST edits, or host files.
vm_files=(
  .dockerignore .env.example Dockerfile README.md docker-compose.yml init.sh
  justfile lib/auth.sh lib/options.sh lib/logging.sh lib/preparation.sh lib/readiness.zsh lib/bootstrap-tools.sh macos-setup.sh enable-korean.swift tailscale-entrypoint.sh mise.toml mise.vm.toml next-script.zsh tailnet.sh
  sdk/setup.mts sdk/cli.mts tests/setup-sdk-test.mts scripts/install-managed-j.sh
  verify-macos-setup.py scripts/check.sh scripts/vm-files.sh
  scripts/vm-tart.sh scripts/vm-fusion.sh scripts/vm-aqua-exec.py scripts/verify-tart-input.py scripts/vm-guest-path.sh scripts/create-macos-vm.sh tests/vm-orchestration-test.py tests/vm-guest-test.py tests/preinstalled-tools-test.py tests/installer-recovery-test.py tests/options-test.py tests/browser-configuration-test.py tests/iterm2-test.py
  scripts/prepare-macos-vm.sh scripts/verify-macos-vm.sh scripts/install-preinstalled-apps.sh scripts/create-preinstalled-macos-image.sh scripts/check-preinstalled-apps.py scripts/verify-portable-browser.py
  scripts/verify-intel-macos.sh scripts/prepare-fusion-base.sh
  tests/check.Dockerfile tests/run.sh tests/bootstrap-static.sh
  tests/bootstrap-remote.sh tests/bootstrap-runtime.sh tests/managed-j-runtime.sh tests/startup-overlap-test.sh
  tests/preparation-safety-test.sh tests/auth-prompt-test.sh tests/diagnostic-upload-test.py tests/macos-fake-tools.py
  tests/macos-setup-test.py tests/fixtures/dockerignore tests/fixtures/gost.yaml
  chrome-extension/manifest.json chrome-extension/background.mjs chrome-extension/proxy.mjs
  chrome-extension/popup.html chrome-extension/popup.css chrome-extension/popup.mjs
  chrome-extension/README.md chrome-extension/startup.json scripts/install-chrome-extension.sh tests/chrome-extension-test.mjs
  scripts/tailnet-browser.sh scripts/browser-version.sh scripts/install-gureum.sh tests/portable-browser-test.py
  scripts/configure-tailnet-browser.py
  scripts/install-tailnet-tools.sh scripts/tailnet-dns.sh scripts/prepare-startup.sh scripts/install-iterm2.sh scripts/configure-iterm2.sh scripts/configure-shell.sh
  scripts/verify-tailnet-runtime.py
  tests/tailnet-dns-test.sh tests/gureum-activation-test.sh tests/gureum-activation-test.swift
)
