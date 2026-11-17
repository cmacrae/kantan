// Prints the states of the tailscale module's preview: connected to a
// tailnet, and disconnected.
package main

import (
	"encoding/json"
	"os"
)

func main() {
	settings := loadSettings()
	_ = json.NewEncoder(os.Stdout).Encode(map[string]any{"states": []map[string]any{
		{"name": "Connected", "output": render(state{Connected: true, Tailnet: "example.ts.net"}, settings)},
		{"name": "Disconnected", "output": render(state{}, settings)},
	}})
}
