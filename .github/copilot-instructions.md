# Copilot Instructions for `performance-engineering`

## Build, test, and lint commands

The tracked repository currently does **not** define build, test, or lint automation in checked-in manifests or task runners. Do **not** invent package managers, CI commands, or test selectors. If automation is added later, document the exact full-run and single-test commands from the real toolchain.

## High-level architecture

This repository is currently a **bootstrap for a performance-engineering knowledge base**, not an application codebase.

- `README.md` is the public-facing description: the repository is for experiments, profiling, benchmarking, and optimization across Linux, Kubernetes, distributed systems, HPC, and GPU infrastructure.
- `plan.md` is the operating blueprint for the repo. It defines the intended long-term topic taxonomy, the phased build order, the templates for investigations/benchmarks/labs, and the quality bar for every contribution.

Treat the repository as a portfolio of **evidence-driven engineering artifacts**. The main content types are:

- **Investigations** for root-cause analysis and optimization write-ups
- **Benchmarks** for reproducible measurement with preserved raw output
- **Labs** for reproducible hands-on exercises
- **Scripts** for benchmark/profiling/data-collection automation
- **References** for curated books, papers, blogs, talks, and videos

The long-term directory structure in `plan.md` is a target design, not something to scaffold all at once. The current phased priority is important:

1. Build now: GPU, HPC, benchmarks, investigations, case studies, plus a few specific early entries in Linux, distributed systems, observability, and databases
2. Phase 2: security and most remaining topic areas, created only when real work exists

When future sessions add real content, they should preserve the intended content model from `plan.md`:

- Topic areas are expected to grow around `README.md`, `concepts/`, `labs/`, `benchmarks/`, `investigations/`, and `references.md` when those sections are actually needed
- Benchmark-heavy work belongs under the benchmarks/investigations flow, with raw output preserved whenever practical
- Labs are expected to be reproducible documents, not loose notes

## Key conventions

- **No empty scaffolding.** Create a directory only when there is real content ready to commit.
- **Evidence precedes conclusions.** Prefer measured data, reproducible benchmarks, and root-cause analysis over summaries or opinion.
- **Do not publish borrowed metrics as local results.** Any reported numbers should be self-measured for this repository's experiments.
- **Use the right document weight.** Capstone-grade work should use the full investigation template from `plan.md`; regular weekly additions should usually use the lightweight Field Note format.
- **Preserve reproducibility.** Benchmarks should keep raw command output when practical, and labs should include setup, validation, cleanup, and expected results.
- **Prefer primary sources.** Use books, papers, and original engineering sources where possible instead of building entries from secondary summaries.
- **Separate facts from hypotheses.** Investigations should make it clear what was observed, what was inferred, and what optimization was actually validated.
- **Keep scripts under `scripts/`.** Automation should be production-quality and documented.
- **Organize references deliberately.** Use the reference categories defined in `plan.md` (`books.md`, `papers.md`, `blogs.md`, `talks.md`, `videos.md`) instead of dumping links into arbitrary notes.
- **Optimize for portfolio-grade artifacts.** Contributions should strengthen the repo as a public body of work for senior infrastructure, performance, HPC, GPU, and AI-infrastructure roles.
- **Respect the current priority path.** Near-term work should bias toward GPU, HPC, benchmarks, investigations, case studies, and the specific early entries called out in `plan.md` rather than filling every planned topic evenly.
