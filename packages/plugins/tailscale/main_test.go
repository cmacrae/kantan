package main

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"testing"
)

// fakeCLI writes an executable script standing in for the Tailscale.app
// CLI: it prints stdout and exits with code.
func fakeCLI(t *testing.T, stdout string, code int) string {
	t.Helper()
	path := filepath.Join(t.TempDir(), "Tailscale")
	script := fmt.Sprintf("#!/bin/sh\ncat <<'EOF'\n%s\nEOF\nexit %d\n", stdout, code)
	if err := os.WriteFile(path, []byte(script), 0o755); err != nil {
		t.Fatalf("write fake CLI: %v", err)
	}
	return path
}

// TestAppCLI_ParsesStatusJSON verifies the bundled CLI's `status --json`
// output is decoded into the LocalAPI status shape.
func TestAppCLI_ParsesStatusJSON(t *testing.T) {
	path := fakeCLI(t, `{"BackendState":"Running","CurrentTailnet":{"Name":"example.ts.net"}}`, 0)
	s, err := appCLI{path: path}.status(context.Background())
	if err != nil {
		t.Fatalf("status: %v", err)
	}
	if s.BackendState != "Running" || s.CurrentTailnet == nil || s.CurrentTailnet.Name != "example.ts.net" {
		t.Errorf("got %+v", s)
	}
}

// stubSource is a statusSource returning a fixed result.
type stubSource struct {
	s   *localAPIStatus
	err error
}

func (s stubSource) status(context.Context) (*localAPIStatus, error) { return s.s, s.err }

// TestQueryStatus_FallsThroughToNextSource verifies that a source that
// fails (e.g. a stale socket) does not hide a working one behind it.
func TestQueryStatus_FallsThroughToNextSource(t *testing.T) {
	want := &localAPIStatus{BackendState: "Running"}
	got, err := queryStatus(context.Background(), []statusSource{
		stubSource{err: errors.New("connection refused")},
		stubSource{s: want},
	})
	if err != nil || got != want {
		t.Fatalf("got %v, %v", got, err)
	}
	if _, err := queryStatus(context.Background(), nil); err == nil {
		t.Error("expected error with no sources")
	}
}

// captureStdout runs fn with os.Stdout temporarily replaced by a pipe and
// returns whatever bytes fn wrote. Used to assert on buildOutput's JSON
// without coupling tests to a particular formatter.
func captureStdout(t *testing.T, fn func()) []byte {
	t.Helper()
	r, w, err := os.Pipe()
	if err != nil {
		t.Fatalf("pipe: %v", err)
	}
	orig := os.Stdout
	os.Stdout = w
	defer func() { os.Stdout = orig }()

	done := make(chan []byte)
	go func() {
		var buf bytes.Buffer
		_, _ = io.Copy(&buf, r)
		done <- buf.Bytes()
	}()
	fn()
	_ = w.Close()
	return <-done
}

// decodeOutput parses the plugin JSON produced by buildOutput so tests
// can inspect individual fields.
func decodeOutput(t *testing.T, raw []byte) map[string]interface{} {
	t.Helper()
	var m map[string]interface{}
	if err := json.Unmarshal(raw, &m); err != nil {
		t.Fatalf("decode output %q: %v", raw, err)
	}
	return m
}

// TestBuildOutput_ConnectedUsesTailnetTooltip checks the connected branch
// emits the tailnet name as the tooltip and stays active.
func TestBuildOutput_ConnectedUsesTailnetTooltip(t *testing.T) {
	raw := captureStdout(t, func() {
		buildOutput(state{Connected: true, Tailnet: "example.ts.net"}, Settings{})
	})
	out := decodeOutput(t, raw)
	if out["icon"] != defaultIcons["connected"] {
		t.Errorf("icon: got %v", out["icon"])
	}
	if out["active"] != true {
		t.Errorf("active: got %v", out["active"])
	}
	vars := out["variables"].(map[string]interface{})
	if vars["status"] != "connected" {
		t.Errorf("status var: got %v", vars["status"])
	}
	if vars["tooltip"] != "example.ts.net" {
		t.Errorf("tooltip var: got %v", vars["tooltip"])
	}
	if vars["tailnet"] != "example.ts.net" {
		t.Errorf("tailnet var: got %v", vars["tailnet"])
	}
}

// TestBuildOutput_DisconnectedDimsByDefault confirms the disconnected
// branch sets active=false (dim) by default and exposes the
// "Disconnected" tooltip with an empty tailnet variable.
func TestBuildOutput_DisconnectedDimsByDefault(t *testing.T) {
	raw := captureStdout(t, func() { buildOutput(state{}, Settings{}) })
	out := decodeOutput(t, raw)
	if out["icon"] != defaultIcons["disconnected"] {
		t.Errorf("icon: got %v", out["icon"])
	}
	if out["active"] != false {
		t.Errorf("active: got %v", out["active"])
	}
	vars := out["variables"].(map[string]interface{})
	if vars["status"] != "disconnected" {
		t.Errorf("status var: got %v", vars["status"])
	}
	if vars["tooltip"] != "Disconnected" {
		t.Errorf("tooltip var: got %v", vars["tooltip"])
	}
	if vars["tailnet"] != "" {
		t.Errorf("tailnet var: got %v", vars["tailnet"])
	}
}

// TestClientStatus_UnixSocket verifies the Unix-socket transport path is
// exercised when talking to a tailscaled-style daemon and that no
// Authorization header is attached (peer credentials authenticate the
// socket connection itself).
func TestClientStatus_UnixSocket(t *testing.T) {
	dir := t.TempDir()
	sockPath := filepath.Join(dir, "tailscaled.socket")
	ln, err := net.Listen("unix", sockPath)
	if err != nil {
		t.Fatalf("listen unix: %v", err)
	}
	defer ln.Close()

	var gotAuth, gotSec string
	srv := &http.Server{
		Handler: http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			gotAuth = r.Header.Get("Authorization")
			gotSec = r.Header.Get("Sec-Tailscale")
			_, _ = io.WriteString(w, `{"BackendState":"Running"}`)
		}),
	}
	go srv.Serve(ln)
	defer srv.Close()

	c, err := newUnixClient(sockPath)
	if err != nil {
		t.Fatalf("newUnixClient: %v", err)
	}
	if _, err := c.status(context.Background()); err != nil {
		t.Fatalf("status: %v", err)
	}
	if gotSec != "localapi" {
		t.Errorf("Sec-Tailscale header: got %q", gotSec)
	}
	if gotAuth != "" {
		t.Errorf("Authorization header should be empty for unix socket, got %q", gotAuth)
	}
}
