# Plugins

kantan plugins are standalone executables, written in any language, that extend kantan. They talk to kantan through environment variables and JSON output.

## Overview

Plugins are executable programs that integrate with kantan modules through the `command` module type. They can be written in any language that can read environment variables and output JSON to stdout.

**Key characteristics:**

- **Language-agnostic**: Write plugins in Swift, Go, Python, shell scripts, or any language that produces executables
- **Simple protocol**: Input via environment variables, output via JSON on stdout
- **Flexible invocation**: Polling-based (periodic execution) or event-driven (via watch mode)
- **Rich UI support**: Use the View DSL to create interactive menus, tooltips, and popups
- **Standalone executables**: Binaries named `kantan-plugin-<name>` placed on PATH

## Communication Model

```
kantan → Environment Variables → Plugin
Plugin → JSON stdout → kantan
Plugin → `kantan trigger <name> refresh` IPC → kantan (watch mode)
```

kantan invokes the plugin as a subprocess, passing configuration through environment variables:
- `KANTAN_SETTINGS`: Module's `settings:` configuration as JSON
- `KANTAN_APPEARANCE`: Current system appearance (`"dark"` or `"light"`)
- `KANTAN_MODULE_NAME`: Module identifier from config (watch process only)
- `KANTAN_PID`: kantan's process ID

The plugin processes these inputs and outputs a JSON object describing what to display:
```json
{
  "value": "Display text",
  "icon": "\uf0ae",
  "variables": {"count": "5"},
  "view": { ... }
}
```

## Plugin Modes

### Polling Mode
kantan invokes the plugin at regular intervals based on the configured `interval` (in seconds). Suitable for monitoring resources that don't provide event notifications.

### Event-Driven Mode (Watch)
For plugins that need to respond to external events, the watch mode enables a long-lived background process that triggers updates when events occur. The watch process signals kantan via `kantan trigger`, which then invokes the main command to retrieve updated output.

## Built-in Plugins

kantan ships with these plugins:

- **reminders**: Shows due items from macOS Reminders and completes them from its view (Swift, event-driven)
- **system-monitor**: Displays CPU, memory, disk, thermal, and uptime statistics (Swift, polling)
- **caffeine**: Prevents system sleep, toggled by a click (shell script)
- **calendar**: Integrates with macOS Calendar, shows upcoming events with countdowns (Swift, event-driven)
- **pomodoro**: Pomodoro timer with work/break sessions, pause/resume/skip controls (Go, polling)
- **tailscale**: Indicates Tailscale connection state via the LocalAPI, with tailnet tooltip (Go, polling)

Their sources in `packages/plugins/` are reference implementations.

## View DSL Integration

Plugins can define rich interactive interfaces using kantan's View DSL. By returning a `view` field in the JSON output, plugins can create:

- Custom tooltips with formatted text and icons
- Multi-level menus with submenus and actions
- Interactive popups with buttons and status displays
- Data-driven lists using `foreach` iteration

See the [View DSL documentation](/docs/view-dsl) for details on building interactive plugin UIs.

## Documentation Structure

This section contains detailed guides for plugin development:

- **[Building a Plugin](/docs/plugins/building-a-plugin)**: Step-by-step tutorial for creating your first plugin, from simple shell scripts to event-driven Swift executables
- **[API Reference](/docs/plugins/api-reference)**: Formal specification of the plugin protocol, including environment variables, JSON output schema, and IPC mechanisms

## Distribution

Plugins can be:
- Distributed as standalone executables via any package manager
- Packaged with the kantan flake using the built-in build helpers (`buildSwiftPlugin`, `buildGoPlugin`, `buildShellPlugin`)
- Auto-discovered from `packages/plugins/` in the kantan repository (detected by `Package.swift`, `go.mod`, or `main.sh`)

The only requirement is that the executable is named `kantan-plugin-<name>` and available on PATH when kantan invokes it.
