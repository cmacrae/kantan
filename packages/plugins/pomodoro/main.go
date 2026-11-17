package main

import (
	"fmt"
	"os"
)

func main() {
	settings := loadSettings()

	if len(os.Args) > 1 {
		switch os.Args[1] {
		case "--start":
			cmdStart(settings)
		case "--pause":
			cmdPause()
		case "--resume":
			cmdResume()
		case "--skip":
			cmdSkip(settings)
		case "--reset":
			cmdReset()
		default:
			fmt.Fprintf(os.Stderr, "unknown command: %s\n", os.Args[1])
			os.Exit(1)
		}
		return
	}

	buildOutput(settings)
}
