# Command

The command module executes shell commands or plugin binaries and displays their output in the status bar. It is the foundation of kantan's [plugin system](../plugins/README.md).

## Configuration

| Field | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| `command` | string | **yes** | — | Shell command or executable to run |
| `output` | string | no | `"text"` | Output format: `"text"` (raw stdout) or `"json"` (structured plugin protocol) |
| `interval` | number | no | `1` | Polling interval in seconds. Set to `0` for event-driven modules (no timer) |
| `timeout` | number | no | `10` | Execution timeout in seconds |
| `watch` | string | no | — | Long-lived watcher process command |
| `toggle` | string | no | — | Command to run on toggle interaction |
| `settings` | object | no | — | Arbitrary settings passed to the plugin via `KANTAN_SETTINGS` env var |
| `launcher.path` | string | no | `"/bin/sh"` | Shell/interpreter path |
| `launcher.args` | array | no | `["-c"]` | Arguments passed before the command string |

## Output Modes

### Text Mode (`output: text`)

The command's stdout is used directly as the module's display text. This is the default.

```yaml
- name: uptime
  type: command
  placement: right
  config:
    command: "uptime | awk '{print $3}'"
    interval: 60
```

### JSON Mode (`output: json`)

The command's stdout is parsed as JSON conforming to the [plugin output schema](../plugins/api-reference.md#output-specification). This enables dynamic icons, styling, visibility control, View DSL content, template variables, and data collections for `foreach` iteration.

```yaml
- name: weather
  type: command
  placement: left
  icon: cloud
  config:
    command: kantan-plugin-weather
    output: json
    interval: 300
    settings:
      location: "San Francisco"
```

## Watch Mode

A `watch` command launches a long-lived background process for event-driven updates. The watch process triggers refreshes via `kantan trigger <module-name> refresh` instead of polling.

```yaml
- name: reminders
  type: command
  placement: right
  icon: checklist
  config:
    command: kantan-plugin-reminders
    output: json
    interval: 0
    watch: kantan-plugin-reminders --watch
```

When a watch process is configured, polling is always disabled regardless of the `interval` value. See the [Watch Mode Protocol](../plugins/api-reference.md#watch-mode-protocol) for details.

## Toggle Command

The `toggle` field specifies a command to run when the module is clicked with `click.type: toggle`:

```yaml
- name: caffeine
  type: command
  placement: right
  config:
    command: kantan-plugin-caffeine
    output: json
    toggle: kantan-plugin-caffeine --toggle
  interaction:
    click:
      type: toggle
```

## Relative Paths

Commands starting with `./` or `../` are resolved relative to the config file directory:

```yaml
config:
  command: ./scripts/my-status.sh
```

## Environment Variables

All commands receive these environment variables:

| Variable | Description |
|----------|-------------|
| `KANTAN_SETTINGS` | JSON-serialized `settings` object (if configured) |
| `KANTAN_APPEARANCE` | Current system appearance: `"dark"` or `"light"` |
| `KANTAN_PID` | kantan's process ID |
| `KANTAN_MODULE_NAME` | Module name (watch processes only) |

## Custom Launcher

Override the default shell with the `launcher` field:

```yaml
config:
  command: my-plugin-script
  launcher:
    path: /usr/bin/env
    args: ["python3", "-c"]
```

## Examples

**Simple polling command:**
```yaml
- name: disk
  type: command
  placement: right
  icon: device-floppy
  config:
    command: "df -h / | awk 'NR==2 {print $5}'"
    interval: 30
```

**Plugin with settings and interaction:**
```yaml
- name: monitor
  type: command
  placement: left
  icon: activity
  config:
    command: kantan-plugin-system-monitor
    output: json
    interval: 5
    settings:
      showCPU: true
      showMemory: true
  interaction:
    click:
      type: popup
```
