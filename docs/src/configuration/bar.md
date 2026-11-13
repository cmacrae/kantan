# Bar Settings

Top-level configuration options control the status bar's appearance and behavior across all displays.

## Configuration Options

| Key | Type | Required | Default | Description |
|-----|------|----------|---------|-------------|
| `height` | integer | no | `33` | Bar height in pixels |
| `padding` | integer | no | `10` | Horizontal padding *around each module*, in pixels. Applied as left and right insets on every module (so the visible gap between two adjacent modules is `2 × padding`) |
| `iconTextSpacing` | integer | no | `5` | Spacing between icon and text in pixels |
| `fonts` | object | no | — | Font configuration (see below) |
| `style` | object | no | — | Colour configuration (see below) |
| `cornerRadius` | number | no | `0` | Corner radius of the bar background |
| `blur` | integer | no | `0` | Background blur level (0-6). 0 disables blur. Lower values produce a more transparent tint with prominent blur; higher values produce a more opaque tint with subtle blur |
| `gaps` | object | no | all `0` | Gaps around the bar (see below) |
| `autohide` | object | no | enabled, 0s delay | Hover-to-hide behavior (see below). Enabled even when this key is omitted: the bar hides while the cursor rests at the very top of the screen, over the native macOS menu bar |
| `displays` | string/array | no | `main` | Which displays to show the bar on |
| `theme` | string/object | no | — | Theme configuration (see below) |
| `modules` | array | no | — | Module definitions (see [Modules](modules.md)). When no modules are defined here or in `modules.d/`, kantan shows its welcome bar |

## Font Configuration

Fonts are specified under a `fonts:` key, with separate entries for text and icon fonts:

```yaml
fonts:
  text: "SF Pro:Regular:13"
  icon: "system:Font Awesome 6 Free:Solid:14"
```

The font descriptor format is `Name:Weight:Size`, `Name:Size` (weight defaults to regular), or just `Name` (weight defaults to regular, size defaults to 14). Fonts are looked up by name among the fonts installed on the system and those bundled with kantan.

Prefix a descriptor with `system:` to mark it as a system-installed font. kantan loads its bundled icon fonts for an icon font without the prefix. A global icon font with the prefix stops kantan loading them unless a module's icon font needs them (see [Icons](icons.md#custom-icon-fonts)).

Recognised weight names: `ultralight`, `thin`, `light`, `regular`, `medium`, `semibold` (or `demi-bold`), `bold`, `heavy` (or `extrabold`), `black`. A weight other than `regular` picks the nearest face in the named font's family: `Helvetica Neue:medium:13` renders Helvetica Neue Medium. When the family has no faces to choose from, the named font renders as is. Naming a face directly (e.g. `SFPro-Medium`) always works.

When no text font is specified, kantan defaults to Helvetica Neue at 13pt.

When no icon font is specified, kantan uses the bundled [tabler-icons](https://tabler.io/icons) font at 15pt. Icon names like `bell` or `bell-filled` are resolved automatically from this font.

## Style Configuration

The `style` section defines colours for light and dark appearance modes:

```yaml
style:
  light:
    fg: "#f0f0f0"
    bg: "#333333"
    text:
      fg: "#222222"
    icon:
      fg: "#0000ff"
  dark:
    fg: "#e0e0e0"
    bg: "#1a1a1a"
    text:
      fg: "#cccccc"
    icon:
      fg: "#4d9fff"
```

### Style Mode Properties

| Property | Description |
|----------|-------------|
| `fg` | Foreground colour (hex, applies to both text and icon unless overridden) |
| `bg` | Bar background colour (hex), also used as the background of module shapes that set no `bg` of their own |
| `text.fg` | Text-specific foreground colour (hex) |
| `icon.fg` | Icon-specific foreground colour (hex) |

Colours are hex strings, `#rrggbb` or `#rrggbbaa` with alpha, with or without the `#`; quote them so YAML reads them as strings. Other lengths aren't read as colours. Module shapes (`shape`) are set per module, not in the global style (see [Per-Module Style](modules.md#per-module-style)).

When no theme is set and a `style` block is provided, both `light` and `dark` blocks are required and must each contain `fg` and `bg`. If `style` is omitted entirely (and no theme is set), kantan uses its native macOS appearance instead (see below).

When a theme is set, a `style` block replaces the theme's default `fg` and `bg` as a pair. Set both: a missing `fg` falls back to white and a missing `bg` to black.

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

In native appearance, kantan ignores per-module `style` colours but applies the colours in a plugin's `style` output. With `blur` set, the bar uses the blur effect with a black tint instead of the `headerView` material.

## Theme Configuration

The `theme` key loads a colour palette from a theme file. See [Themes](themes.md) for full details on theme file formats, template syntax, and creating custom themes.

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
3. Bundled themes (`<prefix>/share/themes/`, or the directory given by `--themes-dir`)

A theme that can't be found or loaded stops the whole config loading.

## Gaps Configuration

The `gaps` key controls spacing around the bar edges:

```yaml
gaps:
  top: 5
  bottom: 0
  left: 10
  right: 10
```

Values are whole numbers of points. All default to `0`. Negative values are clamped to `0`. `left` and `right` inset the bar from the screen edges. `top` lowers it from the top of the screen.

## Auto-Hide Configuration

The `autohide` key controls the bar's hover-to-hide behavior. With autohide enabled, the bar hides only while the mouse cursor is at the very top of the screen. The native macOS menu bar underneath is then free to use. Once the cursor moves back below the menu bar, the bar fades back in.

```yaml
autohide:
  enabled: true
  delay: 0.5
```

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `enabled` | boolean | `true` | Whether the bar should hide itself while the cursor is at the top of the screen |
| `delay` | number | `0.0` | Seconds the cursor must dwell at the top edge before the bar hides, clamped to 0-5. With `delay: 0` (the default) the bar hides immediately on hover |

### How it works

1. **Visible state (default).** With `enabled: true`, the bar is shown with its modules updating and taking clicks.
2. **Hide trigger.** kantan watches the mouse position on each screen. When the cursor enters the top 4 px of the screen the bar is on (its "trigger zone"), a hide is scheduled. Multi-display setups are evaluated per-screen. A cursor arriving from a display above doesn't trigger a hide until it has left the trigger zone once.
3. **Hide delay.** If `delay > 0`, the cursor must stay in the trigger zone for `delay` seconds before the bar fades out. Moving the cursor out of the trigger zone before the delay elapses cancels the pending hide. Setting `delay: 0` (the default) hides the bar immediately on hover.
4. **Reveal trigger.** Once hidden, the bar fades back in as soon as the cursor moves below the menu bar region or off the screen. There is no reveal delay.

> Autohide is enabled by default: omitting the `autohide` key is equivalent to `autohide: { enabled: true, delay: 0 }`. The bar hides whenever the cursor reaches the very top of the screen, where macOS reveals its own menu bar. To keep the bar always visible, set `autohide: { enabled: false }`.

## Multi-Display Support

The `displays` option controls which connected displays show the kantan bar:

### Display Modes

**Show on the main display only (default):**
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

Display names must match exactly as reported by macOS. Use the system Display preferences to see the exact names. Any string other than `all` is treated as `main`.

`main` is the display macOS reports as main (`NSScreen.main`), resolved when the bar is built and whenever the display configuration changes.

### Per-Module Display Filtering

Modules can also specify a `displays` key to restrict which displays they appear on (using the same format). See the [Modules](modules.md) documentation.

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
