# [Bug] Synthetic opposing lock order leaves two threads blocked

> **Evidence scope:** This is an actual observation of the original synthetic fixture only. It is not
> evidence that the supplied program deadlocks; authorized observations belong in restricted evidence.

## 1. Description

With `MULTI_THREAD_ENABLE=true`, two fixture threads each acquire a different mutex, synchronize at a
barrier, and then wait for the mutex held by the peer. The process remains present during the bounded
observation window and makes no further application progress.

## 2. Evidence & Logs

The harness requires all of the following, not merely a live PID:

- both `Thread-A WAITING BLOCKED on peer lock` and `Thread-B ...` final log points;
- stable `ps -L` snapshots with the same process and worker thread IDs;
- eight process samples with bounded RSS variation and at least three threads;
- no application-log growth during the stable sample window;
- successful completion of the disabled control.

The durable summary is:

```text
DEADLOCK-CHECK pid-persisted=yes blocked-log-pairs=2 metrics-stable=yes thread-set-stable=yes log-stable=yes control-completed=yes
```

Raw generated monitor/thread logs stay in ignored runtime artifacts rather than being committed.
On 2026-10-09, both Docker and QEMU TCG satisfied all assertions and emitted this summary; the
disabled control exited zero in both environments.

## 3. Root Cause Analysis

The known lock sequence satisfies the four deadlock conditions: mutexes provide mutual exclusion;
each thread holds one while waiting for another; locks are not preempted; and A waits for B while B
waits for A, forming a cycle. The paired final logs and blocked multi-thread state support the observed
hang. A live PID or flat CPU/RSS alone would not prove this explanation.

## 4. Workaround & Verification

With `MULTI_THREAD_ENABLE=false`, the fixture takes the single-thread path and logs
`SINGLE_THREAD_CONTROL_COMPLETED without circular wait`, exiting zero. This removes the triggering
concurrency but sacrifices parallelism. A proper fix is a global lock order or a combined critical
section with bounded acquisition. Supplied-program deadlock evidence is not established publicly and
must be assessed only from authorized private guest logs and thread metrics.
