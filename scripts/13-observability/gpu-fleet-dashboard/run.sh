#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
artifacts_dir="$repo_root/13-observability/investigations/artifacts"
mkdir -p "$artifacts_dir"
summary_log="$artifacts_dir/gpu-fleet-dashboard-run.txt"

dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$dir"

: >"$summary_log"

echo "==> building and starting stack (exporter + prometheus + grafana)"
docker compose build -q
docker compose up -d
trap 'docker compose down' EXIT

echo "==> waiting for exporter"
for i in $(seq 1 60); do
  curl -sf http://localhost:9400/metrics >/dev/null 2>&1 && break
  sleep 1
done

echo "==> waiting for prometheus"
for i in $(seq 1 60); do
  curl -sf "http://localhost:9090/-/ready" >/dev/null 2>&1 && break
  sleep 1
done

echo "==> waiting for grafana"
for i in $(seq 1 60); do
  curl -sf "http://localhost:3000/api/health" >/dev/null 2>&1 && break
  sleep 1
done

echo "==> collecting 60s of metric samples"
sleep 60

pq() { # pq <promql>
  curl -sG "http://localhost:9090/api/v1/query" --data-urlencode "query=$1" \
    | python3 -c 'import sys,json;d=json.load(sys.stdin);print(json.dumps(d["data"]["result"],indent=1))'
}

{
  echo "benchmark=gpu-fleet-dashboard (simulated DCGM metrics)"
  echo "description=DCGM-style metrics from a simulator on a machine with no NVIDIA GPU"
  echo "images=prom/prometheus:v2.53.0, grafana/grafana-oss:11.2.0, exporter=local Go build"
  echo "stack=docker compose in scripts/13-observability/gpu-fleet-dashboard/"
  echo "simulation=8 synthetic GPUs (4x A100, 3x H100, 1x A40), sine+noise values, scrape 5s"
  echo
  echo "--- exporter /metrics (raw sample, truncated) ---"
  curl -s http://localhost:9400/metrics | head -30
  echo
  echo "--- prometheus targets ---"
  curl -s "http://localhost:9090/api/v1/targets" \
    | python3 -c 'import sys,json;d=json.load(sys.stdin);[print(t["labels"]["job"],t["health"],t["scrapeUrl"]) for t in d["data"]["activeTargets"]]'
  echo
  echo "--- fleet utilization avg (instant) ---"
  pq 'avg(dcgm_gpu_utilization)'
  echo "--- per-GPU utilization (instant) ---"
  pq 'dcgm_gpu_utilization'
  echo "--- peak temperature (instant) ---"
  pq 'max(dcgm_gpu_temperature_celsius)'
  echo "--- fleet power sum W (instant) ---"
  pq 'sum(dcgm_gpu_power_usage_watts)'
  echo "--- GPUs reporting (instant) ---"
  pq 'count(dcgm_gpu_utilization)'
  echo "--- memory used GiB by GPU (instant) ---"
  pq 'dcgm_gpu_memory_used_bytes / 1024^3'
  echo "--- NVLink TX GB/s summed per GPU (instant) ---"
  pq 'sum by (gpu) (dcgm_gpu_nvlink_tx_bytes) / 1024^3'
  echo "--- fleet util avg trend, 5m range (60 samples) ---"
  curl -sG "http://localhost:9090/api/v1/query_range" \
    --data-urlencode "query=avg(dcgm_gpu_utilization)" \
    --data-urlencode "start=$(( $(date +%s) - 300 ))" \
    --data-urlencode "end=$(date +%s)" \
    --data-urlencode "step=5" \
    | python3 -c '
import sys,json
d=json.load(sys.stdin)["data"]["result"]
if d:
    vals=[round(float(v[1]),1) for v in d[0]["values"]]
    print("samples=%d min=%s max=%s mean=%.1f"%(len(vals),min(vals),max(vals),sum(vals)/len(vals)))
    print(vals[:20])
'
  echo "--- grafana dashboard provisioning (api) ---"
  curl -s -u admin:admin "http://localhost:3000/api/dashboards/uid/gpu-fleet" \
    | python3 -c 'import sys,json;d=json.load(sys.stdin)["dashboard"];print("uid=%s title=%s panels=%d tags=%s"%(d["uid"],d["title"],len(d["panels"]),d["tags"]))'
} >>"$summary_log" 2>&1

echo "==> done"
cat "$summary_log"
echo
echo "grafana: http://localhost:3000 (admin/admin), dashboard 'GPU Fleet (simulated DCGM)'"
echo "transcript saved to $summary_log"
