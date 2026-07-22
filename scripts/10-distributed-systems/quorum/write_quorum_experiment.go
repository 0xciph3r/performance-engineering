package main

import (
	"context"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"
)

type scenario struct {
	name          string
	availableNodes []int
}

type result struct {
	committed bool
	acks      int
	failures  int
	duration  time.Duration
	reason    string
}

type replicaServer struct {
	id     int
	server *http.Server
}

func main() {
	replicaPorts := map[int]string{
		1: "127.0.0.1:18081",
		2: "127.0.0.1:18082",
		3: "127.0.0.1:18083",
	}

	scenarios := []scenario{
		{name: "3-of-3-available", availableNodes: []int{1, 2, 3}},
		{name: "2-of-3-available", availableNodes: []int{1, 2}},
		{name: "1-of-3-available", availableNodes: []int{1}},
	}

	for _, s := range scenarios {
		fmt.Printf("scenario=%s\n", s.name)
		fmt.Printf("available_nodes=%d/3\n", len(s.availableNodes))

		servers := startReplicas(s.availableNodes, replicaPorts)
		time.Sleep(50 * time.Millisecond)

		var results []result
		for writeNumber := 1; writeNumber <= 5; writeNumber++ {
			r := quorumWrite(replicaPorts, fmt.Sprintf("value-%d", writeNumber), 2)
			results = append(results, r)
			fmt.Printf("write=%d committed=%t acks=%d failures=%d duration_ms=%d reason=%s\n",
				writeNumber,
				r.committed,
				r.acks,
				r.failures,
				r.duration.Milliseconds(),
				r.reason,
			)
		}

		shutdownReplicas(servers)
		printSummary(results)
		fmt.Println()
	}
}

func startReplicas(nodeIDs []int, replicaPorts map[int]string) []replicaServer {
	var servers []replicaServer

	for _, nodeID := range nodeIDs {
		mux := http.NewServeMux()
		replicaID := nodeID
		mux.HandleFunc("/write", func(w http.ResponseWriter, r *http.Request) {
			defer r.Body.Close()
			_, _ = io.ReadAll(r.Body)
			time.Sleep(40 * time.Millisecond)
			w.WriteHeader(http.StatusNoContent)
			_, _ = w.Write([]byte(fmt.Sprintf("replica=%d", replicaID)))
		})

		server := &http.Server{
			Addr:    replicaPorts[nodeID],
			Handler: mux,
		}

		servers = append(servers, replicaServer{id: nodeID, server: server})

		go func(s *http.Server) {
			_ = s.ListenAndServe()
		}(server)
	}

	return servers
}

func shutdownReplicas(servers []replicaServer) {
	for _, s := range servers {
		ctx, cancel := context.WithTimeout(context.Background(), time.Second)
		_ = s.server.Shutdown(ctx)
		cancel()
	}
}

func quorumWrite(replicaPorts map[int]string, value string, quorum int) result {
	start := time.Now()

	type ackResult struct {
		success bool
		error   string
	}

	client := &http.Client{Timeout: 250 * time.Millisecond}
	results := make(chan ackResult, len(replicaPorts))

	for _, addr := range replicaPorts {
		go func(endpoint string) {
			req, err := http.NewRequest(http.MethodPost, "http://"+endpoint+"/write", strings.NewReader(value))
			if err != nil {
				results <- ackResult{success: false, error: err.Error()}
				return
			}

			resp, err := client.Do(req)
			if err != nil {
				results <- ackResult{success: false, error: err.Error()}
				return
			}
			defer resp.Body.Close()

			if resp.StatusCode != http.StatusNoContent {
				results <- ackResult{success: false, error: resp.Status}
				return
			}

			results <- ackResult{success: true}
		}(addr)
	}

	acks := 0
	failures := 0
	total := len(replicaPorts)

	for range total {
		r := <-results
		if r.success {
			acks++
			if acks >= quorum {
				return result{
					committed: true,
					acks:      acks,
					failures:  failures,
					duration:  time.Since(start),
					reason:    "majority-achieved",
				}
			}
			continue
		}

		failures++
		if failures > total-quorum {
			return result{
				committed: false,
				acks:      acks,
				failures:  failures,
				duration:  time.Since(start),
				reason:    "majority-unreachable",
			}
		}
	}

	return result{
		committed: acks >= quorum,
		acks:      acks,
		failures:  failures,
		duration:  time.Since(start),
		reason:    "completed-all-requests",
	}
}

func printSummary(results []result) {
	var committed, failed int
	var totalDuration time.Duration
	var durations []int64

	for _, r := range results {
		totalDuration += r.duration
		durations = append(durations, r.duration.Milliseconds())
		if r.committed {
			committed++
		} else {
			failed++
		}
	}

	average := totalDuration / time.Duration(len(results))
	fmt.Printf("summary committed=%d failed=%d avg_duration_ms=%d samples_ms=%v\n",
		committed,
		failed,
		average.Milliseconds(),
		durations,
	)
}
