# 11 - GPU

GPU infrastructure is a portfolio target, but this machine has **no NVIDIA
GPU**: no CUDA, NCCL, nsight, DCGM, MIG, or tensor cores. Everything here is
either (a) measured on the Apple M1 Pro (NEON SIMD + AMX), clearly labeled, or
(b) documentation of what requires NVIDIA hardware and is deferred to
`15-benchmarks/`.

## Compute throughput: GEMM scalar vs BLAS (measured)

FP32 `C = A x B`, n=128..2048, three implementations, all verified
bit-identical: `naive_ijk` (worst-order scalar, 0.64-2.3 GFLOPS),
`naive_ikj` (contiguous + auto-NEON, ~21-27 GFLOPS), `cblas_sgemm`
(Accelerate NEON+AMX, 840-1831 GFLOPS). Peak 1830.8 GFLOPS at n=1024, ~84x
over the best hand-written loop. Elementwise control (memory-bound): scalar
~95 GB/s, vDSP ~132-142 GB/s, so SIMD only buys ~1.4x when DRAM-bound.

- Script: `scripts/11-gpu/compute-throughput/run-experiment.sh`
- Artifact: `investigations/artifacts/compute-throughput-run.txt`
- Field note: `investigations/compute-throughput-field-note.md`

## Deferred (needs NVIDIA hardware)

CUDA kernels, NCCL ring/tree + `nccl-tests`, `nsight` compute/systems, DCGM,
MIG partitioning, NVLink, tensor-core GEMM, vLLM with GPUs. These become the
`15-benchmarks/` entries; no numbers are published until they are measured on
real hardware.
