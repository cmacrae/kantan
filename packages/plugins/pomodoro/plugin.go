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
	Colors            map[string]string `json:"colors"`
}

var defaultColors = map[string]string{
	"work":        "red",
	"break":       "green",
	"paused":      "gray",
	"dot":         "red",
	"dot_outline": "gray",
}

// colorFor is the colour of the popup's part `key`: the settings' own, or
// the plugin's, or none for a part left to the system's colour.
func (s Settings) colorFor(key string) string {
	if color := s.Colors[key]; color != "" {
		return color
	}
	return defaultColors[key]
}

// colored is `node` with `color` as its property `key`, when there is one.
func colored(node map[string]interface{}, key, color string) map[string]interface{} {
	if color != "" {
		node[key] = color
	}
	return node
}

var defaultIcons = map[string]string{
	"idle":        "circle-filled",
	"work":        "hourglass",
	"short_break": "moon-filled",
	"long_break":  "moon-filled",
	"paused":      "player-pause-filled",
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
	if d := os.Getenv("XDG_CACHE_HOME"); filepath.IsAbs(d) {
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
// advisory lock, so concurrent invocations can't lose updates. The state is
// saved only when fn changes it.
func mutateState(fn func(*State)) {
	unlock, err := acquireStateLock()
	if err == nil {
		defer unlock()
	}
	s := loadState()
	before := s
	fn(&s)
	if s != before {
		saveState(s)
	}
}

// Compute seconds remaining in the current segment.
func remaining(s State) float64 {
	return remainingAt(s, float64(time.Now().Unix()))
}

// Compute seconds remaining in the current segment at unix time `now`.
func remainingAt(s State, now float64) float64 {
	if s.Mode == "idle" {
		return 0
	}
	totalSecs := float64(s.Duration) * 60
	var elapsed float64
	if s.PausedAt > 0 {
		elapsed = s.PausedAt - s.StartedAt
	} else {
		elapsed = now - s.StartedAt
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

func cmdStart(settings Settings) { run("--start", settings) }
func cmdPause()                  { run("--pause", Settings{}) }
func cmdResume()                 { run("--resume", Settings{}) }
func cmdSkip(settings Settings)  { run("--skip", settings) }
func cmdReset()                  { run("--reset", Settings{}) }

// run applies the subcommand `command` to the saved state now.
func run(command string, settings Settings) {
	mutateState(func(s *State) {
		apply(s, command, float64(time.Now().Unix()), settings)
	})
}

// apply changes `s` as the subcommand `command` does at unix time `now`,
// reporting whether `command` is one.
func apply(s *State, command string, now float64, settings Settings) bool {
	switch command {
	case "--start":
		s.Mode = "work"
		s.Duration = settings.WorkDuration
		s.StartedAt = now
		s.PausedAt = 0
	case "--pause":
		if s.Mode != "idle" && s.PausedAt == 0 {
			s.PausedAt = now
		}
	case "--resume":
		if s.PausedAt != 0 {
			s.StartedAt += now - s.PausedAt
			s.PausedAt = 0
		}
	case "--skip":
		switch s.Mode {
		case "work":
			s.Sessions++
			mode, dur := nextBreakMode(s.Sessions, settings)
			s.Mode = mode
			s.Duration = dur
			s.StartedAt = now
			s.PausedAt = 0
		case "short_break", "long_break":
			s.Mode = "work"
			s.Duration = settings.WorkDuration
			s.StartedAt = now
			s.PausedAt = 0
		}
	case "--reset":
		*s = State{Mode: "idle"}
	default:
		return false
	}
	return true
}

// --- JSON Output ---

func buildOutput(settings Settings) {
	var state State
	mutateState(func(s *State) {
		maybeTransition(s, settings)
		state = *s
	})

	pluginName := os.Getenv("KANTAN_MODULE_NAME")
	if pluginName == "" {
		pluginName = "pomodoro"
	}

	enc := json.NewEncoder(os.Stdout)
	enc.SetIndent("", "  ")
	_ = enc.Encode(render(state, float64(time.Now().Unix()), settings, pluginName))
}

// The output for `state` at unix time `now`, for the module `pluginName`.
func render(state State, now float64, settings Settings, pluginName string) map[string]interface{} {
	rem := remainingAt(state, now)
	remainStr := formatDuration(rem)
	isPaused := state.PausedAt > 0
	isActive := state.Mode != "idle"
	mode := modeLabel(state.Mode)
	sessionsStr := fmt.Sprintf("%d", state.Sessions)

	icon := settings.iconFor(state.Mode)
	if isPaused {
		icon = settings.iconFor("paused")
	}

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

	// The ring empties as the segment's time runs out. Idle, it is full,
	// around the length of the work session a start begins.
	fraction := 1.0
	ringText := formatDuration(float64(settings.WorkDuration) * 60)
	if isActive {
		ringText = remainStr
		if total := float64(state.Duration) * 60; total > 0 {
			fraction = rem / total
		}
	}
	statusText := mode
	if isPaused {
		statusText = "Paused"
	}

	// The ring's stroke is centred on its frame's edge, so the frame around
	// the two is the stroke wider than the ring's.
	viewChildren := []interface{}{
		map[string]interface{}{
			"type":  "zstack",
			"frame": map[string]interface{}{"w": ringSize + ringStroke, "h": ringSize + ringStroke},
			"children": []interface{}{
				colored(map[string]interface{}{
					"type": "progress", "style": "ring", "value": fraction,
					"strokeWidth": ringStroke,
					"color":       settings.colorFor(ringColor(state.Mode, isPaused)),
					"frame":       map[string]interface{}{"w": ringSize, "h": ringSize},
				}, "trackColor", settings.colorFor("track")),
				map[string]interface{}{
					"type": "vstack", "alignment": "center", "spacing": 2,
					"children": []interface{}{
						map[string]interface{}{
							"type": "text", "content": ringText, "size": 20,
							"weight": "semibold", "style": "monospaced",
						},
						map[string]interface{}{
							"type": "text", "content": statusText, "size": 11, "style": "secondary",
						},
					},
				},
			},
		},
	}

	// A dot for each work session of the round that ends in a long break,
	// filled once the session is done.
	if round := settings.LongBreakInterval; round > 0 {
		done := state.Sessions % round
		if state.Mode == "long_break" {
			done = round
		}
		var dots []interface{}
		for i := 0; i < round; i++ {
			dot := map[string]interface{}{
				"type": "circle", "size": 10, "strokeColor": settings.colorFor("dot_outline"), "strokeWidth": 1,
			}
			if i < done {
				dot["color"] = settings.colorFor("dot")
			}
			dots = append(dots, dot)
		}
		sessionText := fmt.Sprintf("%d of %d sessions done", done, round)
		if state.Mode == "work" {
			sessionText = fmt.Sprintf("Session %d of %d", done+1, round)
		}
		viewChildren = append(viewChildren,
			centredRow(6, dots),
			map[string]interface{}{
				"type": "text", "content": sessionText, "size": 11, "style": "secondary",
			},
		)
	}

	// Buttons depend on state. With a timer on, Skip sits in the middle
	// with a place of one width either side: the button before it ends at
	// its place's far side and Reset starts at its own's near side, so
	// neither Skip nor Reset moves as Pause gives way to Resume.
	button := func(label, icon, subcommand string) map[string]interface{} {
		return buttonView(label, settings.iconFor(icon), menuCommand(subcommand, pluginName), settings.colorFor("button"))
	}
	place := func(children ...interface{}) map[string]interface{} {
		return map[string]interface{}{
			"type": "hstack", "spacing": 0, "children": children,
			"frame": map[string]interface{}{"w": buttonPlace},
		}
	}
	buttons := []interface{}{button("Start", "start", "--start")}
	if isActive {
		first := button("Pause", "pause", "--pause")
		if isPaused {
			first = button("Resume", "resume", "--resume")
		}
		buttons = []interface{}{
			place(spacerView(), first),
			button("Skip", "skip", "--skip"),
			place(button("Reset", "reset", "--reset"), spacerView()),
		}
	}
	viewChildren = append(viewChildren, centredRow(12, buttons))

	view := map[string]interface{}{
		"type":      "vstack",
		"alignment": "center",
		"spacing":   10,
		"padding":   map[string]interface{}{"top": 14, "leading": 16, "bottom": 14, "trailing": 16},
		"frame":     map[string]interface{}{"w": 260},
		"children":  viewChildren,
	}

	active := isActive
	output := map[string]interface{}{
		"value":     displayValue,
		"icon":      icon,
		"active":    active,
		"variables": variables,
		"view":      view,
	}
	return output
}

// --- View tree helpers ---

// menuCommand is the command a button runs: `subcommand`, then a refresh of
// the module `pluginName`.
func menuCommand(subcommand, pluginName string) string {
	return fmt.Sprintf("kantan-plugin-pomodoro %s && kantan trigger %s refresh", subcommand, shellQuote(pluginName))
}

// ringColor is the setting that colours the ring in `mode`: `work` while
// working, `break` on a break, and `paused` while paused or idle.
func ringColor(mode string, paused bool) string {
	switch {
	case paused || mode == "idle":
		return "paused"
	case mode == "work":
		return "work"
	default:
		return "break"
	}
}

// The ring's diameter and the width of its stroke, in points, and the
// width of the place a button either side of Skip has, which holds the
// longest of them, Resume.
const (
	ringSize    = 100
	ringStroke  = 18
	buttonPlace = 72
)

// centredRow is `children` in a row, `spacing` apart, with a spacer either
// side that keeps them in the middle of the popup.
func centredRow(spacing int, children []interface{}) map[string]interface{} {
	return map[string]interface{}{
		"type":    "hstack",
		"spacing": 0,
		"children": []interface{}{
			spacerView(),
			map[string]interface{}{"type": "hstack", "spacing": spacing, "children": children},
			spacerView(),
		},
	}
}

// spacerView is a spacer that may shrink to nothing, so what it centres
// has the whole width to itself.
func spacerView() map[string]interface{} {
	return map[string]interface{}{"type": "spacer", "minLength": 0}
}

// buttonView is a button that leaves the popup open, so the timer can be
// paused, skipped and reset in one visit.
func buttonView(label, icon, command, color string) map[string]interface{} {
	return colored(map[string]interface{}{
		"type":    "button",
		"label":   label,
		"icon":    icon,
		"command": command,
		"dismiss": false,
	}, "color", color)
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
