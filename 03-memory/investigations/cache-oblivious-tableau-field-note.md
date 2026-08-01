# Cache-oblivious tableau: recursive 4-way is NOT faster here

## Problem

MIT 6.172 HW8 asks for the cache complexity of filling an `N x N` tableau
`A(i,j) = f(A(i-1,j-1), A(i,j-1), A(i-1,j))` two ways:

- **iterative**: fill row by row
- **recursive 4-way**: divide the quadrant into 4 sub-quadrants, recurse (the
  cache-oblivious formulation, claimed `Q(n) = Theta(n^2/MB)` vs the
  iterative `Theta(n^2/B)`)

The claim is the recursive version should have better cache behavior at large
`N`. I measured whether that shows up in wall-clock time on this machine.

## What I tried

Implemented both formulations exactly (`scripts/03-memory/cache-oblivious-tableau/tableau_bench.c`),
using the PDF's space optimization: the tableau is stored on the 2N-1
anti-diagonals, so `A(i,j)` lives at `A[N + i - j - 1]`. With `f(a,b,c) = a ^ b ^ c`,
both formulations produce identical results (verified `result=7` at every N).
Swept `N = 512..16384`, best of 3 trials each, `-O3 -DNDEBUG` on Apple M1 Pro
(clang 16.0.0).

Run it with:

```bash
bash scripts/03-memory/cache-oblivious-tableau/run-experiment.sh
```

## Result (real numbers/output only)

| method | N | best_ms | Mcells_per_s |
| --- | --- | ---: | ---: |
| iterative | 512 | 0.19 | 1374 |
| iterative | 1024 | 0.76 | 1377 |
| iterative | 2048 | 3.10 | 1352 |
| iterative | 4096 | 12.64 | 1327 |
| iterative | 8192 | 50.64 | 1325 |
| iterative | 16384 | 201.70 | 1331 |
| recursive | 512 | 0.76 | 344 |
| recursive | 1024 | 3.08 | 340 |
| recursive | 2048 | 12.24 | 342 |
| recursive | 4096 | 49.16 | 341 |
| recursive | 8192 | 196.95 | 341 |
| recursive | 16384 | 787.70 | 341 |

Full transcript in `03-memory/investigations/artifacts/tableau-cache-complexity-run.txt`.

## Takeaway

The recursive 4-way version is **~3.9x slower at every N**, and its throughput
is flat (341 Mcells/s) exactly like the iterative version (1330 Mcells/s).
Flat throughput across N is the tell: neither formulation is becoming
cache-bound, so the cache-oblivious advantage never appears. The working set
is `(2N-1)*4 = 128KB` even at N=16384, which fits in L2 (4MB). The PDF's own
space optimization (the 2N-1 diagonal layout) keeps the tableau cache-resident
at every size I can measure, so the recursive formulation's ~N^2 function-call
overhead is pure loss. The `Q(n) = Theta(n^2/MB)` win would only show up when
the diagonal array outgrows cache, i.e. N > ~500,000 (unmeasurable: N^2 cells).

## Core questions

- **Why is this system slow?** The recursive version pays roughly `(4/3)N^2`
  function calls to recompute the same N^2 cells the iterative version computes
  with two nested loops.
- **Where is time being spent?** In the recursive formulation, in call/return
  and quadrant bookkeeping; the arithmetic itself is the same for both.
- **What is the bottleneck?** With the working set cache-resident, there are no
  cache misses to amortize; instruction/call overhead dominates.
- **How can the bottleneck be measured?** Sweep N and plot throughput. Flat
  throughput per method => compute-bound, not cache-bound. Both methods stay
  flat to N=16384, so no cache-complexity gap is reachable here.
- **What evidence supports the conclusion?** Iterative holds ~1330 Mcells/s and
  recursive holds ~341 Mcells/s at every N; identical result values confirm
  both compute the same tableau.
- **What optimization was applied?** None yet — the honest finding is that the
  cache-oblivious claim is not observable in this configuration. A base-case
  cutoff (switch to the iterative kernel below a block size) is the standard
  practical version and would remove the call overhead; that is a follow-up,
  not something measured here.
- **What trade-offs were introduced?** The diagonal layout trades an N x N
  matrix for a 2N-1 array, shrinking the working set so far that the
  cache-oblivious benefit becomes unmeasurable.

## Reference

- MIT 6.172 HW8, `caching.pdf`
- Cache-oblivious model: `Q(n) = Theta(n^2/MB)` (recursive) vs
  `Theta(n^2/B)` (iterative) for this recurrence (theory only; see Takeaway).
- Apple M1 Pro: L1d 64KB, L2 4MB, ARM NEON.
