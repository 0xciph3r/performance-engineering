# Graceful shutdown under SIGTERM

## Problem

Processes in containers are commonly stopped with `SIGTERM`. If the process exits immediately, in-flight work can be interrupted before it completes.

## What I tried

I built a small Linux container-backed experiment with two workers:

- `baseline_worker.go` does not install a `SIGTERM` handler
- `graceful_worker.go` traps `SIGTERM`, stops accepting new work, and lets the current unit of work finish before exiting

The experiment is run with:

```bash
docker run --rm -v "$PWD":/work -w /work golang:1.24-bookworm \
  bash scripts/01-linux/graceful-shutdown/run-experiment.sh
```

## Result (real numbers/output only)

Latest run summary:

| case | exit_code | term_to_exit_ms | completed work unit |
| --- | ---: | ---: | --- |
| baseline | 143 | 2 | no |
| graceful | 0 | 4017 | yes |

Captured output excerpt:

```text
case=baseline
exit_code=143
term_to_exit_ms=2
pid=684 baseline worker started
starting work unit duration=5s

case=graceful
exit_code=0
term_to_exit_ms=4017
pid=823 graceful worker started
starting work unit duration=5s
progress second=1
received SIGTERM; draining current work unit
progress second=2
progress second=3
progress second=4
progress second=5
completed work unit
shutdown complete after drain
```

Results from the latest run are preserved in:

```text
01-linux/investigations/artifacts/graceful-shutdown-run.txt
```

## Takeaway

In this run, the baseline process exited almost immediately after `SIGTERM` and never finished its 5-second work unit. The graceful version stayed alive for about 4 more seconds, completed the work already in flight, and exited cleanly with status `0`.

## Core questions

- **Why is this system slow?** This experiment is primarily about correctness during shutdown rather than steady-state slowness. The meaningful delay appears only in the graceful case, where the process intentionally remains alive long enough to finish in-flight work.
- **Where is time being spent?** After `SIGTERM`, the graceful worker spends about 4 more seconds finishing the current 5-second work unit instead of exiting immediately.
- **What is the bottleneck?** The limiting factor is whether the process has explicit signal-aware shutdown logic. Without it, the worker cannot drain work already in progress.
- **How can the bottleneck be measured?** Measure `SIGTERM`-to-exit latency, exit code, and whether the current work unit completes before process exit.
- **What evidence supports the conclusion?** The baseline case exited with code `143` in `2 ms` and never printed `completed work unit`. The graceful case exited with code `0` in `4017 ms`, printed all progress lines through second 5, then printed `completed work unit` and `shutdown complete after drain`.
- **What optimization was applied?** The graceful worker installs a `SIGTERM` handler, records the shutdown request, and allows the in-flight unit of work to complete before returning.
- **What trade-offs were introduced?** Shutdown latency increases by roughly the remaining duration of in-flight work, but termination becomes controlled and avoids abandoning work mid-flight.

## Reference

- `signal(7)`
- `docker stop` / container stop semantics
