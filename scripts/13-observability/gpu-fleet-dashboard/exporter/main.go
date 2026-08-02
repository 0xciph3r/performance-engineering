package main

import (
	"flag"
	"fmt"
	"log"
	"math"
	"math/rand"
	"net/http"
	"os"
	"sync"
	"time"
)

// dcgm-exporter-style simulator. Emits NVIDIA DCGM metric names/labels that
// dcgm-exporter would produce on real hardware. Values are synthetic sine+noise
// so the dashboard moves; this runs on machines with no GPU.

type gpu struct {
	index   int
	name    string
	uuid    string
	model   string
	driver  string
	memGiB  float64
	phase   float64
	basePct float64
}

var fleet = []gpu{
	{0, "NVIDIA A100-SXM4-80GB", "GPU-9f1d2c3e-aaaa-4b0a-8f2d-1a2b3c4d5e6f", "A100", "535.183.01", 80, 0.0, 55},
	{1, "NVIDIA A100-SXM4-80GB", "GPU-9f1d2c3e-bbbb-4b0a-8f2d-1a2b3c4d5e6f", "A100", "535.183.01", 80, 1.1, 40},
	{2, "NVIDIA A100-SXM4-80GB", "GPU-9f1d2c3e-cccc-4b0a-8f2d-1a2b3c4d5e6f", "A100", "535.183.01", 80, 2.2, 25},
	{3, "NVIDIA A100-SXM4-80GB", "GPU-9f1d2c3e-dddd-4b0a-8f2d-1a2b3c4d5e6f", "A100", "535.183.01", 80, 3.3, 70},
	{4, "NVIDIA H100 SXM5 80GB", "GPU-5e7f8a9b-eeee-4b0a-8f2d-1a2b3c4d5e6f", "H100", "550.54.15", 80, 4.4, 60},
	{5, "NVIDIA H100 SXM5 80GB", "GPU-5e7f8a9b-ffff-4b0a-8f2d-1a2b3c4d5e6f", "H100", "550.54.15", 80, 5.5, 85},
	{6, "NVIDIA H100 SXM5 80GB", "GPU-5e7f8a9b-0000-4b0a-8f2d-1a2b3c4d5e6f", "H100", "550.54.15", 80, 6.6, 10},
	{7, "NVIDIA A40", "GPU-1b2c3d4e-1111-4b0a-8f2d-1a2b3c4d5e6f", "A40", "535.183.01", 48, 7.7, 30},
}

// h100 peak FP16 dense TFLOPS ~ 989.6 (with sparsity halved w/o); A100 ~312.
func peakFp16(name string) float64 {
	if name == "NVIDIA H100 SXM5 80GB" {
		return 494.5
	}
	if name == "NVIDIA A100-SXM4-80GB" {
		return 156.0
	}
	return 149.7 // A40
}

func peakFp32(name string) float64 {
	if name == "NVIDIA H100 SXM5 80GB" {
		return 67.0
	}
	if name == "NVIDIA A100-SXM4-80GB" {
		return 19.5
	}
	return 37.4 // A40
}

var mu sync.Mutex
var lastScrape = time.Now()

func metric(name, labels, value string) string {
	return fmt.Sprintf("%s{%s} %s\n", name, labels, value)
}

func scrape(w http.ResponseWriter, r *http.Request) {
	now := time.Now()
	mu.Lock()
	lastScrape = now
	mu.Unlock()

	rng := rand.New(rand.NewSource(now.UnixNano()))
	t := float64(now.UnixMilli()) / 1e3

	w.Header().Set("Content-Type", "text/plain; version=0.0.4")
	for _, g := range fleet {
		labels := fmt.Sprintf("gpu=%q,model_name=%q,uuid=%q,driver_version=%q", g.name, g.model, g.uuid, g.driver)

		util := clamp(g.basePct + 15*math.Sin(t/12.0+g.phase) + 8*math.Sin(t/3.1+g.phase*1.7) + rng.Float64()*3, 0, 100)
		mem := clamp(g.basePct+20+20*math.Sin(t/20.0+g.phase)*0.5, 5, 100) // % of total
		temp := 40 + util*0.35 + rng.Float64()*2
		power := util / 100 * powerMax(g.name)

		fmt.Fprint(w, metric("dcgm_gpu_utilization", labels, f(util)))
		fmt.Fprint(w, metric("dcgm_gpu_memory_used_bytes", labels, f(mem/100*g.memGiB*1024*1024*1024)))
		fmt.Fprint(w, metric("dcgm_gpu_memory_total_bytes", labels, f(g.memGiB*1024*1024*1024)))
		fmt.Fprint(w, metric("dcgm_gpu_temperature_celsius", labels, f(temp)))
		fmt.Fprint(w, metric("dcgm_gpu_power_usage_watts", labels, f(power)))
		fmt.Fprint(w, metric("dcgm_gpu_sm_clock_mhz", labels, f(clamp(300+util*13.5, 300, 1980))))
		fmt.Fprint(w, metric("dcgm_gpu_mem_clock_mhz", labels, f(405+util*7.5)))
		fmt.Fprint(w, metric("dcgm_gpu_fp16_tflops", labels, f(util/100*peakFp16(g.name))))
		fmt.Fprint(w, metric("dcgm_gpu_fp32_tflops", labels, f(util/100*peakFp32(g.name))))
		pcie := util / 100 * 50 // GB/s
		fmt.Fprint(w, metric("dcgm_gpu_pcie_rx_bytes", labels, f(pcie*1024*1024*1024)))
		fmt.Fprint(w, metric("dcgm_gpu_pcie_tx_bytes", labels, f(pcie*0.6*1024*1024*1024)))

		for _, peer := range fleet {
			if peer.index == g.index {
				continue
			}
			link := fmt.Sprintf("%s,peer_uuid=%q,peer_gpu=%q", labels, peer.uuid, peer.name)
			nvlink := (util+peer.basePct) / 2 / 100 * 50 // GB/s per direction
			fmt.Fprint(w, metric("dcgm_gpu_nvlink_rx_bytes", link, f(nvlink*1024*1024*1024)))
			fmt.Fprint(w, metric("dcgm_gpu_nvlink_tx_bytes", link, f(nvlink*1024*1024*1024)))
		}
	}
	fmt.Fprint(w, metric("dcgm_gpu_fan_speed_percent", "gpu=\"fleet\"", "45.000"))
	fmt.Fprint(w, metric("dcgm_exporter_scrape_duration_seconds", "", "0.001"))
	fmt.Fprint(w, metric("dcgm_exporter_build_info", "version=\"sim-1.0\"", "1"))
}

func powerMax(name string) float64 {
	switch name {
	case "NVIDIA H100 SXM5 80GB":
		return 700
	case "NVIDIA A100-SXM4-80GB":
		return 400
	}
	return 300 // A40
}

func clamp(v, lo, hi float64) float64 {
	if v < lo {
		return lo
	}
	if v > hi {
		return hi
	}
	return v
}

func f(v float64) string {
	return fmt.Sprintf("%.3f", v)
}

func main() {
	port := flag.String("port", "9400", "listen port")
	flag.Parse()

	if _, err := os.Getwd(); err != nil {
		log.Fatal(err)
	}
	http.HandleFunc("/metrics", scrape)
	addr := ":" + *port
	log.Printf("dcgm-sim exporter listening on %s/metrics", addr)
	log.Fatal(http.ListenAndServe(addr, nil))
}
