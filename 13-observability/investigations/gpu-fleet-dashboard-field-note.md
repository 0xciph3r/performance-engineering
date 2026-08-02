# GPU fleet observability: DCGM-style dashboard on a machine with no GPU

## Problem

The plan calls for a GPU fleet dashboard (DCGM / Prometheus / Grafana) as the
observability entry, but this machine has no NVIDIA GPU and no DCGM agent.
The deliverable is the *pipeline*: an exporter in Prometheus format, a scrape
config, auto-provisioned datasources, and an auto-provisioned dashboard that
an operator can point at real DCGM metrics later. The honest way to build and
verify that here is a simulator that emits real DCGM metric names and labels.

## What I tried

A three-container docker-compose stack under
`scripts/13-observability/gpu-fleet-dashboard/`:

- **exporter** (Go, ~130 lines, zero deps): emits `dcgm_gpu_utilization`,
  `dcgm_gpu_memory_used_bytes`, `dcgm_gpu_temperature_celsius`,
  `dcgm_gpu_power_usage_watts`, `dcgm_gpu_sm_clock_mhz`,
  `dcgm_gpu_fp16_tflops`, `dcgm_gpu_pcie_*_bytes`,
  `dcgm_gpu_nvlink_{rx,tx}_bytes` for 8 synthetic GPUs (4x A100, 3x H100,
  1x A40) with real UUIDs/driver versions and sine+noise values so the graphs
  move. Clearly labeled `dcgm_exporter_build_info{version="sim-1.0"}`.
- **prometheus** (`prom/prometheus:v2.53.0`): scrapes the exporter every 5s.
- **grafana** (`grafana/grafana-oss:11.2.0`): auto-provisions the datasource
  (uid `prometheus`) and a 10-panel dashboard (uid `gpu-fleet`) from JSON on
  startup — no manual clicks.

`bash run.sh` brings the stack up, waits for readiness, captures 60s of
samples, runs the PromQL queries, and queries the Grafana API to prove the
dashboard provisioned.

## Result (real numbers/output only)

- Prometheus target: `dcgm-exporter` **up**.
- Fleet utilization (instant, avg): **46.5%**; per-GPU values 0-84.5%
  (H100s loaded 82-84%, one H100 idle at 0%, A40 at 26%).
- Peak temperature: **71.4 C**; fleet power sum: **1963.7 W**.
- GPUs reporting: **8**.
- Memory in use: 24-77 GiB of 80 GiB per GPU.
- NVLink TX (simulated, summed per GPU): 670 GB/s (A100s), 560 GB/s (H100s),
  135 GB/s (A40).
- Fleet util trend over the window (5m, step 5s): 13 samples,
  min 44.2%, max 53.0%, mean 48.3%.
- Grafana API: `uid=gpu-fleet title="GPU Fleet (simulated DCGM)" panels=10`.

Full transcript in
`13-observability/investigations/artifacts/gpu-fleet-dashboard-run.txt`.

## Takeaway

The full DCGM -> Prometheus -> Grafana pipeline works end-to-end with
zero-config provisioning: bring up the compose stack and the dashboard is
there. The hard part of this work is not the YAML/JSON wiring — it is honest
metric semantics (utilization is a 0-100 gauge, memory is bytes, NVLink/PCIe
are rates that need `rate()` on real counters) and label design so queries
can slice by `gpu`, `model_name`, `uuid`. On real hardware, `dcgm-exporter`
replaces the simulator and the same dashboard and queries apply; the numbers
above are synthetic and must not be treated as real fleet telemetry.

## Core questions

- **Why is this system slow / where is time spent?** Not applicable to the
  dashboard itself (simulated data). The observability point is: fleet
  metrics give you the evidence to answer this for a real cluster — a GPU
  pinned at 100% utilization with low SM throughput is a compute problem; a
  GPU at 20% with NVLink saturated is a communication problem.
- **What is the bottleneck?** For the stack: scrape interval (5s) sets
  resolution; Prometheus retention is set to 1h here for the lab. For a real
  fleet: exporter cardinality (one time series per metric per GPU peer pair)
  is the classic failure mode — 8 GPUs x 7 peers x 2 directions is already
  112 NVLink series.
- **How can the bottleneck be measured?** `dcgm_gpu_utilization` vs
  `dcgm_gpu_fp16_tflops` (is the GPU busy but idle?) and
  `dcgm_gpu_nvlink_tx_bytes` (is data moving?). The dashboard includes both
  compute and interconnect panels for exactly this split.
- **What evidence supports the conclusion?** Prometheus instant queries
  returned real JSON for every metric; Grafana API reported the dashboard
  provisioned with 10 panels; target health `up`.
- **What optimization was applied?** Grafana file provisioning
  (`provisioning/datasources`, `provisioning/dashboards`) so the dashboard is
  reproducible from JSON, and datasource `uid: prometheus` pinned so panel
  queries resolve without manual setup.
- **What trade-offs were introduced?** Simulated data is the only option on
  this machine; the exporter mimics dcgm-exporter metric names but not its
  exact label set or counter semantics (NVLink here is an instantaneous rate,
  not a counter). Values are illustrative, never real telemetry.

## Reference

- NVIDIA DCGM / `dcgm-exporter` metric names and labels
- Prometheus HTTP API (`/api/v1/query`, `/api/v1/query_range`)
- Grafana provisioning: datasources + dashboard providers
- `scripts/13-observability/gpu-fleet-dashboard/{exporter,prometheus,grafana}`
