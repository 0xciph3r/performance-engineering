#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
artifacts_dir="$repo_root/09-databases/investigations/artifacts"
mkdir -p "$artifacts_dir"
summary_log="$artifacts_dir/cdc-replication-lag-run.txt"

network="perfeng-cdc"
source_ctr="cdc-source"
target_ctr="cdc-target"
source_port=15432
target_port=15433
source_pw="source"
target_pw="target"
image="postgres:16-alpine"

cleanup() {
  docker rm -f "$source_ctr" "$target_ctr" >/dev/null 2>&1 || true
  docker network rm "$network" >/dev/null 2>&1 || true
}
trap cleanup EXIT

src() { docker exec "$source_ctr" psql -U postgres -d cdc -tA -c "$1"; }
tgt() { docker exec "$target_ctr" psql -U postgres -d cdc -tA -c "$1"; }
lag_ms() {
  docker exec "$source_ctr" psql -U postgres -d cdc -tA -c \
    "SELECT round(extract(epoch FROM replay_lag) * 1000)::bigint FROM pg_stat_replication WHERE application_name = 'cdc_sub' AND replay_lag IS NOT NULL;"
}

now_ms() { date +%s%3N; }

echo "starting source+target postgres containers" >&2
docker network create "$network" >/dev/null
docker run -d --name "$source_ctr" --network "$network" -p "127.0.0.1:${source_port}:5432" \
  -e POSTGRES_PASSWORD="$source_pw" -e POSTGRES_DB=cdc \
  "$image" postgres -c wal_level=logical -c max_replication_slots=8 -c max_wal_senders=8 >/dev/null
docker run -d --name "$target_ctr" --network "$network" -p "127.0.0.1:${target_port}:5432" \
  -e POSTGRES_PASSWORD="$target_pw" -e POSTGRES_DB=cdc \
  "$image" >/dev/null

wait_ready() {
  local ctr="$1"
  for _ in $(seq 1 60); do
    if docker exec "$ctr" pg_isready -U postgres -q 2>/dev/null; then return 0; fi
    sleep 1
  done
  echo "container $ctr failed to become ready" >&2
  return 1
}
wait_ready "$source_ctr"
wait_ready "$target_ctr"

echo "configuring logical replication (publication on source, subscription on target)" >&2
src "CREATE TABLE cdc_steady(id bigint PRIMARY KEY, value text NOT NULL, ts timestamptz NOT NULL DEFAULT now());"
src "CREATE TABLE cdc_burst(id bigint PRIMARY KEY, value text NOT NULL, ts timestamptz NOT NULL DEFAULT now());"
src "CREATE PUBLICATION cdc_pub FOR TABLE cdc_steady, cdc_burst;"
tgt "CREATE TABLE cdc_steady(id bigint PRIMARY KEY, value text NOT NULL, ts timestamptz NOT NULL DEFAULT now());"
tgt "CREATE TABLE cdc_burst(id bigint PRIMARY KEY, value text NOT NULL, ts timestamptz NOT NULL DEFAULT now());"
tgt "CREATE SUBSCRIPTION cdc_sub CONNECTION 'host=${source_ctr} port=5432 user=postgres password=${source_pw} dbname=cdc' PUBLICATION cdc_pub;"

echo "waiting for end-to-end replication to come up (canary write)" >&2
src "INSERT INTO cdc_steady(id, value) VALUES (0, 'canary');"
for _ in $(seq 1 30); do
  if [ "$(tgt 'SELECT count(*) FROM cdc_steady;')" = "1" ]; then break; fi
  sleep 1
done
if [ "$(tgt 'SELECT count(*) FROM cdc_steady;')" != "1" ]; then
  echo "replication never established; aborting" >&2
  exit 1
fi

: >"$summary_log"

{
  echo "experiment=postgres-logical-replication-cdc-lag"
  echo "image=$image"
  echo "host_arch=$(uname -m)"
  echo "host_model=Apple M1 Pro (16-core GPU, Metal)"
  echo "source_config=wal_level=logical max_replication_slots=8 max_wal_senders=8"
  echo
} >>"$summary_log"

