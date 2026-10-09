# Git Practice VM

The Docker build assembles an x86_64 Alpine root and kernel, installs pinned Git/Bash/Node packages
as guest data, and copies only this subtree's public utility and verification code. QEMU TCG then
runs the real utilities and disposable Git exercises inside that kernel. No network or host socket
is present at runtime; no KVM or privileged container is required. The guest has one CPU, 512 MiB
of RAM, and a 150-second outer timeout.

The wrapper requires both a successful QEMU process and the guest's final `VM-CHECK-PASS` signal.
Missing markers or guest failures cannot be represented as a passing verification. This remains a
synthetic practice environment, not human GitHub collaboration evidence.
