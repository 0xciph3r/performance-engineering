package main

import (
	"fmt"
	"os"
	"time"
)

func main() {
	fmt.Printf("pid=%d baseline worker started\n", os.Getpid())
	fmt.Println("starting work unit duration=5s")
	time.Sleep(5 * time.Second)
	fmt.Println("completed work unit")
}
