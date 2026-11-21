# Codyssey macOS environment

Set up a macOS course workstation from Terminal. The bootstrap installs or reuses
iTerm2 and offers Tailnet services, the `j` launcher, and personal macOS preferences.

## Quick start

From the root of a reviewed checkout, run:

```sh
sh init.sh
```

To use the latest public version without a checkout, run:

```sh
curl -fsSL https://raw.githubusercontent.com/mjy9088/codyssey-public/main/init.sh | sh
```

Use Terminal for the setup prompts. The optional features default to **No**. Run the
same command again to choose features or retry a failed setup.

## Optional features

| Feature | Set to `1` for an unattended run |
| --- | --- |
| Tailscale, GOST, and the Tailnet browser | `CODYSSEY_TAILNET_SETUP` |
| `j` command and Dock launcher | `CODYSSEY_INSTALL_J` |
| Gureum Hangul, keyboard shortcuts, and text preferences | `CODYSSEY_MACOS_SETUP` |
| Dock cleanup within macOS preferences | `CODYSSEY_DOCK_SETUP` |

Tailnet setup requires a compatible Docker engine with Compose. The Tailnet container
uses kernel networking and mounts your home directory read/write. Review the
[container privilege and mount boundary](docs/tailnet.md#container-privilege-and-mount-boundary)
before enabling it.

## Guides

- [Bootstrap options and troubleshooting](docs/bootstrap.md)
- [macOS workstation settings and recovery](docs/workstation.md)
- [Tailnet login, services, and terminal](docs/tailnet.md)
- [Portable Tailnet browser](docs/portable-browser.md)
- [TypeScript setup SDK](docs/setup-sdk.md)

For a remote installation, the guides are also available in the
[public repository](https://github.com/mjy9088/codyssey-public/tree/main/environment/codyssey-init/docs).

## Verification

- [Reproduce workstation verification on an Intel Mac with Fusion](docs/intel-macos-vm.md)
- [Run the isolated tests, verify a desktop, or use Apple Silicon with Tart](docs/verification.md)
