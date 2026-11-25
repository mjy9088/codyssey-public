# QEMU verifier

The VM image boots an x86_64 Alpine kernel with QEMU TCG and runs the real Python
unit and CLI tests inside its initramfs. The guest emits `VM-BOOT-READY` with its
kernel release before the suite starts, emits `VM-TEST-PASS` or `VM-TEST-FAIL`
afterwards, and powers off. The verifier requires clean QEMU termination and
both success markers within the 300-second one-shot run. It prints guest serial
output even on failure. There is no HTTP service or guest network.

This path uses no KVM, privileged mode, added capability, bind mount, or Docker
socket. It verifies an emulated guest run, not cloud deployment or behavior on
every architecture. The Docker image pins its Python and Alpine bases and uses
Alpine 3.22's signed `linux-virt` package.
