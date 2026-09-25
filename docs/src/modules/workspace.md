# Workspace

Type: `workspace`

Displays window manager workspace indicators. Supports native macOS spaces and the [aerospace](https://github.com/nikitabobko/AeroSpace) and [Rift](https://github.com/acsandmann/rift) tiling window managers.

## Configuration

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `type` | string | `"native"` | Workspace provider: `"native"`, `"aerospace"` or `"rift"` |
| `icons` | array | -- | Per-workspace icon names, indexed by workspace position |
| `overflow.enabled` | bool | `false` | Enable overflow mode to limit visible workspaces |
| `overflow.max` | int | `5` | Maximum visible workspaces before overflow kicks in |
| `overflow.icon` | bool/string/object | `true` | Overflow indicator icons (see below) |
| `overflow.style` | object | -- | Style overrides for overflow indicators |
| `rainbow.enabled` | bool | `false` | Enable rainbow colouring for workspace indicators |
| `rainbow.random` | bool | `true` | Randomise colour order (deterministic, no adjacent repeats) |
| `rainbow.colors` | array | -- | Colour palette for rainbow mode |
| `scrolling.enabled` | bool | `false` | Show the windows of a Rift scrolling layout instead of the workspaces (see [Scrolling](#scrolling)) |
| `scrolling.icon` | string | `"rectangle-vertical-filled"` | Icon for each window |
| `scrolling.icons` | object | -- | App → icon overrides |
| `scrolling.workspaces` | bool | `true` | Show pips for the other workspaces with windows |
| `scrolling.rainbow.enabled` | bool | `false` | Colour windows by app from a palette |
| `scrolling.rainbow.colors` | array | `rainbow.colors` | Palette for window colours |

### Icons

The `icons` array maps workspace indices (0-based) to icon names. Workspaces beyond the array length fall back to the module-level `icon` field (if set), or the workspace label (number/name).

```yaml
icon: point-filled        # Fallback for workspaces beyond the icons list
config:
  icons:
    - browser             # Workspace 1
    - code                # Workspace 2
    - terminal-2          # Workspace 3
```

### Overflow

When there are many workspaces, overflow mode limits how many are shown and adds directional indicators:

```yaml
config:
  overflow:
    enabled: true
    max: 5
    icon:                 # Custom directional indicators
      left: chevron-left
      right: chevron-right
```

The default overflow indicators are `‹` (left) and `›` (right).

The `icon` field accepts:
- `false` - hide overflow indicators entirely
- A string - use the same icon/text for both directions
- An object with `left` and `right` keys

### Rainbow

Rainbow mode assigns colours from a palette to each workspace indicator:

```yaml
config:
  rainbow:
    enabled: true
    random: true          # Deterministic shuffle avoiding adjacent repeats
    colors:
      - "#FF0000"
      - "#FF7F00"
      - "#FFFF00"
      - "#00FF00"
      - "#0000FF"
```

When `random` is true (default), colours are shuffled deterministically based on the workspace count, ensuring no two adjacent workspaces share the same colour.

### Scrolling

With Rift, the module can follow a scrolling layout instead of the workspaces. While the active workspace uses Rift's `scrolling` layout and has windows, each segment is one of its windows, in strip order: left to right by column, then top to bottom within a column. The scroll's selected window is highlighted. It stays highlighted while focus is on another display or a floating window. Floating windows aren't part of the scroll and aren't shown.

```yaml
config:
  type: rift
  scrolling:
    enabled: true
    icon: rectangle-vertical-filled   # Icon for each window (default)
    icons:                            # Per-app icons
      Ghostty: terminal-2
      company.thebrowser.Browser: world
    workspaces: true                  # Pips for the other workspaces (default)
    rainbow:
      enabled: true                   # Colour windows by app
```

The default window icon, a column, sets windows apart from workspaces at a glance. Each window takes at least the width of the active workspace's segment. Windows are spaced like workspaces. `icons` keys are app names or bundle identifiers, matched ignoring case, with the bundle identifier tried first. `overflow` applies to windows as it does to workspaces.

Windows take the active workspace's colour: its rainbow colour, or the module's. With `rainbow` enabled, each app's windows take a colour from `rainbow.colors`, or from the module's `rainbow.colors` when it lists none. A window keeps its colour as the scroll changes around it. Different apps can share a colour, more often with a small palette.

A column of pips to the left of the windows stands for the workspaces: those with windows, and the active one, top to bottom in workspace order, with the active one highlighted and each in its workspace's colour. It takes the width of a single dot. It's hidden while the active workspace is the only one with windows, or with `workspaces: false`.

Switching between workspaces and a scroll is animated. Each workspace's segment moves into its pip and back. The other workspaces fade. The windows slide out from the pips. Windows opening, closing, moving and being selected animate too.

## Behavior

The workspace module does not poll. Updates are driven by:

- **Native**: `NSWorkspace.activeSpaceDidChangeNotification` (via EventObserver)
- **Aerospace**: CLI triggers (`kantan trigger`)
- **Rift**: `workspace_changed` events from a `rift-cli subscribe mach` process kantan keeps running, so Rift needs no configuration. If Rift restarts, kantan reconnects and resynchronises automatically

The active workspace is highlighted. Inactive workspaces are dimmed. Changes animate. Segments fade as they come and go. The modules beside the workspace module move with it as it changes width. With *Reduce motion* on (*System Settings → Accessibility → Display*), changes are shown at once.

### Aerospace

kantan runs the `aerospace` CLI that shipped with the running AeroSpace.app: the one in the `bin` directory beside the app (release archive and Nix package layouts), then Homebrew's (`/opt/homebrew/bin` or `/usr/local/bin`), falling back to `aerospace` on kantan's `PATH`. No workspaces are shown while AeroSpace isn't running.

### Rift

kantan shows the virtual workspaces of the active display's macOS space, in Rift's workspace order, labelled with their `workspace_names` unless `icons` or a module `icon` is set. It runs the `rift-cli` installed beside the running `rift`. Nothing needs adding to kantan's `PATH`. The CLI always matches the running Rift, including after an upgrade restarts Rift from a new location. No workspaces are shown while Rift isn't running.

With `scrolling.enabled`, kantan subscribes to all of Rift's events instead of `workspace_changed` alone, as opening, closing, focusing and moving windows all change the scroll. Window title and stack changes are ignored, as are layout changes outside a scrolling layout, and a burst of events, such as scrolling the strip by gesture, refreshes the module once.

## Examples

Basic native macOS workspace indicator:

```yaml
- name: workspaces
  type: workspace
  placement: left
```

Aerospace workspace indicator with custom icons:

```yaml
- name: workspaces
  type: workspace
  placement: left
  icon: point-filled
  config:
    type: aerospace
    icons:
      - browser
      - code
      - terminal-2
      - message
      - music
```

Rift workspace indicator:

```yaml
- name: workspaces
  type: workspace
  placement: left
  icon: point-filled
  config:
    type: rift
```

Rift workspace indicator that shows the windows of scrolling workspaces:

```yaml
- name: workspaces
  type: workspace
  placement: left
  icon: point-filled
  config:
    type: rift
    scrolling:
      enabled: true
      icons:
        Ghostty: terminal-2
```

With overflow and rainbow:

```yaml
- name: workspaces
  type: workspace
  placement: left
  icon: point-filled
  config:
    type: native
    overflow:
      enabled: true
      max: 4
    rainbow:
      enabled: true
      colors:
        - "#FF6B6B"
        - "#4ECDC4"
        - "#45B7D1"
        - "#96CEB4"
        - "#FFEAA7"
```
