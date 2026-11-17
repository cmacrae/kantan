# Plugin API Reference

Formal specification of the kantan plugin protocol.

## Overview

kantan plugins communicate through a subprocess-based protocol:

1. **Input**: kantan sets environment variables and invokes the plugin executable
2. **Processing**: Plugin reads environment, performs work, constructs output
3. **Output**: Plugin prints JSON to stdout and exits with code 0
4. **Updates**: Watch processes print new output to stdout as it changes, or ask kantan to run the command again with `kantan trigger`

## Input Specification

### Environment Variables

kantan sets these environment variables before invoking the plugin:

| Variable | Type | Set When | Description |
|----------|------|----------|-------------|
| `KANTAN_SETTINGS` | JSON string | Normal invocation, watch, toggle, view commands, when the module has `settings:` | Module's `settings:` configuration from config file |
| `KANTAN_APPEARANCE` | enum string | Normal invocation, watch, toggle, view commands | Current system appearance: `"dark"` or `"light"` |
| `KANTAN_MODULE_NAME` | string | Normal invocation, watch, toggle, view commands | Module's `name:` field from config |
| `KANTAN_PID` | string | Normal invocation, watch, toggle, view commands | kantan's process ID (useful for tying child processes to kantan's lifetime) |

The plugin also inherits kantan's own environment, including its `PATH`. Commands run from the module's views (`action`, `button`, `check`, `toggle`, a clickable `hstack`) get the same variables as its toggle, for the appearance when the view opened. A built-in module's view commands get `KANTAN_MODULE_NAME` alone.

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
Settings values can contain `{theme(...)}` template references (e.g., `{theme(accent)}`). kantan resolves these against the theme palette for the current appearance before passing the JSON to the plugin. A name the palette doesn't define, or any template without a configured theme, is passed through unchanged.

**Empty settings:**
If no `settings:` field is configured, or it is empty, the variable is not set (not present in the environment).

#### KANTAN_APPEARANCE

Current macOS system appearance. Set during normal invocation, watch process launch, and toggle execution.

**Values:**
- `"dark"` — Dark mode enabled
- `"light"` — Light mode enabled

Use this to adapt plugin behavior or output styling to the current appearance.

#### KANTAN_MODULE_NAME

The module's `name:` identifier from the config file. Set during normal invocation, watch process launch, and toggle execution. Useful for:
- IPC triggers (`kantan trigger <module-name> refresh`), including commands the plugin puts in its view for kantan to run later
- Shared state storage (if plugin maintains state)

#### KANTAN_PID

kantan's process ID as a string. Set during normal invocation, watch process launch, and toggle execution. Useful for tying child processes to kantan's lifetime (e.g., `caffeinate -w $KANTAN_PID`).

## Output Specification

### JSON Schema

The plugin must output a single JSON object to stdout with the following schema:

