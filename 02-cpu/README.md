# CPU

CPU entries in this repository focus on measurable performance of scalar and SIMD code paths, profiling-driven optimization, and scheduling behavior rather than theory-only notes.

## SIMD / auto-vectorization

Experiment: MIT 6.172 `loop.c`, scalar (`-fno-vectorize`) vs vectorized
(`-ffast-math -Rpass=loop-vectorize`) builds for 4 ops x 4 types on Apple
M1 Pro. Auto-vectorization gives ~3.8x for 32-bit element types (vector
width 4), ~1.9x for 64-bit (width 2), and **nothing for integer division**
(no NEON instruction; 0.98x) or 64-bit integer multiply (interleaved only,
1.51x). `-ffast-math` is required to vectorize floating-point loops.

- Script: `scripts/02-cpu/simd-vectorization/run-experiment.sh`
- Artifact: `investigations/artifacts/simd-vectorization-run.txt`
- Field note: `investigations/simd-auto-vectorization-field-note.md`

## Cache hierarchy

Cross-reference: cache behavior experiments live under
`03-memory/investigations/cache-oblivious-tableau-field-note.md`. The SIMD
vector width (4x 32-bit / 2x 64-bit) is a direct function of the 128-bit
SIMD register width.

## Topics (background)

- Scheduling
- Cache hierarchy / cache misses
- Branch prediction
- Context switching
- CPU affinity
- False sharing
- Hyper-threading
