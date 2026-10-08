# QEMU website verifier

This image boots an x86_64 Alpine Linux guest under QEMU TCG and serves the
portfolio from **inside the guest**. It does not use KVM, privileged mode, extra
capabilities, a host Docker socket, or runtime bind mounts.

## Build-context contract

Build from the `coursework/B1-1` directory. The Dockerfile deliberately copies
only these public website inputs:

- `index.html`
- `css/`
- `js/`
- `images/`
- `verify/vm/guest-init`
- `verify/vm/launch-vm.sh`

```sh
docker build -f verify/vm/Dockerfile -t b1-1-vm .
docker run --rm --name b1-1-vm -p 8080:8080 b1-1-vm
```

QEMU's user-mode network listens on container port 8080 and forwards it to the
guest's static `10.0.2.15:8080`. For Compose, expose `8080` from the service and
have other services request `http://vm:8080/`. Publishing `8080:8080` is only
needed for access from the Docker host.

The embedded healthcheck and an equivalent external check are:

```sh
docker inspect --format '{{.State.Health.Status}}' b1-1-vm
wget -qO- http://127.0.0.1:8080/__vm-proof.txt
wget -qO- http://127.0.0.1:8080/
```

`/__vm-proof.txt` is generated during guest boot from `uname` and DMI data. It
is not a host-container fixture. Serial output contains `VM-BOOT-READY` after
the NIC, proof file, and BusyBox HTTP server are ready. Missing website files,
kernel modules, or network setup produce a visible `VM-BOOT-FATAL` message.

## Pins and resource contract

- Host/base image: Alpine 3.22.2 manifest list digest
  `sha256:4b7ce07002c69e8f3d704a9c5d6fd3053be500b7f1c69fc0d80990c2ad8dd412`
- Guest root: Alpine minirootfs 3.22.6 x86_64, SHA-256
  `27694aaa55fd7a9e3ef596e0ad4eb66802308bb20172b17030cd5f4d8ae9bac2`
- Guest kernel: Alpine `linux-virt` 6.12.112-r0 x86_64 APK, SHA-256
  `6694e66849759265135a930306452c944bf2159f259b8c8f1c8731e474f2830b`
- Guest HTTP server: Alpine `busybox-extras` 1.37.0-r20 x86_64 APK,
  SHA-256 `2b8e8919faa2fc7b52d36eebe2b42844d8a9e19e7e833de8e29883dd4eb0d6c1`
- Runtime QEMU package: `qemu-system-x86_64=10.0.0-r1`
- Build packages: `ca-certificates=20260909-r0`, `cpio=2.15-r0`,
  `curl=8.14.1-r3`, and `gzip=1.14-r2`
- Guest: one vCPU and 256 MiB RAM. Allow at least 512 MiB for the container;
  TCG is intentionally slower than hardware virtualization.

The guest artifacts are downloaded as x86_64 data and unpacked without running
guest executables, so the image can be built on native amd64 or arm64 Docker
hosts. Runtime always emulates x86_64 in software. The build needs HTTPS access
to the pinned Alpine artifact URLs, while runtime needs no external network.

## Caveats

This validates the static site, Linux guest boot, and HTTP forwarding locally;
it is not evidence of a cloud deployment. QEMU `restrict=on` blocks guest-initiated
connections except the explicit inbound host forward. Alpine package repository
retention can eventually require updating the exact package pins and their
documented checksums together.
