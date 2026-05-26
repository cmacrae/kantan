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

### Reading Configuration

Access the environment variables kantan provides:

```swift
import Foundation

let settings = ProcessInfo.processInfo.environment["KANTAN_SETTINGS"] ?? "{}"
let appearance = ProcessInfo.processInfo.environment["KANTAN_APPEARANCE"] ?? "light"
// KANTAN_MODULE_NAME is only set in watch mode
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

kantan sets these environment variables before invoking your plugin:

| Variable | Type | Set When | Description | Example |
|----------|------|----------|-------------|---------|
| `KANTAN_SETTINGS` | JSON string | Normal invocation, watch, toggle | Module's `settings:` config | `{"refresh": 10, "units": "metric"}` |
| `KANTAN_APPEARANCE` | string | Normal invocation, watch, toggle | Current appearance | `"dark"` or `"light"` |
| `KANTAN_MODULE_NAME` | string | Watch process only | Module identifier | `"my-plugin"` |
| `KANTAN_PID` | string | Normal invocation, watch, toggle | kantan's process ID | `"12345"` |

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
  "icon": "\uf0ae",
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

### Field Reference

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `value` | string | no | Text displayed in the status bar (falls back to raw stdout if omitted) |
| `icon` | string | no | Icon override (replaces module's configured icon) |
| `hidden` | bool | no | If `true`, hides the module from the bar |
| `active` | bool | no | Active state, defaults to `true` (when `false`, module renders in inactive/dimmed style) |
| `variables` | object | no | Key-value pairs for `{var}` template substitution in tooltips/views |
| `data` | object | no | Named arrays accessible via `foreach` in View DSL |
| `style` | object | no | Dynamic style override with `fg`, `bg`, `icon.fg`, and `text.fg` hex colors |
| `view` | object | no | View DSL tree for rich popup/menu/tooltip content |

### Common Patterns

**Simple text output:**
```json
{"value": "42°C"}
```

**Text with icon:**
```json
{"value": "42°C", "icon": "\uf2c9"}
```

**Hidden when inactive:**
```json
{"value": "Idle", "hidden": true}
```

**Toggle state:**
```json
{"value": "Enabled", "active": true}
```

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
    icon: "\uf005"
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
| `command` | string | Executable path or name (must be on PATH) |
| `output` | string | `"json"` for plugin protocol, `"text"` for plain text |
| `interval` | number | Polling interval in seconds (default: 1, 0 = event-driven only, no polling) |
| `timeout` | number | Execution timeout in seconds (default: 10) |
| `watch` | string | Long-lived watcher process command (for event-driven updates) |
| `toggle` | string | Command to run on click (when `click.type: toggle`) |
| `settings` | object | Arbitrary JSON passed via `KANTAN_SETTINGS` |
| `launcher` | object | Shell override with `path` and `args` sub-fields (default: `{path: "/bin/sh", args: ["-c"]}`) |

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
        - type: button
          label: "Refresh"
          command: "kantan trigger my-plugin refresh"
  hover:
    type: tooltip
    content: "Status: {status}"
```

## Step 5: Watch Mode (Event-Driven Plugins)

For plugins that respond to external events rather than polling on an interval, use watch mode. Watch mode is optional — plugins whose state only changes on a timer or user action can skip it entirely. Among the bundled plugins, `reminders` and `calendar` use watch mode (to react to EventKit changes); `pomodoro`, `caffeine`, and `system-monitor` are polling-only by design.

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
- When `watch` is configured, polling is always disabled regardless of `interval` (setting `interval: 0` is conventional but not strictly required)
- The main `command` is still invoked when updates are triggered

### Watch Process Requirements

The watch process:

