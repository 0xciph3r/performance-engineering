#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
artifacts_dir="$repo_root/01-linux/investigations/artifacts"
mkdir -p "$artifacts_dir"
build_dir="$(mktemp -d)"
trap 'rm -rf "$build_dir"' EXIT

baseline_log="$artifacts_dir/baseline.log"
graceful_log="$artifacts_dir/graceful.log"
summary_log="$artifacts_dir/graceful-shutdown-run.txt"

run_case() {
  local label="$1"
  local source_path="$2"
  local log_path="$3"
  local binary_path="$build_dir/$label-worker"
  local relative_source_path="${source_path#$repo_root/}"

  : > "$log_path"
  (
    cd "$repo_root"
    GO111MODULE=off go build -o "$binary_path" "./$relative_source_path"
  )
  "$binary_path" >"$log_path" 2>&1 &
  local pid=$!

  sleep 1

  local start_ms
  start_ms="$(date +%s%3N)"
  kill -TERM "$pid"

  local wait_status
  set +e
  wait "$pid"
  wait_status=$?
  set -e

  local end_ms
  end_ms="$(date +%s%3N)"
  local elapsed_ms=$((end_ms - start_ms))

  {
    echo "case=$label"
    echo "pid=$pid"
    echo "exit_code=$wait_status"
    echo "term_to_exit_ms=$elapsed_ms"
    echo "log_start"
    cat "$log_path"
    echo "log_end"
    echo
  } >>"$summary_log"
}

: > "$summary_log"
run_case "baseline" "$repo_root/scripts/01-linux/graceful-shutdown/baseline_worker.go" "$baseline_log"
run_case "graceful" "$repo_root/scripts/01-linux/graceful-shutdown/graceful_worker.go" "$graceful_log"

cat "$summary_log"
