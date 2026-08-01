#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
artifacts_dir="$repo_root/03-memory/investigations/artifacts"
mkdir -p "$artifacts_dir"
summary_log="$artifacts_dir/tableau-cache-complexity-run.txt"

src_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/tableau_bench.c"
build_dir="$(mktemp -d)"
trap 'rm -rf "$build_dir"' EXIT

TRIALS=3
sizes=(512 1024 2048 4096 8192 16384)
methods=(iterative recursive)

clang -O3 -DNDEBUG -Wall "$src_dir" -o "$build_dir/tableau_bench"

: >"$summary_log"
{
  echo "benchmark=tableau-cache-complexity"
  echo "source=scripts/03-memory/cache-oblivious-tableau/tableau_bench.c"
  echo "problem=fill N x N tableau A(i,j)=f(A(i-1,j-1),A(i,j-1),A(i-1,j)) on diagonal layout 2N-1"
  echo "hardware=Apple M1 Pro (10-core CPU, ARM NEON)"
  echo "compiler=$(clang --version | head -1)"
  echo "cflags=-O3 -DNDEBUG"
  echo "trials_per_config=$TRIALS (best of)"
  echo "element_size=4 bytes, working_set_bytes=(2N-1)*4"
  echo
  echo "method N cells best_ms avg_ms Mcells_per_s result"
} >>"$summary_log"

run_best() {
  local method="$1" n="$2" best=999999999 sum=0
  for _ in $(seq 1 "$TRIALS"); do
    local line ms
    line="$("$build_dir/tableau_bench" "$method" "$n")"
    ms="$(echo "$line" | sed -E 's/.*elapsed_ms=([0-9.]+).*/\1/')"
    sum="$(echo "$sum $ms" | awk '{print $1 + $2}')"
    best="$(echo "$best $ms" | awk '{if ($2 < $1) print $2; else print $1}')"
  done
  printf "%s %s\n" "$best" "$(echo "$sum $TRIALS" | awk '{printf "%.2f", $1 / $2}')"
}

for method in "${methods[@]}"; do
  for n in "${sizes[@]}"; do
    read -r best avg < <(run_best "$method" "$n")
    result="$("$build_dir/tableau_bench" "$method" "$n" | sed -E 's/.*result=([0-9]+).*/\1/')"
    cells=$(((n - 1) * (n - 1)))
    mcells="$(echo "$cells $best" | awk '{printf "%.1f", $1 / $2 / 1000}')"
    echo "$method $n $cells $best $avg $mcells $result" >>"$summary_log"
  done
done

cat "$summary_log"
echo
echo "transcript saved to $summary_log"
