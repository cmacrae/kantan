# kantan-plugin-system-monitor

A native system monitor plugin for [kantan](https://github.com/cmacrae/kantan) that reports real-time CPU, memory, disk, thermal, and process information using macOS kernel APIs.

## Features

- **CPU usage** — Overall percentage
- **Per-core CPU** — Individual core usage displayed in the dynamic menu (opt-in via settings)
- **Memory** — Used/total with breakdown: active, wired, compressed, free
- **Disk** — Root volume usage
- **Thermal state** — `ProcessInfo.thermalState` with severity-mapped icons and colors
- **Load average** — 1/5/15 minute load
- **Uptime** — System uptime in human-readable format
- **Top processes** — Top N CPU consumers
- **Dynamic colors** — CPU and thermal color thresholds are fully configurable
- **Activity Monitor** — Quick-launch from the menu

### Template Variables

| Variable           | Example          | Description                        |
|--------------------|------------------|------------------------------------|
| `{cpu}`            | `45%`            | Overall CPU usage                  |
| `{mem}`            | `12.3/32 GB`     | Memory used/total                  |
| `{mem_pct}`        | `38%`            | Memory pressure percentage         |
| `{mem_used}`       | `12.3 GB`        | Memory used                        |
| `{mem_total}`      | `32 GB`          | Total physical memory              |
| `{mem_wired}`      | `3.2 GB`         | Wired (non-pageable) memory        |
| `{mem_active}`     | `6.1 GB`         | Active memory                      |
| `{mem_compressed}` | `3.0 GB`         | Compressed memory                  |
| `{mem_free}`       | `8.5 GB`         | Free memory                        |
| `{disk}`           | `250/500 GB`     | Disk used/total                    |
| `{disk_pct}`       | `50%`            | Disk usage percentage              |
| `{disk_used}`      | `250 GB`         | Disk space used                    |
| `{disk_total}`     | `500 GB`         | Total disk capacity                |
| `{disk_free}`      | `250 GB`         | Free disk space                    |
| `{thermal}`        | `Nominal`        | Thermal state name                 |
| `{thermal_icon}`   | (icon)           | Thermometer icon matching severity |
| `{thermal_color}`  | `#30d158`        | Color matching thermal severity    |
| `{uptime}`         | `3d 12h`         | System uptime                      |
| `{load}`           | `2.45 1.80 1.50` | Load average (1/5/15m)             |
| `{load_1m}`        | `2.45`           | 1-minute load average              |
| `{load_5m}`        | `1.80`           | 5-minute load average              |
| `{load_15m}`       | `1.50`           | 15-minute load average             |

## Configuration

Copy the example config into your kantan `modules.d/` directory:

```yaml
name: system-monitor
type: command
placement: right
icon: "\uf2db"
style:
  light:
    fg: "#a6d189"
  dark:
    fg: "#a6e3a1"
config:
  command: kantan-plugin-system-monitor
  output: json
  interval: 3
  settings:
    style:
      light:
        cpu_low: "#34c759"
        cpu_medium: "#f0a500"
        cpu_high: "#e8590c"
        cpu_critical: "#e03131"
      dark:
        cpu_low: "#30d158"
        cpu_medium: "#ffcc00"
        cpu_high: "#ff9500"
        cpu_critical: "#ff3b30"
    process_count: 5
    show_cores: false
interaction:
  hover:
    type: tooltip
    content: "CPU {cpu} | Mem {mem} | {thermal}"
  click:
    type: menu
    items:
      - header: "System Monitor"
      - dynamic: true
```

### Plugin Settings

Settings are passed to the plugin via the `config.settings` block. All settings are optional, the plugin uses sensible defaults when omitted.

Colors are defined under `style.light` and `style.dark` to match the system appearance, following kantan's convention.
If no style is specified for the active system appearance, built-in defaults are used.
This is respected per-setting, so if you only want to set colours for specific threshold conditions, you only need to set those.

| Setting                        | Default     | Description                                 |
|--------------------------------|-------------|---------------------------------------------|
| `style.light.cpu_low`          | `#30d158`   | CPU color when usage < 30%                  |
| `style.light.cpu_medium`       | `#ffcc00`   | CPU color when usage 30-49%                 |
| `style.light.cpu_high`         | `#ff9500`   | CPU color when usage 50-79%                 |
| `style.light.cpu_critical`     | `#ff3b30`   | CPU color when usage >= 80%                 |
| `style.light.thermal_nominal`  | `#30d158`   | Thermal color for nominal state             |
| `style.light.thermal_fair`     | `#ffcc00`   | Thermal color for fair state                |
| `style.light.thermal_serious`  | `#ff9500`   | Thermal color for serious state             |
| `style.light.thermal_critical` | `#ff3b30`   | Thermal color for critical state            |
| `style.dark.cpu_low`           | `#30d158`   | CPU color when usage < 30% (dark mode)      |
| `style.dark.cpu_medium`        | `#ffcc00`   | CPU color when usage 30-49% (dark mode)     |
| `style.dark.cpu_high`          | `#ff9500`   | CPU color when usage 50-79% (dark mode)     |
| `style.dark.cpu_critical`      | `#ff3b30`   | CPU color when usage >= 80% (dark mode)     |
| `style.dark.thermal_nominal`   | `#30d158`   | Thermal color for nominal (dark mode)       |
| `style.dark.thermal_fair`      | `#ffcc00`   | Thermal color for fair (dark mode)          |
| `style.dark.thermal_serious`   | `#ff9500`   | Thermal color for serious (dark mode)       |
| `style.dark.thermal_critical`  | `#ff3b30`   | Thermal color for critical (dark mode)      |
| `format`                       | `CPU {cpu}` | Format string for the bar display value     |
| `color_target`                 | `both`      | What to colorise: `icon`, `text`, or `both` |
| `process_count`                | `5`         | Number of top processes to show             |
| `show_cores`                   | `false`     | Show per-core CPU usage in the menu         |

### Module Options

| Field                       | Default | Description                                                              |
|-----------------------------|---------|--------------------------------------------------------------------------|
| `config.interval`           | `3`     | Polling interval in seconds                                              |
| `interaction.hover.content` | —       | Template string for tooltip (see variables above)                        |
| `interaction.click`         | —       | `menu` with `dynamic: true` for live stats, or `popup` for custom layout |

### Popup Example

Optionally, a popup can be defined, instead of a menu

```yaml
interaction:
  click:
    type: popup
    popup:
      title: "System Monitor"
      width: 280
      rows:
        - type: header
          content: "CPU"
        - type: text
          icon: "\uf2db"
          label: "Usage"
          value: "{cpu}"
        - type: text
          icon: "\uf080"
          label: "Load (1m)"
          value: "{load_1m}"
        - type: separator
        - type: header
          content: "Memory"
        - type: text
          icon: "\uf538"
          label: "Used"
          value: "{mem} ({mem_pct})"
        - type: text
          label: "Wired"
          value: "{mem_wired}"
          style: secondary
        - type: text
          label: "Compressed"
          value: "{mem_compressed}"
          style: secondary
        - type: separator
        - type: header
          content: "Disk"
        - type: text
          icon: "\uf0a0"
          label: "Usage"
          value: "{disk} ({disk_pct})"
        - type: text
          label: "Free"
          value: "{disk_free}"
          style: secondary
        - type: separator
        - type: action
          icon: "\uf0e4"
          label: "Activity Monitor"
          command: "open -a 'Activity Monitor'"
```
