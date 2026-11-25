# QEMU website verifier

This image boots an x86_64 Alpine Linux guest under QEMU TCG and serves the
health endpoint from **inside the guest**. It does not use KVM, privileged mode, extra
capabilities, a host Docker socket, or runtime bind mounts.

## Build-context contract

Build from this candidate's root directory. The Dockerfile deliberately copies
only these public website inputs:

- `web/`
- `verify/vm/guest-init`
- `verify/vm/launch-vm.sh`

```sh
docker build -f verify/vm/Dockerfile -t network-lab-vm .
docker run --rm --name network-lab-vm -p 127.0.0.1:8080:8080 network-lab-vm
```

QEMU's user-mode network listens on container port 8080 and forwards it to the
guest's static `10.0.2.15:8080`. For Compose, expose `8080` from the service and
have other services request `http://vm:8080/`. Publishing `8080:8080` is only
needed for access from the Docker host.

The embedded healthcheck and an equivalent external check are:

```sh
docker inspect --format '{{.State.Health.Status}}' network-lab-vm
wget -qO- http://127.0.0.1:8080/__vm-proof.txt
wget -qO- http://127.0.0.1:8080/
```

`/__vm-proof.txt` is generated during guest boot from `uname` and DMI data. It
is not a host-container fixture. Serial output contains `VM-BOOT-READY` after
the NIC, proof file, and BusyBox HTTP server are ready. Missing website files,
kernel modules, or network setup produce a visible `VM-BOOT-FATAL` message.

## Build inputs and resource contract

- Host/base image: Alpine 3.22.2 manifest list digest
  `sha256:4b7ce07002c69e8f3d704a9c5d6fd3053be500b7f1c69fc0d80990c2ad8dd412`
- Guest root: Alpine minirootfs 3.22.6 x86_64, SHA-256
  `27694aaa55fd7a9e3ef596e0ad4eb66802308bb20172b17030cd5f4d8ae9bac2`
- Guest kernel and modules: the same signed x86_64 `linux-virt` package from Alpine 3.22.
- Guest HTTP server: the signed x86_64 `busybox-extras` package from Alpine 3.22.
- Build tools and QEMU: packages from the Alpine 3.22 repositories, without exact revisions.
- Guest: one vCPU and 256 MiB RAM. Allow at least 512 MiB for the container;
  TCG is intentionally slower than hardware virtualization.

The x86_64 packages are signature-checked and unpacked without running guest executables,
so the image can be built on native amd64 or arm64 Docker hosts. Runtime always emulates
x86_64 in software. The build needs access to Alpine's release archive and package repositories;
runtime needs no external network.

## Caveats

This validates the static site, Linux guest boot, and HTTP forwarding locally;
it is not evidence of a cloud deployment. This minimal Alpine guest does not
contain or run cloud-init, so it is separate from the verifier image's bounded
cloud-config schema/rendering/command check and does not validate Ubuntu boot or
bootstrap completion. QEMU `restrict=on` blocks guest-initiated connections except
the explicit inbound host forward.
