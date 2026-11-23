# Styling

All nodes in the View DSL support common styling properties that control their appearance and layout.

## Common Properties

These properties can be applied to any node type. They apply in tooltips and popups; [native menus](nodes.md#native-menu-rendering) ignore them, including `visible`.

| Property | Type | Description |
|----------|------|-------------|
| `padding` | number or object | Uniform padding (number), or per-edge object with `top`, `leading`, `bottom`, `trailing` keys |
| `frame` | object | Frame constraints: `w`, `h`, `minW`, `maxW`, `minH`, `maxH` |
| `opacity` | number | Opacity from 0.0 (transparent) to 1.0 (opaque) |
| `background` | string | Background colour (hex, named, or template) drawn behind the node, including its padding |
| `cornerRadius` | number | Corner rounding of the `background`, in points |
| `visible` | string | Visibility controlled by a bare variable name (e.g., `"show_details"`) |

They are applied in this order: `visible`, `padding`, `frame`, `background`, `opacity`. `background` covers the padding and frame. `opacity` fades the background too.

A size, spacing or padding further than 10,000 points from zero is drawn as 10,000. A tooltip or popup is no larger than its display.

## Colours

Colours can be specified as hex strings or as named system colours.

**Hex format** (the `#` is optional):

- **RGB**: `"#RRGGBB"` (e.g., `"#FF0000"` for red)
- **RGBA**: `"#RRGGBBAA"` (e.g., `"#FF000080"` for half-transparent red)

Other lengths, such as `#RGB`, are not recognised.

**Named colours:**

`primary`, `secondary`, `accent`, `red`, `orange`, `yellow`, `green`, `blue`, `purple`, `pink`, `gray` (or `grey`), `white`, `black`, `clear`

Names are case-insensitive. These are system colours. All except `white`, `black`, and `clear` adapt to light/dark mode automatically. `accent` is the system accent colour.

Colour properties can contain templates (e.g. `"{status_color}"`). A value that resolves to an unrecognised colour falls back to the property's default: the default text colour for `text` and `icon`, the accent colour for `progress`, `gauge`, and `badge` backgrounds, and no colour for shapes and `background`.

**Theme colours:**

When a [theme](../configuration/themes.md) is configured, you can reference palette colours with `{theme(name)}` syntax:

```json
{
  "type": "text",
  "content": "Themed",
  "color": "{theme(accent)}"
}
```

See [Templates & Data](templates.md#theme-colour-templates) for details.

**Example:**
```json
{
  "type": "text",
  "content": "Error",
  "color": "#FF3B30"
}
```

```json
{
  "type": "text",
  "content": "Subtle",
  "color": "secondary"
}
```

## Padding

Padding can be specified as a single number (uniform padding) or as an object with per-edge keys `top`, `leading`, `bottom`, `trailing`. Any omitted key defaults to `0`.

**Uniform padding:**
```json
{
  "type": "vstack",
  "padding": 12,
  "children": [
    { "type": "text", "content": "Padded content" }
  ]
}
```

**Edge-specific padding:**
```json
{
  "type": "vstack",
  "padding": { "top": 8, "leading": 16, "bottom": 8, "trailing": 16 },
  "children": [
    { "type": "text", "content": "Custom padding" }
  ]
}
```

Positional arrays (e.g. `[8, 16, 8, 16]`) are not supported. kantan uses
RTL-safe `leading`/`trailing` edges, which CSS's `top, right, bottom, left`
order can't express. Use the named-key object form instead.

## Frame Sizing

The `frame` property controls size constraints. Property names use short forms:

| Frame Property | Description |
|---------------|-------------|
| `w` | Fixed width |
| `h` | Fixed height |
| `minW` | Minimum width |
| `maxW` | Maximum width |
| `minH` | Minimum height |
| `maxH` | Maximum height |

**Fixed size:**
```json
{
  "type": "rect",
  "color": "#007AFF",
  "frame": {
    "w": 200,
    "h": 100
  }
}
```

**Minimum/maximum constraints:**
```json
{
  "type": "vstack",
  "frame": {
    "minW": 200,
    "maxW": 400,
    "minH": 50
  },
  "children": [
    { "type": "text", "content": "Flexible sizing" }
  ]
}
```

## Background

Apply a background colour to any node:

```json
{
  "type": "hstack",
  "spacing": 8,
  "padding": 8,
  "background": "#F5F5F5",
  "cornerRadius": 8,
  "children": [
    { "type": "text", "content": "Highlighted" }
  ]
}
```

## Corner Radius

`cornerRadius` rounds the node's `background`. On `rect` and `image` nodes, the same property also rounds the shape or image itself:

```json
{
  "type": "rect",
  "width": 100,
  "height": 50,
  "color": "#007AFF",
  "cornerRadius": 12
}
```

## Opacity

Control transparency of nodes:

```json
{
  "type": "text",
  "content": "Faded text",
  "opacity": 0.5
}
```

On `text`, `style: secondary` is applied as an extra 50% opacity. It combines with `opacity`.

## Visibility

Control whether a node is rendered. The `visible` property takes a variable name (without braces) that is looked up and evaluated as a boolean, or a literal `true` or `false`:

```json
{
  "type": "text",
  "content": "Details",
  "visible": "show_details"
}
```

The variable is looked up as if written `{show_details}` and evaluated as a boolean. Values `"true"`, `"1"`, `"yes"`, and other non-empty strings are truthy (case-insensitive).
Values `"false"`, `"0"`, `"no"`, and empty strings are falsy. A variable that doesn't exist resolves to an empty string and is therefore **falsy** — the node is hidden.
This matches the behaviour of the [`if`](nodes.md#data-nodes) node.

Don't wrap the name in braces: `"visible": "{show_details}"` is always truthy. `visible` has no effect in native menus; use an `if` node there.

## Combining Properties

All styling properties can be combined on a single node:

```json
{
  "type": "vstack",
  "spacing": 8,
  "padding": 12,
  "background": "#FFFFFF",
  "cornerRadius": 8,
  "opacity": 0.95,
  "frame": {
    "minW": 200,
    "maxW": 400
  },
  "children": [
    {
      "type": "text",
      "content": "Styled container",
      "weight": "bold",
      "color": "#000000"
    }
  ]
}
```

## Text-Specific Styling

Text nodes have additional styling properties:

| Property | Values | Description |
|----------|--------|-------------|
| `size` | number | Font size in points (default: 13; the system font is used) |
| `weight` | `ultraLight`, `thin`, `light`, `regular`, `medium`, `semibold`, `bold`, `heavy`, `black` | Font weight |
| `style` | `normal`, `secondary`, `italic`, `monospaced` | Text style (`secondary` reduces opacity to 50%; `italic` and `monospaced` are accepted but do not currently have a visual effect) |
| `color` | hex string or named colour | Text colour (default: the theme's foreground) |
| `align` | `leading`, `center`, `trailing` | Alignment of the lines within multi-line text (default: `leading`) |
| `strikethrough` | boolean | Draw a line through the text |

**Example:**
```json
{
  "type": "text",
  "content": "Large bold header",
  "size": 18,
  "weight": "bold",
  "color": "#000000",
  "align": "center"
}
```

**Strikethrough example:**
```json
{
  "type": "text",
  "content": "Completed task",
  "strikethrough": true,
  "style": "secondary"
}
```

## Best Practices

- Use the `secondary` text style for less prominent text, as it adapts to light/dark mode
- Use named colours like `"primary"` and `"secondary"` when you want automatic dark mode adaptation
- Prefer `padding` and `spacing` for layout over fixed `frame` sizes
- Use `minW`/`maxW` instead of fixed `w` for responsive layouts
- Apply `background` and `cornerRadius` together for card-like elements
- Use `opacity` sparingly for subtle visual effects, not for hiding elements (use `visible` or `if` instead)
