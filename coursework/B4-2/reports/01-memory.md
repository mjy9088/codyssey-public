# [Bug] Synthetic memory growth ends in an application policy exit

> **Evidence scope:** This required issue-style report records the behavior asserted by the public,
> original synthetic fixture. It is not a finding about the supplied program. Any authorized
> supplied-program observation is recorded separately in restricted evidence.

## 1. Description

With `MEMORY_LIMIT=50`, the fixture allocates and touches 4 MiB chunks every 200 ms. Resident memory
increases until the fixture logs its configured boundary and exits with status 42. This is a bounded
application self-termination, not an unexpected process disappearance.

## 2. Evidence & Logs

`tests/run.sh` samples `ps -o %cpu,rss,stat,nlwp` by PID with a requested 100 ms sleep between samples
and requires peak RSS to exceed initial RSS in both runs. It also requires the application log to contain both the threshold message and
`SELF-TERMINATED: application MemoryGuard policy (not kernel OOM)`. The durable terminal summary is:

```text
MEMORY-CHECK before-rss-kb=<first>..<peak> after-rss-kb=<first>..<peak> samples-before=<n> samples-after=<m> target-policy-exit=yes
```

The executable status is asserted as 42 in both runs. This establishes the fixture's target-policy
exit. The public harness collects no kernel evidence and therefore makes no kernel-OOM conclusion.

On the 2026-10-09 validation, Docker observed RSS rising from 4,724 to 53,924 KiB, with 25 samples at
50 MiB versus 38 at 80 MiB. QEMU TCG independently observed 4,724 to 53,924 KiB, with 18 versus 28
samples. These are observations from those runs, not timeless expected constants or supplied-program
measurements.

## 3. Root Cause Analysis

The fixture deliberately retains every allocated chunk, so touched anonymous pages remain resident.
Its MemoryGuard-like branch compares allocated bytes to the environment limit and returns 42. The
observed rising RSS supports retained allocation; the known fixture implementation establishes the
cause. For an unknown executable, the same shape would be a hypothesis requiring further evidence.

## 4. Workaround & Verification

The control raises `MEMORY_LIMIT` from 50 to 80 MiB. Both runs eventually self-terminate, but the
harness requires the 80 MiB run to produce more monitor samples and therefore survive longer. Raising
the threshold delays the symptom and is not a leak fix. The proper production fix would bound object
retention and verify that RSS reaches a plateau. Any supplied-program before/after result must come
from a separate private guest observation; synthetic results cannot satisfy it.
