package main

import (
	"encoding/json"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"
	"testing"
	"time"
)

// subscribeHelperEnv makes the test binary run subscribe on the script it
// names instead of the tests, so a test can kill a subscribing process.
const subscribeHelperEnv = "RIFT_INDICATOR_SUBSCRIBE_HELPER"

func TestMain(m *testing.M) {
	if script := os.Getenv(subscribeHelperEnv); script != "" {
		_ = subscribe([]string{script}, func() {}, func() {})
		os.Exit(0)
	}
	os.Exit(m.Run())
}

// writeScript writes an executable shell script and returns its path.
func writeScript(t *testing.T, dir, name, body string) string {
	t.Helper()
	path := filepath.Join(dir, name)
	if err := os.WriteFile(path, []byte("#!/bin/sh\n"+body+"\n"), 0o755); err != nil {
		t.Fatalf("write %s: %v", name, err)
	}
	return path
}

// TestCLIAmong_FindsCLIBesideRunningRift verifies the CLI comes from the
// running rift's own directory.
func TestCLIAmong_FindsCLIBesideRunningRift(t *testing.T) {
	bin := t.TempDir()
	rift := writeScript(t, bin, "rift", "")
	cli := writeScript(t, bin, "rift-cli", "")
	got := cliAmong([]string{"/usr/sbin/cfprefsd", "", rift, "/bin/zsh"})
	if got != cli {
		t.Errorf("got %q, want %q", got, cli)
	}
}

// TestActiveWorkspace_ParsesQueryOutput decodes `rift-cli query
// workspaces` output and picks the active workspace.
func TestActiveWorkspace_ParsesQueryOutput(t *testing.T) {
	data := []byte(`[
	  {"id":"00000011","index":0,"is_active":false,"layout_mode":"traditional","name":"1","window_count":2,"windows":[]},
	  {"id":"00000021","index":1,"is_active":true,"layout_mode":"master_stack","name":"2","window_count":0,"windows":[]}
	]`)
	ws, err := activeWorkspace(data)
	if err != nil {
		t.Fatalf("activeWorkspace: %v", err)
	}
	if ws == nil || ws.Name != "2" || ws.LayoutMode != "master_stack" {
		t.Errorf("got %+v", ws)
	}
}

// TestActiveWorkspace_NoneActive returns no workspace when none is active.
func TestActiveWorkspace_NoneActive(t *testing.T) {
	for _, data := range []string{`[]`, `[{"name":"1","is_active":false,"layout_mode":"bsp"}]`} {
		ws, err := activeWorkspace([]byte(data))
		if err != nil || ws != nil {
			t.Errorf("activeWorkspace(%s) = %+v, %v", data, ws, err)
		}
	}
}

// TestRender_DefaultIconForEachLayout checks every Rift layout mode has a
// default icon and is named as Rift's menu names it.
func TestRender_DefaultIconForEachLayout(t *testing.T) {
	want := map[string][2]string{
		"traditional":  {"layout-columns", "Traditional"},
		"bsp":          {"layout-board-split", "BSP"},
		"floating":     {"picture-in-picture", "Floating"},
		"stack":        {"stack-2", "Stack"},
		"master_stack": {"layout-sidebar-right", "Master Stack"},
		"scrolling":    {"carousel-horizontal", "Scrolling"},
	}
	for mode, w := range want {
		out := render(&workspace{Name: "3", IsActive: true, LayoutMode: mode}, Settings{})
		if out.Hidden || out.Icon != w[0] || out.Style != nil {
			t.Errorf("%s: got %+v", mode, out)
		}
		if out.Variables["layout"] != w[1] || out.Variables["layout_mode"] != mode ||
			out.Variables["workspace"] != "3" {
			t.Errorf("%s: variables %v", mode, out.Variables)
		}
	}
}

// decodeSettings parses a KANTAN_SETTINGS payload.
func decodeSettings(t *testing.T, raw string) Settings {
	t.Helper()
	var s Settings
	if err := json.Unmarshal([]byte(raw), &s); err != nil {
		t.Fatalf("settings: %v", err)
	}
	return s
}

// TestRender_IconSettingsMatchModeOrName verifies icon settings are keyed
// by layout mode identifier or by name, preferring the identifier.
func TestRender_IconSettingsMatchModeOrName(t *testing.T) {
	settings := decodeSettings(t, `{"icons":{
	  "master_stack":"layout-sidebar",
	  "Master Stack":"ignored",
	  "BSP":"layout-grid",
	  "floating":""
	}}`)
	cases := map[string]string{
		"master_stack": "layout-sidebar",
		"bsp":          "layout-grid",
		"floating":     "",
		"stack":        "stack-2",
	}
	for mode, icon := range cases {
		if got := render(&workspace{IsActive: true, LayoutMode: mode}, settings).Icon; got != icon {
			t.Errorf("%s: icon %q, want %q", mode, got, icon)
		}
	}
}

