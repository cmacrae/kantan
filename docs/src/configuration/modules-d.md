# Modular Configuration

For complex setups with many modules, kantan supports splitting module configurations into separate files in a `modules.d/` directory. This is the recommended approach for organizing multi-module configurations.

## Directory Structure

Put the `modules.d/` directory beside your main `config.yaml` file. The `--modules-dir` flag sets another location.

**Example directory structure:**
```
~/.config/kantan/
├── config.yaml           # Global settings + optional core modules
└── modules.d/
    ├── 00-caffeine.yaml  # Loaded first
    ├── 10-sysmon.yaml
    ├── 20-reminders.yaml
    ├── 30-drawer.yaml
    └── 40-network.yaml   # Loaded last
```

## File Format

Each file in `modules.d/` contains a single module configuration with the same structure as an entry in the `modules:` array:

**Example: `modules.d/10-sysmon.yaml`**
```yaml
name: sysmon
type: command
placement: right
icon: "cpu"
config:
  command: kantan-plugin-system-monitor
  output: json
  interval: 3
  settings:
    format: "{cpu}"
interaction:
  hover:
    type: tooltip
    content: "CPU: {cpu}% | Mem: {mem}%"
  click:
    type: menu
    view:
      type: vstack
      children:
        - type: text
          content: "System Monitor"
        - type: text
          content: "CPU: {cpu}%"
```

## Loading Order

Files are loaded in **alphabetical order**. Use numeric prefixes to control the order:

- `00-caffeine.yaml` - Loaded first
- `10-sysmon.yaml` - Loaded second
- `20-reminders.yaml` - Loaded third
- etc.

Ordering matters because it determines the visual position of modules within their placement group (left vs. right).

## Merging Behavior

Modules from `modules.d/` are merged with modules defined in the main `config.yaml`. The merging ensures that `config.yaml` modules occupy the screen edges and `modules.d/` modules are placed inward (toward center):

- **Left-placed modules** from `modules.d/` are **appended** to left-placed modules from `config.yaml` (appearing to the right of them, closer to center)
- **Right-placed modules** from `modules.d/` are **prepended** to right-placed modules from `config.yaml` (appearing to the left of them, closer to center)

**Example:**

`config.yaml`:
```yaml
modules:
  - name: clock
    type: clock
    placement: right
    config:
      format: "HH:mm"
```

`modules.d/10-battery.yaml`:
```yaml
name: battery
type: power
placement: right
```

**Result:** Clock appears at the right edge (outer), battery appears to the left of clock (inner, toward center).

## Hot-Reload

Adding, editing, or removing files in `modules.d/` triggers automatic reloading. Changes are detected and applied in real-time with a 0.2-second debounce.

## File Types

Both `.yaml` and `.yml` extensions are supported. Other file types are ignored.

## Use Cases

The modules.d/ approach is ideal for:

- **Per-feature organization** - One file per logical feature (system monitoring, notifications, network, etc.)
- **Environment-specific modules** - Enable/disable modules by adding/removing files
- **Shared configurations** - Maintain a base `config.yaml` with global settings, customize modules per-machine
- **Version control** - Track individual module changes in separate commits

## Example: Complete Setup

**`config.yaml`** (global settings only):
```yaml
height: 36
padding: 12
iconTextSpacing: 6
blur: 3

fonts:
  text: "SF Pro:Regular:13"

style:
  light:
    bg: "ffffff"
    fg: "000000"
  dark:
    bg: "000000"
    fg: "ffffff"
```

**`modules.d/00-caffeine.yaml`**:
```yaml
name: caffeine
type: command
placement: left
icon: "coffee"
config:
  command: kantan-plugin-caffeine
  output: json
  interval: 0
  toggle: kantan-plugin-caffeine --toggle
interaction:
  click:
    type: toggle
```

**`modules.d/10-sysmon.yaml`**:
```yaml
name: sysmon
type: command
placement: right
icon: "cpu"
config:
  command: kantan-plugin-system-monitor
  output: json
  interval: 3
```

**`modules.d/20-clock.yaml`**:
```yaml
name: clock
type: clock
placement: right
mask:
  name: Clock
config:
  format: "HH:mm"
```

This setup produces a clean separation between global bar settings and individual module configurations.
