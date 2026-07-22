# Majority quorum availability with three replicas

## Problem

A replicated system that requires a majority quorum can tolerate some failures, but only up to a point. The practical question is where that boundary is for a three-replica setup and what failure mode appears once quorum is lost.

## What I tried

I built a small Linux container-backed Go experiment that simulates a coordinator sending writes to three replicas over HTTP and committing once it receives a majority of acknowledgements.

The experiment runs three scenarios:

- `3/3 available`
- `2/3 available`
- `1/3 available`

Each scenario runs five writes and records:

- whether the write committed
- how many replica acknowledgements were received
- how long the coordinator took to decide

Run it with:

```bash
docker run --rm -v "$PWD":/work -w /work golang:1.24-bookworm \
  bash scripts/10-distributed-systems/quorum/run-experiment.sh
```

## Result (real numbers/output only)

Latest run summary:

| scenario | committed writes | failed writes | avg_duration_ms | exact failure mode |
| --- | ---: | ---: | ---: | --- |
| 3/3 available | 5 | 0 | 44 | none |
| 2/3 available | 5 | 0 | 43 | one replica unavailable, quorum still achieved |
| 1/3 available | 0 | 5 | 2 | `majority-unreachable` |

Captured output excerpt:

```text
scenario=3-of-3-available
available_nodes=3/3
summary committed=5 failed=0 avg_duration_ms=44 samples_ms=[46 44 47 42 44]

scenario=2-of-3-available
available_nodes=2/3
summary committed=5 failed=0 avg_duration_ms=43 samples_ms=[46 43 40 41 45]

scenario=1-of-3-available
available_nodes=1/3
summary committed=0 failed=5 avg_duration_ms=2 samples_ms=[4 2 0 2 1]
```

Results from the latest run are preserved in:

```text
10-distributed-systems/investigations/artifacts/majority-quorum-run.txt
```

## Takeaway

This experiment demonstrates the majority boundary directly: with three replicas, the system continues to commit writes with one replica unavailable, but once availability drops to one replica, every write fails because a majority acknowledgement is no longer possible.

## Core questions

- **Why is this system slow?** The main finding here is not steady-state slowness; it is a hard availability boundary. Successful writes with quorum take about 43-44 ms because two replica acknowledgements must be received before commit.
- **Where is time being spent?** In the successful cases, time is spent waiting for the two live replicas to accept and acknowledge the write. In the failed `1/3` case, time is spent quickly determining that majority is unreachable.
- **What is the bottleneck?** The bottleneck is the majority quorum requirement itself. A three-replica system can lose one replica and still commit, but cannot lose two.
- **How can the bottleneck be measured?** Measure committed versus failed writes, acknowledgement counts, and coordinator decision latency under `3/3`, `2/3`, and `1/3` availability.
- **What evidence supports the conclusion?** With `3/3` available, all 5 writes committed with `avg_duration_ms=44`. With `2/3` available, all 5 writes still committed with `avg_duration_ms=43`. With `1/3` available, all 5 writes failed with reason `majority-unreachable` and `avg_duration_ms=2`.
- **What optimization was applied?** The coordinator returns as soon as quorum is reached instead of waiting for all replicas, which is why the `2/3` case still commits at nearly the same latency as the `3/3` case.
- **What trade-offs were introduced?** Majority quorum preserves correctness and failure tolerance, but it reduces availability once more than half the replicas are lost. Early quorum return keeps latency low, but non-quorum replicas may still be behind at the moment the client sees success.

## Reference

- quorum / majority write semantics
- `fault tolerance = floor((n - 1) / 2)` for majority-based replication
