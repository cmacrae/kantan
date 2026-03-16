# Workspace

Type: `workspace`

Displays window manager workspace indicators. Supports native macOS spaces and the aerospace tiling window manager.

## Configuration

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `type` | string | `"native"` | Workspace provider: `"native"` or `"aerospace"` |
| `icons` | array | -- | Per-workspace icon names, indexed by workspace position |
| `aerospacePath` | string | auto-detected | Path to the `aerospace` binary (aerospace provider only) |
| `overflow.enabled` | bool | `false` | Enable overflow mode to limit visible workspaces |
| `overflow.max` | int | `5` | Maximum visible workspaces before overflow kicks in |
| `overflow.icon` | bool/string/object | `true` | Overflow indicator icons (see below) |
| `overflow.style` | object | -- | Style overrides for overflow indicators |
| `rainbow.enabled` | bool | `false` | Enable rainbow colouring for workspace indicators |
| `rainbow.random` | bool | `true` | Randomise colour order (deterministic, no adjacent repeats) |
| `rainbow.colors` | array | -- | Colour palette for rainbow mode |

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

## Behavior

The workspace module does not poll. Updates are driven by:

- **Native**: `NSWorkspace.activeSpaceDidChangeNotification` (via EventObserver)
- **Aerospace**: CLI triggers (`kantan trigger`)

The active workspace is highlighted; inactive workspaces are shown in a dimmed state.

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
