# Power

Type: `power`

Displays battery level and charging state. Uses IOKit to monitor battery information in real-time.

## Configuration

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `showLevel` | bool | `false` | Show battery percentage text |
| `lowThreshold` | int | `20` | Battery level (%) below which the low style applies |
| `icons.charging` | string | `"bolt-filled"` | Icon when charging |
| `icons.plugged` | string | `"plug"` | Icon when plugged in but not charging |
| `icons.level` | array | see below | Icons for battery levels (low to full) |
| `style.charging` | string/object | -- | Style override when charging |
| `style.plugged` | string/object | -- | Style override when plugged in |
| `style.lowPowerMode` | string/object | -- | Style override when Low Power Mode is active (on battery) |
| `style.low` | string/object | -- | Style override when battery is below `lowThreshold` (on battery) |

### Default Level Icons

The default `icons.level` array contains five battery states from empty to full:

```yaml
icons:
  level:
    - battery-filled      # Empty
    - battery-1-filled    # Low
    - battery-2-filled    # Medium
    - battery-3-filled    # High
    - battery-4-filled    # Full
```

### Style Overrides

Power state styles can be specified as a simple string (sets the foreground colour) or an expanded object:

```yaml
style:
  charging: "#00FF00"     # Shorthand: sets fg colour

  low:                    # Expanded form
    fg: "#FF0000"
    bg: "#330000"
    icon:
      fg: "#FF3333"
    text:
      fg: "#FF6666"
```

Style priority (highest to lowest): charging, plugged, lowPowerMode, low.

## Behavior

The power module is event-driven and updates automatically when:

- Battery percentage changes
- Charging state changes (plugged in/unplugged)
- Power source changes
- Low Power Mode is toggled

## Examples

Basic battery display with percentage:

```yaml
- name: battery
  type: power
  placement: right
  config:
    showLevel: true
```

Icon-only battery indicator (no percentage text):

```yaml
- name: battery
  type: power
  placement: right
```

Custom icons and low battery styling:

```yaml
- name: battery
  type: power
  placement: right
  config:
    showLevel: true
    lowThreshold: 15
    icons:
      charging: bolt-filled
      plugged: plug
      level:
        - battery-filled
        - battery-1-filled
        - battery-2-filled
        - battery-3-filled
        - battery-4-filled
    style:
      charging: "#34C759"
      low: "#FF3B30"
```

With menu bar item masking:

```yaml
- name: battery
  type: power
  placement: right
  config:
    showLevel: true
  mask:
    name: Battery
```
