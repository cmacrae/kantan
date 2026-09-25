package main

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
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

// statusSource reports the status of a Tailscale backend.
type statusSource interface {
	status(ctx context.Context) (*localAPIStatus, error)
}

// tailscaleClient talks to the tailscaled LocalAPI over its Unix socket.
type tailscaleClient struct {
	httpClient *http.Client
	baseURL    string
}

func (c *tailscaleClient) status(ctx context.Context) (*localAPIStatus, error) {
	req, err := http.NewRequestWithContext(ctx, "GET", c.baseURL+"/localapi/v0/status", nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("Sec-Tailscale", "localapi")
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

// appCLI runs the CLI bundled with Tailscale.app. The app keeps its
// LocalAPI port and token in its own container, which macOS lets only
// Tailscale's signed binaries read, so its CLI is the permission-free way
// to reach the backend.
type appCLI struct {
	path string
}

func (c appCLI) status(ctx context.Context) (*localAPIStatus, error) {
	out, err := exec.CommandContext(ctx, c.path, "status", "--json").Output()
	if err != nil {
		return nil, err
	}
	var s localAPIStatus
	if err := json.Unmarshal(out, &s); err != nil {
		return nil, err
	}
	return &s, nil
}

// tailscaleAppCLIPaths returns where the CLI bundled with Tailscale.app
// (App Store or standalone build) may be installed.
func tailscaleAppCLIPaths() []string {
	const cli = "Tailscale.app/Contents/MacOS/Tailscale"
	paths := []string{filepath.Join("/Applications", cli)}
	if home, err := os.UserHomeDir(); err == nil {
		paths = append(paths, filepath.Join(home, "Applications", cli))
	}
	return paths
}

// statusSources lists the installed Tailscale backends in priority order:
// the tailscaled Unix socket (homebrew / open-source daemon), then the
// Tailscale.app CLI.
func statusSources(socketPath string, cliPaths []string) []statusSource {
	var sources []statusSource
	if c, err := newUnixClient(socketPath); err == nil {
		sources = append(sources, c)
	}
	for _, p := range cliPaths {
		if _, err := os.Stat(p); err == nil {
			sources = append(sources, appCLI{path: p})
		}
	}
	return sources
}

// queryStatus returns the status from the first source that answers.
func queryStatus(ctx context.Context, sources []statusSource) (*localAPIStatus, error) {
	for _, source := range sources {
		if s, err := source.status(ctx); err == nil {
			return s, nil
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
	sources := statusSources("/var/run/tailscaled.socket", tailscaleAppCLIPaths())
	s, err := queryStatus(ctx, sources)
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
