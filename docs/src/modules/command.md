# Command

Type: `command`

The command module executes shell commands or plugin binaries and displays their output in the status bar. It is the foundation of kantan's [plugin system](/docs/plugins).

## Configuration

| Field | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| `command` | string | **yes** | — | Shell command or executable to run |
| `output` | string | no | `"text"` | Output format: `"text"` (raw stdout) or `"json"` (structured plugin protocol) |
| `interval` | number | no | `1` | Polling interval in seconds. Set to `0` for no timer: the command then runs at startup, on wake and space changes, and when triggered |
| `timeout` | number | no | `10` | Seconds before a running command is terminated |
| `watch` | string | no | — | Long-lived watcher process command, run with `/bin/sh -c` |
| `toggle` | string | no | — | Command to run on toggle interaction, run with the `launcher` |
| `settings` | object | no | — | Arbitrary settings passed to the plugin via `KANTAN_SETTINGS` env var |
| `launcher.path` | string | no | `"/bin/sh"` | Shell/interpreter path for `command` and `toggle` |
| `launcher.args` | array | no | `["-c"]` | Arguments passed before the command string |

The command also runs whenever `kantan trigger <name> refresh` is sent for the module.

## Output Modes

### Text Mode (`output: text`)

The command's stdout, with surrounding newlines trimmed, is used directly as the module's display text. This is the default. A command that exits non-zero or times out shows nothing.

```yaml
- name: uptime
  type: command
  placement: right
  config:
    command: "uptime | awk '{print $3}'"
    interval: 60
```

### JSON Mode (`output: json`)

The command's stdout is parsed as JSON conforming to the [plugin output schema](/docs/plugins/api-reference#output-specification). This enables dynamic icons, styling, visibility control, View DSL content, template variables, data collections for `foreach` iteration, and `segments` that colour parts of the value. Output that isn't a JSON object is shown as plain text. So is the whole output when the object has no string `value`.

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

A `watch` command launches a long-lived background process for event-driven updates. The watch process either prints the module's new output to stdout or runs `kantan trigger <module-name> refresh` to have kantan run `command` again. With `output: json`, each line of stdout that is a JSON object is shown as though `command` had printed it. Other lines, and all lines in text mode, are ignored.

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

A configured watch process turns polling off, whatever the `interval`. `command` still runs at startup, on wake and on space changes. One watch process runs per module, however many displays show it.

- **Lifetime**: the process's stdin is a pipe that reaches EOF when kantan exits. To stop the process itself, kantan closes stdin and sends `SIGTERM` if the process is still running a second later. The process is stopped on sleep and started again on wake. It's relaunched when the system appearance changes, with `KANTAN_APPEARANCE` and theme templates in `KANTAN_SETTINGS` matching the new appearance.
- **Restarts**: when the process exits, kantan relaunches it after 1s, doubling to 16s, and gives up after 10 consecutive restarts. A process that ran for at least 30 seconds before exiting starts the count afresh. So does launching kantan or waking from sleep.

See the [Watch Mode Protocol](/docs/plugins/api-reference#watch-mode-protocol) for details.

## Toggle Command

The `toggle` field specifies a command to run when the module is clicked with `click.type: toggle` (or `complete`). It runs in the background with the same environment variables as `command`. The module refreshes once it exits:

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

A `command` starting with `./` or `../` runs from the config file's directory. The path resolves relative to it. `watch` and `toggle` commands are not resolved this way:

```yaml
config:
  command: ./scripts/my-status.sh
```

## Environment Variables

The `command`, `watch` and `toggle` commands all receive these environment variables:

| Variable | Description |
|----------|-------------|
| `KANTAN_SETTINGS` | JSON-serialized `settings` object (if configured), with `{theme(name)}` templates resolved for the current appearance |
| `KANTAN_APPEARANCE` | Current system appearance: `"dark"` or `"light"` |
| `KANTAN_PID` | kantan's process ID |
| `KANTAN_MODULE_NAME` | Module name |

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