```typescript
{
  value?: string,             // Optional (falls back to raw stdout if missing)
  segments?: Array<{          // Optional
    text: string,
    fg?: string
  }>,
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

kantan ignores fields it doesn't know. A field of the wrong type is treated as absent. Each output replaces the previous one entirely: a field left out is cleared rather than kept.

### Field Definitions

#### value (optional)

**Type:** `string`
**Default:** Raw stdout output
**Description:** Primary text displayed in the status bar. If omitted, or not a string, the entire raw stdout string (the JSON text itself) is used as the display value. Always include it.

**Examples:**
```json
{"value": "42°C"}
{"value": "3 items"}
{"value": "Idle"}
```

**Rendering:** Displayed using the module's configured font and styling, after the icon. An empty value shows the icon alone.

#### segments (optional)

**Type:** `Array<{text: string, fg?: string}>`
**Description:** The value in parts, each in its own colour, drawn in place of `value`. `fg` is a hex colour (`"#89B4FA"` or `"89B4FA"`) or a `{theme(name)}` template. A part without one takes the module's text colour. `value` should still carry the same text. Tooltips and `{value}` templates use it.

**Example:**
```json
{
  "value": "Review in 1h 30m",
  "segments": [
    {"text": "Review", "fg": "#89B4FA"},
    {"text": " in "},
    {"text": "1h 30m", "fg": "{theme(overlay1)}"}
  ]
}
```

**Rendering:** An `fg` override from `kantan trigger <name> set fg=...`, and the native appearance, colour every part alike. `kantan trigger <name> set value=...` shows its value in one colour.

#### icon (optional)

**Type:** `string`  
**Description:** Icon to display before the value: an icon name from the bundled icon font (e.g. `"bell"`, with `-filled` for the filled variant, `"bell-filled"`) or a literal glyph in the module's icon font. Overrides the module's configured `icon:` field.

**Examples:**
```json
{"value": "42°C", "icon": "temperature"}
{"value": "Online", "icon": "wifi"}
```

**Typical use cases:**
- Dynamic icon based on state (battery level, network status)
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

**Styling:** When `active: false`, kantan draws the module's icon at reduced opacity and leaves the text unchanged. It suits toggle buttons and stateful indicators.

#### variables (optional)

**Type:** `object` (key-value pairs, values must be strings)  
**Description:** Template variables for substitution in tooltips, views, and interaction content. If any value isn't a string, kantan ignores the whole object. `{value}` and `{icon}` are always available alongside them.

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
- The bar text is not a template: `value` is shown as given

#### data (optional)

**Type:** `object` containing named arrays of objects  
**Description:** Named datasets for iteration in View DSL `foreach` elements. If any entry isn't an array of objects, kantan ignores the whole `data` object.

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
- Field values are converted to strings. Give them as strings, numbers or bools. A bool becomes `"1"` or `"0"`. Nested arrays and objects don't become usable text

#### style (optional)

**Type:** `object`  
**Description:** Dynamic colour and shape override for the module.

**Fields:**
| Field | Type | Description |
|-------|------|-------------|
| `fg` | string | Foreground colour (applies to both icon and text) |
| `bg` | string | Background colour |
| `icon` | object | Icon-specific overrides: `{"fg": "#RRGGBB"}` |
| `text` | object | Text-specific overrides: `{"fg": "#RRGGBB"}` |
| `shape` | string | The module's background shape in place of its configured one: `pill`, `box`, `underline`, `overline`, or `none` for no shape |

Colours are hex (`#RRGGBB` or `RRGGBB`) or `{theme(name)}` templates, resolved against the theme palette for the current appearance. A template that doesn't resolve is skipped.

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
- Overrides module's configured colours and shape, including under the native appearance
- Is itself overridden by `kantan trigger <name> set fg=… bg=…`
- Applies to status bar display only (not popups/menus)
- Use sparingly for state-driven colour changes (alerts, status indicators)

#### view (optional)

**Type:** `ViewNode` (View DSL tree)  
**Description:** Rich UI definition using kantan's View DSL, shown when the module is clicked with `click.type: menu` or `popup`. While it's open, the menu or popup updates with each new output. A `view:` in the module's `click` config takes precedence. Hover tooltips only show a `view:` from the config. A `view` that fails to decode (an unknown node type, a missing required field, or a field with a value of the wrong kind, such as an unknown `weight`) is dropped whole, and kantan logs where in the view it failed. The rest of the output still applies.

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

A `menu` is a native macOS menu. It shows text, headers, dividers, `action`, `check` and `toggle` rows, and each `hstack` as one row of its text and icons. It skips `button`, shapes, images, `progress`, `gauge` and `badge` elsewhere. A `popup` renders every node. Commands in a view run with `/bin/sh -c`. A URL such as `https://…` is opened instead. kantan doesn't refresh the module afterwards. End a command with `&& kantan trigger <module-name> refresh` when it changes the module's state.

See the [View DSL documentation](../view-dsl/index.md) for complete specification.

## Exit Codes

| Code | Meaning | kantan Behavior |
|------|---------|----------------|
| `0` | Success | Parse JSON output and update module |
| Non-zero | Error | Value is empty; every other output field is cleared |

**Error scenarios:**
- Non-zero exit code: The value is empty and the output's icon, segments, variables, data, style, view, `hidden` and `active` are cleared. The module shows its configured icon alone
- Invalid JSON: The same fields are cleared and the raw stdout is shown as plain text
- Execution timeout: The process is terminated with SIGTERM and treated as a non-zero exit

kantan trims trailing newlines from stdout and discards stderr.

## IPC Protocol

### kantan trigger

Watch processes and external scripts can trigger module updates using the `kantan` CLI:

**Syntax:**
```bash
kantan trigger <module-name> <action> [key=value ...]
```

