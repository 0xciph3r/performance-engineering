# 03 - Memory & Cache

Field notes and scripts for memory-hierarchy and cache-behavior experiments.
Rules of this repo: only measured numbers get reported; theory is labeled as
theory; every experiment ships a reproducible script, an artifact transcript,
and a field note.

## Cache-oblivious tableau (recursive 4-way vs iterative)

Experiment: fill an `N x N` tableau `A(i,j) = f(A(i-1,j-1), A(i,j-1), A(i-1,j))`
with an iterative row-sweep vs the cache-oblivious 4-way recursive
formulation, stored on the 2N-1 diagonal layout from the assignment.

Measured result (Apple M1 Pro, clang 16.0.0, `-O3`): the iterative version is
**~3.9x faster at every N (512..16384)** and both stay flat in throughput
(iterative ~1330 Mcells/s, recursive ~341 Mcells/s), so neither is
cache-bound at any measurable size. The diagonal layout keeps the working set
at `(2N-1)*4 = 128KB`, inside L2, so the cache-oblivious cache-complexity win
is unobservable here; the recursive version only pays call overhead. The
`Theta(n^2/MB)` vs `Theta(n^2/B)` gap is theory, not a measured effect.

- Script: `scripts/03-memory/cache-oblivious-tableau/run-experiment.sh`
- Artifact: `investigations/artifacts/tableau-cache-complexity-run.txt`
- Field note: `investigations/cache-oblivious-tableau-field-note.md`

## SIMD vectorization

Cross-reference: the SIMD auto-vectorization field note lives under
`02-cpu/investigations/simd-auto-vectorization-field-note.md`. Vector width
(4x 32-bit / 2x 64-bit) is exactly a function of the 128-bit SIMD register
width on this machine, so it is the "how the CPU exploits data-level
parallelism" counterpart to the memory-hierarchy notes here.

## Not yet done

- A measurement that actually makes the working set exceed L2 (e.g. multiple
  large working arrays or a bigger element type) to observe a cache-complexity
  crossover. Current 2N-1 layout makes this impractical for this problem.
