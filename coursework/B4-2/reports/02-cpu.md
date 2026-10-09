# [Bug] Synthetic CPU saturation triggers an application watchdog

> **Evidence scope:** This report covers only the public synthetic fixture. It demonstrates the
> diagnostic workflow but does not establish supplied-program CPU or watchdog behavior; authorized
> black-box observations belong only in restricted evidence.

## 1. Description

The fixture runs a compute loop on one worker process. At `CPU_MAX_OCCUPY=25`, its internal watchdog
calculates process CPU against elapsed wall time, logs the exceeded threshold, sends SIGTERM to itself,
and exits with status 43. This occurs after at least one second of sustained work.

## 2. Evidence & Logs

The external monitor records the target PID's `%CPU`, not aggregate host load, and the harness requires
a sampled peak of at least 50%. It also requires the watchdog threshold and SIGTERM-observed messages.
The durable summary has this form:

```text
CPU-CHECK peak_pct=<peak> threshold-before=25 watchdog-exit=yes threshold-after=100 control-completed=yes
```

The before status must be 43. This combination distinguishes an intentional application protection
path from an unexplained crash, while avoiding a claim that the whole system was saturated.

On the 2026-10-09 validation, the sampled process-local peak was 98.9% in Docker and 71.1% under QEMU
TCG. Both runs observed the low-threshold watchdog exit and the 100% control completing. The different
peaks reinforce that TCG and native-container timing are not interchangeable benchmarks.

## 3. Root Cause Analysis

The known fixture performs an unthrottled arithmetic loop, keeping its one available CPU runnable.
After measuring utilization above the configured threshold, its watchdog initiates termination. In a
real unknown service, high per-process CPU plus watchdog text supports this diagnosis, but source-level
root cause would still require authorized application investigation.

## 4. Workaround & Verification

The control changes `CPU_MAX_OCCUPY` from 25 to 100. The same work runs for three seconds and logs
`CPU_CONTROL_COMPLETED`; status zero is required. Raising the watchdog boundary avoids termination but
does not reduce CPU demand. A durable fix would bound work, yield or queue excess jobs, and retain a
protective limit appropriate to service latency. Supplied-program before/after behavior remains a
separate private-observation requirement.
