# Drawer

Type: `drawer`

An expandable module group that can show/hide adjacent modules. Drawers allow you to keep the status bar clean while providing access to additional modules on demand.

## Configuration

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `icons.show` | string | `"〈"` | Icon/text shown when drawer is collapsed (click to expand) |
| `icons.hide` | string | `"〉"` | Icon/text shown when drawer is expanded (click to collapse) |

## Behavior

Drawers are placement-aware and expand in different directions based on their position:

- **Left placement**: Drawer expands rightward
- **Right placement**: Drawer expands leftward

Which modules become drawer contents depends on the placement side:

- **Right / notchleft placement**: Modules that appear **before** the drawer in the configuration (within the same placement group) become the drawer's contents.
- **Left / notchright placement**: Modules that appear **after** the drawer in the configuration (within the same placement group) become the drawer's contents.

### Notch Placement Interaction

Drawers on `notchleft` or `notchright` placement will automatically hide notch-placed modules if an open drawer would occlude them. This prevents visual overlap in the notch area.

## Module Ordering

Order matters in your configuration. The drawer's position relative to other modules determines which modules are its contents:

```yaml
# These become drawer contents (before the right-side drawer)
- name: bluetooth
  type: bluetooth
  placement: right

- name: volume
  type: volume
  placement: right

# Drawer on the right side
- name: controls
  type: drawer
  placement: right
  config:
    icons:
      show: "〈"
      hide: "〉"
```

## Examples

Right-side drawer with system controls:

```yaml
- name: bluetooth
  type: bluetooth
  placement: right

- name: volume
  type: volume
  placement: right

- name: wifi
  type: wifi
  placement: right

- name: controls
  type: drawer
  placement: right
  config:
    icons:
      show: "〈"
      hide: "〉"
```

Left-side drawer with workspace info:

```yaml
- name: info
  type: drawer
  placement: left
  config:
    icons:
      show: "〉"
      hide: "〈"

- name: workspaces
  type: workspace
  placement: left
  config:
    type: aerospace

- name: clock
  type: clock
  placement: left
  config:
    format: "HH:mm"
```

Custom styled drawer icons:

```yaml
- name: tools
  type: drawer
  placement: right
  config:
    icons:
      show: chevron-left
      hide: chevron-right
  style:
    fg: "#007AFF"
```
