# kantan-plugin-rift-indicator

A layout indicator for the [Rift](https://github.com/acsandmann/rift) window manager, for [kantan](https://github.com/cmacrae/kantan). Shows a single icon for the layout mode of the active workspace, with an icon and style per layout. It is meant to sit over Rift's own menu bar icon, with clicks passed through to Rift's menu.

## Installation

This plugin is bundled with kantan and requires no separate installation. It is included in both the [Nix flake](https://github.com/cmacrae/kantan) default package and the Homebrew `kantan` formula. The `kantan-without-plugins` variant (available via both Nix and Homebrew) does not include this plugin.

## Features

- **Per-layout icons and colours** — Configurable for each of Rift's layout modes
- **Event-driven** — Updates as soon as the workspace or its layout mode changes, with no polling
- **Hidden without Rift** — The module hides while Rift isn't running
- **No `PATH` dependency** — Runs the `rift-cli` installed beside the running `rift`, so it always matches the running Rift and needs nothing added to kantan's `PATH`

## How It Works

The plugin asks the running Rift for the active display's workspaces with `rift-cli query workspaces` and shows the layout mode of the active one.

In watch mode it keeps a `rift-cli subscribe mach workspace_changed` subscription open. Rift reports both workspace switches and layout mode changes as `workspace_changed`, and the plugin runs `kantan trigger <name> refresh` for each event. When Rift quits, the plugin refreshes (hiding the module) and resubscribes once Rift is running again, retrying after 1, 2, 4, 8 and then every 16 seconds.

### Layouts

| Layout mode    | Name           | Default icon           |
|----------------|----------------|------------------------|
| `traditional`  | `Traditional`  | `layout-columns`       |
| `bsp`          | `BSP`          | `layout-board-split`   |
| `floating`     | `Floating`     | `picture-in-picture`   |
| `stack`        | `Stack`        | `stack-2`              |
| `master_stack` | `Master Stack` | `layout-sidebar-right` |
| `scrolling`    | `Scrolling`    | `carousel-horizontal`  |

A layout mode not in this table, or one whose icon is set to `""`, shows the module's own `icon`.

### Template Variables

| Variable        | Example        | Description                         |
|-----------------|----------------|-------------------------------------|
| `{layout}`      | `Master Stack` | Name of the active layout mode      |
| `{layout_mode}` | `master_stack` | Identifier of the active layout mode |
| `{workspace}`   | `2`            | Name of the active workspace        |

## Configuration

Copy the example config into your kantan `modules.d/` directory:

```yaml
name: rift-indicator
type: command
placement: right
mask:
  name: rift
config:
  command: kantan-plugin-rift-indicator
  output: json
  interval: 0
  watch: kantan-plugin-rift-indicator --watch
  settings:
    icons:
      traditional: layout-columns
      bsp: layout-board-split
      floating: picture-in-picture
      stack: stack-2
      master_stack: layout-sidebar-right
      scrolling: carousel-horizontal
    style:
      bsp: "{theme(blue)}"
      floating: "{theme(peach)}"
      master_stack:
        icon:
          fg: "{theme(mauve)}"
      scrolling: "{theme(teal)}"
interaction:
  hover:
    type: tooltip
    content: "{workspace} · {layout}"
  click:
    type: passthrough
```

### Plugin Settings

Both settings are keyed by layout mode identifier (e.g. `master_stack`) or name (e.g. `Master Stack`); the identifier wins when both are set.

| Setting | Default | Description |
|---------|---------|-------------|
| `icons` | See [Layouts](#layouts) | Layout → icon |
| `style` | -- | Layout → style override. Layouts without an entry use the module's `style` |

Like the [focus module's mode styles](/docs/modules/focus#mode-styles), each `style` value is either a colour string (sets `fg`) or an object with `fg`, `bg`, `icon.fg` and `text.fg`; colours can be hex or `{theme(name)}` templates.

### Module Options

| Field               | Value                                   | Description                                          |
|---------------------|-----------------------------------------|------------------------------------------------------|
| `config.interval`   | `0`                                     | No polling; the watch process drives every refresh   |
| `config.watch`      | `kantan-plugin-rift-indicator --watch`  | Keeps the Rift subscription open                     |
| `mask.name`         | `rift`                                  | Covers Rift's own menu bar icon                      |
| `interaction.click` | `passthrough`                           | Opens Rift's own menu when the module sits over it   |

## Covering Rift's Menu Bar Icon

The example config masks Rift's own menu bar icon with `mask: {name: rift}`, and `click: passthrough` opens Rift's menu. Masking a third-party item needs [Accessibility permission](/docs/configuration/masking#granting-accessibility), which kantan asks for when it starts; until it's granted, a masked module stays hidden. Without a mask, the module is placed like any other right-hand module.

By default Rift's icon draws one cell for each workspace with windows plus the active one. It widens when you switch to an empty workspace. The mask moves with it. Setting `mode = "active"` under `[settings.ui.menu_bar]` in Rift's config draws only the active workspace, which keeps the icon, and the module over it, in one place.
