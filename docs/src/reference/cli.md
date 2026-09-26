# CLI Reference

kantan has a minimal command-line interface.

**Usage:**
```
kantan [--config <path>] [--modules-dir <path>] [--fonts-dir <path>] [--themes-dir <path>]
kantan trigger <module-name> <action> [key=value ...]
```

**Flags:**

| Flag | Description |
|------|-------------|
| `--config <path>` | Path to configuration file |
| `--modules-dir <path>` | Path to modules.d directory |
| `--fonts-dir <path>` | Path to bundled fonts directory |
| `--themes-dir <path>` | Path to themes directory |

**Config file resolution (in order):**
1. `--config` flag (explicit path)
2. `./config.yaml` (current working directory)
3. `$XDG_CONFIG_HOME/kantan/config.yaml` (defaults to `~/.config/kantan/config.yaml`)

If no config file is found at any of these locations, kantan displays a default welcome bar with a setup hint.

**Modules directory resolution:**
1. `--modules-dir` flag (explicit path)
2. `modules.d/` sibling to the resolved config file

**Fonts directory resolution:**
1. `--fonts-dir` flag (explicit path)
2. `<prefix>/share/fonts/` relative to the kantan binary

**Themes directory resolution:**
1. `--themes-dir` flag (explicit path)
2. `<prefix>/share/themes/` relative to the kantan binary

## Trigger command
```
kantan trigger <module-name> <action> [key=value ...]
```

Sends an IPC notification to a running kantan instance via `DistributedNotificationCenter`. Used by watch processes and external scripts to trigger module updates.

- `<module-name>` — The module's `name:` from config (use `*` to target all modules)
- `<action>` — The action to perform
- `[key=value ...]` — Optional key-value pairs included in the notification payload

**Supported actions:**

| Action | Description |
|--------|-------------|
| `refresh` | Re-run the module's data source and update its display |
| `set` | Directly set display properties via key-value pairs: `value=`, `icon=`, `fg=`, `bg=`, `duration=` (auto-reset after N seconds) |

**Examples:**
```bash
kantan trigger my-plugin refresh
kantan trigger my-module set value="Hello" icon="!" duration=5
```

> **Fire-and-forget:** `kantan trigger` posts the notification and returns immediately with exit code 0. It does **not** verify that the named module exists, that a kantan process is running, or that the notification was received. A misspelled module name, a stopped kantan, and a successful delivery all look the same from the caller's perspective. Watch processes should therefore treat triggers as best-effort and avoid retry loops that assume delivery confirmation.

## Exit codes & signals

| Subcommand | Exit code | Meaning |
|------------|-----------|---------|
| `kantan` (foreground) | `0` | Clean shutdown via `applicationWillTerminate` (e.g. SIGTERM) |
| `kantan` (foreground) | non-zero | Unhandled exception in AppKit; check Console.app for the crash trace |
| `kantan trigger …` | `0` | Notification posted (delivery not guaranteed — see above) |

**Signals:**

- **SIGTERM / SIGINT** — kantan relies on AppKit's default signal handling. The `AppDelegate.applicationWillTerminate(_:)` hook fires before exit, which cancels timers and tears down panels.
- **SIGKILL** — Watch processes are not given a chance to exit cleanly; rely on stdin EOF for graceful shutdown.

**Watch process signalling:** When kantan stops a watch process (on quit, sleep, or module reload), it first closes the stdin pipe (EOF) and gives the process a moment to exit. If the process is still running, kantan sends SIGTERM via `Process.terminate()`. Watch plugins should treat stdin EOF as the canonical shutdown signal and exit promptly so SIGTERM is rarely needed. See [Plugins — Handling stdin EOF](/docs/plugins/building-a-plugin#handling-stdin-eof).

## Environment variables passed to plugins

When kantan invokes a command-module plugin (one-shot, watch, or toggle), it sets a small number of environment variables on the child process.
These are documented in full in [the plugin API reference](/docs/plugins/api-reference#environment-variables); the short version:

| Variable | Set when |
|----------|----------|
| `KANTAN_SETTINGS` | The module declares a `settings:` block; absent otherwise |
| `KANTAN_APPEARANCE` | Always (`"dark"` or `"light"`) |
| `KANTAN_PID` | Always (kantan's PID, useful for `caffeinate -w $KANTAN_PID` style lifetime ties) |
| `KANTAN_MODULE_NAME` | Always (the module's `name:`) |

The formal schema lives in [`docs/schemas/module-config.schema.json`](/docs/reference/schemas).
Plugin authors should always provide sensible defaults when a variable is absent.
