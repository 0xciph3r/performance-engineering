#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
artifacts_dir="$repo_root/10-distributed-systems/investigations/artifacts"
mkdir -p "$artifacts_dir"

summary_log="$artifacts_dir/majority-quorum-run.txt"

(
  cd "$repo_root"
  GO111MODULE=off go run scripts/10-distributed-systems/quorum/write_quorum_experiment.go
) | tee "$summary_log"
