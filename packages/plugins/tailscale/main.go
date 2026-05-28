package main

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"
)

// Settings decoded from KANTAN_SETTINGS env var.
type Settings struct {
	Icons   map[string]string `json:"icons"`
	Dimming *bool             `json:"dimming"`
}

var defaultIcons = map[string]string{
	"connected":    "world",
	"disconnected": "world-off",
}

func (s Settings) iconFor(state string) string {
	if s.Icons != nil {
		if v, ok := s.Icons[state]; ok && v != "" {
			return v
		}
	}
	return defaultIcons[state]
}

func (s Settings) dimming() bool {
	if s.Dimming != nil {
		return *s.Dimming
	}
	return true
}

func loadSettings() Settings {
	var s Settings
	raw := os.Getenv("KANTAN_SETTINGS")
	if raw == "" {
		return s
	}
	_ = json.Unmarshal([]byte(raw), &s)
	return s
}

// localAPIStatus is the subset of the Tailscale LocalAPI /status response
// we need to determine connectivity and the active tailnet name.
type localAPIStatus struct {
	BackendState   string `json:"BackendState"`
	MagicDNSSuffix string `json:"MagicDNSSuffix"`
	CurrentTailnet *struct {
		Name           string `json:"Name"`
		MagicDNSSuffix string `json:"MagicDNSSuffix"`
	} `json:"CurrentTailnet"`
}

// tailscaleClient talks to the Tailscale LocalAPI over either a Unix
// domain socket (tailscaled) or localhost TCP (Tailscale.app).
type tailscaleClient struct {
	httpClient *http.Client
	baseURL    string
	token      string
}

func (c *tailscaleClient) status(ctx context.Context) (*localAPIStatus, error) {
	req, err := http.NewRequestWithContext(ctx, "GET", c.baseURL+"/localapi/v0/status", nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("Sec-Tailscale", "localapi")
	if c.token != "" {
		auth := base64.StdEncoding.EncodeToString([]byte(":" + c.token))
		req.Header.Set("Authorization", "Basic "+auth)
	}
	resp, err := c.httpClient.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, err
	}
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("localapi status %d: %s", resp.StatusCode, body)
	}
	var s localAPIStatus
	if err := json.Unmarshal(body, &s); err != nil {
		return nil, err
	}
	return &s, nil
}

// newUnixClient returns a client that speaks to a tailscaled Unix socket.
func newUnixClient(path string) (*tailscaleClient, error) {
	if _, err := os.Stat(path); err != nil {
		return nil, err
	}
	transport := &http.Transport{
		DialContext: func(ctx context.Context, _, _ string) (net.Conn, error) {
			var d net.Dialer
			return d.DialContext(ctx, "unix", path)
		},
	}
	return &tailscaleClient{
		httpClient: &http.Client{Transport: transport, Timeout: 3 * time.Second},
		baseURL:    "http://local-tailscaled.sock",
	}, nil
}

// newTCPClient returns a client that speaks to the Tailscale.app LocalAPI
// listening on localhost:port, authenticated with the given token.
func newTCPClient(port int, token string) *tailscaleClient {
	return &tailscaleClient{
		httpClient: &http.Client{Timeout: 3 * time.Second},
		baseURL:    fmt.Sprintf("http://127.0.0.1:%d", port),
		token:      token,
	}
}

// parseSameuserproof extracts the port and token from a sameuserproof-*
// filename and (if necessary) the file's contents. The historical layout
// embeds the token in the filename ("sameuserproof-PORT-TOKEN"); newer
// macOS builds may use "sameuserproof-PORT" with the token in the file.
func parseSameuserproof(dir, name string) (int, string, bool) {
	if !strings.HasPrefix(name, "sameuserproof-") {
		return 0, "", false
	}
	rest := strings.TrimPrefix(name, "sameuserproof-")
	if idx := strings.Index(rest, "-"); idx > 0 {
		if port, err := strconv.Atoi(rest[:idx]); err == nil {
			return port, rest[idx+1:], true
		}
	}
	port, err := strconv.Atoi(rest)
	if err != nil {
		return 0, "", false
	}
	data, err := os.ReadFile(filepath.Join(dir, name))
	if err != nil {
		return 0, "", false
	}
	return port, strings.TrimSpace(string(data)), true
}

