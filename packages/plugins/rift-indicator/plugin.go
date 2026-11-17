package main

import (
	"bufio"
	"context"
	"encoding/json"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"time"
)

// layout describes one of Rift's layout modes.
type layout struct {
	Title string
	Icon  string
}

// layouts maps Rift's layout mode identifiers to the names Rift's menu
// shows for them and their default icons.
var layouts = map[string]layout{
	"traditional":  {"Traditional", "layout-columns"},
	"bsp":          {"BSP", "layout-board-split"},
	"floating":     {"Floating", "picture-in-picture"},
	"stack":        {"Stack", "stack-2"},
	"master_stack": {"Master Stack", "layout-sidebar-right"},
	"scrolling":    {"Scrolling", "carousel-horizontal"},
}

// Settings decoded from KANTAN_SETTINGS env var. Both maps are keyed by
// layout mode identifier (e.g. `master_stack`) or name (e.g. `Master Stack`).
type Settings struct {
	Icons map[string]string          `json:"icons"`
	Style map[string]json.RawMessage `json:"style"`
}

func loadSettings() Settings {
	var s Settings
	if raw := os.Getenv("KANTAN_SETTINGS"); raw != "" {
		_ = json.Unmarshal([]byte(raw), &s)
	}
	return s
}

// lookup returns the entry for a layout mode, matched by identifier then name.
func lookup[V any](entries map[string]V, mode, title string) (V, bool) {
	if v, ok := entries[mode]; ok {
		return v, true
	}
	v, ok := entries[title]
	return v, ok
}

// colour is a foreground override for the icon or text alone.
type colour struct {
	Fg string `json:"fg,omitempty"`
}

// style is a dynamic style override in the plugin output format.
type style struct {
	Fg   string  `json:"fg,omitempty"`
	Bg   string  `json:"bg,omitempty"`
	Icon *colour `json:"icon,omitempty"`
	Text *colour `json:"text,omitempty"`
}

// parseStyle reads a style setting: a colour string, which sets `fg`, or an
// object with `fg`, `bg`, `icon.fg` and `text.fg`. Returns nil when it sets
// nothing.
func parseStyle(raw json.RawMessage) *style {
	var fg string
	if json.Unmarshal(raw, &fg) == nil {
		if fg == "" {
			return nil
		}
		return &style{Fg: fg}
	}
	var s style
	if json.Unmarshal(raw, &s) != nil {
		return nil
	}
	if s.Icon != nil && s.Icon.Fg == "" {
		s.Icon = nil
	}
	if s.Text != nil && s.Text.Fg == "" {
		s.Text = nil
	}
	if s == (style{}) {
		return nil
	}
	return &s
}

// workspace is the subset of `rift-cli query workspaces` output the
// indicator uses.
type workspace struct {
	Name       string `json:"name"`
	IsActive   bool   `json:"is_active"`
	LayoutMode string `json:"layout_mode"`
}

// activeWorkspace returns the active workspace from `rift-cli query
// workspaces` output, or nil when none is active.
func activeWorkspace(data []byte) (*workspace, error) {
	var workspaces []workspace
	if err := json.Unmarshal(data, &workspaces); err != nil {
		return nil, err
	}
	for i := range workspaces {
		if workspaces[i].IsActive {
			return &workspaces[i], nil
		}
	}
	return nil, nil
}

// riftCLI returns the rift-cli installed beside the user's running rift, so
// the CLI always matches the running server. Returns "" when Rift isn't
// running.
func riftCLI(ctx context.Context) string {
	out, err := exec.CommandContext(ctx, "/bin/ps", "-axo", "uid=,comm=").Output()
	if err != nil {
		return ""
	}
	return cliAmong(executablesOf(strings.Split(string(out), "\n"), os.Getuid()))
}

// executablesOf returns the executables of uid's processes, from lines of
// `ps -o uid=,comm=` output.
func executablesOf(lines []string, uid int) []string {
	var executables []string
	for _, line := range lines {
		owner, exe, ok := strings.Cut(strings.TrimSpace(line), " ")
		if ok && owner == strconv.Itoa(uid) {
			executables = append(executables, strings.TrimSpace(exe))
		}
	}
	return executables
}

// cliAmong returns the rift-cli beside the first rift among executables,
// given as the full paths `ps -o comm` reports.
func cliAmong(executables []string) string {
	for _, exe := range executables {
		exe = strings.TrimSpace(exe)
		if !filepath.IsAbs(exe) || filepath.Base(exe) != "rift" {
			continue
		}
		cli := filepath.Join(filepath.Dir(exe), "rift-cli")
		if info, err := os.Stat(cli); err == nil && info.Mode().IsRegular() && info.Mode().Perm()&0o111 != 0 {
			return cli
		}
	}
	return ""
}

