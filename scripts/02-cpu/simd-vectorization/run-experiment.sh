#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
artifacts_dir="$repo_root/02-cpu/investigations/artifacts"
mkdir -p "$artifacts_dir"
summary_log="$artifacts_dir/simd-vectorization-run.txt"

src_dir="$repo_root/vectorization/homework3/loop.c"
build_dir="$(mktemp -d)"
trap 'rm -rf "$build_dir"' EXIT

TRIALS=5
ops=("+" "-" "*" "/")
types=("uint32_t" "uint64_t" "float" "double")

op_name() {
  case "$1" in
    "+") echo "plus" ;;
    "-") echo "minus" ;;
    "*") echo "mul" ;;
    "/") echo "div" ;;
  esac
}

now_ms() { date +%s%3N; }

run_trials() {
  local binary="$1"
  local best=999999999
  local sum=0
  local n=0
  for _ in $(seq 1 "$TRIALS"); do
    local line
    line="$("$binary")"
    local sec
    sec="$(echo "$line" | sed -E 's/.*Elapsed execution time: ([0-9.eE-]+) sec.*/\1/')"
    local ms
    ms="$(echo "$sec" | awk '{print $1 * 1000}')"
    sum="$(echo "$sum $ms" | awk '{print $1 + $2}')"
    n=$((n + 1))
    best="$(echo "$best $ms" | awk '{if ($2 < $1) print $2; else print $1}')"
  done
  local avg
  avg="$(echo "$sum $n" | awk '{printf "%.2f", $1 / $2}')"
  printf "%s %s\n" "$best" "$avg"
}

echo "benchmark=simd-vectorization" >"$summary_log"
echo "source=$src_dir" >>"$summary_log"
echo "hardware=Apple M1 Pro (10-core CPU, ARM NEON)" >>"$summary_log"
echo "compiler=$(clang --version | head -1)" >>"$summary_log"
echo "trials_per_config=$TRIALS" >>"$summary_log"
echo "loop_geometry=N=1024 I=100000 (element ops = I*N = 102400000)" >>"$summary_log"
echo "scalar_flags=-O3 -DNDEBUG -fno-vectorize" >>"$summary_log"
echo "vector_flags=-O3 -DNDEBUG -ffast-math" >>"$summary_log"
echo >>"$summary_log"

echo "op type scalar_best_ms scalar_avg_ms vector_best_ms vector_avg_ms speedup_x" | tee -a "$summary_log"

for op in "${ops[@]}"; do
  opn=$(op_name "$op")
  for ty in "${types[@]}"; do
    scalar_bin="$build_dir/scalar_${opn}_${ty}"
    vec_bin="$build_dir/vec_${opn}_${ty}"
    remarks_file="$build_dir/remarks_${opn}_${ty}.txt"

    clang -O3 -DNDEBUG -Wall -std=gnu99 -fno-vectorize \
      -D"__OP__=$op" -D"__TYPE__=$ty" "$src_dir" -o "$scalar_bin" 2>/dev/null || true
    clang -O3 -DNDEBUG -Wall -std=gnu99 -ffast-math -Rpass=loop-vectorize \
      -D"__OP__=$op" -D"__TYPE__=$ty" "$src_dir" -o "$vec_bin" 2>"$remarks_file" || true

    read -r s_best s_avg < <(run_trials "$scalar_bin")
    read -r v_best v_avg < <(run_trials "$vec_bin")
    speedup="$(echo "$s_best $v_best" | awk '{printf "%.2f", $1 / $2}')"
    remark="none"
    if rg -q "remark: vectorized loop" "$remarks_file" 2>/dev/null; then
      remark="vectorized"
    elif rg -q "remark: interleaved loop" "$remarks_file" 2>/dev/null; then
      remark="interleaved-only"
    fi

    printf "%s %s %s %s %s %s %s\n" "$op" "$ty" "$s_best" "$s_avg" "$v_best" "$v_avg" "$speedup" | tee -a "$summary_log" >/dev/null
    echo "remark=$remark" >>"$summary_log"
    rg -I -N "loop.c:70:9: remark" "$remarks_file" 2>/dev/null | sed -E 's/.*loop.c:70:9: remark: ([^[]*).*/loop.c:70:9: remark: \1/' >>"$summary_log" || true
  done
done

echo
echo "transcript saved to $summary_log"
