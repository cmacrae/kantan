# Bar Settings

Top-level configuration options control the status bar's appearance and behavior across all displays.

## Configuration Options

| Key | Type | Required | Default | Description |
|-----|------|----------|---------|-------------|
| `height` | integer | no | `33` | Bar height in pixels |
| `padding` | integer | no | `10` | Horizontal padding *around each module*, in pixels. Applied as left and right insets on every module (so the visible gap between two adjacent modules is `2 × padding`) |
| `iconTextSpacing` | integer | no | `5` | Spacing between icon and text in pixels |
| `fonts` | object | no | — | Font configuration (see below) |
| `style` | object | no | — | Color and shape configuration (see below) |
| `cornerRadius` | number | no | `0` | Corner radius of the bar background |
| `blur` | integer | no | `0` | Background blur level (0-6). 0 disables blur. Lower values produce a more transparent tint with prominent blur; higher values produce a more opaque tint with subtle blur |
| `gaps` | object | no | all `0` | Gaps around the bar (see below) |
| `autohide` | object | no | enabled, 0s delay | Hover-to-hide behavior (see below). Enabled even when this key is omitted: the bar hides while the cursor rests at the very top of the screen, over the native macOS menu bar |
| `displays` | string/array | no | `main` | Which displays to show the bar on |
| `theme` | string/object | no | — | Theme configuration (see below) |

## Font Configuration

Fonts are specified under a `fonts:` key, with separate entries for text and icon fonts:

```yaml
fonts:
  text: "SF Pro:Regular:13"
  icon: "system:Font Awesome 6 Free:Solid:14"
```

The font descriptor format is `Name:Weight:Size`, `Name:Size` (weight defaults to regular), or just `Name` (weight defaults to regular, size defaults to 14). Prefix with `system:` to use a system-installed font; otherwise the font is resolved from bundled fonts.

Supported weight names: `ultralight`, `thin`, `light`, `regular`, `medium`, `semibold` (or `demi-bold`), `bold`, `heavy` (or `extrabold`), `black`.

When no text font is specified, kantan defaults to Helvetica Neue at 13pt.

