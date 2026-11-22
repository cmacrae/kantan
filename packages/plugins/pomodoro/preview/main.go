// Prints the states of the pomodoro module's preview: the timer a moment
// after each command, so clicking a button in one state leads to another.
package main

import (
	"encoding/json"
	"os"
)

func main() {
	const now = 1_800_000_000
	const module = "pomodoro"
	settings := loadSettings()

	// How far into its segment each running state is, in seconds, so its
	// ring is part empty.
	worked := float64(settings.WorkDuration) * 60 * 0.3
	rested := float64(settings.ShortBreak) * 60 * 0.4

	type named struct {
		name  string
		state State
	}
	states := []named{
		{"Idle", State{Mode: "idle"}},
		{"Working", State{Mode: "work", StartedAt: now - worked, Duration: settings.WorkDuration}},
		{"Paused", State{Mode: "work", StartedAt: now - worked, PausedAt: now, Duration: settings.WorkDuration}},
		{"Short break", State{Mode: "short_break", StartedAt: now - rested, Duration: settings.ShortBreak, Sessions: 1}},
		{"Break paused", State{Mode: "short_break", StartedAt: now - rested, PausedAt: now, Duration: settings.ShortBreak, Sessions: 1}},
		{"Long break", State{Mode: "long_break", StartedAt: now - rested, Duration: settings.LongBreak, Sessions: settings.LongBreakInterval}},
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
