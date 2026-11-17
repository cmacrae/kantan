package main

import (
	"context"
	"time"
)

func main() {
	settings := loadSettings()
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	buildOutput(resolveState(ctx), settings)
}
