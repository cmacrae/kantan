# Modules

Modules are the individual components displayed in the status bar. Each module appears in the `modules:` array in the configuration file, or as a standalone file in the `modules.d/` directory.

The [builder](https://kantan.bar/builder/) edits a module's fields in a form and draws the module as they change. It writes the YAML described here, and can share a module on its own as a link.

## Common Module Fields

All modules support these configuration fields:

| Key | Type | Required | Description |
|-----|------|----------|-------------|
| `name` | string | **yes** | Unique module identifier, used by `kantan trigger` and passed to plugins as `KANTAN_MODULE_NAME` |
| `type` | string | **yes** | Module type (see below) |
| `placement` | string | **yes** | Position in the bar (see below) |
| `icon` | string | no | Icon name or character to display |
| `fonts` | object | no | Per-module font overrides (`text`, `icon`) |
| `style` | object | no | Per-module style overrides |
| `config` | object | no | Type-specific configuration |
| `interaction` | object | no | Hover and click behavior |
| `mask` | object | no | Menu bar masking configuration |
| `displays` | string/array | no | Restrict module to specific displays |

A module missing `name`, `type` or `placement`, with an unknown `type`, or whose `config` fails to parse is skipped and the error logged. The rest of the config still loads. So is a module named like one before it, in `config.yaml` and then `modules.d/` in filename order. The `text`, `clock` and `command` types require a `config` block.

## Module Types

The following module types are available:

| Type | Description |
|------|-------------|
| `text` | Static text display |
| `clock` | Date/time display |
| `power` | Battery status |
| `command` | Run a command and display output |
| `workspace` | Desktop/workspace indicator |
| `volume` | System volume (icon-only) |
| `wifi` | WiFi status (icon-only) |
| `bluetooth` | Bluetooth status (icon-only) |
| `icon` | Icon-only display |
| `drawer` | Collapsible section toggle |
| `focus` | Focus mode status |

## Placement

The `placement` field controls where the module appears in the bar. It is a required field.

| Value | Behavior |
|-------|----------|
| `left` | Left side of the bar, grows rightward |
| `right` | Right side of the bar, grows leftward |
| `notchleft` | Left of the notch, grows leftward (notched displays only) |
| `notchright` | Right of the notch, grows rightward (notched displays only) |

Within each placement, modules appear left to right in the order they are listed: the first `left` module sits at the left edge and the last `right` module at the right edge. Masked modules sit over their native items instead. Unmasked modules are laid out inward of them (see [Menu Bar Masking](masking.md)).

### Or-Wise Placement

Placement values can use `|` to pair a notch-side value with a non-notch fallback:

```yaml
placement: "notchright|right"    # right notch, with right side fallback
placement: "notchleft|left"      # left notch, with left side fallback
```

The notch-side value (`notchleft` / `notchright`) is used on notched displays. The non-notch value (`left` / `right`) is used on non-notched displays. Order is irrelevant — `"right|notchright"` behaves identically to `"notchright|right"`.

A placement of just `notchleft` or `notchright` hides the module on displays without a notch. Pairing a notch value with a non-notch value is the only useful combination. A pair of two non-notch values, such as `left|right`, uses the first on every display. A pair of two notch values, such as `notchleft|notchright`, uses the first on notched displays and hides the module on the others.

## Per-Module Fonts

Modules can override the global font configuration:

```yaml
fonts:
  text: "SF Mono:Regular:12"
  icon: "system:Font Awesome 6 Free:Solid:14"
```

The format is the same as the global `fonts` key (see [Bar Settings](bar.md)).

## Per-Module Style

Modules can override the global style configuration. Colours are [theme templates](themes.md#using-theme-colours) or hex values:

```yaml
style:
  fg: "{theme(text)}"
  bg: "{theme(surface0)}"
  shape: pill
  text:
    fg: "{theme(subtext1)}"
  icon:
    fg: "{theme(blue)}"
```

Theme templates resolve against the palette of the current appearance, so one block suits both light and dark mode. To give a mode values of its own, nest them under `light` and `dark` (see [Per-Mode Styles](themes.md#per-mode-styles)):

```yaml
style:
  light:
    shape: pill
    icon:
      fg: "{theme(blue)}"
  dark:
    shape: pill
    icon:
      fg: "{theme(sapphire)}"
```

A nested block takes every property from its modes: keys beside `light` and `dark` are ignored. A nested block with only one mode leaves the other mode on the global style.

### Style Properties

| Property | Description |
|----------|-------------|
| `fg` | Foreground color (applies to both text and icon if not overridden) |
| `bg` | Shape color. Drawn only when `shape` is set |
| `shape` | Background shape: `pill`, `box`, `underline`, or `overline` |
| `text.fg` | Text-specific foreground color |
| `icon.fg` | Icon-specific foreground color |

A module without a `shape` has no background of its own. A shape without a `bg` takes the theme's `shape` colour, or the global `bg` when no theme is set. `pill` and `box` add 6pt of horizontal and 3pt of vertical padding around the module's content. `underline` and `overline` draw a 2pt line along the bottom or top of the bar.

Foreground colours resolve in this order: a state style (e.g. the power module's `config.style`) or the colour a plugin's output sets, the module's `text.fg`/`icon.fg`, the module's `fg`, the global `text.fg`/`icon.fg`, then the global `fg`. Module colours are ignored in [native appearance](bar.md#native-appearance).

## Per-Module Display Filtering

Modules can restrict which displays they appear on, using the same format as the global `displays` setting:

```yaml
- name: my-module
  type: text
  placement: left
  displays: main
  config:
    value: "Primary only"
```

Or to target specific named displays:

```yaml
displays:
  - "Built-in Retina Display"
```

If not specified, the module appears on all displays that the bar is shown on.

## Interaction

The `interaction` field defines hover and click behavior.

### Hover Interaction

**Plain text tooltip:**
```yaml
interaction:
  hover:
    type: tooltip
    content: "CPU: {cpu} | Memory: {mem}"
```

**Rich tooltip using view DSL:**
```yaml
interaction:
  hover:
    type: tooltip
    view:
      type: vstack
      children:
        - type: text
          content: "CPU Usage"
        - type: text
          content: "{cpu}"
```

Tooltip content supports variable substitution using `{variableName}` syntax: `{value}` and `{icon}` are the module's current value and icon. Other variables come from the module: a plugin's `variables`, or those a built-in module sets, listed on its [page](../modules/index.md) (such as the volume module's `{state}`). Without `content` or `view`, the tooltip shows `{value}`. `type` defaults to `tooltip`.

### Click Interaction

**Menu (dropdown):**
```yaml
interaction:
  click:
    type: menu
    view:
      type: vstack
      children:
        - type: text
          content: "Menu Item 1"
```

**Popup (themed panel):**
```yaml
interaction:
  click:
    type: popup
    view:
      type: vstack
      children:
        - type: text
          content: "Popup content"
```

A `click` block without a `type` is a menu. For `menu` and `popup`, a `view` in the config takes priority. Without one, the view from the plugin's output is shown. Either updates while it's open, each time the module does.

**Toggle (run command):**
```yaml
interaction:
  click:
    type: toggle
```

`toggle` runs a `command` module's `config.toggle` command, then refreshes the module. It does nothing for other module types.

**Passthrough (clicks pass through to underlying window):**
```yaml
interaction:
  click:
    type: passthrough
```

A passthrough module takes no clicks. They reach whatever is underneath. Its `hover` tooltip still shows until a click hides it. Masked modules are passthrough unless they set a click type (see [Menu Bar Masking](masking.md#default-click-behavior)). Drawer modules get a `drawer` click that toggles the drawer.

### View DSL

The `view` field uses a declarative DSL to build UI hierarchies. See the [View DSL documentation](../view-dsl/index.md) for complete reference.

## Module Configuration Examples

The `config` object contains type-specific settings. Each module type has different configuration options:

**Clock module:**
```yaml
- name: clock
  type: clock
  placement: right
  config:
    format: "HH:mm"
    timezone: "America/New_York"  # optional
```

These keys go under a clock module's `config` key:

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `format` | string | — | **Required.** Date format string (e.g. `"HH:mm"`, `"EEE d MMM"`) |
| `timezone` | string | system | Optional timezone identifier (e.g. `"America/New_York"`). Unknown identifiers use the system timezone |

**Command module:**
```yaml
- name: sysmon
  type: command
  placement: right
  config:
    command: kantan-plugin-system-monitor
    output: json
    interval: 3
    timeout: 10          # command timeout in seconds (default: 10)
    settings:
      format: "{cpu}"

- name: caffeine
  type: command
  placement: right
  config:
    command: kantan-plugin-caffeine
    output: json
    interval: 0                              # no polling
    toggle: kantan-plugin-caffeine --toggle  # run by a toggle click
  interaction:
    click:
      type: toggle

- name: reminders
  type: command
  placement: right
  config:
    command: kantan-plugin-reminders
    output: json
    watch: kantan-plugin-reminders --watch   # long-lived watcher process
```

These keys go under a command module's `config` key:

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `command` | string | — | **Required.** Command to execute. Relative paths (`./` or `../`) are resolved relative to the config file directory, or the `modules.d/` directory for modules defined there |
| `output` | string | `text` | Output format: `text` or `json` |
| `interval` | number | `1` | Polling interval in seconds. `0` disables the timer (event-only), as does configuring `watch` |
| `timeout` | number | `10` | Command execution timeout in seconds |
| `settings` | object | — | Opaque settings passed to plugins via `KANTAN_SETTINGS` env var |
| `watch` | string | — | Long-lived watcher process command for event-driven updates |
| `toggle` | string | — | Command to run on toggle interaction |
| `launcher.path` | string | `/bin/sh` | Executable path for running commands |
| `launcher.args` | array | `["-c"]` | Arguments passed before the command string |

**Power module:**
```yaml
- name: battery
  type: power
  placement: right
  config:
    showLevel: true
    lowThreshold: 20
    icons:
      charging: "bolt-filled"
      plugged: "plug"
      level:
        - "battery-filled"
        - "battery-1-filled"
        - "battery-2-filled"
        - "battery-3-filled"
        - "battery-4-filled"
    style:
      charging: "{theme(green)}"   # shorthand: a colour sets fg
      low:
        fg: "{theme(red)}"
        icon:
          fg: "{theme(maroon)}"
```

These keys go under a power module's `config` key:

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `showLevel` | boolean | `false` | Show battery percentage text |
| `lowThreshold` | integer | `20` | Battery level (%) below which the low style activates |
| `icons.charging` | string | `bolt-filled` | Icon when charging |
| `icons.plugged` | string | `plug` | Icon when plugged in but not charging |
| `icons.level` | array | 5 battery icons | Icons for battery level, lowest charge first (indexed by charge %) |
| `style.charging` | string/object | — | Style override when charging |
| `style.plugged` | string/object | — | Style override when plugged in |
| `style.lowPowerMode` | string/object | — | Style override when Low Power Mode is active |
| `style.low` | string/object | — | Style override when battery is below `lowThreshold` |

Each per-state style override is either a colour, which sets `fg`, or an object with `fg`, `bg`, `icon.fg`, and `text.fg` properties. Colours are theme templates or hex values. Priority: charging > plugged > lowPowerMode > low. `lowPowerMode` and `low` styles only activate when the device is **not** plugged in.

**Drawer module:**
```yaml
- name: drawer
  type: drawer
  placement: right
  config:
    icons:
      show: "chevron-left"
      hide: "chevron-right"
```

These keys go under a drawer module's `config` key:

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `icons.show` | string | `box-align-right` | Icon while the drawer is closed |
| `icons.hide` | string | `box-align-left` | Icon while the drawer is open |

The drawer hides the modules in its own placement that sit inward of it: the modules listed before the drawer for `right` and `notchleft`, and those listed after it for `left` and `notchright`. Clicking the drawer, or an empty part of the bar on its side, opens and closes it. One drawer per side is supported.

**Volume module** (icon-only, no text):
```yaml
- name: volume
  type: volume
  placement: right
  config:
    icons:
      muted: "volume-off"
      level:
        - "volume-4"
        - "volume-2"
        - "volume"
      device:
        AirPods: "device-airpods"
        Headphones: "headphones"
```

These keys go under a volume module's `config` key:

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `icons.level` | array | `["volume-4", "volume-2", "volume"]` | Icons for volume levels (low to high) |
| `icons.muted` | string | `"volume-off"` | Icon when muted |
| `icons.device` | object | `{AirPods: device-airpods, Headphones: headphones}` | Output device name substrings (case-insensitive) mapped to icons, shown in place of the level icons while that device is the audio output. The longest matching key wins. Setting it replaces the defaults. `{}` disables device icons |

**WiFi module** (icon-only, no text):
```yaml
- name: wifi
  type: wifi
  placement: right
  config:
    icons:
      disconnected: "wifi-off"
      strength:
        - "wifi-1"
        - "wifi-2"
        - "wifi"
      hotspot: "circles-relation"
```

These keys go under a WiFi module's `config` key:

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `icons.strength` | array | `["wifi-1", "wifi-2", "wifi"]` | Icons for signal strength levels (weak to strong) |
| `icons.disconnected` | string | `"wifi-off"` | Icon when disconnected |
| `icons.hotspot` | string | `"circles-relation"` | Icon while connected to a personal hotspot, such as an iPhone's |

**Bluetooth module** (icon-only, no text):
```yaml
- name: bluetooth
  type: bluetooth
  placement: right
  config:
    icon: "bluetooth"
    disabledIcon: "bluetooth-off"
```

These keys go under a Bluetooth module's `config` key:

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `icon` | string | `"bluetooth"` | Icon when Bluetooth is on |
| `disabledIcon` | string | `"bluetooth-off"` | Icon when Bluetooth is off |

When Bluetooth is on but no devices are connected, the icon appears dimmed (inactive state). When at least one device is connected, the icon appears at full brightness.

**Focus module** (icon-only, hidden while no Focus mode is on):
```yaml
- name: focus
  type: focus
  placement: right
  config:
    icons:
      Work: "briefcase"
    style:
      Sleep: "{theme(lavender)}"
```

These keys go under a focus module's `config` key:

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `icons` | object | — | Focus mode name or identifier mapped to an icon. Unlisted modes use the module-level `icon` |
| `style` | object | — | Focus mode name or identifier mapped to a style override (a colour for `fg`, or an object with `fg`, `bg`, `icon.fg`, `text.fg`) |

The module-level `icon` defaults to `brain`. State is checked every 2 seconds. With Full Disk Access, kantan reads the active mode from the Do Not Disturb database for `icons`, `style` and the `{mode}` variable to follow. Without it, kantan only detects whether the menu bar's Focus indicator is shown. See [Focus](../modules/focus.md).

**Text module:**
```yaml
- name: greeting
  type: text
  placement: left
  icon: "mood-smile-beam"
  config:
    value: "Hello, world!"
```

These keys go under a text module's `config` key:

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `value` | string | — | **Required.** Static text to display |

**Icon module** (icon-only, no text):
```yaml
- name: separator
  type: icon
  placement: right
  icon: "point-filled"
```

The icon module has no configuration options. It displays only the module-level `icon` with no text.

**Workspace module:**
```yaml
- name: spaces
  type: workspace
  placement: left
  icon: "point-filled"
  config:
    type: native
    icons:
      - "circle-number-1"
      - "circle-number-2"
      - "circle-number-3"
```

These keys go under a workspace module's `config` key:

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `type` | string | `"native"` | Workspace provider: `native` (macOS Spaces), `aerospace` or `rift`. Unknown values use `native` |
| `icons` | array | `[]` | Icon names for each workspace (by index). Workspaces beyond this list use the module-level `icon` as fallback, then the workspace label (number). To use the same icon for every workspace, set the top level `icon` value and leave `config.icons` undefined/empty |
| `overflow` | object | disabled | Overflow/windowed view config (see below) |
| `rainbow` | object | disabled | Per-workspace colour assignment (see below) |
| `scrolling` | object | disabled | Show the windows of a Rift scrolling layout in place of the workspaces (see [Workspace](../modules/workspace.md)) |

**Overflow configuration** (nested under `config.overflow`):

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `enabled` | boolean | `false` | Enable overflow windowed view when workspace count exceeds `max` |
| `max` | integer | `5` | Maximum visible workspaces before overflow kicks in |
| `icon` | bool/string/object | `true` | Overflow indicator icons. `false` disables, a string sets both sides, or `{left: "...", right: "..."}` sets individually. Defaults to `‹`/`›` |
| `style` | object | — | Style override for overflow indicator segments |

**Rainbow configuration** (nested under `config.rainbow`):

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `enabled` | boolean | `false` | Enable per-workspace colour assignment |
| `random` | boolean | `true` | When true, colours are assigned in a deterministic random order avoiding adjacent repeats. When false, colours map index-wise |
| `colors` | array | `[]` | Colour values (hex or `{theme(...)}` templates) to assign to workspaces. Rainbow has no effect without colours |

See individual module type documentation for complete configuration options.

## Full Example

```yaml
- name: system-monitor
  type: command
  placement: right
  icon: "cpu"
  fonts:
    text: "SF Mono:Regular:12"
  config:
    command: kantan-plugin-system-monitor
    output: json
    interval: 3
    settings:
      format: "{cpu}"
  interaction:
    hover:
      type: tooltip
      content: "CPU: {cpu} | Memory: {mem}"
    click:
      type: menu
      view:
        type: vstack
        children:
          - type: text
            content: "System Monitor"
          - type: text
            content: "CPU: {cpu}"
          - type: text
            content: "Memory: {mem}"
  style:
    icon:
      fg: "{theme(blue)}"
```