// findPortToken scans a directory for the first valid sameuserproof-*
// file and returns the parsed port and token.
func findPortToken(dir string) (int, string, error) {
	entries, err := os.ReadDir(dir)
	if err != nil {
		return 0, "", err
	}
	for _, e := range entries {
		if e.IsDir() {
			continue
		}
		if port, token, ok := parseSameuserproof(dir, e.Name()); ok {
			return port, token, nil
		}
	}
	return 0, "", fmt.Errorf("no sameuserproof-* file in %s", dir)
}

// tailscaleAppDirs returns the candidate directories where Tailscale.app
// writes its sameuserproof-* port/token file on macOS. The macsys build
// stores it under a Containers path; the App Store build uses a
// team-id-prefixed Group Container.
func tailscaleAppDirs() []string {
	home, err := os.UserHomeDir()
	if err != nil {
		return nil
	}
	dirs := []string{
		filepath.Join(home, "Library/Containers/io.tailscale.ipn.macsys/Data/IPN"),
	}
	matches, _ := filepath.Glob(filepath.Join(home, "Library/Group Containers/*.io.tailscale.ipn.macos"))
	dirs = append(dirs, matches...)
	return dirs
}

// discoverClient locates a running Tailscale backend in priority order:
// the tailscaled Unix socket (homebrew / open-source daemon), then the
// Tailscale.app port/token files (macsys / App Store).
func discoverClient() (*tailscaleClient, error) {
	if c, err := newUnixClient("/var/run/tailscaled.socket"); err == nil {
		return c, nil
	}
	for _, dir := range tailscaleAppDirs() {
		if port, token, err := findPortToken(dir); err == nil {
			return newTCPClient(port, token), nil
		}
	}
	return nil, fmt.Errorf("no running Tailscale backend found")
}

// state holds the resolved tailnet state for rendering.
type state struct {
	Connected bool
	Tailnet   string
}

// resolveState queries the Tailscale daemon and reduces its response to
// the connected/disconnected indicator plus a display name for the active
// tailnet. Any failure (no daemon, bad response, timeout) is treated as
// disconnected — the user's status bar should never crash because the
// daemon is offline.
func resolveState(ctx context.Context) state {
	c, err := discoverClient()
	if err != nil {
		return state{}
	}
	s, err := c.status(ctx)
	if err != nil {
		return state{}
	}
	if s.BackendState != "Running" {
		return state{}
	}
	name := ""
	if s.CurrentTailnet != nil && s.CurrentTailnet.Name != "" {
		name = s.CurrentTailnet.Name
	} else if s.MagicDNSSuffix != "" {
		name = s.MagicDNSSuffix
	}
	return state{Connected: true, Tailnet: name}
}

// buildOutput renders the plugin protocol JSON for the given state and
// settings, then writes it to stdout.
func buildOutput(st state, settings Settings) {
	var icon, status, tooltip string
	if st.Connected {
		icon = settings.iconFor("connected")
		status = "connected"
		tooltip = st.Tailnet
		if tooltip == "" {
			tooltip = "Connected"
		}
	} else {
		icon = settings.iconFor("disconnected")
		status = "disconnected"
		tooltip = "Disconnected"
	}

	active := true
	if !st.Connected && settings.dimming() {
		active = false
	}

	output := map[string]interface{}{
		"value":  "",
		"icon":   icon,
		"active": active,
		"variables": map[string]string{
			"status":  status,
			"tailnet": st.Tailnet,
			"tooltip": tooltip,
		},
	}

	enc := json.NewEncoder(os.Stdout)
	enc.SetIndent("", "  ")
	_ = enc.Encode(output)
}

func main() {
	settings := loadSettings()
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	buildOutput(resolveState(ctx), settings)
}
