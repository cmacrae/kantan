package main

import (
	"encoding/json"
	"fmt"
	"math"
	"os"
	"path/filepath"
	"syscall"
	"time"
)

// Settings decoded from KANTAN_SETTINGS env var.
type Settings struct {
	Format            string            `json:"format"`
	WorkDuration      int               `json:"work_duration"`
	ShortBreak        int               `json:"short_break"`
	LongBreak         int               `json:"long_break"`
	LongBreakInterval int               `json:"long_break_interval"`
	AutoStartBreaks   bool              `json:"auto_start_breaks"`
	AutoStartWork     bool              `json:"auto_start_work"`
	Icons             map[string]string `json:"icons"`
}

var defaultIcons = map[string]string{
	"idle":        "circle-filled",
	"work":        "hourglass",
	"short_break": "moon-filled",
	"long_break":  "moon-filled",
	"sessions":    "trophy-filled",
	"start":       "player-play-filled",
	"resume":      "player-play-filled",
	"pause":       "player-pause-filled",
	"skip":        "player-track-next-filled",
	"reset":       "x",
}

func defaultSettings() Settings {
	return Settings{
		Format:            "{remaining}",
		WorkDuration:      25,
		ShortBreak:        5,
		LongBreak:         15,
		LongBreakInterval: 4,
		AutoStartBreaks:   true,
		AutoStartWork:     false,
		Icons:             nil,
	}
}

func (s Settings) iconFor(mode string) string {
	if s.Icons != nil {
		if icon, ok := s.Icons[mode]; ok {
			return icon
		}
	}
	if icon, ok := defaultIcons[mode]; ok {
		return icon
	}
	return ""
}

func loadSettings() Settings {
	s := defaultSettings()
	raw := os.Getenv("KANTAN_SETTINGS")
	if raw == "" {
		return s
	}
	// Decode on top of defaults — missing fields keep defaults
	_ = json.Unmarshal([]byte(raw), &s)
	return s
}

// Persistent state written to disk.
type State struct {
	Mode      string  `json:"mode"`       // "idle", "work", "short_break", "long_break"
	StartedAt float64 `json:"started_at"` // unix timestamp when current segment started
	PausedAt  float64 `json:"paused_at"`  // unix timestamp when paused (0 if running)
	Duration  int     `json:"duration"`   // duration of current segment in minutes
	Sessions  int     `json:"sessions"`   // completed work sessions
}

func stateDir() string {
	if d := os.Getenv("XDG_CACHE_HOME"); d != "" {
		return filepath.Join(d, "kantan")
	}
	home, _ := os.UserHomeDir()
	return filepath.Join(home, ".cache", "kantan")
}

func statePath() string {
	return filepath.Join(stateDir(), "pomodoro.json")
}

func lockPath() string {
	return filepath.Join(stateDir(), "pomodoro.lock")
}

// acquireStateLock blocks until an exclusive advisory lock on the state file
// is held. The returned release function unlocks and closes the descriptor.
// Serialises load → modify → save across concurrent plugin invocations
// (interval ticks vs. menu actions).
func acquireStateLock() (func(), error) {
	if err := os.MkdirAll(stateDir(), 0o755); err != nil {
		return nil, err
	}
	f, err := os.OpenFile(lockPath(), os.O_CREATE|os.O_RDWR, 0o644)
	if err != nil {
		return nil, err
	}
	if err := syscall.Flock(int(f.Fd()), syscall.LOCK_EX); err != nil {
		_ = f.Close()
		return nil, err
	}
	return func() {
		_ = syscall.Flock(int(f.Fd()), syscall.LOCK_UN)
		_ = f.Close()
	}, nil
}

func loadState() State {
	data, err := os.ReadFile(statePath())
	if err != nil {
		return State{Mode: "idle"}
	}
	var s State
	if err := json.Unmarshal(data, &s); err != nil {
		return State{Mode: "idle"}
	}
	return s
}

// saveState writes via a temp file in the same directory then atomically
// renames into place, so a reader never sees a partial write.
func saveState(s State) {
	dir := stateDir()
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return
	}
	data, err := json.Marshal(s)
	if err != nil {
		return
	}
	tmp, err := os.CreateTemp(dir, "pomodoro.json.tmp.*")
	if err != nil {
		return
	}
	tmpPath := tmp.Name()
	if _, err := tmp.Write(data); err != nil {
		_ = tmp.Close()
		_ = os.Remove(tmpPath)
		return
	}
	if err := tmp.Close(); err != nil {
		_ = os.Remove(tmpPath)
		return
	}
	if err := os.Rename(tmpPath, statePath()); err != nil {
		_ = os.Remove(tmpPath)
	}
}

