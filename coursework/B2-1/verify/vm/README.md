# QEMU verifier

The VM image boots an x86_64 Alpine kernel with QEMU TCG and runs the real Python
unit and CLI tests inside its initramfs. A guest-created JSON endpoint reports the
result; the container health check stays unhealthy when guest tests fail. The path
uses no KVM device, privileged mode, added capability, bind mount, or Docker socket.

The Python base, Alpine host image, guest kernel package checksum, package versions,
application, and tests are all included by this subtree's Docker build. QEMU user
networking exposes only guest port 8080 to the container. This proves an emulated
guest run, not cloud deployment or behavior on every architecture.
