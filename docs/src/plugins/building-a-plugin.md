# Building a Plugin

This guide builds a kantan plugin from scratch, from a minimal example to an event-driven watch process.

## Prerequisites

A kantan plugin is any executable that:
1. Reads configuration from environment variables
2. Outputs JSON to stdout
3. Exits with code 0 on success

It needs no dependencies, libraries or frameworks.

## Step 1: Create the Executable

### Minimal Shell Example

```bash
#!/bin/bash
echo '{"value": "Hello from my plugin"}'
```

Save as `kantan-plugin-hello`, make executable, and place on PATH:
```bash
chmod +x kantan-plugin-hello
```

### Minimal Swift Example

```swift
import Foundation

let output: [String: Any] = ["value": "Hello from my plugin"]
let data = try JSONSerialization.data(withJSONObject: output)
print(String(data: data, encoding: .utf8)!)
```

### Minimal Go Example

```go
package main

import (
    "encoding/json"
    "os"
)

func main() {
    output := map[string]interface{}{"value": "Hello from my plugin"}
    enc := json.NewEncoder(os.Stdout)
    _ = enc.Encode(output)
}
```

`encoding/json`'s `Encoder.Encode` writes a trailing newline and does not require an explicit flush for a one-shot plugin.
See [Common Pitfalls](#common-pitfalls) for watch-mode flushing rules.

### Reading Configuration

Read the environment variables kantan sets. Not every variable is set on every invocation: see
[Step 2: Environment Variables](#step-2-environment-variables) for when each one is. `KANTAN_SETTINGS` is only present when your module
declares `settings:`. The defaults below handle its absence.

```swift
import Foundation

let settings = ProcessInfo.processInfo.environment["KANTAN_SETTINGS"] ?? "{}"
let appearance = ProcessInfo.processInfo.environment["KANTAN_APPEARANCE"] ?? "light"
let moduleName = ProcessInfo.processInfo.environment["KANTAN_MODULE_NAME"] ?? ""

// Parse settings JSON
let settingsData = settings.data(using: .utf8)!
let config = try JSONSerialization.jsonObject(with: settingsData) as? [String: Any] ?? [:]

// Access custom settings
let myOption = config["myOption"] as? String ?? "default"

let output: [String: Any] = [
    "value": "Option: \(myOption)",
    "variables": ["appearance": appearance]
]
let data = try JSONSerialization.data(withJSONObject: output)
print(String(data: data, encoding: .utf8)!)
```

## Step 2: Environment Variables

kantan sets these environment variables before invoking your plugin. Not every variable is set on every invocation. Read the *Set When* column and give each variable a default in your plugin code:

| Variable | Type | Set When | Description | Example |
|----------|------|----------|-------------|---------|
| `KANTAN_SETTINGS` | JSON string | Only when the module declares `settings:` (covers normal invocation, watch, and toggle) | Module's `settings:` config | `{"refresh": 10, "units": "metric"}` |
| `KANTAN_APPEARANCE` | string | Normal invocation, watch, toggle | Current appearance | `"dark"` or `"light"` |
| `KANTAN_MODULE_NAME` | string | Normal invocation, watch, toggle | Module identifier | `"my-plugin"` |
| `KANTAN_PID` | string | Normal invocation, watch, toggle | kantan's process ID | `"12345"` |

The plugin also inherits kantan's own environment, including its `PATH`. The kantan flake package puts its bundled plugins on that `PATH`.

A plugin run from the shell without these variables should still produce reasonable output. It can then be tested by hand (`./kantan-plugin-foo`). Use `?? "{}"` / `?? ""` style defaults.

The `KANTAN_SETTINGS` variable contains the arbitrary JSON object you define in your module's config:

```yaml
- name: weather
  type: command
  config:
    command: kantan-plugin-weather
    output: json
    settings:
      location: "San Francisco"
      units: "fahrenheit"
```

These settings become: `{"location": "San Francisco", "units": "fahrenheit"}`

## Step 3: JSON Output Format

Your plugin must print a single JSON object to stdout. kantan parses this to determine what to display.

### Complete Schema

```json
{
  "value": "Display text",
  "segments": [
    { "text": "Display", "fg": "#89b4fa" },
    { "text": " text" }
  ],
  "icon": "list-check",
  "hidden": false,
  "active": true,
  "variables": {
    "count": "5",
    "status": "running"
  },
  "data": {
    "items": [
      { "name": "Item 1", "id": "1" },
      { "name": "Item 2", "id": "2" }
    ]
  },
  "style": {
    "fg": "#ff0000",
    "bg": "#000000"
  },
  "view": {
    "type": "vstack",
    "children": [...]
  }
}
```

kantan ignores fields it doesn't know.

### Field Reference

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `value` | string | no | Text displayed in the status bar. If omitted, the whole of stdout (the JSON text itself) is shown. Always include it |
| `segments` | array | no | The value in parts, each `{"text", "fg"}` drawn in its own colour in place of `value` |
| `icon` | string | no | Icon override: an icon name (`bell`, `bell-filled`) or a literal glyph. Empty or omitted uses the module's configured `icon:` |
| `hidden` | bool | no | If `true`, hides the module from the bar |
| `active` | bool | no | Active state, defaults to `true` (when `false`, the module's icon is dimmed) |
| `variables` | object | no | String key-value pairs for `{var}` template substitution in tooltips and views. A non-string value makes kantan ignore the whole object |
| `data` | object | no | Named arrays of objects accessible via `foreach` in View DSL |
| `style` | object | no | Dynamic colour override with `fg`, `bg`, `icon.fg`, and `text.fg`: hex colours or `{theme(name)}` templates |
| `view` | object | no | View DSL tree shown by the module's click `menu` or `popup` |

Each output replaces the last one entirely: a field left out is cleared, not kept from the previous output.

### Common Patterns

**Simple text output:**
```json
{"value": "42°C"}
```

**Text with icon:**
```json
{"value": "42°C", "icon": "temperature"}
```

**Hidden when inactive:**
```json
{"value": "Idle", "hidden": true}
```

**Toggle state:**
```json
{"value": "Enabled", "active": true}
```

**Coloured parts:**
```json
{
  "value": "Review in 1h 30m",
  "segments": [
    {"text": "Review", "fg": "{theme(blue)}"},
    {"text": " in 1h 30m"}
  ]
}
```

`value` should carry the same text as the segments. Tooltips and `{value}` templates use it.

**Template variables:**
```json
{
  "value": "5 items",
  "variables": {
    "total": "5",
    "completed": "3"
  }
}
```

In your config, reference these with `{total}` and `{completed}` in tooltip/view text.

**Dynamic styling:**
```json
{
  "value": "Critical",
  "style": {
    "fg": "#ffffff",
    "bg": "#ff0000"
  }
}
```

## Step 4: Configure the Module

Add a module to your kantan config that invokes your plugin:

```yaml
modules:
  - name: my-plugin
    type: command
    placement: right
    icon: "star"
    config:
      command: kantan-plugin-my-plugin
      output: json
      interval: 10
      settings:
        myOption: "value"
    interaction:
      hover:
        type: tooltip
        content: "{count} items — {status}"
```

### Command Module Config Fields

| Key | Type | Description |
|-----|------|-------------|
| `command` | string | Shell command to run (required). One starting with `./` or `../` runs from the directory of the file that declares the module |
| `output` | string | `"json"` for plugin protocol, `"text"` (default) for plain text |
| `interval` | number | Polling interval in seconds (default: 1, 0 = no polling) |
| `timeout` | number | Execution timeout in seconds (default: 10) |
| `watch` | string | Long-lived watcher process command (for event-driven updates), run with `/bin/sh -c` |
| `toggle` | string | Command to run on click when `click.type` is `toggle` or `complete`. The module refreshes when it exits |
| `settings` | object | Arbitrary settings passed as JSON via `KANTAN_SETTINGS` |
| `launcher` | object | Interpreter for `command` and `toggle`, with `path` and `args` sub-fields (default: `{path: "/bin/sh", args: ["-c"]}`) |

### Interaction Configuration

Plugins can define rich interactions via the module config:

```yaml
interaction:
  click:
    type: menu
    view:
      type: vstack
      children:
        - type: text
          content: "Count: {count}"
        - type: action
          label: "Refresh"
          command: "kantan trigger my-plugin refresh"
  hover:
    type: tooltip
    content: "Status: {status}"
```

A `view:` in the module config takes precedence over the plugin's `view` output. Leave it out of `click` to show the plugin's view instead; a hover tooltip only shows a `view:` from the config. Commands in views run with `/bin/sh -c` without the `KANTAN_*` variables, and kantan doesn't refresh the module after them, so end them with `kantan trigger <module-name> refresh` when they change its state.

## Step 5: Watch Mode (Event-Driven Plugins)

For plugins that respond to external events rather than polling on an interval, use watch mode. Watch mode is optional. Plugins whose state only changes on a timer or user action can skip it. Among the bundled plugins, `reminders`, `calendar` and `rift-indicator` use watch mode to react to EventKit changes and Rift's events. `pomodoro`, `caffeine`, `system-monitor` and `tailscale` only poll.

### Configuration

```yaml
- name: my-events
  type: command
  config:
    command: kantan-plugin-my-events
    output: json
    interval: 0
    watch: kantan-plugin-my-events --watch
```

Key points:
- `watch:` specifies the long-lived background process
- When `watch` is configured, polling is disabled whatever `interval` says. Setting `interval: 0` is conventional, not required
- The main `command` still runs when the module starts, on wake, when the active Space changes, after a `toggle`, and when a refresh is triggered
- The watch command runs with `/bin/sh -c`, whatever `launcher:` says

### Watch Process Requirements

The watch process:

1. **Runs as a background daemon**: Started when kantan launches or reloads its config, stopped when kantan quits or reloads
2. **Receives environment variables**: `KANTAN_MODULE_NAME`, `KANTAN_SETTINGS`, `KANTAN_APPEARANCE`, `KANTAN_PID`
3. **Receives stdin pipe**: EOF signals kantan is shutting down (clean exit expected — see [Handling stdin EOF](#handling-stdin-eof))
4. **Sends updates**: Prints the module's new output as a line of JSON when events occur (read only with `output: json`), or calls `kantan trigger <module-name> refresh` for kantan to run the command again (see [Printing Output](/docs/plugins/api-reference#printing-output))
5. **Auto-restarts on exit**: Exponential backoff (1s → 16s cap). kantan gives up after 10 restarts of a process that keeps exiting within 30 seconds of launch. A watch process with nothing to watch should wait for stdin to close instead of exiting
6. **Lifecycle integration**: Stopped on system sleep and while no display shows the module, restarted on wake, and restarted with the new appearance when it changes
7. **One process per module**: kantan launches exactly one watch process per module, no matter how many displays are configured. Module view-models are shared across `DisplayInstance`s. Plugin authors do not need to deduplicate work or coordinate across multiple invocations.

### Handling stdin EOF

A watch process must monitor stdin and exit cleanly when it closes. That is how kantan signals shutdown. A plugin that ignores it leaks watch processes when kantan crashes, restarts or is killed.

**Swift:**

```swift
// Run on a background thread; availableData blocks until bytes arrive
// or stdin reaches EOF (returns empty Data).
DispatchQueue.global().async {
  while true {
    let data = FileHandle.standardInput.availableData
    if data.isEmpty { exit(0) }
  }
}
```

**Go:**

```go
go func() {
  buf := make([]byte, 1)
  for {
    if _, err := os.Stdin.Read(buf); err != nil {
      os.Exit(0)
    }
  }
}()
```

**Shell:**

```bash
# A background job's stdin is /dev/null, so hand it kantan's pipe as fd 3.
# `read` returns non-zero on EOF; the loop discards any input until then.
exec 3<&0
(while read -r _ <&3; do :; done; kill -TERM $$) &
```

### Watch Process Example

```swift
import Foundation

func printState() {
    let output: [String: Any] = ["value": "..."]
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
// (example: notification observer)
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

### Watch vs Polling

Use watch mode when:
- Events are unpredictable (user actions, system notifications, file changes)
- High-frequency polling would waste resources
- You need immediate updates when events occur

Use polling when:
- Monitoring resources that don't provide event notifications
- Simple periodic checks are sufficient
- Event setup overhead isn't worth it

## Step 6: Package as a Nix Plugin

The kantan flake discovers every directory in `packages/plugins/` (except those starting with `_`) and builds it as `kantan-plugin-<directory name>`. The build helper is picked by the marker file the directory contains, checked in this order:

| Marker | Builder | Build | Tests |
|--------|---------|-------|-------|
| `Package.swift` | `buildSwiftPlugin` | `swift build -c release --product kantan-plugin-<name>` with the system Xcode toolchain | `swift test`, when the package has a `Tests/` directory |
| `go.mod` | `buildGoPlugin` | `go build`, with no module dependencies fetched (`vendorHash = null`): use the standard library or a checked-in `vendor/` | `go test ./...` |
| `main.sh` | `buildShellPlugin` | `main.sh` is installed as the executable. Give it a shebang | none |

Each plugin is a flake package (`kantan.plugins.<name>`) and a flake check (`plugin-<name>`). `nix flake check` builds it and runs its tests. The default `kantan` package joins every plugin into its prefix and puts that prefix's `bin/` on kantan's `PATH`. A plugin directory may also hold:

- `examples/` — module configs, installed to `share/examples/`
- `README.md` — the plugin's documentation, copied into the docs build as `plugins/<name>.md`

A Swift plugin's executable target must be named `kantan-plugin-<name>`, with its sources in `Sources/kantan-plugin-<name>/`:

```
packages/plugins/my-plugin/
├── Package.swift
├── Sources/
│   └── kantan-plugin-my-plugin/
│       └── main.swift
└── Tests/
    └── kantan-plugin-my-pluginTests/
        └── MyPluginTests.swift
```

Example `Package.swift`:

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "kantan-plugin-my-plugin",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "kantan-plugin-my-plugin"
        ),
        .testTarget(
            name: "kantan-plugin-my-pluginTests",
            dependencies: ["kantan-plugin-my-plugin"]
        ),
    ]
)
```

Tests reach the plugin's code with `@testable import kantan_plugin_my_plugin`.

### PluginKit

The build copies `packages/plugins/_shared/swift/PluginKit.swift` into every Swift plugin's target. Its helpers need no import. They exist only in the Nix build, not in a plain `swift build` of the plugin directory.

**Output**

| API | Description |
|-----|-------------|
| `PluginOutput(value:segments:icon:hidden:active:variables:data:view:style:)` | The output object. Only `value` is required. `view` and `style` take a `JSONValue` |
| `ValueSegment(text:fg:)` | A coloured part of the value, for `segments` |
| `printJSON(_ output: PluginOutput, pretty: Bool = false)` | Prints the output as JSON with sorted keys, for a one-shot run |
| `JSONValue` | An encodable JSON value (`.string`, `.int`, `.double`, `.bool`, `.array`, `.object`, `.null`) for view trees and styles |

**View builders**, each returning a `JSONValue` node: `vstack(spacing:padding:frame:children:)`, `hstack(spacing:padding:command:children:)`, `text(_:size:weight:style:color:strikethrough:)`, `header(_:)`, `divider()`, `spacer()`, `icon(_:size:color:)`, `action(label:icon:command:)`, `check(label:checked:command:uncheckedCommand:)`, `foreach(items:child:)`, `conditional(variable:then:)` (an `if` node), `group(children:)`, `badge(content:color:textColor:)` and `rect(width:height:color:cornerRadius:)`. Other nodes and properties can be written as `JSONValue.object`.

**Settings and formatting**

| API | Description |
|-----|-------------|
| `loadSettings(defaults:)` | Decodes `KANTAN_SETTINGS` into a `Decodable` type, returning `defaults` when it is unset or fails to decode |
| `moduleName(fallback:)` | `KANTAN_MODULE_NAME`, or `fallback` when unset |
| `shellQuote(_:)` | Single-quotes a string for a shell command, such as a module name in a view's `command` |
| `parseDuration(_:)` | Parses `"10m"`, `"12h"` or `"2d"` into seconds, or returns nil |
| `applyFormat(_:variables:)` | Replaces `{key}` with its variable, and keeps `{?key:text}` / `{?!key:text}` sections only when the variable is non-empty / empty. A variable that isn't given is empty. A conditional section's text can't contain `}` |
| `Format` | A decodable `format` setting: a template string, or a list of segments `{text, fg?, when?}`. A segment shows only while its `when` variable is non-empty, or empty for `!name`. `apply(_:)` returns the value and, for a list, its segments, leaving out any that come out empty |

**Watch mode**

| API | Description |
|-----|-------------|
| `WatchOutput` | Writes each output as one unbuffered line, skipping one identical to the last |
| `Watch(output:render:)` | Calls `render` and shows its output now, at the start of every minute, and when `changed()` is called, once 0.5 s of changes have settled |
| `Watch.run(on:from:)` | Shows the output, calls `changed()` for each `Notification.Name` from the object, and runs until stdin closes |
| `exitWhenStdinCloses()` | Exits the process when stdin reaches EOF |
| `idleWatch(showing:)` | Shows one output and waits for stdin to close, for a watch process with nothing to watch (such as one without the access it needs) |

A watch mode built on PluginKit, as the `calendar` plugin does it:

```swift
@MainActor
func watchMode() -> Never {
  let settings = loadSettings(defaults: Settings())
  let store = EKEventStore()
  guard ensureAccess(store: store) else {
    idleWatch(showing: noAccessOutput)
  }
  Watch { currentOutput(store: store, settings: settings) }
    .run(on: .EKEventStoreChanged, from: store)
}
```

## Step 7: Use the View DSL

For rich interactive UIs, return a `view` field with a View DSL tree. kantan shows it when the module is clicked, with `click.type: menu` or `popup` and no `view:` of its own in the module config:

```json
{
  "value": "3 items",
  "data": {
    "items": [
      {"name": "Item 1", "status": "done"},
      {"name": "Item 2", "status": "pending"}
    ]
  },
  "view": {
    "type": "vstack",
    "children": [
      {
        "type": "text",
        "content": "My Items",
        "color": "#ffffff",
        "weight": "bold"
      },
      {
        "type": "foreach",
        "items": "items",
        "child": {
          "type": "hstack",
          "children": [
            {"type": "icon", "name": "check"},
            {"type": "text", "content": "{name} - {status}"}
          ]
        }
      }
    ]
  }
}
```

This is a vertical stack with a header and a list of items. A `menu` is a native macOS menu and shows only some node types. A `popup` renders them all. See the [View DSL documentation](/docs/view-dsl) for building views.

## Testing Your Plugin

Test your plugin directly from the command line:

```bash
export KANTAN_SETTINGS='{"myOption": "test"}'
export KANTAN_APPEARANCE="dark"
export KANTAN_MODULE_NAME="my-plugin"

./kantan-plugin-my-plugin | jq .
```

Verify the JSON output is valid and contains the expected fields. kantan discards a plugin's stderr. Use it for debugging output.

## Examples

See the built-in plugins for complete reference implementations:

- `packages/plugins/reminders/` — Event-driven Swift plugin with watch mode, View DSL menus, and command actions
- `packages/plugins/system-monitor/` — Polling Swift plugin with formatted metrics and dynamic styling
- `packages/plugins/caffeine/` — Shell script plugin with toggle state management and `KANTAN_PID`-tied `caffeinate`
- `packages/plugins/calendar/` — Event-driven Swift plugin with watch mode, calendar integration, and conditional visibility
- `packages/plugins/pomodoro/` — Polling Go plugin with persistent state, timer management, and interactive actions
- `packages/plugins/tailscale/` — Polling Go plugin that talks to a local daemon's HTTP API over a Unix socket
- `packages/plugins/rift-indicator/` — Event-driven Go plugin whose watch process prints fresh output for each event of a long-lived CLI subscription

## Error Handling

- **Exit code 0**: Success. kantan parses the JSON output
- **Non-zero exit code**: The value is empty. The output's icon, segments, variables, data, style, view, `hidden` and `active` are cleared. The module shows its configured icon alone
- **Invalid JSON**: The same fields are cleared and the raw stdout is shown as plain text
- **Invalid `view`**: A `view` that doesn't decode as a View DSL tree, such as one with an unknown node type, is dropped. The rest of the output still applies
- **Timeout**: If execution exceeds configured `timeout`, kantan terminates the process with SIGTERM and treats it as a non-zero exit

For watch processes, crashes trigger automatic restart with exponential backoff.

## Common Pitfalls

### Buffered stdout in watch mode

A watch process prints its output to stdout, as a one-shot plugin does. Many runtimes (Python, C stdio, Swift's `print`, etc.) buffer stdout when it isn't a terminal. In watch mode it never is. A plugin that prints JSON without flushing appears to hang: kantan sees no bytes until the buffer fills or the process exits.

Flush after every emitted JSON document:

- **Go**: `os.Stdout` is unbuffered. `json.NewEncoder(os.Stdout).Encode(v)` and `fmt.Println` write immediately. A `bufio.Writer` around it needs `writer.Flush()` after each line.
- **Python**: `print(payload, flush=True)`, or `sys.stdout.flush()` after `print(payload)`. Alternatively launch Python with `-u` for unbuffered I/O.
- **C / C++**: `fflush(stdout)` after `printf`/`fprintf`, or `setbuf(stdout, NULL)` once at startup.
- **Shell**: `printf` and `echo` write immediately. Filters such as `awk`, `sed` and `grep` buffer when writing to a pipe: call `fflush()` in `awk`, and use `sed -l` or `grep --line-buffered`.
- **Swift**: `print(...)` is line-buffered to a tty and fully-buffered to a pipe. Call `fflush(stdout)` (via `import Darwin`) after each emit, or write directly to `FileHandle.standardOutput`.

The EOF-on-stdin convention handles shutdown. Flushing handles delivery.

### Forgetting `interval: 0` with `watch:`

The polling interval is ignored whenever `watch:` is configured. Set `interval: 0` anyway so the config says the module doesn't poll. A reader shouldn't have to remember that `watch:` turns polling off.

### Assuming `kantan trigger` returned a result

`kantan trigger` posts a distributed notification and returns immediately — see [the CLI reference](/docs/reference/cli#trigger-command).
It neither waits for kantan to act on the notification nor reports whether kantan picked it up. Watch processes should treat trigger calls as fire-and-forget.

### Two modules running the same command

kantan keeps a JSON module's latest output under its `command` string, so two modules with an identical `command` (say, two `kantan-plugin-reminders` modules with different `settings:`) share one icon, variables, view and style: whichever ran last. Give each module a distinct `command` string.

## Performance Considerations

- Keep polling plugins fast (< 100ms execution time)
- Use watch mode for expensive operations that don't need to run on every interval
- Cache data between invocations if appropriate
- Set reasonable `interval` values (polling every second is usually unnecessary)
- The `timeout` prevents hung plugins from blocking kantan

## Next Steps

- Read the [API Reference](/docs/plugins/api-reference) for the full protocol
- Explore [View DSL](/docs/view-dsl) for building interactive UIs
- Study the built-in plugins for real-world examples
- Join the kantan community to share your plugins