// mutateState performs an atomic load → mutate → save under an exclusive
// advisory lock, so concurrent invocations can't lose updates.
func mutateState(fn func(*State)) {
	unlock, err := acquireStateLock()
	if err == nil {
		defer unlock()
	}
	s := loadState()
	fn(&s)
	saveState(s)
}

// Compute seconds remaining in the current segment.
func remaining(s State) float64 {
	if s.Mode == "idle" {
		return 0
	}
	totalSecs := float64(s.Duration) * 60
	var elapsed float64
	if s.PausedAt > 0 {
		elapsed = s.PausedAt - s.StartedAt
	} else {
		elapsed = float64(time.Now().Unix()) - s.StartedAt
	}
	rem := totalSecs - elapsed
	if rem < 0 {
		return 0
	}
	return rem
}

func formatDuration(secs float64) string {
	total := int(math.Ceil(secs))
	m := total / 60
	s := total % 60
	return fmt.Sprintf("%02d:%02d", m, s)
}

func modeLabel(mode string) string {
	switch mode {
	case "work":
		return "Work"
	case "short_break":
		return "Short Break"
	case "long_break":
		return "Long Break"
	default:
		return "Idle"
	}
}

// Determine which break type comes next based on completed sessions.
func nextBreakMode(sessions int, settings Settings) (string, int) {
	if settings.LongBreakInterval > 0 && sessions%settings.LongBreakInterval == 0 {
		return "long_break", settings.LongBreak
	}
	return "short_break", settings.ShortBreak
}

// Check if timer has completed and auto-transition if configured.
func maybeTransition(s *State, settings Settings) bool {
	if s.Mode == "idle" || s.PausedAt > 0 {
		return false
	}
	if remaining(*s) > 0 {
		return false
	}

	switch s.Mode {
	case "work":
		s.Sessions++
		if settings.AutoStartBreaks {
			mode, dur := nextBreakMode(s.Sessions, settings)
			s.Mode = mode
			s.Duration = dur
			s.StartedAt = float64(time.Now().Unix())
			s.PausedAt = 0
		} else {
			s.Mode = "idle"
		}
	case "short_break", "long_break":
		if settings.AutoStartWork {
			s.Mode = "work"
			s.Duration = settings.WorkDuration
			s.StartedAt = float64(time.Now().Unix())
			s.PausedAt = 0
		} else {
			s.Mode = "idle"
		}
	}
	return true
}

// --- Subcommands ---

func cmdStart(settings Settings) {
	mutateState(func(s *State) {
		s.Mode = "work"
		s.Duration = settings.WorkDuration
		s.StartedAt = float64(time.Now().Unix())
		s.PausedAt = 0
	})
}

func cmdPause() {
	mutateState(func(s *State) {
		if s.Mode == "idle" || s.PausedAt > 0 {
			return
		}
		s.PausedAt = float64(time.Now().Unix())
	})
}

func cmdResume() {
	mutateState(func(s *State) {
		if s.PausedAt == 0 {
			return
		}
		pauseDuration := float64(time.Now().Unix()) - s.PausedAt
		s.StartedAt += pauseDuration
		s.PausedAt = 0
	})
}

func cmdSkip(settings Settings) {
	mutateState(func(s *State) {
		switch s.Mode {
		case "work":
			s.Sessions++
			mode, dur := nextBreakMode(s.Sessions, settings)
			s.Mode = mode
			s.Duration = dur
			s.StartedAt = float64(time.Now().Unix())
			s.PausedAt = 0
		case "short_break", "long_break":
			s.Mode = "work"
			s.Duration = settings.WorkDuration
			s.StartedAt = float64(time.Now().Unix())
			s.PausedAt = 0
		}
	})
}

func cmdReset() {
	mutateState(func(s *State) {
		*s = State{Mode: "idle"}
	})
}

// --- JSON Output ---

