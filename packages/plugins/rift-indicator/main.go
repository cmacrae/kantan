package main

import (
	"context"
	"encoding/json"
	"os"
	"time"
)

func main() {
	if len(os.Args) > 1 && os.Args[1] == "--watch" {
		watch(loadSettings())
	}
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	_ = json.NewEncoder(os.Stdout).Encode(render(queryActiveWorkspace(ctx), loadSettings()))
}
