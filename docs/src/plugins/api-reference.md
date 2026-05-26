# Plugin API Reference

Formal specification of the kantan plugin protocol.

## Overview

kantan plugins communicate through a subprocess-based protocol:

1. **Input**: kantan sets environment variables and invokes the plugin executable
2. **Processing**: Plugin reads environment, performs work, constructs output
3. **Output**: Plugin prints JSON to stdout and exits with code 0
4. **IPC**: Watch processes trigger updates via `kantan trigger` command

## Input Specification

### Environment Variables

kantan sets these environment variables before invoking the plugin:

| Variable | Type | Set When | Description |
|----------|------|----------|-------------|
| `KANTAN_SETTINGS` | JSON string | Normal invocation, watch, toggle | Module's `settings:` configuration from config file |
| `KANTAN_APPEARANCE` | enum string | Normal invocation, watch, toggle | Current system appearance: `"dark"` or `"light"` |
| `KANTAN_MODULE_NAME` | string | Watch process only | Module's `name:` field from config |
| `KANTAN_PID` | string | Normal invocation, watch, toggle | kantan's process ID (useful for tying child processes to kantan's lifetime) |

#### KANTAN_SETTINGS

A JSON-serialized string containing the module's `settings:` object from the config file. Set during normal invocation, watch process launch, and toggle execution.

**Example config:**
```yaml
- name: weather
  type: command
  config:
    command: kantan-plugin-weather
    output: json
    settings:
      location: "San Francisco"
      units: "metric"
      refresh: 600
```

**Resulting environment variable:**
```
KANTAN_SETTINGS='{"location":"San Francisco","units":"metric","refresh":600}'
```

**Theme template resolution:**
Settings values can contain `{theme(...)}` template references (e.g., `{theme(accent)}`). kantan resolves these against the active theme palette before passing the JSON to the plugin, allowing theme-aware plugin configuration.

**Empty settings:**
If no `settings:` field is configured, the variable is not set (not present in the environment).

#### KANTAN_APPEARANCE

Current macOS system appearance. Set during normal invocation, watch process launch, and toggle execution.

**Values:**
- `"dark"` — Dark mode enabled
- `"light"` — Light mode enabled

Use this to adapt plugin behavior or output styling to the current appearance.

#### KANTAN_MODULE_NAME

The module's `name:` identifier from the config file. **Only set for watch processes**, not during normal command invocation or toggle execution. Useful for:
- IPC triggers (`kantan trigger <module-name> refresh`)
- Shared state storage (if plugin maintains state)

Since this variable is only available in watch mode, plugins that need the module name during normal invocation should accept it as a setting or hard-code a default.

#### KANTAN_PID

kantan's process ID as a string. Set during normal invocation, watch process launch, and toggle execution. Useful for tying child processes to kantan's lifetime (e.g., `caffeinate -w $KANTAN_PID`).

## Output Specification

### JSON Schema

The plugin must output a single JSON object to stdout with the following schema:

```typescript
{
  value?: string,             // Optional (falls back to raw stdout if missing)
  icon?: string,              // Optional
  hidden?: boolean,           // Optional
  active?: boolean,           // Optional
  variables?: {               // Optional
    [key: string]: string
  },
  data?: {                    // Optional
    [name: string]: Array<{
      [key: string]: any
    }>
  },
  style?: {                   // Optional
    fg?: string,
    bg?: string,
    icon?: { fg?: string },
    text?: { fg?: string }
  },
  view?: ViewNode             // Optional (see View DSL spec)
}
```

### Field Definitions

#### value (optional)

**Type:** `string`
**Default:** Raw stdout output
**Description:** Primary text displayed in the status bar. If omitted, the entire raw stdout string is used as the display value.

**Examples:**
```json
{"value": "42°C"}
{"value": "3 items"}
{"value": "Idle"}
```

**Rendering:** Displayed using the module's configured font and styling. If the module has a configured icon, it appears before this text.

#### icon (optional)