When no icon font is specified, kantan uses the bundled [tabler-icons](https://tabler.io/icons) font at 14pt. Icon names like `bell` or `bell-filled` are resolved automatically from this font.

## Style Configuration

The `style` section defines colours for light and dark appearance modes:

```yaml
style:
  light:
    fg: "#f0f0f0"
    bg: "#333333"
    shape: pill
    text:
      fg: "#222222"
    icon:
      fg: "#0000ff"
  dark:
    fg: "#e0e0e0"
    bg: "#1a1a1a"
    shape: box
    text:
      fg: "#cccccc"
    icon:
      fg: "#4d9fff"
```

### Style Mode Properties

| Property | Description |
|----------|-------------|
| `fg` | Foreground color (hex, applies to both text and icon unless overridden) |
| `bg` | Background color (hex) |
| `shape` | Module background shape: `pill`, `box`, `underline`, or `overline` |
| `text.fg` | Text-specific foreground color (hex) |
| `icon.fg` | Icon-specific foreground color (hex) |

When no theme is set and a `style` block is provided, both `light` and `dark` blocks are required and must each contain `fg` and `bg`. If `style` is omitted entirely (and no theme is set), kantan uses its native macOS appearance instead (see below).

### Flat Style

A flat style block (without `light`/`dark` nesting) applies the same values to both modes. It suits theme templates, whose `{theme(...)}` values resolve against the active palette for each mode:

```yaml
style:
  fg: "{theme(text)}"
  bg: "{theme(surface)}"
```

A flat style block can also be used without a theme using plain hex colours (both `fg` and `bg` are still required).

### Native Appearance

If neither `theme` nor `style` colours are set, kantan uses the native macOS appearance of menu bar elements. The bar background is a translucent vibrancy effect (the system `headerView` material). Foreground colours follow light and dark mode through the system label colour. Module backgrounds are transparent.

## Theme Configuration

The `theme` key loads a colour palette from a theme file. See [Themes](/docs/configuration/themes) for full details on theme file formats, template syntax, and creating custom themes.

**Single theme (same for both modes):**
```yaml
theme: catppuccin[mocha]
```

**Per-mode themes:**
```yaml
theme:
  light: catppuccin[latte]
  dark: catppuccin[mocha]
```

Theme files are searched in this order:
1. `<config-dir>/themes/<name>.yaml` or `<config-dir>/themes/<name>/`
2. `$XDG_CONFIG_HOME/kantan/themes/<name>.yaml` or `<name>/`
3. Bundled themes (`<prefix>/share/themes/`)

## Gaps Configuration

The `gaps` key controls spacing around the bar edges:

```yaml
gaps:
  top: 5
  bottom: 0
  left: 10
  right: 10
```

All values default to `0` and are clamped to non-negative integers.

## Auto-Hide Configuration

The `autohide` key controls the bar's hover-to-hide behavior. When autohide is enabled, the bar is visible normally and hides itself only while the mouse cursor is at the very top of the screen — getting out of the way so you can interact with the native macOS menu bar underneath. As soon as the cursor moves away from the top edge, the bar slides back into view.

```yaml
autohide:
  enabled: true
  delay: 0.5
```

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `enabled` | boolean | `true` | Whether the bar should hide itself while the cursor is at the top of the screen |
| `delay` | number | `0.0` | Seconds the cursor must dwell at the top edge before the bar hides (0-5). With `delay: 0` (the default) the bar hides immediately on hover |

### How it works

1. **Visible state (default).** When `enabled: true`, the bar is shown normally; the modules update and the bar is fully interactive.
2. **Hide trigger.** kantan watches the mouse position on each screen. When the cursor enters the top 4 px of the screen the bar is on (its "trigger zone"), a hide is scheduled. Multi-display setups are evaluated per-screen.
3. **Hide delay.** If `delay > 0`, the cursor must stay in the trigger zone for `delay` seconds before the bar fades out. Moving the cursor out of the trigger zone before the delay elapses cancels the pending hide. Setting `delay: 0` (the default) hides the bar immediately on hover.
4. **Reveal trigger.** Once hidden, the bar fades back in as soon as the cursor moves below the menu bar region. There is no reveal delay; the bar follows the cursor.

> Autohide is enabled by default: omitting the `autohide` key is equivalent to `autohide: { enabled: true, delay: 0 }`. The bar hides whenever the cursor reaches the very top of the screen, where macOS reveals its own menu bar. To keep the bar always visible, set `autohide: { enabled: false }`.

## Multi-Display Support

The `displays` option controls which connected displays show the kantan bar:

### Display Modes

**Show on primary display only (default):**
```yaml
displays: main
```

**Show on all connected displays:**
```yaml
displays: all
```

**Show on specific named displays:**
```yaml
displays:
  - "LG UltraFine"
  - "Built-in Retina Display"
```

Display names must match exactly as reported by macOS. Use the system Display preferences to see the exact names.

### Per-Module Display Filtering

Modules can also specify a `displays` key to restrict which displays they appear on (using the same format). See the [Modules](/docs/configuration/modules) documentation.

### Screen Change Detection

kantan automatically detects display configuration changes (displays added, removed, or rearranged). The bar will appear or disappear on affected displays without requiring a restart.

## Example Configuration

```yaml
height: 36
padding: 12
iconTextSpacing: 6
cornerRadius: 8
blur: 3
displays: all

fonts:
  text: "SF Pro:Regular:13"
  icon: "system:Font Awesome 6 Free:Solid:14"

gaps:
  top: 5
  left: 10
  right: 10

autohide:
  enabled: true
  delay: 0.5

style:
  light:
    bg: "#ffffff"
    fg: "#000000"
  dark:
    bg: "#000000"
    fg: "#ffffff"

modules:
  # Module configurations...
```
