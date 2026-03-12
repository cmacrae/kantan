# kantan-plugin-caffeine

A shell-based caffeine plugin for [kantan](https://github.com/cmacrae/kantan) that prevents display sleep using the macOS `caffeinate` command.

## Features

- **Display sleep prevention** — Runs `caffeinate -d` to keep the display awake
- **Toggle on click** — Click to activate/deactivate directly from the bar
- **Visual feedback** — Icon dims when inactive via the `active` state
- **Template variables** — `{status}` for tooltip and display text
- **Automatic cleanup** — When `KANTAN_PID` is set, the `caffeinate` process is tied to kantan's lifetime via `-w`

### Template Variables

| Variable   | Example | Description                                          |
|------------|---------|------------------------------------------------------|
| `{status}` | `on`    | Current state: `on` when active, `off` when inactive |

## Configuration

Copy the example config into your kantan `modules.d/` directory:

```yaml
name: caffeine
type: command
placement: right
icon: "\uf0f4"
style:
  light:
    fg: "#e5c890"
  dark:
    fg: "#f9e2af"
config:
  command: kantan-plugin-caffeine
  output: json
  interval: 0
  toggle: kantan-plugin-caffeine --toggle
interaction:
  hover:
    type: tooltip
    content: "Caffeine: {status}"
  click:
    type: toggle
```

### Module Options

| Field                       | Value                             | Description                                       |
|-----------------------------|-----------------------------------|---------------------------------------------------|
| `config.command`            | `kantan-plugin-caffeine`          | Plugin binary                                     |
| `config.output`             | `json`                            | Structured output mode                            |
| `config.interval`           | `0`                               | No polling (state only changes on toggle)         |
| `config.toggle`             | `kantan-plugin-caffeine --toggle` | Command run when the module is toggled            |
| `interaction.click.type`    | `toggle`                          | Click toggles active state and dims the icon      |
| `interaction.hover.content` | ---                               | Template string for tooltip (see variables above) |

## How It Works

The plugin is a simple shell script that wraps the macOS `caffeinate` command.

**Default mode** (no arguments) --- Checks whether a background `caffeinate` process is alive by reading a PID file at `~/.cache/kantan/caffeine.pid`. Outputs JSON with the current `active` state and `{status}` template variable. When inactive, kantan renders the module icon at reduced opacity.

**Toggle mode** (`--toggle`) --- Flips the current state. If active, kills the `caffeinate` process and removes the PID file. If inactive, spawns `caffeinate -d` in the background and writes its PID to the state file. When `KANTAN_PID` is available, the process is started with `caffeinate -d -w $KANTAN_PID` so it automatically exits if kantan terminates.

**Explicit control** (`--activate` / `--deactivate`) --- One-directional subcommands for scripting use.