**Type:** `string`  
**Description:** Icon character to display before the value. Overrides the module's configured `icon:` field.

**Examples:**
```json
{"value": "42°C", "icon": "\uf2c9"}
{"value": "Online", "icon": "\uf1eb"}
```

**Typical use cases:**
- Dynamic icon based on state (battery level, network status)
- SF Symbols or custom icon fonts
- Omit the field entirely to fall back to the module's configured `icon:` (an empty string also falls back to the configured icon)

#### hidden (optional)

**Type:** `boolean`  
**Default:** `false`  
**Description:** If `true`, the module is hidden from the status bar.

**Examples:**
```json
{"value": "Idle", "hidden": true}
{"value": "Active", "hidden": false}
```

**Typical use cases:**
- Hide module when no data is available
- Show only when certain conditions are met
- Conditional visibility based on state

#### active (optional)

**Type:** `boolean`
**Default:** `true`
**Description:** Marks the module as "active", affecting its visual styling.

**Examples:**
```json
{"value": "Enabled", "active": true}
{"value": "Disabled", "active": false}
```

**Styling:** When `active: false`, kantan applies the module's inactive style (typically dimmed or muted appearance). Useful for toggle buttons and stateful indicators.

#### variables (optional)

**Type:** `object` (key-value pairs, values must be strings)  
**Description:** Template variables for substitution in tooltips, views, and interaction content.

**Examples:**
```json
{
  "value": "5 items",
  "variables": {
    "total": "5",
    "completed": "3",
    "status": "running"
  }
}
```

**Usage in config:**
```yaml
interaction:
  hover:
    type: tooltip
    content: "{completed} of {total} items — {status}"
```

**Rendering:** kantan replaces `{varname}` placeholders with the corresponding variable values.

**Variable naming:**
- Use lowercase, snake_case or camelCase
- Avoid spaces and special characters
- Values must be strings (convert numbers/bools to strings)

#### data (optional)

**Type:** `object` containing named arrays  
**Description:** Named datasets for iteration in View DSL `foreach` elements.

**Examples:**
```json
{
  "value": "3 items",
  "data": {
    "items": [
      {"name": "Item 1", "id": "1", "status": "done"},
      {"name": "Item 2", "id": "2", "status": "pending"}
    ],
    "categories": [
      {"label": "Work"},
      {"label": "Personal"}
    ]
  }
}
```

**Usage in View DSL:**
```json
{
  "type": "foreach",
  "items": "items",
  "child": {
    "type": "text",
    "content": "{name} ({status})"
  }
}
```

**Data access:**
- Reference arrays by name in `foreach` elements
- Each item's fields become template variables within the loop
- All field values are converted to strings internally (numbers, bools, etc. are stringified via `"\(value)"`)

#### style (optional)

**Type:** `object`  
**Description:** Dynamic colour styling override for the module.

**Fields:**
| Field | Type | Description |
|-------|------|-------------|
| `fg` | string | Foreground color (applies to both icon and text) as hex: `#RRGGBB` |
| `bg` | string | Background color as hex: `#RRGGBB` |
| `icon` | object | Icon-specific overrides: `{"fg": "#RRGGBB"}` |
| `text` | object | Text-specific overrides: `{"fg": "#RRGGBB"}` |

When both `fg` and `icon.fg`/`text.fg` are set, the specific overrides take precedence for their respective elements.

**Examples:**
```json
{
  "value": "Critical",
  "style": {
    "fg": "#ffffff",
    "bg": "#ff0000"
  }
}
```

```json
{
  "value": "Warning",
  "style": {
    "icon": {"fg": "#ffaa00"},
    "text": {"fg": "#000000"}
  }
}
```

**Behavior:**
- Overrides module's configured colors
- Applies to status bar display only (not popups/menus)
- Use sparingly for state-driven colour changes (alerts, status indicators)

#### view (optional)

**Type:** `ViewNode` (View DSL tree)  
**Description:** Rich UI definition for popups, menus, and tooltips using kantan's View DSL.