1. **Runs as a background daemon**: Started when kantan launches, stopped when kantan quits
2. **Receives environment variables**: `KANTAN_MODULE_NAME`, `KANTAN_SETTINGS`, `KANTAN_APPEARANCE`, `KANTAN_PID`
3. **Receives stdin pipe**: EOF signals kantan is shutting down (clean exit expected)
4. **Triggers updates via IPC**: Calls `kantan trigger <module-name> refresh` when events occur
5. **Auto-restarts on crash**: Exponential backoff (1s → 16s cap, max 10 consecutive retries)
6. **Lifecycle integration**: Stopped on system sleep, restarted on wake

### Watch Process Example

```swift
import Foundation

// Check for --watch flag
guard CommandLine.arguments.contains("--watch") else {
    // Normal invocation: output current state
    let output: [String: Any] = ["value": "..."]
    let data = try JSONSerialization.data(withJSONObject: output)
    print(String(data: data, encoding: .utf8)!)
    exit(0)
}

// Watch mode: monitor events and trigger updates
let moduleName = ProcessInfo.processInfo.environment["KANTAN_MODULE_NAME"] ?? ""
let triggerCmd = "kantan trigger '\(moduleName)' refresh"

// Set up event monitoring (example: notification observer)
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

For distribution via the kantan flake, create a plugin directory:

```
packages/plugins/my-plugin/
├── Package.swift
└── Sources/
    └── my-plugin/
        └── main.swift
```

The flake's `buildSwiftPlugin` function auto-discovers plugins from `packages/plugins/`. Your plugin will be built and symlinked into the kantan wrapper as `kantan-plugin-my-plugin`.

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
        )
    ]
)
```

Plugins can also be written in other languages. The build system auto-detects the plugin type:
- **Swift**: Detected by `Package.swift` in the plugin directory
- **Go**: Detected by `go.mod` in the plugin directory
- **Shell**: Detected by `main.sh` in the plugin directory

## Step 7: Use the View DSL

For rich interactive UIs, return a `view` field with a View DSL tree:

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
            {"type": "icon", "name": "\uf00c"},
            {"type": "text", "content": "{name} - {status}"}
          ]
        }
      }
    ]
  }
}
```

This creates a vertical stack with a header and a list of items. See the [View DSL documentation](../view-dsl/README.md) for complete details on building views.

## Testing Your Plugin

Test your plugin directly from the command line:

```bash
export KANTAN_SETTINGS='{"myOption": "test"}'
export KANTAN_APPEARANCE="dark"
export KANTAN_MODULE_NAME="my-plugin"

./kantan-plugin-my-plugin
```

Verify the JSON output is valid and contains the expected fields.

## Examples

See the built-in plugins for complete reference implementations:

- `packages/plugins/reminders/` — Event-driven Swift plugin with watch mode, View DSL menus, and command actions
- `packages/plugins/system-monitor/` — Polling Swift plugin with formatted metrics and dynamic styling
- `packages/plugins/caffeine/` — Shell script plugin with toggle state management and `KANTAN_PID`-tied `caffeinate`
- `packages/plugins/calendar/` — Event-driven Swift plugin with watch mode, calendar integration, and conditional visibility
- `packages/plugins/pomodoro/` — Polling Go plugin with persistent state, timer management, and interactive actions

## Error Handling

- **Exit code 0**: Success, kantan parses the JSON output
- **Non-zero exit code**: Empty string returned and cached icon/variables/style are cleared
- **Invalid JSON**: Cached icon/variables/style are cleared and the raw stdout is shown as plain text
- **Timeout**: If execution exceeds configured `timeout`, kantan terminates the process and treats it as a non-zero exit

For watch processes, crashes trigger automatic restart with exponential backoff.

## Performance Considerations

- Keep polling plugins fast (< 100ms execution time)
- Use watch mode for expensive operations that don't need to run on every interval
- Cache data between invocations if appropriate
- Set reasonable `interval` values (polling every second is usually unnecessary)
- The `timeout` prevents hung plugins from blocking kantan

## Next Steps

- Read the [API Reference](api-reference.md) for complete protocol specification
- Explore [View DSL](../view-dsl/README.md) for building interactive UIs
- Study the built-in plugins for real-world examples
- Join the kantan community to share your plugins
