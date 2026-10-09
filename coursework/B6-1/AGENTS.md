# Library SQL subtree

- Keep this directory independently executable with Docker Engine and Compose.
- Keep the submission SQL-first: no backend framework, network service, view, trigger, or procedure.
- Use only synthetic deterministic records and enforce SQLite foreign keys on every connection.
- Keep the required golden query result in Git; keep all other generated databases and run logs untracked.
- VM verification must execute SQLite inside QEMU TCG without KVM, privileged mode, capabilities, bind mounts, or a Docker socket.