**Node categories** (full reference in [View DSL nodes](../view-dsl/nodes.md)):

| Category | Nodes |
|----------|-------|
| Layout | `vstack`, `hstack`, `zstack`, `scroll`, `group`, `spacer`, `divider` |
| Content | `text`, `icon`, `image`, `header`, `badge` |
| Shape | `rect`, `circle`, `capsule` |
| Interactive | `action`, `button`, `check`, `toggle` |
| Data | `foreach` (iterate over `data` arrays), `if` (conditional on template var) |
| Advanced | `progress`, `gauge`, `grid` |

The data nodes (`foreach`, `if`) and advanced nodes (`progress`, `gauge`, `grid`) are particularly useful for plugins:

- `foreach` renders its `child` once for each item of a named array from the `data` field
- `if` renders `then` or `else` based on a template-variable condition
- `progress` and `gauge` visualise numeric values driven by template variables
- `grid` lays children out in `columns` (default 2)

**Example:**
```json
{
  "value": "3 tasks",
  "view": {
    "type": "vstack",
    "spacing": 8,
    "children": [
      {
        "type": "text",
        "content": "Tasks",
        "weight": "bold"
      },
      {
        "type": "button",
        "label": "Refresh",
        "command": "kantan trigger tasks refresh"
      }
    ]
  }
}
```

See the [View DSL documentation](../view-dsl/README.md) for complete specification.

## Exit Codes

| Code | Meaning | kantan Behavior |
|------|---------|----------------|
| `0` | Success | Parse JSON output and update module |
| Non-zero | Error | Empty string returned; cached icon/variables/style are cleared |

**Error scenarios:**
- Non-zero exit code: Empty string returned (nothing displayed), cached icon/variables/style are cleared
- Invalid JSON: Cached icon/variables/style are cleared and the raw stdout is shown as plain text
- Execution timeout: Process terminated, treated as non-zero exit (empty string returned)

## IPC Protocol

### kantan trigger

Watch processes and external scripts can trigger module updates using the `kantan` CLI:

**Syntax:**
```bash
kantan trigger <module-name> refresh
```

**Parameters:**
| Parameter | Description |
|-----------|-------------|
| `module-name` | The module's `name:` field from config (or `*` for all modules) |
| `action` | Action to perform: `refresh` (re-invoke command) or `set` (directly update display values) |

**Example:**
```bash
kantan trigger weather refresh
```

**Actions:**

#### refresh

Re-invokes the module's command and updates the display with the new output.

```bash
kantan trigger weather refresh
```

#### set

Directly updates module display values without re-invoking the command. Accepts key=value pairs:

| Key | Description |
|-----|-------------|
| `value=` | Set the display text (empty string clears it) |
| `icon=` | Set the display icon (empty string clears it) |
| `fg=` | Set foreground color override (hex, empty string clears it) |
| `bg=` | Set background color override (hex, empty string clears it) |
| `duration=` | Auto-reset all overrides after N seconds |

```bash
kantan trigger mymodule set value="Hello" icon="\uf06a" fg="#ff0000" duration=5
```

**Behavior (refresh):**
1. Posts a distributed notification that kantan listens for
2. kantan invokes the module's `command` to retrieve updated output
3. Module display refreshes with new output

