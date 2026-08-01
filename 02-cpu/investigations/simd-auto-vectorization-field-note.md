# SIMD auto-vectorization speedup on Apple Silicon

## Problem

The compiler can turn a scalar loop into a vectorized (SIMD) loop, but the win is not uniform: it depends on the data type width and on whether the target ISA has an instruction for the operation. The practical question is how much speedup auto-vectorization actually delivers per operation and per type on Apple M1 Pro.

## What I tried

I used the MIT 6.172 vectorization microbenchmark (`vectorization/homework3/loop.c`), which computes `C[j] = A[j] OP B[j]` for `N = 1024` elements repeated `I = 100000` times. I compiled it twice for every combination of op (`+ - * /`) and type (`uint32_t uint64_t float double`):

- scalar build: `-O3 -DNDEBUG -fno-vectorize`
- vectorized build: `-O3 -DNDEBUG -ffast-math -Rpass=loop-vectorize`

`-Rpass` records whether the loop was actually vectorized (and at what vector width). Each config ran 5 trials; best times are reported.

Run it with:

```bash
bash scripts/02-cpu/simd-vectorization/run-experiment.sh
```

## Result (real numbers/output only)

| op | type | scalar_best_ms | vector_best_ms | speedup_x | vectorized |
| --- | --- | ---: | ---: | ---: | --- |
| + | uint32_t | 41.62 | 11.02 | 3.78 | yes (width 4) |
| + | uint64_t | 41.57 | 20.68 | 2.01 | yes (width 2) |
| + | float | 39.38 | 10.94 | 3.60 | yes (width 4) |
| + | double | 39.48 | 21.29 | 1.85 | yes (width 2) |
| - | uint32_t | 41.71 | 10.92 | 3.82 | yes (width 4) |
| - | uint64_t | 41.82 | 21.51 | 1.94 | yes (width 2) |
| - | float | 39.40 | 10.94 | 3.60 | yes (width 4) |
| - | double | 39.47 | 20.90 | 1.89 | yes (width 2) |
| * | uint32_t | 39.47 | 11.00 | 3.59 | yes (width 4) |
| * | uint64_t | 39.49 | 26.14 | 1.51 | no (interleaved only) |
| * | float | 39.47 | 10.99 | 3.59 | yes (width 4) |
| * | double | 39.47 | 21.35 | 1.85 | yes (width 2) |
| / | uint32_t | 76.83 | 78.47 | 0.98 | no (interleaved only) |
| / | uint64_t | 76.92 | 78.46 | 0.98 | no (interleaved only) |
| / | float | 39.43 | 11.06 | 3.56 | yes (width 4) |
| / | double | 39.55 | 21.01 | 1.88 | yes (width 2) |

Compiler: Apple clang 16.0.0. Full transcript in `02-cpu/investigations/artifacts/simd-vectorization-run.txt`.

## Takeaway

32-bit element types vectorize to width 4 and get ~3.8x; 64-bit element types vectorize to width 2 and get ~1.9x; float and double vectorize for every op including division. Integer division does not vectorize at all (no speedup, 0.98x) and 64-bit integer multiplication only interleaves (1.51x), because the NEON ISA lacks those instructions and the compiler does not emulate them.

## Core questions

- **Why is this system slow?** The scalar builds are ~2-4x slower than the vectorized builds because they issue one element operation at a time instead of 128-bit SIMD lanes.
- **Where is time being spent?** In the un-vectorized case, the loop body repeats one `add/sub/mul/div` per element. Vectorization amortizes this across 2 or 4 elements per instruction.
- **What is the bottleneck?** Instruction issue throughput for arithmetic, plus the ISA's availability of a native vector instruction for the given op/type. There is no NEON integer division, so `/` stays scalar and even slightly slower.
- **How can the bottleneck be measured?** Compile with `-Rpass=loop-vectorize` to see if the loop vectorized and at what width, then time scalar vs vector builds.
- **What evidence supports the conclusion?** `+ uint32_t` went from 41.62 ms to 11.02 ms (3.78x) with a "vectorized loop (vectorization width: 4)" remark. `/ uint32_t` produced only "interleaved loop" and measured 0.98x, meaning no SIMD speedup.
- **What optimization was applied?** Letting clang auto-vectorize the loop (`-O3` + `-ffast-math` for floating-point reassociation); no hand-written intrinsics.
- **What trade-offs were introduced?** `-ffast-math` relaxes IEEE-754 semantics (reassociation is allowed), which can change floating-point results. Integer division and 64-bit integer multiply cannot benefit and carry the interleaving/unroll overhead.

## Reference

- MIT 6.172 `vectorization/homework3/loop.c`
- `clang -Rpass=loop-vectorize -Rpass-missed=loop-vectorize`
- ARM NEON vector width: 128-bit, i.e. 4x 32-bit or 2x 64-bit lanes