func buildOutput(settings Settings) {
	var state State
	mutateState(func(s *State) {
		maybeTransition(s, settings)
		state = *s
	})

	rem := remaining(state)
	remainStr := formatDuration(rem)
	isPaused := state.PausedAt > 0
	isActive := state.Mode != "idle"
	mode := modeLabel(state.Mode)
	sessionsStr := fmt.Sprintf("%d", state.Sessions)

	icon := settings.iconFor(state.Mode)

	// Format display value
	displayValue := settings.Format
	variables := map[string]string{
		"remaining": remainStr,
		"mode":      mode,
		"sessions":  sessionsStr,
		"status":    state.Mode,
	}
	for k, v := range variables {
		displayValue = replaceVar(displayValue, k, v)
	}

	// Build view tree
	pluginName := os.Getenv("KANTAN_MODULE_NAME")
	if pluginName == "" {
		pluginName = "pomodoro"
	}

	var viewChildren []interface{}

	// Header
	viewChildren = append(viewChildren, map[string]interface{}{
		"type": "header", "content": "Pomodoro",
	})

	// Status row
	statusText := mode
	if isPaused {
		statusText += " (Paused)"
	}
	viewChildren = append(viewChildren, hstackView(
		iconView(icon, nil),
		textView(statusText, nil, nil),
		spacerView(),
		textView(remainStr, nil, strPtr("monospaced")),
	))

	// Sessions row
	viewChildren = append(viewChildren, hstackView(
		iconView(settings.iconFor("sessions"), nil),
		textView("Sessions", nil, nil),
		spacerView(),
		textView("{sessions}", nil, nil),
	))

	viewChildren = append(viewChildren, dividerView())

	// Actions depend on state
	if !isActive {
		viewChildren = append(viewChildren, actionView(
			"Start", settings.iconFor("start"),
			fmt.Sprintf("kantan-plugin-pomodoro --start && kantan trigger %s refresh", shellQuote(pluginName)),
		))
	} else {
		if isPaused {
			viewChildren = append(viewChildren, actionView(
				"Resume", settings.iconFor("resume"),
				fmt.Sprintf("kantan-plugin-pomodoro --resume && kantan trigger %s refresh", shellQuote(pluginName)),
			))
		} else {
			viewChildren = append(viewChildren, actionView(
				"Pause", settings.iconFor("pause"),
				fmt.Sprintf("kantan-plugin-pomodoro --pause && kantan trigger %s refresh", shellQuote(pluginName)),
			))
		}
		viewChildren = append(viewChildren, actionView(
			"Skip", settings.iconFor("skip"),
			fmt.Sprintf("kantan-plugin-pomodoro --skip && kantan trigger %s refresh", shellQuote(pluginName)),
		))
		viewChildren = append(viewChildren, actionView(
			"Reset", settings.iconFor("reset"),
			fmt.Sprintf("kantan-plugin-pomodoro --reset && kantan trigger %s refresh", shellQuote(pluginName)),
		))
	}

	view := map[string]interface{}{
		"type":     "vstack",
		"spacing":  8,
		"padding":  map[string]interface{}{"top": 12, "leading": 16, "bottom": 12, "trailing": 16},
		"frame":    map[string]interface{}{"w": 260},
		"children": viewChildren,
	}

	active := isActive
	output := map[string]interface{}{
		"value":     displayValue,
		"icon":      icon,
		"active":    active,
		"variables": variables,
		"view":      view,
	}

	enc := json.NewEncoder(os.Stdout)
	enc.SetIndent("", "  ")
	_ = enc.Encode(output)
}

// --- View tree helpers ---

func hstackView(children ...interface{}) map[string]interface{} {
	return map[string]interface{}{
		"type":     "hstack",
		"children": children,
	}
}

func textView(content string, color *string, style *string) map[string]interface{} {
	m := map[string]interface{}{
		"type":    "text",
		"content": content,
	}
	if color != nil {
		m["color"] = *color
	}
	if style != nil {
		m["style"] = *style
	}
	return m
}

func iconView(name string, color *string) map[string]interface{} {
	m := map[string]interface{}{
		"type": "icon",
		"name": name,
	}
	if color != nil {
		m["color"] = *color
	}
	return m
}

func spacerView() map[string]interface{} {
	return map[string]interface{}{"type": "spacer"}
}

func dividerView() map[string]interface{} {
	return map[string]interface{}{"type": "divider"}
}

func actionView(label, icon, command string) map[string]interface{} {
	return map[string]interface{}{
		"type":    "action",
		"label":   label,
		"icon":    icon,
		"command": command,
	}
}

func replaceVar(s, key, val string) string {
	target := "{" + key + "}"
	result := s
	for {
		i := indexOf(result, target)
		if i < 0 {
			break
		}
		result = result[:i] + val + result[i+len(target):]
	}
	return result
}

func indexOf(s, substr string) int {
	for i := 0; i <= len(s)-len(substr); i++ {
		if s[i:i+len(substr)] == substr {
			return i
		}
	}
	return -1
}

func strPtr(s string) *string {
	return &s
}

func shellQuote(s string) string {
	// Simple single-quote escaping for shell safety
	result := "'"
	for _, c := range s {
		if c == '\'' {
			result += "'\\''"
		} else {
			result += string(c)
		}
	}
	result += "'"
	return result
}

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
