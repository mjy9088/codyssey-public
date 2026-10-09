# Operations implementation report

This report is a required submission document. Tracking generated run logs is normally poor practice:
they become stale, duplicate rerunnable automation, grow repositories, and may disclose host or
application details. Therefore this report records durable configuration and review commands, while
current public evidence is reproduced by `scripts/verify.sh`; restricted runtime output remains in
ignored private evidence.

## Security and network

The QEMU guest appends an SSH configuration selecting port 20022, disabling root login, and disabling
password authentication. It generates ephemeral host keys, starts `sshd`, and checks `sshd -T` plus
the socket table. QEMU user networking binds forwards only inside its unexposed container.

Firewalld starts over the guest's D-Bus and controls nftables. The public zone target is `DROP`, all
predefined services are removed, and only `20022/tcp` and `15034/tcp` are added. The emulated network
interface is assigned to that zone; `firewall-cmd --state`, ports, services, and target are checked.

## Identities and storage

The guest creates three role accounts. Every role belongs to the common group; admin and development
also belong to the core group. Upload storage is setgid and grants common-group read/write access.
Key and log storage are setgid and grant core-group access. Default ACLs preserve these policies for
new files. The test role's successful upload write and failed key read are executable assertions.

The service home contains upload, key, and binary directories. Test key material is synthetic. The
monitor owner/group/mode are asserted as development/core/750; the admin role executes it manually
and through cron. Application and monitor logs use core-group writable storage.

## Monitoring and retention

The monitor checks process and port health before collecting CPU deltas from `/proc/stat`, available
memory from `/proc/meminfo`, and filesystem use from `df`. It logs one parseable line per successful
sample and emits warnings above configured thresholds. Size-based rotation begins at 10 MiB and keeps
ten numbered files. The report script calculates average, minimum, maximum, and count from valid lines.

The admin crontab contains a once-per-minute command with an explicit PATH and environment. The guest
records the line count, starts `crond`, waits across a real minute boundary, and requires the count to
increase. A fixed fake timestamp or manual second invocation cannot satisfy that assertion.

## Verification commands

```sh
sh scripts/verify.sh docker
sh scripts/verify.sh vm
sh scripts/verify.sh all
```

Expected terminal markers are `SYNTHETIC-TEST-SUCCESS`, `DOCKER-VERIFY-SUCCESS`, `VM-LAB-SUCCESS`,
and `VM-VERIFY-SUCCESS`. The private workflow has separate markers and evidence storage; public
synthetic markers must never be represented as supplied-application proof.
