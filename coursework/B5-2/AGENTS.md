# Mini Git subtree

- Keep this directory independently executable with Docker Engine and Compose.
- Keep the implementation in memory. Do not invoke Git or add persistence, networking, or graph/sort libraries.
- Keep runtime and test modules under 250 non-blank, non-comment lines.
- Use deterministic clocks in tests and keep generated logs or run evidence out of Git.
- VM verification must execute the application inside QEMU TCG without KVM, privileged mode, extra capabilities, bind mounts, or a Docker socket.
