# 13 - Observability

## GPU fleet dashboard (simulated DCGM, measured)

Full DCGM -> Prometheus -> Grafana pipeline that runs on a machine with **no
NVIDIA GPU**. A Go simulator emits real dcgm-exporter metric names and labels
(utilization, memory, temperature, power, clocks, FP16/FP32 TFLOPS, PCIe,
NVLink) for 8 synthetic GPUs; Prometheus scrapes it; Grafana auto-provisions a
10-panel dashboard from JSON. Verified: target `up`, 8 GPUs reporting,
queries return real values, Grafana API reports the dashboard provisioned.
The simulated numbers are labeled as synthetic and must not be read as real
fleet telemetry.

- Stack: `scripts/13-observability/gpu-fleet-dashboard/` (`docker compose up`)
- Run + capture: `scripts/13-observability/gpu-fleet-dashboard/run.sh`
- Artifact: `investigations/artifacts/gpu-fleet-dashboard-run.txt`
- Field note: `investigations/gpu-fleet-dashboard-field-note.md`

## Future work

- Point the same dashboard at real `dcgm-exporter` on NVIDIA hardware; swap
  the simulator's instantaneous NVLink values for true counters and use
  `rate()`.
- Add GPU ECC / Xid error telemetry and alerting (utilization drops, Xid
  events) in Prometheus rules.
