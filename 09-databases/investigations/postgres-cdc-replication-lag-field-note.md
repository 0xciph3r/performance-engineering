# Change Data Capture (CDC) replication lag with Postgres logical replication

## Problem

Active-active Postgres setups built on change data capture (CDC) need to move committed writes from one node to another. The practical question is how far behind the target can get: during steady streaming, and immediately after a large burst.

## What I tried

I built a container-backed experiment with two `postgres:16-alpine` containers connected by native logical replication (WAL-based CDC):

- source node runs with `wal_level=logical` and publishes two tables
- target node subscribes to the publication
- a shell loader inserts rows into the source while a poller samples the authoritative `replay_lag` from `pg_stat_replication` on the source every ~200ms

Two scenarios:

- `steady-state`: 10 batches x 2000 rows inserted at a bounded rate (2000 rows / 0.5s), lag sampled throughout
- `burst`: 50,000 rows inserted in a single statement, then target catch-up time measured

Run it with:

```bash
bash scripts/09-databases/cdc/run-experiment.sh
```

## Result (real numbers/output only)

Latest run summary:

| scenario | loaded rows | source window | avg replay lag | max replay lag | drain/catchup |
| --- | ---: | ---: | ---: | ---: | ---: |
| steady-state | 20000 | 5995 ms | 4.1 ms | 8 ms | 73 ms |
| burst | 50000 | 149 ms | n/a | 6 ms | 399 ms |

Captured output excerpt:

```text
scenario=steady-state
loaded_rows=20000
source_insert_window_ms=5995
steady_max_replay_lag_ms=8
steady_avg_replay_lag_ms=4.1
drain_ms=73

scenario=burst
burst_rows=50000
source_insert_ms=149
replay_lag_ms_after_commit=6
rows_behind_at_commit=50000
target_catchup_ms=399
```

`replay_lag` is reported by the walsender in `pg_stat_replication` and reflects the subscriber's acknowledged replay position, so steady-state lag here is single-digit milliseconds. In the burst case the target was 50,000 rows behind immediately after commit and took ~400 ms to apply them.

Results from the latest run are preserved in:

```text
09-databases/investigations/artifacts/cdc-replication-lag-run.txt
```

## Takeaway

Under a bounded steady workload, logical replication keeps the target within a few milliseconds of the source. Under a single large commit, the target lags the entire batch at commit time and needs additional time to apply it.

## Core questions

- **Why is this system slow?** Not slow in steady state: ~4 ms average lag at 2000 rows per 0.5s. The delay is concentrated after large single commits, when the whole batch is applied after source commit.
- **Where is time being spent?** Steady state: streaming keep-alive and apply, bounded by batch size and network. Burst: the target must decode and apply 50,000 rows after the source has already committed.
- **What is the bottleneck?** For steady state, the insert rate itself stays comfortably below the apply path. For bursts, the target's apply rate becomes the bottleneck until it drains the queue.
- **How can the bottleneck be measured?** Sample `pg_stat_replication.replay_lag` on the source during load, and measure target row count behind the source immediately after a burst commit.
- **What evidence supports the conclusion?** Steady state never exceeded 8 ms replay lag across 22 samples while inserting 20,000 rows. The 50,000-row burst committed on the source in 149 ms while the target was 50,000 rows behind at commit and needed 399 ms to catch up.
- **What optimization was applied?** Logical replication streams WAL asynchronously, so the source never blocks on the target; writes commit locally and replication proceeds in the background.
- **What trade-offs were introduced?** Async CDC means the target can be arbitrarily far behind at any instant (here: a full burst) and there is no read-your-writes guarantee across nodes until catch-up. `replay_lag` reflects acknowledged replay, not necessarily committed application.

## Reference

- `pg_stat_replication` / `pg_stat_subscription` (PostgreSQL 16)
- logical replication (`CREATE PUBLICATION` / `CREATE SUBSCRIPTION`)
- `wal_level=logical`
