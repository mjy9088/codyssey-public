# Review and evidence boundary

## Public checks

Run `sh scripts/verify.sh all`. Require memory, CPU, deadlock, synthetic-lab, Docker, and VM success
markers. Inspect the numeric `MEMORY-CHECK` and `CPU-CHECK` lines rather than accepting fixture text
alone. Confirm the deadlock check combines two opposing lock waits, an unchanged log, stable thread
IDs, bounded RSS variation, persistent sleeping threads, and a successful single-thread control. A
live PID alone does not prove a deadlock.

Inspect Compose and both launchers for one-CPU/memory limits, dropped capabilities, no-new-privileges,
read-only containers, TCG, and absence of guest networking. Public images and build contexts must not
contain ZIP files or restricted inputs.

The public wrapper must bound `compose run` to 60 seconds for Docker and 120 seconds for QEMU, report
nonzero command status without inferring its cause, and always tear down the Compose project. Docker CPU/memory
settings are requests whose enforcement depends on host cgroup support; QEMU's `-smp` and `-m` remain
explicit guest bounds.

## Interpretation limits

The fixture intentionally implements known diagnoses, so public verification proves that the tools
can distinguish those patterns. It cannot establish how a supplied executable behaves. In
particular, exit 42 plus the fixture's MemoryGuard text establishes a target policy exit here. The
public harness does not collect kernel OOM evidence and therefore makes no kernel-OOM conclusion.
CPU percentage is the target's lifetime-average `ps %CPU`, not instantaneous or system-wide load;
uptime is from the host kernel in Docker and the guest kernel in QEMU.
Deadlock is supported by paired lock-order logs and blocked thread observations, not PID liveness.

QEMU TCG is a real guest kernel but emulated CPU timing differs materially from native hardware.
Absolute percentages and durations must not be compared across Docker and TCG as performance
benchmarks; only each run's asserted control relationship is used.

## Restricted-input checks

The optional script must create a stopped container before runtime `docker cp`, use only this subtree
as build context, and write serial output only to the caller-selected private evidence directory.
The private guest may extract and ordinarily execute the bounded x86 target, but must not inspect,
decompile, disassemble, trace, or transmit it. Require no QEMU network device, non-root execution,
bounded archive/member sizes, one vCPU, bounded RAM, and wall-clock limits.

The private runs must be independent pairs: memory changes only `MEMORY_LIMIT`; CPU uses threading
disabled and memory 512 in both runs while changing only `CPU_MAX_OCCUPY`; threading uses equal memory
and CPU values while changing only `MULTI_THREAD_ENABLE`. Each sample must enumerate every process
owned by the dedicated account, label account roots as launchers and their account-owned descendants
as workers, enumerate all threads, report aggregate CPU/RSS, and retain per-PID monitor samples. Outer
container CPU/memory enforcement is host-dependent and must be reported from observed Docker output;
the explicit QEMU vCPU/RAM settings are a separate bound.

Confirm that the supplied executable and its parent are root-owned/non-writable, capture files live in
a root-only directory outside application-writable logs, and every case gets a fresh service-owned
home/state tree. Application output must be prefixed before entering the control stream. Case-end
markers must report `survivors=0`. Deadline classification requires a supervisor-created marker; child
exit values 124 or 137 without that marker remain native target exits.

The private wrapper must capture timeout/docker output directly to a mode-0600 raw file and save the
command's status before normalizing carriage returns into a separate local file. Validation requires
status zero, one completion marker, one case-end marker for each of the six named cases, and no blocked
or failure marker. Guest extraction failures must emit failure/blocked markers and must never emit the
completion marker. The synthetic regression test exercises accepted success plus rejected timeout,
blocked-marker, and missing-case paths without using restricted input.

Any private report must label observations literally. A timeout with a PID is only “unresponsive under
the observation window” unless thread states and logs support a deadlock. A program exit is not a
kernel OOM without kernel evidence. Missing expected log phrases leave that requirement unobserved.
