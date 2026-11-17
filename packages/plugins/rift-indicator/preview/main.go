// Prints the states of the rift-indicator module's preview: the active
// workspace in each of Rift's layouts.
package main

import (
	"encoding/json"
	"os"
)

func main() {
	settings := loadSettings()
	layouts := []struct{ name, mode string }{
		{"BSP", "bsp"},
		{"Floating", "floating"},
		{"Master Stack", "master_stack"},
		{"Scrolling", "scrolling"},
		{"Traditional", "traditional"},
	}

	preview := []map[string]any{}
	for _, layout := range layouts {
		preview = append(preview, map[string]any{
			"name":   layout.name,
			"output": render(&workspace{Name: "2", IsActive: true, LayoutMode: layout.mode}, settings),
		})
	}
	_ = json.NewEncoder(os.Stdout).Encode(map[string]any{"states": preview})
}
