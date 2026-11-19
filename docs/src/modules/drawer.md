# Drawer

Type: `drawer`

An expandable module group that can show/hide adjacent modules. Drawers allow you to keep the status bar clean while providing access to additional modules on demand.

## Configuration

These keys go under the module's `config` key:

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `icons.show` | string | `"box-align-right"` | Icon/text shown when drawer is collapsed (click to expand) |
| `icons.hide` | string | `"box-align-left"` | Icon/text shown when drawer is expanded (click to collapse) |

The default icons suit a drawer on the right. For one on the left, swap them.

## Behavior

Drawers are placement-aware and expand in different directions based on their position:

- **Left placement**: Drawer expands rightward
- **Right placement**: Drawer expands leftward

Which modules become drawer contents depends on the placement side:

- **Right / notchleft placement**: Modules that appear **before** the drawer in the configuration (within the same placement group) become the drawer's contents.
- **Left / notchright placement**: Modules that appear **after** the drawer in the configuration (within the same placement group) become the drawer's contents.

Drawer contents start hidden. Clicking the drawer toggles them. So does clicking an empty part of the bar on the drawer's half of the screen. Such a click never reaches a native menu bar item the bar has no module over. A drawer's click is always this one: an `interaction.click` in its config is ignored. Its `interaction.hover` works as any module's does.

The bar has at most one drawer per side: `left` and `notchleft` placements share the left drawer, and `right` and `notchright` the right one. When a side has several, the first in the configuration is the one that toggles.

### Sharing Room With the Notch's Modules

A drawer's contents at `left` or `right` open toward the notch, where the `notchleft` and `notchright` modules are. When the two would meet, within 12 points of each other, whichever is being used keeps its place:

- **Opening the drawer** over the modules beside the notch slides them behind the notch. They slide back out when the drawer closes, or once there is room for both.
- **Using a module beside the notch** closes the drawer it grows into: a module whose [hover reveals](../configuration/modules.md#hover-interaction) more of it, while the pointer is over it or, with `persist`, while its popup is open. The drawer opens again once the module is let go.

Closing a drawer this way is only for the moment: its icon shows it closed, and it comes back as it was. Opening or closing the drawer yourself in the meantime settles it.

### Masked Modules in a Drawer

A right-side drawer can hold [masked](../configuration/masking.md) modules. They fold away with it, and while they are folded a click on the bar where they were toggles the drawer. It doesn't reach the native items underneath.

A masked module sits over its native item. The items have to be where the open drawer shows them: left of the toggle. kantan makes the room by holding a slot in the native menu bar under the toggle and the modules after it. See [Masked Modules in a Drawer](../configuration/masking.md#masked-modules-in-a-drawer) for a config and what to arrange.

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
      show: box-align-left
      hide: box-align-right

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
    fg: "{theme(blue)}"
```
