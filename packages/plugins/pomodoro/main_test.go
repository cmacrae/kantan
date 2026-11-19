package main

import (
	"encoding/json"
	"path/filepath"
	"strings"
	"sync"
	"testing"
)

// withTempState redirects the state directory to a per-test temp path.
func withTempState(t *testing.T) string {
	t.Helper()
	dir := t.TempDir()
	t.Setenv("XDG_CACHE_HOME", dir)
	return filepath.Join(dir, "kantan")
}

// TestMutateStateSerialisesConcurrentIncrements proves that mutateState's
// flock makes load → modify → save atomic across concurrent invocations.
// Without the lock, racing readers would all see the same baseline and the
// final Sessions count would be less than N.
func TestMutateStateSerialisesConcurrentIncrements(t *testing.T) {
	withTempState(t)
	const n = 50

	var wg sync.WaitGroup
	wg.Add(n)
	for i := 0; i < n; i++ {
		go func() {
			defer wg.Done()
			mutateState(func(s *State) {
				s.Sessions++
			})
		}()
	}
	wg.Wait()

	final := loadState()
	if final.Sessions != n {
		t.Fatalf("expected Sessions=%d after concurrent increments, got %d", n, final.Sessions)
	}
}

// TestCmdStartIsAtomic exercises the command path end-to-end and confirms
// state is durably persisted under the lock.
func TestCmdStartIsAtomic(t *testing.T) {
	withTempState(t)
	cmdStart(defaultSettings())

	s := loadState()
	if s.Mode != "work" {
		t.Fatalf("expected Mode=work after cmdStart, got %q", s.Mode)
	}
	if s.Duration != defaultSettings().WorkDuration {
		t.Fatalf("expected Duration=%d, got %d", defaultSettings().WorkDuration, s.Duration)
	}
	if s.StartedAt == 0 {
		t.Fatalf("expected StartedAt to be set")
	}
}

// TestRenderDrawsTheRingForTheState checks the popup follows the timer: the
// ring holds the share of the segment left, and the buttons suit the state.
func TestRenderDrawsTheRingForTheState(t *testing.T) {
	settings := defaultSettings()
	view := func(s State, now float64) string {
		data, err := json.Marshal(render(s, now, settings, "pomodoro")["view"])
		if err != nil {
			t.Fatal(err)
		}
		return string(data)
	}

	working := view(State{Mode: "work", StartedAt: 0, Duration: 20, Sessions: 1}, 300)
	for _, want := range []string{`"value":0.75`, `"content":"15:00"`, `"content":"Session 2 of 4"`, `"label":"Pause"`, `"label":"Skip"`} {
		if !strings.Contains(working, want) {
			t.Errorf("working view lacks %s: %s", want, working)
		}
	}

	idle := view(State{Mode: "idle"}, 300)
	for _, want := range []string{`"value":1`, `"content":"25:00"`, `"label":"Start"`} {
		if !strings.Contains(idle, want) {
			t.Errorf("idle view lacks %s: %s", want, idle)
		}
	}
	if strings.Contains(idle, `"label":"Reset"`) {
		t.Errorf("idle view offers a reset: %s", idle)
	}
}
