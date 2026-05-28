package main

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"io"
	"net"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// TestParseSameuserproof_TokenInFilename covers the legacy filename
// layout where the token is the third dash-separated field.
func TestParseSameuserproof_TokenInFilename(t *testing.T) {
	dir := t.TempDir()
	port, token, ok := parseSameuserproof(dir, "sameuserproof-12345-deadbeefcafe")
	if !ok {
		t.Fatalf("expected to parse sameuserproof-12345-deadbeefcafe, got ok=false")
	}
	if port != 12345 {
		t.Fatalf("expected port=12345, got %d", port)
	}
	if token != "deadbeefcafe" {
		t.Fatalf("expected token=deadbeefcafe, got %q", token)
	}
}

// TestParseSameuserproof_TokenInFile covers the newer layout where the
// filename is just sameuserproof-PORT and the token lives in the file
// body. A trailing newline must be tolerated since that is how
// Tailscale.app writes the file.
func TestParseSameuserproof_TokenInFile(t *testing.T) {
	dir := t.TempDir()
	name := "sameuserproof-54321"
	body := "abcdef0123\n"
	if err := os.WriteFile(filepath.Join(dir, name), []byte(body), 0o600); err != nil {
		t.Fatalf("write fixture: %v", err)
	}
	port, token, ok := parseSameuserproof(dir, name)
	if !ok {
		t.Fatalf("expected to parse %s, got ok=false", name)
	}
	if port != 54321 {
		t.Fatalf("expected port=54321, got %d", port)
	}
	if token != "abcdef0123" {
		t.Fatalf("expected token=abcdef0123, got %q", token)
	}
}

// TestParseSameuserproof_Rejects ensures we don't accept arbitrary files
// living next to the real port/token marker.
func TestParseSameuserproof_Rejects(t *testing.T) {
	dir := t.TempDir()
	cases := []string{
		"notsameuserproof",
		"sameuserproof-",
		"sameuserproof-notaport",
		"sameuserproof-notaport-token",
	}
	for _, name := range cases {
		if _, _, ok := parseSameuserproof(dir, name); ok {
			t.Errorf("expected reject for %q, got ok=true", name)
		}
	}
}

// TestFindPortToken_PrefersFirstValid verifies that findPortToken returns
// the first parseable sameuserproof file and skips siblings.
func TestFindPortToken_PrefersFirstValid(t *testing.T) {
	dir := t.TempDir()
	for _, f := range []string{"unrelated", "sameuserproof-bogus"} {
		if err := os.WriteFile(filepath.Join(dir, f), nil, 0o600); err != nil {
			t.Fatalf("write fixture: %v", err)
		}
	}
	if err := os.WriteFile(filepath.Join(dir, "sameuserproof-7777-tok"), nil, 0o600); err != nil {
		t.Fatalf("write fixture: %v", err)
	}
	port, token, err := findPortToken(dir)
	if err != nil {
		t.Fatalf("findPortToken: %v", err)
	}
	if port != 7777 || token != "tok" {
		t.Fatalf("got port=%d token=%q", port, token)
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

// TestClientStatus_AuthAndHeader uses an in-process HTTP server to verify
// the LocalAPI request shape: the Sec-Tailscale header is sent, and the
// token (when present) is encoded as HTTP Basic auth with an empty user.
func TestClientStatus_AuthAndHeader(t *testing.T) {
	var gotAuth, gotSec string
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		gotAuth = r.Header.Get("Authorization")
		gotSec = r.Header.Get("Sec-Tailscale")
		_, _ = io.WriteString(w, `{"BackendState":"Running","MagicDNSSuffix":"alpha.ts.net"}`)
	}))
	defer srv.Close()

	c := newTCPClient(0, "secrettoken")
	// httptest binds to a random localhost port; reuse its URL so we
	// don't have to thread the assigned port through newTCPClient.
	c.baseURL = srv.URL

	s, err := c.status(context.Background())
	if err != nil {
		t.Fatalf("status: %v", err)
	}
	if s.BackendState != "Running" {
		t.Errorf("BackendState: got %q", s.BackendState)
	}
	if gotSec != "localapi" {
		t.Errorf("Sec-Tailscale header: got %q", gotSec)
	}
	if !strings.HasPrefix(gotAuth, "Basic ") {
		t.Fatalf("Authorization header: got %q", gotAuth)
	}
	// The Basic auth value should be base64(":secrettoken"), i.e. an
	// empty username with the token as the password.
	want := "Basic " + base64.StdEncoding.EncodeToString([]byte(":secrettoken"))
	if gotAuth != want {
		t.Errorf("Authorization: got %q, want %q", gotAuth, want)
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
