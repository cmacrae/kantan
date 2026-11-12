# CLI Reference

kantan has a minimal command-line interface.

**Usage:**
```
kantan [--config <path>] [--modules-dir <path>] [--fonts-dir <path>] [--themes-dir <path>]
kantan trigger <module-name> <action> [key=value ...]
kantan --help | --version
```

**Flags:**

| Flag | Description |
|------|-------------|
| `--config <path>` | Path to configuration file |
| `--modules-dir <path>` | Path to modules.d directory |
| `--fonts-dir <path>` | Path to the bundled fonts directory |
| `--themes-dir <path>` | Path to the bundled themes directory |
| `-h`, `--help` | Print usage and exit |
| `-V`, `--version` | Print `kantan <version>` and exit |

Each path flag takes the next argument as its path, with a leading `~` expanded, and may appear anywhere on the command line. An unknown `--` flag, or a path flag without its path, is a usage error. Arguments starting with a single `-` are ignored. macOS may pass its own.

A release build reports its release number (`kantan 0.1.0`). Any other build adds the commit it was built from (`kantan 0.1.0-dev+3d0ea26`, with `-dirty` for uncommitted changes).

**Config file resolution (in order):**
1. `--config` flag (explicit path)
2. `./config.yaml` (current working directory)
3. `$XDG_CONFIG_HOME/kantan/config.yaml` (defaults to `~/.config/kantan/config.yaml`)

An explicit `--config` path that doesn't exist is not followed by the other locations. If no config file is found, kantan shows a default welcome bar with a setup hint and checks every 2 seconds for a config file to appear. kantan watches the config file and the modules directory and reloads when either changes. If the config file can't be read or parsed at launch, kantan prints the error to its stdout and shows a bar saying so until the file is fixed.

**Modules directory resolution:**
1. `--modules-dir` flag (explicit path)
2. `modules.d/` sibling to the resolved config file

**Fonts directory resolution:**
1. `--fonts-dir` flag (explicit path)
2. `<prefix>/share/fonts/` relative to the kantan binary

**Bundled themes directory resolution:**
1. `--themes-dir` flag (explicit path)
2. `<prefix>/share/themes/` relative to the kantan binary

Themes in `<config-dir>/themes/` and `$XDG_CONFIG_HOME/kantan/themes/` are found before those in the bundled themes directory. See [Themes](/docs/configuration/themes).

## Trigger command
```
kantan trigger <module-name> <action> [key=value ...]
```

Sends an IPC notification to a running kantan instance via `DistributedNotificationCenter`. Used by watch processes, view commands and external scripts to update modules.

- `<module-name>` — The module's `name:` from config (use `*` to target all modules)
- `<action>` — The action to perform
- `[key=value ...]` — Optional key-value pairs included in the notification payload. An argument without `=`, or with nothing before it, is ignored. Everything after the first `=` is the value. An empty value (`fg=`) clears what it names

Both `<module-name>` and `<action>` are required. With fewer, kantan prints its usage to stderr and exits with code `2`. Arguments starting with `-` are not part of the command.

**Supported actions:**

| Action | Description |
|--------|-------------|
| `refresh` | Re-run the module's data source (a command module's `command`) and update its display |
| `set` | Directly set display properties via key-value pairs: `value=`, `icon=`, `fg=`, `bg=` (hex colours), `duration=` (after N seconds, clear the `fg`/`bg` overrides and refresh the module) |

Any other action does nothing. See [the plugin API reference](/docs/plugins/api-reference#set) for how long `set` overrides last.

**Examples:**
```bash
kantan trigger my-plugin refresh
kantan trigger my-module set value="Hello" icon=bell duration=5
kantan trigger '*' refresh
```

> **Fire-and-forget:** `kantan trigger` posts the notification and returns immediately with exit code 0. It does **not** verify that the named module exists, that a kantan process is running, or that the notification was received. A misspelled module name, a stopped kantan, and a successful delivery all look the same from the caller's perspective. Watch processes should therefore treat triggers as best-effort and avoid retry loops that assume delivery confirmation.

## Exit codes & signals

| Subcommand | Exit code | Meaning |
|------------|-----------|---------|
| `kantan trigger …` | `0` | Notification posted (delivery not guaranteed — see above) |
| `kantan --help`, `kantan --version` | `0` | Usage or version printed to stdout |
| `kantan trigger` without a module and action, an unknown command or `--` flag, or a path flag without its path | `2` | Usage printed to stderr. No bar is started |

**Signals:** kantan installs no signal handlers. SIGTERM and SIGINT end it with the default signal behaviour. When kantan's process ends, its end of each watch process's stdin pipe closes. The watch process then reads EOF. Watch plugins should treat stdin EOF as the shutdown signal. See [Plugins — Handling stdin EOF](/docs/plugins/building-a-plugin#handling-stdin-eof).

**Watch process signalling:** When kantan stops a watch process itself (on sleep, config reload, appearance change, or when no display shows its module), it closes the process's stdin pipe and sends SIGTERM via `Process.terminate()` if the process is still running a second later.

## Environment variables passed to plugins

When kantan invokes a command-module plugin (one-shot, watch, toggle, or a command from one of its views), it sets a small number of environment variables on the child process, on top of kantan's own environment.
[The plugin API reference](/docs/plugins/api-reference#environment-variables) documents them in full. In short:

| Variable | Set when |
|----------|----------|
| `KANTAN_SETTINGS` | The module declares a non-empty `settings:` block. Absent otherwise |
| `KANTAN_APPEARANCE` | Always (`"dark"` or `"light"`) |
| `KANTAN_PID` | Always (kantan's PID, useful for `caffeinate -w $KANTAN_PID` style lifetime ties) |
| `KANTAN_MODULE_NAME` | Always (the module's `name:`) |

The command module's configuration is described by [`docs/schemas/module-config.schema.json`](/docs/reference/schemas).
A plugin should give each variable a default for when it is absent.
