# Themes

A theme is a set of named colour palettes, kept apart from your config. Switching colour schemes means changing the theme. A theme can be shared between setups.

## How Themes Work

A theme has one or more **palettes**, each containing:

| Property | Required | Description |
|----------|----------|-------------|
| `fg` | **yes** | Default foreground colour (hex) |
| `bg` | **yes** | Default background colour (hex) |
| `shape` | no | Background colour for module shapes (pill, box, etc.) |
| `colors` | no | Named colour map for use with `{theme(...)}` templates |

When a theme is loaded, kantan resolves a palette for each appearance mode (light and dark). If no explicit `style` block is set in your config, the theme's `fg` and `bg` values are used as the global foreground and background colours automatically.

## Configuring a Theme

The `theme` key in your config accepts either a string or an object.

### Single Theme

Use a plain string to apply the same theme to both light and dark modes:

```yaml
theme: nordic
```

For themes with multiple flavours, select one with bracket syntax:

```yaml
theme: catppuccin[mocha]
```

When no flavour is specified on a flavoured theme, kantan picks each appearance mode's flavour from the theme's `defaults` mapping.

### Per-Mode Themes

To use different themes (or flavours) for light and dark mode, use an object:

```yaml
theme:
  light: catppuccin[latte]
  dark: catppuccin[mocha]
```

Each value follows the same format as the single-theme string, including bracket syntax for flavour selection.

## Theme File Formats

kantan supports three theme file formats, all written in YAML.

### Single Palette

The simplest format defines one palette used for both appearance modes:

```yaml
fg: "#e0e0e0"
bg: "#1a1a1a"
shape: "#2a2a2a"
colors:
  accent: "#4d9fff"
  warning: "#ff9f43"
  success: "#26de81"
```

### Mode-Aware

Defines separate palettes for light and dark modes in a single file:

```yaml
light:
  fg: "#333333"
  bg: "#f5f5f5"
  shape: "#e0e0e0"
  colors:
    accent: "#1e66f5"

dark:
  fg: "#e0e0e0"
  bg: "#1a1a1a"
  shape: "#2a2a2a"
  colors:
    accent: "#4d9fff"
```

If one mode is missing, the other is used for both.

### Flavoured

Defines multiple named palettes (flavours) with optional defaults:

```yaml
defaults:
  light: latte
  dark: mocha

flavours:
  latte:
    fg: "#4c4f69"
    bg: "#eff1f5"
    shape: "#ccd0da"
    colors:
      text: "#4c4f69"
      blue: "#1e66f5"
      # ...

  mocha:
    fg: "#cdd6f4"
    bg: "#1e1e2e"
    shape: "#313244"
    colors:
      text: "#cdd6f4"
      blue: "#89b4fa"
      # ...
```

The `defaults` block maps each appearance mode to a flavour name. A theme named without a bracket selector (e.g. `theme: catppuccin`) uses these defaults. A selected flavour (e.g. `theme: catppuccin[mocha]`) is used for both modes.

### Directory Themes

Instead of a single YAML file, a theme can be a directory containing one YAML file per flavour and an optional `defaults.yaml`:

```
themes/
  my-theme/
    defaults.yaml
    light.yaml
    dark.yaml
    custom.yaml
```

**`defaults.yaml`:**
```yaml
light: light
dark: dark
```

Each flavour file (e.g. `light.yaml`) contains a single palette:

```yaml
fg: "#333333"
bg: "#f5f5f5"
colors:
  accent: "#1e66f5"
```

It suits a large theme, with each flavour in its own file.

## Theme File Locations

kantan searches for theme files in order of priority:

1. `<config-dir>/themes/<name>.yaml` or `<config-dir>/themes/<name>/`
2. `$XDG_CONFIG_HOME/kantan/themes/<name>.yaml` or `<name>/`
3. Bundled themes (`<prefix>/share/themes/`)

Where `<config-dir>` is the directory containing your config file.

## Using Theme Colours

Once a theme is loaded, its named colours are available throughout your config via the `{theme(...)}` template syntax.

### In Style Blocks

Reference theme colours by name in any colour field:

```yaml
theme: catppuccin[mocha]

style:
  fg: "{theme(text)}"
  bg: "{theme(base)}"
```

The special names `fg`, `bg`, and `shape` resolve to the palette's top-level values:

```yaml
style:
  fg: "{theme(fg)}"
  bg: "{theme(bg)}"
```

### In Module Styles

Per-module style overrides also support theme templates:

```yaml
modules:
  - name: clock
    type: clock
    placement: right
    style:
      light:
        fg: "{theme(blue)}"
        bg: "{theme(surface0)}"
        shape: pill
      dark:
        fg: "{theme(blue)}"
        bg: "{theme(surface0)}"
        shape: pill
```

### Flat Style Shorthand

With a theme, a flat `style` block (without `light`/`dark` nesting) applies the same values to both modes. Theme templates resolve against each mode's active palette, which gives each mode its own colours:

```yaml
theme:
  light: catppuccin[latte]
  dark: catppuccin[mocha]

style:
  fg: "{theme(text)}"
  bg: "{theme(base)}"
```

`{theme(text)}` resolves to mocha's text colour in dark mode and to latte's in light mode.

### In Plugin Settings

Theme templates are also resolved within plugin settings strings, so plugins receive the resolved colour values:

```yaml
modules:
  - name: monitor
    type: command
    placement: left
    config:
      command: kantan-plugin-system-monitor
      settings:
        accent: "{theme(blue)}"
```

## Shape Colour

The `shape` palette property is the colour of module background shapes. A module with a shape (pill, box, underline, or overline) and no `bg` in its style uses the theme's `shape` colour. Shapes stay visible against the bar background without a colour set on each module.

## Bundled Themes

kantan ships with the following built-in themes:

- **catppuccin** - A pastel theme with four flavours: `latte` (light), `frappe`, `macchiato`, and `mocha` (dark). Defaults to `latte` for light mode and `mocha` for dark mode.

## Example: Full Configuration with Theme

```yaml
height: 36
padding: 12
cornerRadius: 8
blur: 3

theme:
  light: catppuccin[latte]
  dark: catppuccin[mocha]

style:
  fg: "{theme(text)}"
  bg: "{theme(base)}"

fonts:
  text: "SF Pro:Regular:13"

modules:
  - name: clock
    type: clock
    placement: right
    style:
      fg: "{theme(blue)}"
      bg: "{theme(surface0)}"
      shape: pill
    config:
      format: "HH:mm"

  - name: battery
    type: power
    placement: right
    style:
      fg: "{theme(green)}"
```
