# Icons

kantan bundles [tabler-icons](https://tabler.io/icons), a comprehensive open-source icon set with over 5,800 icons. When no custom icon font is configured, tabler-icons is the default icon font and icon names are resolved automatically.

## Naming Convention

Tabler-icons ships in two variants: **outline** and **filled**. kantan bundles both as separate font files and picks between them by name:

| Suffix | Variant | Example |
|--------|---------|---------|
| *(none)* | Outline | `bell` |
| `-filled` | Filled | `bell-filled` |

The outline variant renders the icon as a stroke drawing. The filled variant renders a solid shape. Both are available for every icon in the set.

## Using Icons in Config

Icons are set via the `icon` field on any module:

```yaml
- name: clock
  type: clock
  placement: right
  icon: clock
  config:
    format: "HH:mm"
```

Some module types also accept icon names within their `config` block. For example, the power module uses icons for battery levels and charging states:

```yaml
- name: battery
  type: power
  placement: right
  config:
    icons:
      charging: "bolt-filled"
      plugged: "plug"
      level:
        - "battery-filled"
        - "battery-1-filled"
        - "battery-2-filled"
        - "battery-3-filled"
        - "battery-4-filled"
```

The drawer module uses icons for its open/close states (defaults are Unicode angle brackets `〈` and `〉`):

```yaml
- name: drawer
  type: drawer
  placement: right
  config:
    icons:
      show: "chevron-left"
      hide: "chevron-right"
```

The volume module supports level, muted, and device-specific icons:

```yaml
- name: volume
  type: volume
  placement: right
  config:
    icons:
      muted: "volume-off"
      level:
        - "volume-4"      # Low
        - "volume-2"      # Medium
        - "volume"        # High
      device:
        AirPods: "device-airpods"
        Headphones: "headphones"
```

The WiFi module supports signal strength, disconnected, and SSID-specific icons:

```yaml
- name: wifi
  type: wifi
  placement: right
  config:
    icons:
      disconnected: "wifi-off"
      strength:
        - "wifi-1"        # Weak
        - "wifi-2"        # Fair
        - "wifi"          # Strong
      ssid:
        "Home Network": "home-wifi"
        iPhone: "circles-relation"
```

The Bluetooth module uses top-level config keys for its on/off icons:

```yaml
- name: bluetooth
  type: bluetooth
  placement: right
  config:
    icon: "bluetooth"
    disabledIcon: "bluetooth-off"
```

## Non-Icon Characters

The `icon` field also accepts:

- **Unicode characters** -- any literal Unicode character is rendered as-is
- **Emoji** -- emoji characters are rendered using the system emoji font

A value that matches no tabler-icons glyph name passes through unchanged. Named icons and literal characters can be mixed.

## Dynamic Icon Sizing

Different icon glyphs have different visual proportions within their font's em square. A tall narrow glyph like `antenna-bars-5` occupies a different amount of vertical space than a square glyph like `square-filled`.

At startup, kantan measures every glyph's bounding box and scales each icon so its visual height is 85% of the em square. The scale is capped at 1.6x, which keeps tiny decorative glyphs from being blown up. Icons look the same size in the bar whatever their proportions.

## Custom Icon Fonts

You can use a different icon font by setting the `icon` key under `fonts` at the global or per-module level:

**Global:**

```yaml
fonts:
  icon: "system:Font Awesome 6 Free:Solid:14"
```

**Per-module:**

```yaml
- name: my-module
  type: text
  placement: left
  fonts:
    icon: "system:Font Awesome 6 Free:Solid:14"
```

The `system:` prefix tells kantan to use a font installed on the system rather than a bundled font. See [Bar Settings](/docs/configuration/bar) for the full font descriptor format.

When a custom icon font is set, icon name resolution against tabler-icons is still attempted for any modules that do not override the icon font. Modules with a custom icon font receive the raw `icon` string as a literal glyph.

## Browsing Available Icons

The full tabler-icons catalogue is at [tabler.io/icons](https://tabler.io/icons). Search for an icon by keyword and use its name in your kantan config, with `-filled` appended for the filled variant.
