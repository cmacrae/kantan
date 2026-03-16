# Styling

All nodes in the View DSL support common styling properties that control their appearance and layout.

## Common Properties

These properties can be applied to any node type:

| Property | Type | Description |
|----------|------|-------------|
| `padding` | number or array | Uniform padding (number), or `[top, leading, bottom, trailing]` array |
| `frame` | object | Frame constraints: `w`, `h`, `minW`, `maxW`, `minH`, `maxH` |
| `opacity` | number | Opacity from 0.0 (transparent) to 1.0 (opaque) |
| `background` | string | Background color as hex string or named color |
| `cornerRadius` | number | Corner rounding in points |
| `visible` | string | Visibility controlled by a variable name (e.g., `"show_details"`) |

## Colours

Colours can be specified as hex strings or as named system colours.

**Hex format:**

- **RGB**: `"#RRGGBB"` (e.g., `"#FF0000"` for red)

**Named colours:**

`primary`, `secondary`, `accent`, `red`, `orange`, `yellow`, `green`, `blue`, `purple`, `pink`, `gray` (or `grey`), `white`, `black`, `clear`

Named colors adapt to light/dark mode automatically.

**Theme colours:**

When a [theme](../configuration/themes.md) is active, you can reference palette colours with `{theme(name)}` syntax:

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

Padding can be specified as a single number (uniform padding) or as an array with four values `[top, leading, bottom, trailing]`:

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
  "padding": [8, 16, 8, 16],
  "children": [
    { "type": "text", "content": "Custom padding" }
  ]
}
```

The array format is `[top, leading, bottom, trailing]`.

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

Round the corners of nodes with backgrounds or shapes:

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

## Visibility

Control whether a node is rendered. The `visible` property takes a variable name (without braces) that is looked up and evaluated as a boolean:

```json
{
  "type": "text",
  "content": "Details",
  "visible": "show_details"
}
```

The variable is resolved and evaluated as a boolean. Values `"true"`, `"1"`, `"yes"`, and other non-empty strings are truthy. Values `"false"`, `"0"`, `"no"`, and empty strings are falsy. If the variable cannot be resolved (i.e. remains an unresolved template), the node defaults to visible.

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
| `size` | number | Font size in points (default: 13) |
| `weight` | `ultraLight`, `thin`, `light`, `regular`, `medium`, `semibold`, `bold`, `heavy`, `black` | Font weight |
| `style` | `normal`, `secondary`, `italic`, `monospaced` | Text style (`secondary` reduces opacity to 50%; `italic` and `monospaced` are accepted but do not currently have a visual effect) |
| `color` | hex string or named color | Text color |
| `align` | `leading`, `center`, `trailing` | Text alignment |
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
- Use `opacity` sparingly for subtle visual effects, not for hiding elements (use `visible` instead)