// TestRender_StyleSettings covers the shorthand and expanded style forms
// and their plugin output encoding.
func TestRender_StyleSettings(t *testing.T) {
	settings := decodeSettings(t, `{"style":{
	  "bsp":"#89b4fa",
	  "Scrolling":{"icon":{"fg":"#fab387"},"bg":"#313244"},
	  "stack":{"icon":{}},
	  "floating":42
	}}`)
	cases := map[string]string{
		"bsp":         `{"fg":"#89b4fa"}`,
		"scrolling":   `{"bg":"#313244","icon":{"fg":"#fab387"}}`,
		"stack":       `null`,
		"floating":    `null`,
		"traditional": `null`,
	}
	for mode, want := range cases {
		st := render(&workspace{IsActive: true, LayoutMode: mode}, settings).Style
		got, _ := json.Marshal(st)
		if string(got) != want {
			t.Errorf("%s: style %s, want %s", mode, got, want)
		}
	}
}

// TestRender_HiddenWithoutRift hides the module while Rift isn't running.
func TestRender_HiddenWithoutRift(t *testing.T) {
	encoded, _ := json.Marshal(render(nil, Settings{}))
	if string(encoded) != `{"value":"","hidden":true}` {
		t.Errorf("got %s", encoded)
	}
}

// TestSubscribe_ReportsStartAndEachLine calls onStart once, onEvent per
// printed line, and returns when the command exits.
func TestSubscribe_ReportsStartAndEachLine(t *testing.T) {
	script := writeScript(t, t.TempDir(), "events", `printf '{"type":"workspace_changed"}\n{"type":"workspace_changed"}\n'`)
	starts, events := 0, 0
	done := make(chan error, 1)
	go func() {
		done <- subscribe([]string{script}, func() { starts++ }, func() { events++ })
	}()
	select {
	case err := <-done:
		if err != nil {
			t.Fatalf("subscribe: %v", err)
		}
	case <-time.After(5 * time.Second):
		t.Fatal("subscribe did not return after the command exited")
	}
	if starts != 1 || events != 2 {
		t.Errorf("starts=%d events=%d", starts, events)
	}
}

// TestSubscribe_KillsCommandWhenProcessDies SIGKILLs a subscribing process
// and checks its command doesn't outlive it.
func TestSubscribe_KillsCommandWhenProcessDies(t *testing.T) {
	dir := t.TempDir()
	pidFile := filepath.Join(dir, "pid")
	script := writeScript(t, dir, "long-running", "echo $$ > "+pidFile+".tmp && mv "+pidFile+".tmp "+pidFile+"\nexec sleep 60")

	helper := exec.Command(os.Args[0], "-test.run=^$")
	helper.Env = append(os.Environ(), subscribeHelperEnv+"="+script)
	if err := helper.Start(); err != nil {
		t.Fatalf("start helper: %v", err)
	}
	defer helper.Process.Kill()

	var pid int
	for deadline := time.Now().Add(5 * time.Second); pid == 0; {
		if data, err := os.ReadFile(pidFile); err == nil {
			pid, _ = strconv.Atoi(strings.TrimSpace(string(data)))
		}
		if time.Now().After(deadline) {
			t.Fatal("command never started")
		}
		time.Sleep(20 * time.Millisecond)
	}

	if err := helper.Process.Kill(); err != nil {
		t.Fatalf("kill helper: %v", err)
	}
	_ = helper.Wait()

	for deadline := time.Now().Add(5 * time.Second); syscall.Kill(pid, 0) == nil; {
		if time.Now().After(deadline) {
			syscall.Kill(pid, syscall.SIGKILL)
			t.Fatal("command outlived the subscribing process")
		}
		time.Sleep(20 * time.Millisecond)
	}
}

// TestRestartDelay doubles from one second and caps at sixteen.
func TestRestartDelay(t *testing.T) {
	want := []time.Duration{1, 1, 2, 4, 8, 16, 16}
	for failures, w := range want {
		if got := restartDelay(failures); got != w*time.Second {
			t.Errorf("restartDelay(%d) = %v, want %v", failures, got, w*time.Second)
		}
	}
}