// queryActiveWorkspace asks the running Rift for the active workspace on
// the active display. Returns nil when Rift isn't running or doesn't answer.
func queryActiveWorkspace(ctx context.Context) *workspace {
	return activeWorkspaceVia(ctx, riftCLI(ctx))
}

// activeWorkspaceVia asks Rift through cli for the active workspace on the
// active display. Returns nil when cli is "" or Rift doesn't answer.
func activeWorkspaceVia(ctx context.Context, cli string) *workspace {
	if cli == "" {
		return nil
	}
	out, err := exec.CommandContext(ctx, cli, "query", "workspaces").Output()
	if err != nil {
		return nil
	}
	ws, _ := activeWorkspace(out)
	return ws
}

// output is the plugin protocol JSON.
type output struct {
	Value     string            `json:"value"`
	Icon      string            `json:"icon,omitempty"`
	Hidden    bool              `json:"hidden,omitempty"`
	Style     *style            `json:"style,omitempty"`
	Variables map[string]string `json:"variables,omitempty"`
}

// render shows the icon and style configured for the active workspace's
// layout, and hides the module when there is no active workspace (Rift
// isn't running). An unrecognised layout mode, or one whose icon is set to
// "", shows the module's own `icon`.
func render(ws *workspace, settings Settings) output {
	if ws == nil {
		return output{Hidden: true}
	}
	title, icon := ws.LayoutMode, ""
	if l, ok := layouts[ws.LayoutMode]; ok {
		title, icon = l.Title, l.Icon
	}
	if v, ok := lookup(settings.Icons, ws.LayoutMode, title); ok {
		icon = v
	}
	var st *style
	if raw, ok := lookup(settings.Style, ws.LayoutMode, title); ok {
		st = parseStyle(raw)
	}
	return output{
		Icon:  icon,
		Style: st,
		Variables: map[string]string{
			"layout":      title,
			"layout_mode": ws.LayoutMode,
			"workspace":   ws.Name,
		},
	}
}

// tetherScript runs its arguments until they exit or its stdin reaches
// EOF, so the command stops once the process holding the other end of
// stdin exits, however it exits.
const tetherScript = `exec 3<&0
"$@" </dev/null 3<&- &
command=$!
{ read -r _ <&3; kill "$command" 2>/dev/null; } &
watcher=$!
trap 'kill "$watcher" 2>/dev/null' EXIT
wait "$command"`

// subscribe runs command, calling onStart once it has launched and onEvent
// for each line it prints, and returns once it exits. The command is killed
// if this process exits first.
func subscribe(command []string, onStart, onEvent func()) error {
	tether, hold, err := os.Pipe()
	if err != nil {
		return err
	}
	defer hold.Close()
	cmd := exec.Command("/bin/sh", append([]string{"-c", tetherScript, "sh"}, command...)...)
	cmd.Stdin = tether
	stdout, err := cmd.StdoutPipe()
	if err != nil {
		tether.Close()
		return err
	}
	err = cmd.Start()
	tether.Close()
	if err != nil {
		return err
	}
	onStart()
	lines := bufio.NewReader(stdout)
	for {
		if _, err := lines.ReadBytes('\n'); err != nil {
			break
		}
		onEvent()
	}
	return cmd.Wait()
}

// restartDelay is the wait before resubscribing after `failures`
// consecutive subscriptions without an event: 1, 2, 4, 8, then 16 seconds.
func restartDelay(failures int) time.Duration {
	return time.Second << min(max(failures-1, 0), 4)
}

// show writes the output for the active workspace, asking Rift through
// cli, as one line.
func show(out io.Writer, cli string, settings Settings) {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	_ = json.NewEncoder(out).Encode(render(activeWorkspaceVia(ctx, cli), settings))
}

// watch prints the module's output for each workspace change Rift reports,
// which includes layout mode changes, and whenever Rift starts or quits;
// kantan shows each line as it arrives. It exits when stdin closes, as
// kantan does when it stops the watch process.
func watch(settings Settings) {
	go func() {
		_, _ = io.Copy(io.Discard, os.Stdin)
		os.Exit(0)
	}()
	failures := 0
	for {
		if cli := riftCLI(context.Background()); cli != "" {
			refresh := func() { show(os.Stdout, cli, settings) }
			_ = subscribe(
				[]string{cli, "subscribe", "mach", "workspace_changed"},
				refresh,
				func() { failures = 0; refresh() })
			refresh()
		}
		failures++
		time.Sleep(restartDelay(failures))
	}
}
