// Prints the states of the pomodoro module's preview: the timer a moment
// after each command, so running a menu action from one state leads to
// another.
package main

import (
	"encoding/json"
	"os"
)

func main() {
	const now = 1_800_000_000
	const module = "pomodoro"
	settings := loadSettings()

	type named struct {
		name  string
		state State
	}
	states := []named{
		{"Idle", State{Mode: "idle"}},
		{"Working", State{Mode: "work", StartedAt: now, Duration: settings.WorkDuration}},
		{"Paused", State{Mode: "work", StartedAt: now, PausedAt: now, Duration: settings.WorkDuration}},
		{"Short break", State{Mode: "short_break", StartedAt: now, Duration: settings.ShortBreak, Sessions: 1}},
		{"Break paused", State{Mode: "short_break", StartedAt: now, PausedAt: now, Duration: settings.ShortBreak, Sessions: 1}},
	}

	preview := []map[string]any{}
	for _, s := range states {
		after := map[string]any{}
		for _, subcommand := range []string{"--start", "--pause", "--resume", "--skip", "--reset"} {
			next := s.state
			apply(&next, subcommand, now, settings)
			after[menuCommand(subcommand, module)] = render(next, now, settings, module)
		}
		preview = append(preview, map[string]any{
			"name":   s.name,
			"output": render(s.state, now, settings, module),
			"after":  after,
		})
	}
	_ = json.NewEncoder(os.Stdout).Encode(map[string]any{"states": preview})
}