**Delivery semantics:** `kantan trigger` posts a distributed notification and returns immediately with no exit-code variation
if the module name is unknown or if no kantan instance is running. Treat it as fire-and-forget — watch processes should not assume
delivery and should not block waiting for kantan to act. See [the CLI reference](../reference/cli.md#trigger) for the full semantics.

**Typical use case in watch process:**
```swift
let moduleName = ProcessInfo.processInfo.environment["KANTAN_MODULE_NAME"] ?? ""
let triggerCmd = "kantan trigger '\(moduleName)' refresh"

eventSource.onEvent = {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/bin/sh")
    task.arguments = ["-c", triggerCmd]
    task.standardOutput = FileHandle.nullDevice
    task.standardError = FileHandle.nullDevice
    try? task.run()
    task.waitUntilExit()
}
```

## Watch Mode Protocol

Watch mode enables event-driven plugins through a long-lived background process. Implementing `--watch` is optional: plugins whose state only changes on a timer (e.g. the bundled `pomodoro` plugin) or in response to user actions (e.g. the bundled `caffeine` plugin) need not expose a `--watch` subcommand and should rely on polling or `toggle:` instead.

### Configuration

Enable watch mode by adding a `watch:` field to the module config:

```yaml
- name: my-events
  type: command
  config:
    command: kantan-plugin-my-events
    output: json
    interval: 0
    watch: kantan-plugin-my-events --watch
```

### Process Lifecycle

| Event | Behavior |
|-------|----------|
| kantan launch | Watch process started |
| kantan quit | stdin pipe closed (EOF), process should exit gracefully |
| System sleep | Watch process terminated |
| System wake | Watch process restarted |
| Process crash | Auto-restart with exponential backoff (1s → 16s cap, max 10 consecutive retries) |
| Max retries reached | Watch disabled until kantan restart |

**Cardinality:** kantan runs **exactly one watch process per module** for the lifetime of the kantan process,
regardless of how many displays are configured. Module view-models are shared across all `DisplayInstance`s,
so the watch process is shared too. Plugin authors do not need to coordinate or deduplicate work across multiple invocations of the same module.

### Watch Process Requirements

The watch process must:

1. **Check for watch invocation**: Distinguish between normal and watch invocation (e.g., via CLI flag)
2. **Read environment variables**: Access `KANTAN_MODULE_NAME`, `KANTAN_SETTINGS`, `KANTAN_APPEARANCE`, `KANTAN_PID`
3. **Monitor stdin**: Watch for EOF on stdin as shutdown signal
4. **Trigger updates via IPC**: Call `kantan trigger <module-name> refresh` when events occur
5. **Exit cleanly on stdin EOF**: Perform cleanup and exit with code 0

### Watch Process Example

```swift
import Foundation

// Distinguish between normal and watch invocation
guard CommandLine.arguments.contains("--watch") else {
    // Normal invocation: output current state
    let output: [String: Any] = ["value": getCurrentState()]
    let data = try JSONSerialization.data(withJSONObject: output)
    print(String(data: data, encoding: .utf8)!)
    exit(0)
}

// Watch mode: set up event monitoring
let moduleName = ProcessInfo.processInfo.environment["KANTAN_MODULE_NAME"] ?? ""
let triggerCmd = "kantan trigger '\(moduleName)' refresh"

// Monitor events (notifications, timers, etc.)
NotificationCenter.default.addObserver(
    forName: .someEventNotification,
    object: nil,
    queue: nil
) { _ in
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/bin/sh")
    task.arguments = ["-c", triggerCmd]
    task.standardOutput = FileHandle.nullDevice
    task.standardError = FileHandle.nullDevice
    try? task.run()
    task.waitUntilExit()
}

// Monitor stdin on a background thread — EOF means kantan exited
DispatchQueue.global().async {
    while true {
        let data = FileHandle.standardInput.availableData
        if data.isEmpty {
            exit(0)
        }
    }
}

// Run the main RunLoop to process event notifications
RunLoop.main.run()
```

### Auto-Restart Behavior

When a watch process exits unexpectedly (any exit code, including 0):

1. kantan logs the failure
2. Waits according to exponential backoff schedule:
   - Attempt 1: 1 second
   - Attempt 2: 2 seconds
   - Attempt 3: 4 seconds
   - Attempt 4: 8 seconds
   - Attempt 5+: 16 seconds (capped)
3. Restarts the watch process
4. After 10 consecutive failures, gives up until kantan is restarted

## Command Module Configuration

The `command` module type supports plugins through these config fields:

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `command` | string | required | Executable path or name (must be on PATH) |
| `output` | string | `"text"` | Output format: `"json"` for plugin protocol, `"text"` for plain text |
| `interval` | number | `1` | Polling interval in seconds (0 = event-driven only, no polling) |
| `timeout` | number | `10` | Execution timeout in seconds |
| `watch` | string | none | Long-lived watcher process command |
| `toggle` | string | none | Command to run on click (when `click.type: toggle`) |
| `settings` | object | none | Arbitrary JSON passed via `KANTAN_SETTINGS` |
| `launcher` | object | `{path: "/bin/sh", args: ["-c"]}` | Shell interpreter for command execution (with `path` and `args` sub-fields) |

### Interaction with interval and watch

| Configuration | Behavior |
|---------------|----------|
| `interval: 10` (no watch) | Poll every 10 seconds |
| `interval: 0` (no watch) | Never poll (static module) |
| `watch: ...` + `interval: N` | Run watch process only, no polling (interval is ignored when watch is configured) |
| `watch: ...` + `interval: 0` | Run watch process only, no polling |

**Note:** When a watch process is configured, polling is always disabled regardless of the `interval` value. The watch process is responsible for triggering all updates via `kantan trigger`.

## JSON Schemas

Formal JSON schemas are available in the repository:

- `docs/schemas/plugin-output.schema.json` — Complete plugin output schema (includes View DSL node definitions)
- `docs/schemas/module-config.schema.json` — Module configuration schema

These schemas can be used for validation, IDE autocompletion, and documentation generation.

## Versioning and Compatibility

The plugin protocol is versioned through the kantan release version. 

**Current version:** 0.1.0 (proof of concept)

**Breaking changes** will be noted in release notes. Future versions may add:
- Protocol version negotiation via environment variable
- Backwards compatibility for older plugin versions
- New output fields (always optional for backwards compatibility)

**Stability guarantee:** Core fields (`value`) will not be changed in backwards-incompatible ways within the same major version.

## Security Considerations

- Plugins run as subprocesses with the same privileges as kantan
- `settings:` field can contain arbitrary user-provided data — validate all inputs
- Commands in View DSL execute via shell — sanitize user input carefully
- Watch processes run persistently — ensure clean resource management
- Plugin binaries must be on PATH — ensure PATH is controlled and trusted

## Performance Guidelines

- **Execution time**: Keep normal invocations under 100ms
- **Watch processes**: Minimize memory footprint (< 10MB typical)
- **Polling interval**: Default is 1s. Set higher values (30-60s) for resource-intensive plugins
- **Timeout**: Default is 10s — plugins must complete within this time or be killed
- **JSON size**: Keep output under 1MB (a very large View DSL tree slows rendering)

## Debugging

**Test plugin directly:**
```bash
export KANTAN_SETTINGS='{"key": "value"}'
export KANTAN_APPEARANCE="dark"
# KANTAN_MODULE_NAME is only set for watch processes in production,
# but setting it here is useful for testing trigger commands
export KANTAN_MODULE_NAME="test"

./kantan-plugin-name
```

**Validate JSON output:**
```bash
./kantan-plugin-name | jq .
```

**Watch process testing:**
```bash
echo '{}' | ./kantan-plugin-name --watch
# Watch should exit when stdin closes
```

**kantan logs:** Check Console.app for kantan plugin errors and crashes.

## Examples

See the built-in plugins for reference implementations:

- **`packages/plugins/reminders/`**: Event-driven Swift plugin with watch process, View DSL menus, IPC triggers
- **`packages/plugins/system-monitor/`**: Polling-based Swift plugin with metrics, dynamic styling, formatted output
- **`packages/plugins/caffeine/`**: Shell script plugin with toggle state management and `KANTAN_PID`-tied `caffeinate`
- **`packages/plugins/calendar/`**: Event-driven Swift plugin with watch process, calendar integration, conditional visibility
- **`packages/plugins/pomodoro/`**: Polling-based Go plugin with persistent state, timer management, and interactive actions