# ---------------------------------------------------------------------------
# Scenario A: steady-state streaming with a fixed write rate
# ---------------------------------------------------------------------------
steady_batches=10
steady_rows=2000
steady_interval=0.5

steady_before=$(src "SELECT count(*) FROM cdc_steady;")
steady_start=$(now_ms)
{
  # loader: bounded-rate inserts for a fixed window
  for b in $(seq 1 "$steady_batches"); do
    offset=$(((b - 1) * steady_rows))
    src "INSERT INTO cdc_steady(id, value) SELECT $offset + g, 'v' || ($offset + g) FROM generate_series(1, $steady_rows) AS g;"
    sleep "$steady_interval"
  done
} &
loader_pid=$!

# poller: sample authoritative replay_lag every 200ms for ~6.5s
poll_log="$(mktemp)"
(
  poll_end=$((steady_start + 6500))
  while [ "$(now_ms)" -lt "$poll_end" ]; do
    lag=$(lag_ms)
    [ -n "$lag" ] || lag="NULL"
    now=$(now_ms)
    echo "$((now - steady_start)) $lag" >>"$poll_log"
    sleep 0.2
  done
) &

wait "$loader_pid"
steady_end=$(now_ms)
steady_final=$(src "SELECT count(*) FROM cdc_steady;")
wait

# drain: how long does the target take to catch up after the source stops?
drain_start=$(now_ms)
while [ "$(tgt 'SELECT count(*) FROM cdc_steady;')" != "$steady_final" ]; do sleep 0.1; done
drain_end=$(now_ms)

steady_max_lag=$(awk '{if ($2 ~ /^[0-9]+$/ && $2 > max) max = $2} END {print max}' "$poll_log")
steady_avg_lag=$(awk '{if ($2 ~ /^[0-9]+$/) {sum += $2; n++}} END {printf "%.1f", sum / n}' "$poll_log")

{
  echo "scenario=steady-state"
  echo "batches=$steady_batches rows_per_batch=$steady_rows interval_s=$steady_interval"
  echo "loaded_rows=$((steady_final - steady_before))"
  echo "source_insert_window_ms=$((steady_end - steady_start))"
  echo "steady_max_replay_lag_ms=$steady_max_lag"
  echo "steady_avg_replay_lag_ms=$steady_avg_lag"
  echo "drain_ms=$((drain_end - drain_start))"
  echo "poll_samples_n=$(wc -l <"$poll_log" | tr -d ' ')"
  echo "poll_samples_ms=[$(cut -d' ' -f1 "$poll_log" | paste -sd, -)]"
  echo
} >>"$summary_log"
rm -f "$poll_log"

# ---------------------------------------------------------------------------
# Scenario B: burst workload (single large commit)
# ---------------------------------------------------------------------------
burst_rows=50000
burst_before=$(src "SELECT count(*) FROM cdc_burst;")

burst_t0=$(now_ms)
src "INSERT INTO cdc_burst(id, value) SELECT g, 'v' || g FROM generate_series(1, $burst_rows) AS g;"
burst_t1=$(now_ms)

# sample lag immediately after commit, then track target catch-up
lag_after_commit=$(lag_ms)
[ -n "$lag_after_commit" ] || lag_after_commit="NULL"
burst_src_final=$(src "SELECT count(*) FROM cdc_burst;")
burst_tgt_at_commit=$(tgt "SELECT count(*) FROM cdc_burst;")
peak_lag_rows=$((burst_src_final - burst_tgt_at_commit))

while :; do
  burst_tgt=$(tgt "SELECT count(*) FROM cdc_burst;")
  if [ "$((burst_src_final - burst_tgt))" -le 0 ]; then break; fi
  sleep 0.1
done
burst_t2=$(now_ms)

{
  echo "scenario=burst"
  echo "burst_rows=$burst_rows"
  echo "source_insert_ms=$((burst_t1 - burst_t0))"
  echo "replay_lag_ms_after_commit=$lag_after_commit"
  echo "rows_behind_at_commit=$peak_lag_rows"
  echo "target_catchup_ms=$((burst_t2 - burst_t1))"
  echo "source_count=$burst_src_final"
  echo "target_count=$burst_tgt"
  echo
} >>"$summary_log"

echo "transcript saved to $summary_log"
cat "$summary_log"
