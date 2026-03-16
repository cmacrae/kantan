# kantan-plugin-system-monitor

A native system monitor plugin for [kantan](https://github.com/cmacrae/kantan) that reports real-time CPU, memory, disk, thermal, and process information using macOS kernel APIs.

## Installation

This plugin is bundled with kantan and requires no separate installation. It is included in both the [Nix flake](https://github.com/cmacrae/kantan) default package and the Homebrew `kantan` formula. The `kantan-without-plugins` variant (available via both Nix and Homebrew) does not include this plugin.

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

| Variable           | Example          | Description                                  |
|--------------------|------------------|----------------------------------------------|
| `{cpu}`            | ` 45%`           | Overall CPU usage (space-padded to 3 digits) |
| `{cpu_pct}`        | `0.45`           | CPU usage normalised to 0.00–1.00            |
| `{mem}`            | `12.3/32 GB`     | Memory used/total                            |
| `{mem_pct}`        | `38%`            | Memory pressure percentage                   |
| `{mem_pct_norm}`   | `0.38`           | Memory pressure normalised to 0.00–1.00      |
| `{mem_used}`       | `12.3 GB`        | Memory used                                  |
| `{mem_total}`      | `32 GB`          | Total physical memory                        |
| `{mem_wired}`      | `3.2 GB`         | Wired (non-pageable) memory                  |
| `{mem_active}`     | `6.1 GB`         | Active memory                                |
| `{mem_compressed}` | `3.0 GB`         | Compressed memory                            |
| `{mem_free}`       | `8.5 GB`         | Free memory                                  |
| `{disk}`           | `250/500 GB`     | Disk used/total                              |
| `{disk_pct}`       | `50%`            | Disk usage percentage                        |
| `{disk_pct_norm}`  | `0.50`           | Disk usage normalised to 0.00–1.00           |
| `{disk_used}`      | `250 GB`         | Disk space used                              |
| `{disk_total}`     | `500 GB`         | Total disk capacity                          |
| `{disk_free}`      | `250 GB`         | Free disk space                              |
| `{thermal}`        | `Nominal`        | Thermal state name                           |
| `{thermal_icon}`   | (icon)           | Thermometer icon matching severity           |
| `{thermal_color}`  | `#30d158`        | Color matching thermal severity (only present when thermal colors are configured) |
| `{show_cores}`     | `true`           | Truthy when `show_cores` is enabled          |
| `{show_processes}` | `true`           | Truthy when top processes are available       |
| `{uptime}`         | `3d 12h`         | System uptime                                |
| `{load}`           | `2.45 1.80 1.50` | Load average (1/5/15m)                       |
| `{load_1m}`        | `2.45`           | 1-minute load average                        |
| `{load_5m}`        | `1.80`           | 5-minute load average                        |
| `{load_15m}`       | `1.50`           | 15-minute load average                       |

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
        thermal_nominal: "#34c759"
        thermal_fair: "#f0a500"
        thermal_serious: "#e8590c"
        thermal_critical: "#e03131"
      dark:
        cpu_low: "#30d158"
        cpu_medium: "#ffcc00"
        cpu_high: "#ff9500"
        cpu_critical: "#ff3b30"
        thermal_nominal: "#30d158"
        thermal_fair: "#ffcc00"
        thermal_serious: "#ff9500"
        thermal_critical: "#ff3b30"
    process_count: 5
    show_cores: false
interaction:
  hover:
    type: tooltip
    content: "CPU {cpu} | Mem {mem} | {thermal}"
  click:
    type: menu
```

### Plugin Settings

Settings are passed to the plugin via the `config.settings` block. All settings are optional; the plugin uses sensible defaults when omitted.

Colors are defined under `style.light` and `style.dark` to match the system appearance, following kantan's convention.
Alternatively, colors can be specified flat (without `light`/`dark` nesting) to use the same values for both modes.
When a color is not configured, it is omitted from the output and kantan inherits its own default styling.
This is respected per-setting, so if you only want to set colours for specific threshold conditions, you only need to set those.

| Setting                        | Default     | Description                                 |
|--------------------------------|-------------|---------------------------------------------|
| `style.light.cpu_low`          | —           | CPU color when usage < 30%                  |
| `style.light.cpu_medium`       | —           | CPU color when usage 30-49%                 |
| `style.light.cpu_high`         | —           | CPU color when usage 50-79%                 |
| `style.light.cpu_critical`     | —           | CPU color when usage >= 80%                 |
| `style.light.thermal_nominal`  | —           | Thermal color for nominal state             |
| `style.light.thermal_fair`     | —           | Thermal color for fair state                |
| `style.light.thermal_serious`  | —           | Thermal color for serious state             |
| `style.light.thermal_critical` | —           | Thermal color for critical state            |
| `style.dark.cpu_low`           | —           | CPU color when usage < 30% (dark mode)      |
| `style.dark.cpu_medium`        | —           | CPU color when usage 30-49% (dark mode)     |
| `style.dark.cpu_high`          | —           | CPU color when usage 50-79% (dark mode)     |
| `style.dark.cpu_critical`      | —           | CPU color when usage >= 80% (dark mode)     |
| `style.dark.thermal_nominal`   | —           | Thermal color for nominal (dark mode)       |
| `style.dark.thermal_fair`      | —           | Thermal color for fair (dark mode)          |
| `style.dark.thermal_serious`   | —           | Thermal color for serious (dark mode)       |
| `style.dark.thermal_critical`  | —           | Thermal color for critical (dark mode)      |
| `format`                       | `CPU {cpu}` | Format string for the bar display value     |
| `color_target`                 | `both`      | What to colorise: `icon`, `text`, or `both` |
| `process_count`                | `5`         | Number of top processes to show             |
| `show_cores`                   | `false`     | Show per-core CPU usage in the menu         |

#### Icon Overrides

Icons for each menu section can be customised via the `icons` block. Values are icon names resolved by kantan's bundled icon font system (e.g. `cpu`, `server`, `clock`). Raw Unicode glyphs are also accepted. All fields are optional and fall back to their defaults when omitted.

| Setting                    | Default        | Description                        |
|----------------------------|----------------|------------------------------------|
| `icons.cpu`                | `cpu`          | CPU section icon                   |
| `icons.memory`             | `script`       | Memory section icon                |
| `icons.disk`               | `device-floppy`| Disk section icon                  |
| `icons.thermal_nominal`    | `thermometer`  | Thermal icon for nominal state     |
| `icons.thermal_fair`       | `thermometer`  | Thermal icon for fair state        |
| `icons.thermal_serious`    | `thermometer`  | Thermal icon for serious state     |
| `icons.thermal_critical`   | `thermometer`  | Thermal icon for critical state    |
| `icons.uptime`             | `clock`        | Uptime section icon                |
| `icons.load`               | `graph`        | Load average section icon          |
| `icons.activity_monitor`   | `dashboard`    | Activity Monitor action icon       |

### Module Options

| Field                       | Default | Description                                                              |
|-----------------------------|---------|--------------------------------------------------------------------------|
| `config.interval`           | `1`     | Polling interval in seconds (the example uses `3` for a good balance)    |
| `interaction.hover.content` | —       | Template string for tooltip (see variables above)                        |
| `interaction.click`         | —       | `menu` for native menu with live stats, or `popup` for custom layout |

### Data Collections

The plugin outputs these data collections for use with the `foreach` view DSL node:

| Collection  | Fields                       | Description            |
|-------------|------------------------------|------------------------|
| `cores`     | `core`, `usage`, `usage_pct` | Per-core CPU usage     |
| `processes` | `name`, `cpu_pct`            | Top CPU consumers      |

### Built-in View

The plugin outputs a complete view tree via the `view` field in its JSON output. This includes an overview section (CPU, memory, disk, thermal, uptime, load), conditional per-core CPU breakdown (when `show_cores` is enabled), conditional top processes list, and an Activity Monitor launch action. The built-in view uses the configured icon overrides and thermal colors automatically.

To use the built-in view, set the click interaction to `popup`:

```yaml
interaction:
  click:
    type: popup
```

### Custom Popup Example

Optionally, a custom popup layout can be defined using the View DSL instead of using the built-in view:

```yaml
interaction:
  click:
    type: popup
    view:
      type: vstack
      spacing: 8
      padding: [12, 16, 12, 16]
      frame:
        w: 280
      children:
        - type: header
          content: "CPU"
        - type: hstack
          children:
            - type: icon
              name: cpu
            - type: text
              content: "Usage"
            - type: spacer
            - type: text
              content: "{cpu}"
        - type: hstack
          children:
            - type: icon
              name: graph
            - type: text
              content: "Load (1m)"
            - type: spacer
            - type: text
              content: "{load_1m}"
        - type: divider
        - type: header
          content: "Memory"
        - type: hstack
          children:
            - type: text
              content: "Used"
            - type: spacer
            - type: text
              content: "{mem} ({mem_pct})"
        - type: text
          content: "Wired: {mem_wired}"
          style: secondary
        - type: text
          content: "Compressed: {mem_compressed}"
          style: secondary
        - type: divider
        - type: header
          content: "Disk"
        - type: hstack
          children:
            - type: text
              content: "Usage"
            - type: spacer
            - type: text
              content: "{disk} ({disk_pct})"
        - type: text
          content: "Free: {disk_free}"
          style: secondary
        - type: divider
        - type: action
          icon: dashboard
          label: "Activity Monitor"
          command: "open -a 'Activity Monitor'"
```
