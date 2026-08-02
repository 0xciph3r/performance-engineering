#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
artifacts_dir="$repo_root/11-gpu/investigations/artifacts"
mkdir -p "$artifacts_dir"
summary_log="$artifacts_dir/compute-throughput-run.txt"

src_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/gemm.c"
build_dir="$(mktemp -d)"
trap 'rm -rf "$build_dir"' EXIT

clang -O3 -DNDEBUG -Wall -Wno-deprecated-declarations -framework Accelerate "$src_dir" -o "$build_dir/gemm_bench"

{
  echo "benchmark=compute-throughput (GEMM + elementwise)"
  echo "source=scripts/11-gpu/compute-throughput/gemm.c"
  echo "hardware=Apple M1 Pro (10-core CPU, ARM NEON, AMX coprocessor) - no NVIDIA GPU present"
  echo "compiler=$(clang --version | head -1)"
  echo "lib=Accelerate (vDSP + CBLAS sgemm, vecLib)"
  echo "precision=float32, gemm flops=2*n^3, elem bytes=n*12*repeats"
  echo "trials=best of {5,5,3,2,2} for n={128,256,512,1024,2048}, best of 3 for elem"
  echo
  echo "--- GEMM (C = A x B, FP32) ---"
  "$build_dir/gemm_bench" gemm
  echo
  echo "--- elementwise add/mul over n=2^20 floats x300 ---"
  "$build_dir/gemm_bench" elem
} | tee "$summary_log"

echo
echo "transcript saved to $summary_log"
