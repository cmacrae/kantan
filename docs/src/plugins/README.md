# Plugins

kantan plugins are programs, written in any language, that kantan runs as commands to extend the bar. They talk to kantan through environment variables and JSON output.

## Key Characteristics

- **Language-agnostic**: Write plugins in Swift, Go, Python, shell or any other language, as long as kantan can run the plugin as a command
- **Simple protocol**: Input via environment variables, output via JSON on stdout
- **Flexible invocation**: Polling-based (periodic execution) or event-driven (via watch mode)
- **Rich UI support**: Use the View DSL to create interactive menus, tooltips, and popups
- **Standalone programs**: Run by a module's `command:`. Bundled plugins are named `kantan-plugin-<name>`

## Communication Model

```
kantan → Environment Variables → Plugin
Plugin → JSON stdout → kantan
Plugin → JSON lines on stdout, or `kantan trigger <name> refresh` → kantan (watch mode)
```

kantan invokes the plugin as a subprocess, passing configuration through environment variables:
- `KANTAN_SETTINGS`: Module's `settings:` configuration as JSON (unset when the module has no `settings:`)
- `KANTAN_APPEARANCE`: Current system appearance (`"dark"` or `"light"`)
- `KANTAN_MODULE_NAME`: Module identifier from config
- `KANTAN_PID`: kantan's process ID

The plugin processes these inputs and outputs a JSON object describing what to display:
```json
{
  "value": "Display text",
  "icon": "list-check",
  "variables": {"count": "5"},
  "view": { ... }
}
```

## Plugin Modes

### Polling Mode
kantan invokes the plugin at regular intervals based on the configured `interval` (in seconds, default 1). It suits resources that have no event notifications.

### Event-Driven Mode (Watch)
A plugin that responds to external events can run a long-lived watch process that sends updates when events occur. The watch process prints the module's new output to stdout, one line of JSON at a time. Or it runs `kantan trigger` to have kantan run the main command again.

## Built-in Plugins

kantan ships with these plugins:

- **reminders**: Shows due items from macOS Reminders and completes them from its view (Swift, event-driven)
- **system-monitor**: Displays CPU, memory, disk, thermal, and uptime statistics (Swift, polling)
- **caffeine**: Prevents system sleep, toggled by a click (shell script)
- **calendar**: Integrates with macOS Calendar, shows upcoming events with countdowns (Swift, event-driven)
- **pomodoro**: Pomodoro timer with work/break sessions, pause/resume/skip controls (Go, polling)
- **tailscale**: Indicates Tailscale connection state via the LocalAPI, with tailnet tooltip (Go, polling)
- **rift-indicator**: Shows the Rift window manager's active layout mode, with an icon and colour per layout (Go, event-driven)

Their sources in `packages/plugins/` are reference implementations.

## View DSL Integration

A plugin's `view` output field holds a View DSL tree, shown by the module's click `menu` or `popup`. Hover tooltips take their view from the module config. Views can contain:

- Formatted text, icons, badges and shapes
- Multi-level menus with submenus and actions
- Interactive popups with buttons and status displays
- Data-driven lists using `foreach` iteration

See the [View DSL documentation](../view-dsl/index.md) for details on building interactive plugin UIs.

## Documentation Structure

This section contains detailed guides for plugin development:

- **[Building a Plugin](building-a-plugin.md)**: Step-by-step tutorial for creating your first plugin, from simple shell scripts to event-driven Swift executables
- **[API Reference](api-reference.md)**: Formal specification of the plugin protocol, including environment variables, JSON output schema, and IPC mechanisms

## Distribution

Plugins can be:
- Distributed as standalone executables via any package manager
- Added to the kantan flake package with `kantan.withPlugins { extraPlugins = [ ... ]; }`, which puts each package's `bin/` on kantan's PATH
- Built in the kantan repository from `packages/plugins/<name>/`, which the flake discovers and builds as `kantan-plugin-<name>` (Swift, Go or shell, detected by `Package.swift`, `go.mod` or `main.sh`)

kantan runs a module's `command:` through `/bin/sh -c`. A plugin can be any name or path the shell can run. The `kantan-plugin-<name>` naming is the convention the bundled plugins follow.