**Parameters:**
| Parameter | Description |
|-----------|-------------|
| `module-name` | The module's `name:` field from config (or `*` for all modules) |
| `action` | Action to perform: `refresh` (re-invoke command) or `set` (directly update display values). Any other action does nothing |

**Example:**
```bash
kantan trigger weather refresh
```

**Actions:**

#### refresh

Re-invokes the module's command and updates the display with the new output. Built-in modules take it too and re-read their data.

```bash
kantan trigger weather refresh
```

#### set

Directly updates module display values without re-invoking the command. Accepts key=value pairs:

| Key | Description |
|-----|-------------|
| `value=` | Set the display text, in one colour |
| `icon=` | Set the display icon (an icon name or a glyph) |
| `fg=` | Set a foreground colour override for icon and text (hex only) |
| `bg=` | Set a background colour override (hex only) |
| `duration=` | After N seconds, at most 3600, clear the `fg`/`bg` overrides and run the module's command again |

```bash
kantan trigger mymodule set value="Hello" icon=alert-circle fg="#ff0000" duration=5
```

A `value` or `icon` set without `duration` lasts until the module next updates. `fg` and `bg` overrides last until a `set … duration=N` ends. A key with an empty value clears what it names. `fg=` removes the override. `value=` or `icon=` shows none. While a `duration` is pending, kantan ignores the module's refreshes, polls and watch process output.

**Behavior (refresh):**
1. Posts a distributed notification that kantan listens for
2. kantan invokes the module's `command` to retrieve updated output
3. Module display refreshes with new output

