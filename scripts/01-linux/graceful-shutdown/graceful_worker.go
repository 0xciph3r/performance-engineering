package main

import (
	"fmt"
	"os"
	"os/signal"
	"sync/atomic"
	"syscall"
	"time"
)

func main() {
	var termRequested atomic.Bool

	sigCh := make(chan os.Signal, 1)
	signal.Notify(sigCh, syscall.SIGTERM)

	go func() {
		<-sigCh
		termRequested.Store(true)
		fmt.Println("received SIGTERM; draining current work unit")
	}()

	fmt.Printf("pid=%d graceful worker started\n", os.Getpid())
	fmt.Println("starting work unit duration=5s")

	for second := 1; second <= 5; second++ {
		time.Sleep(1 * time.Second)
		fmt.Printf("progress second=%d\n", second)
	}

	fmt.Println("completed work unit")

	if termRequested.Load() {
		fmt.Println("shutdown complete after drain")
		return
	}

	fmt.Println("no shutdown signal received")
}
