# Compute throughput without a GPU: GEMM scalar vs BLAS (AMX) on M1

## Problem

GPU infrastructure work is the portfolio target, but this machine has no
NVIDIA GPU: no CUDA, NCCL, nsight, DCGM, MIG, or tensor cores. The honest
question is what CAN be measured here. GEMM (matrix multiply) is the workload
tensor cores exist for, and Apple's Accelerate/BLAS on the M1 has a hardware
path of its own (NEON SIMD + the undocumented AMX coprocessor). So: how much
faster is a tuned library GEMM than the same computation written by hand on
this CPU?

## What I tried

FP32 `C = A x B` for `n = 128..2048` three ways, all verified bit-identical
to Apple's `cblas_sgemm` (rel_err=0 for every size):

- `naive_ijk` — worst-order scalar triple loop (inner loop walks a column)
- `naive_ikj` — contiguous scalar triple loop (inner loop walks a row; clang
  `-O3` auto-vectorizes it to NEON, per the SIMD field note)
- `blas_sgemm` — Accelerate `cblas_sgemm` (NEON + AMX coprocessor)

Plus a memory-bound control: elementwise add/mul over 2^20 floats, scalar vs
`vDSP_vadd`/`vDSP_vmul`. Apple M1 Pro, clang 16.0.0, best of up to 5 trials.

Run it with:

```bash
bash scripts/11-gpu/compute-throughput/run-experiment.sh
```

## Result (real numbers/output only)

| method | n=128 | n=256 | n=512 | n=1024 | n=2048 | (GFLOPS) |
| --- | ---: | ---: | ---: | ---: | ---: | --- |
| naive_ijk | 2.32 | 1.85 | 1.55 | 1.38 | 0.64 | 0.64-2.3 |
| naive_ikj | 27.24 | 21.95 | 22.04 | 21.70 | 20.95 | ~21-27 |
| blas_sgemm | 838.8 | 1082.4 | 1579.0 | 1830.8 | 1454.9 | 840-1831 |

At n=1024: `blas_sgemm` is **~1330x** faster than `naive_ijk` and **~84x**
faster than `naive_ikj`. Peak measured 1830.8 GFLOPS (n=1024).

Elementwise (n=2^20 x 300), GB/s: scalar add 95.9 / vdsp add 141.8 (1.48x);
scalar mul 94.6 / vdsp mul 131.4 (1.39x).

Full transcript in `11-gpu/investigations/artifacts/compute-throughput-run.txt`.

## Takeaway

A tuned BLAS is not a few percent better than hand-written loops — it is
1-2 orders of magnitude better, because it uses every hardware resource
(NEON + AMX) and cache-blocks so the data actually arrives in time. The
GEMM gap (1.4 GFLOPS hand-written worst-case vs 1831 GFLOPS BLAS) is the same
order of magnitude as CPU-vs-GPU gaps that motivate shipping GEMMs to tensor
cores in the first place. The elementwise control shows the caveat: once a
loop is memory-bound, SIMD only helps ~1.4x (95 -> 142 GB/s), because the
bottleneck is DRAM bandwidth, not the ALUs. This is exactly why "just use a
library" is the correct first optimization and why the library's quality
matters: naive ikj is already cache-blocked by accident of the loop order,
and it is still 84x slower than AMX.

What this machine CANNOT measure (documented, not measured here): NVIDIA
CUDA kernels, NCCL ring/tree collectives and `nccl-tests`, `nsight`
compute/systems profilers, DCGM metrics, MIG partitioning, NVLink bandwidth,
tensor-core GEMM, vLLM with real GPUs. Those need NVIDIA hardware and are the
deferred `15-benchmarks/` entries.

## Core questions

- **Why is this system slow?** `naive_ijk` strides across B columns: every
  inner-loop access misses cache, so it runs at ~1.4 GFLOPS (memory-bound),
  and throughput falls as n grows (0.64 GFLOPS at n=2048).
- **Where is time being spent?** In `naive_ijk`, in DRAM loads. In
  `naive_ikj`, in NEON FMA issue (data is contiguous and cache-resident,
  ~22 GFLOPS = ~3.4 FMA/cycle). In BLAS, in the AMX coprocessor.
- **What is the bottleneck?** `naive_ijk`: memory latency/bandwidth.
  `naive_ikj`: NEON arithmetic throughput. BLAS: AMX throughput, then memory
  for large n (dips 1831 -> 1455 GFLOPS at n=2048).
- **How can the bottleneck be measured?** Vary n and watch GFLOPS vs n: the
  worst-order kernel degrades with n (cache misses grow), the BLAS grows with
  n until the working set (3n^2 floats) exceeds L2, then dips.
- **What evidence supports the conclusion?** Measured 1830.8 GFLOPS peak BLAS
  vs 21.70 GFLOPS best scalar at n=1024 (84x), and the memory-bound
  elementwise results where vDSP only reaches 1.4x (142 vs 96 GB/s).
- **What optimization was applied?** None to hand-written code — the point is
  that substituting `cblas_sgemm` IS the optimization. vDSP/vBLAS calls route
  to NEON + AMX that scalar C cannot reach.
- **What trade-offs were introduced?** BLAS results were bit-identical here,
  but library GEMMs may accumulate in non-standard order (results can differ
  in last-bit from scalar). Accelerate is Apple-only; the portable story is
  OpenBLAS/oneAPI MKL on x86, cuBLAS on NVIDIA.

## Reference

- Apple Accelerate/vecLib (vDSP, CBLAS), M1 AMX coprocessor
- MIT 6.172 `vectorization/homework3/loop.c` for the NEON width evidence
  (see `02-cpu/investigations/simd-auto-vectorization-field-note.md`)
- NVIDIA tooling (nccl-tests, nsight, DCGM, MIG): deferred, no hardware here