**Delivery semantics:** `kantan trigger` posts a distributed notification and returns immediately with no exit-code variation
if the module name is unknown or if no kantan instance is running. Treat it as fire-and-forget — watch processes should not assume
delivery and should not block waiting for kantan to act. See [the CLI reference](../reference/cli.md#trigger-command) for the full semantics.

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

The watch command always runs with `/bin/sh -c`. `launcher:` applies only to `command` and `toggle`. Its stderr is discarded.

### Process Lifecycle

| Event | Behavior |
|-------|----------|
| kantan launch | Watch process started |
| kantan quit | stdin reaches EOF when kantan's end of the pipe closes. The process should exit |
| Config reload | Watch process stopped, and a new one started for the reloaded module |
| System sleep | Watch process stopped |
| System wake | Watch process restarted, with the restart count reset |
| No display shows the module | Watch process stopped, and restarted once a display shows it again |
| Appearance change | Watch process restarted, with the new `KANTAN_APPEARANCE` and settings resolved for it |
| Process exit | Auto-restart with exponential backoff (1s → 16s cap, max 10 consecutive restarts) |
| Max restarts reached | Watch disabled until kantan restarts or the system wakes |

When kantan stops a watch process itself, it closes the process's stdin and sends SIGTERM if the process is still running a second later. A process that exits on EOF has that second to clean up.

**Cardinality:** kantan runs **exactly one watch process per module** at a time, however many displays are configured. Module view-models are shared across all `DisplayInstance`s. The watch process is shared too. Plugin authors do not need to coordinate or deduplicate work across multiple invocations of the same module.

### Watch Process Requirements

The watch process must:

1. **Check for watch invocation**: Distinguish between normal and watch invocation (e.g., via CLI flag)
2. **Read environment variables**: Access `KANTAN_MODULE_NAME`, `KANTAN_SETTINGS`, `KANTAN_APPEARANCE`, `KANTAN_PID`
3. **Monitor stdin**: Watch for EOF on stdin as shutdown signal
4. **Send updates when events occur**: Print the module's new output as a line of JSON (see [Printing Output](#printing-output)), or call `kantan trigger <module-name> refresh` to have kantan run the command again
5. **Exit cleanly on stdin EOF**: Perform cleanup and exit with code 0

### Printing Output

A watch process can send the module's output itself. Each line it prints to stdout that is a JSON object is shown as though the command had printed it, in the [output format](#output-specification). Its fields replace the module's. A line without `value` shows the line itself. This saves kantan launching the command for each update and lets the watch process send state it already holds.

- Print each output as one line and flush stdout after it.
- Lines that aren't JSON objects are ignored. Logging belongs on stderr, which kantan discards.
- Only modules with `output: json` read a watch process's output.
- kantan still runs the command when the module starts, on wake, when the active Space changes, after a `toggle`, and on `kantan trigger <name> refresh`. The command and the watch process should report the same state.
- Printed output is ignored while a `kantan trigger <name> set … duration=N` override shows. kantan runs the command when the override ends.

A watch process may instead print nothing and call `kantan trigger <name> refresh` when something changes.

### Watch Process Example

```swift
import Foundation

func printState() {
    let output: [String: Any] = ["value": getCurrentState()]
    let data = try! JSONSerialization.data(withJSONObject: output)
    print(String(data: data, encoding: .utf8)!)
    fflush(stdout)
}

// Normal invocation: output the current state and exit
guard CommandLine.arguments.contains("--watch") else {
    printState()
    exit(0)
}

// Watch mode: print the state whenever an event changes it
NotificationCenter.default.addObserver(
    forName: .someEventNotification,
    object: nil,
    queue: nil
) { _ in
    printState()
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

When a watch process exits without kantan stopping it (any exit code, including 0):

1. kantan prints the exit to its stdout
2. Waits according to exponential backoff schedule:
   - Attempt 1: 1 second
   - Attempt 2: 2 seconds
   - Attempt 3: 4 seconds
   - Attempt 4: 8 seconds
   - Attempt 5+: 16 seconds (capped)
3. Restarts the watch process
4. After 10 consecutive restarts, gives up until kantan restarts or the system wakes

A watch process that ran for 30 seconds or more before exiting starts the count afresh at attempt 1. Only a process that keeps exiting soon after launch is given up on. A watch process with nothing to watch, such as one without the access it needs, should wait for stdin to close. kantan restarts it each time it exits.

## Command Module Configuration

The `command` module type supports plugins through these config fields:

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `command` | string | required | Shell command to run, looked up on kantan's `PATH`. One starting with `./` or `../` runs from the directory of the file that declares the module |
| `output` | string | `"text"` | Output format: `"json"` for plugin protocol, `"text"` for plain text |
| `interval` | number | `1` | Polling interval in seconds (0 = no polling) |
| `timeout` | number | `10` | Execution timeout in seconds |
| `watch` | string | none | Long-lived watcher process command, run with `/bin/sh -c` |
| `toggle` | string | none | Command to run on click when `click.type` is `toggle` or `complete`; its output is discarded and the module refreshes when it exits |
| `settings` | object | none | Arbitrary settings passed as JSON via `KANTAN_SETTINGS` |
| `launcher` | object | `{path: "/bin/sh", args: ["-c"]}` | Interpreter for `command` and `toggle`: kantan runs `path` with `args` followed by the command string |

Each module keeps its own output. Modules can run the same `command` with different `settings`.

### Interaction with interval and watch

| Configuration | Behavior |
|---------------|----------|
| `interval: 10` (no watch) | Poll every 10 seconds |
| `interval: 0` (no watch) | Never poll; the command runs only on start, wake, Space change, toggle and refresh |
| `watch: ...` + `interval: N` | Run watch process only, no polling (interval is ignored when watch is configured) |
| `watch: ...` + `interval: 0` | Run watch process only, no polling |

When a watch process is configured, polling is disabled whatever the `interval` value. The watch process makes every update, by printing output or running `kantan trigger`.

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
- Plugin commands are looked up on kantan's PATH — ensure PATH is controlled and trusted

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

**kantan logs:** kantan prints watch process exits and restarts to its own stdout. Run `kantan` from a terminal to see them. Plugins' stderr is discarded.

## Examples

See the built-in plugins for reference implementations:

- **`packages/plugins/reminders/`**: Event-driven Swift plugin with watch process, View DSL menus, IPC triggers
- **`packages/plugins/system-monitor/`**: Polling-based Swift plugin with metrics, dynamic styling, formatted output
- **`packages/plugins/caffeine/`**: Shell script plugin with toggle state management and `KANTAN_PID`-tied `caffeinate`
- **`packages/plugins/calendar/`**: Event-driven Swift plugin with watch process, calendar integration, conditional visibility
- **`packages/plugins/pomodoro/`**: Polling-based Go plugin with persistent state, timer management, and interactive actions
- **`packages/plugins/tailscale/`**: Polling-based Go plugin that queries the Tailscale LocalAPI over a Unix socket
- **`packages/plugins/rift-indicator/`**: Event-driven Go plugin whose watch process prints fresh output for each event of a long-lived CLI subscription
