# Node Types

This page documents all available node types in the View DSL, organized by category.

## Layout Nodes

Layout nodes arrange their children in specific patterns. All layout nodes have a `children` property containing an array of child nodes.

| Type | Description | Properties |
|------|-------------|------------|
| `vstack` | Vertical stack | `spacing` (number), `padding` (number or array), `alignment` (`leading`/`center`/`trailing`, default `leading`), `children` (array) |
| `hstack` | Horizontal stack | `spacing` (number), `padding` (number or [top, leading, bottom, trailing]), `alignment` (`top`/`center`/`bottom`, default `center`), `children` (array), `command` (string, optional; makes the row clickable) |
| `zstack` | Overlay stack (children layered on top of each other) | `alignment` (`leading`/`trailing`/`center`/`top`/`bottom`/`topLeading`/`topTrailing`/`bottomLeading`/`bottomTrailing`, default `center`), `children` (array) |
| `scroll` | Scrollable container | `axis` (`vertical`/`horizontal`, default `vertical`), `children` (array) |
| `spacer` | Flexible spacing element | `minLength` (number, optional minimum size) |
| `group` | Logical grouping without visual impact | `children` (array) |

**Example:**
```json
{
  "type": "vstack",
  "spacing": 12,
  "alignment": "leading",
  "children": [
    { "type": "text", "content": "First item" },
    { "type": "text", "content": "Second item" }
  ]
}
```

**Clickable hstack:**
```json
{
  "type": "hstack",
  "spacing": 8,
  "command": "open -a 'Activity Monitor'",
  "children": [
    { "type": "text", "content": "Open Activity Monitor" }
  ]
}
```

## Content Nodes

Content nodes render specific types of content.

| Type | Description | Properties |
|------|-------------|------------|
| `text` | Text display | `content` (string), `size` (number), `weight` (`ultraLight`/`thin`/`light`/`regular`/`medium`/`semibold`/`bold`/`heavy`/`black`), `style` (`normal`/`secondary`/`italic`/`monospaced`), `color` (hex or named color), `align` (`leading`/`center`/`trailing`), `strikethrough` (boolean) |
| `icon` | Icon from bundled icon fonts or SF Symbols | `name` (string, icon name or glyph), `size` (number, default 13), `color` (hex or named color), `style` (`regular`/`filled`) |
| `image` | Image display | `url` (string, image URL), `width` (number), `height` (number), `cornerRadius` (number) |
| `divider` | Visual separator line | No specific properties |
| `header` | Section header text | `content` (string) |

**Text Example:**
```json
{
  "type": "text",
  "content": "Battery: {percentage}",
  "weight": "semibold",
  "style": "secondary",
  "strikethrough": false,
  "size": 14
}
```

The `style` property affects rendering: `secondary` reduces opacity to 50%. The values `italic` and `monospaced` are accepted but do not currently have a visual effect. The default is `normal`.

**Icon Example:**
```json
{
  "type": "icon",
  "name": "bell",
  "size": 16
}
```

Icons are resolved by name from bundled icon fonts (tabler-icons). Use the `-filled` suffix convention (e.g., `"bell-filled"`) for filled variants. ASCII-only names are also looked up as SF Symbols. The `style` property (`regular`/`filled`) is accepted but does not currently have a visual effect; use the `-filled` name suffix instead.

**Image Example:**
```json
{
  "type": "image",
  "url": "https://example.com/avatar.png",
  "width": 24,
  "height": 24,
  "cornerRadius": 4
}
```

## Shape Nodes

Shape nodes render geometric shapes.

| Type | Description | Properties |
|------|-------------|------------|
| `rect` | Rectangle | `width` (number), `height` (number), `color` (hex or named color), `cornerRadius` (number), `strokeColor` (hex or named color), `strokeWidth` (number, default 1.0) |
| `circle` | Circle | `size` (number, diameter), `color` (hex or named color), `strokeColor` (hex or named color), `strokeWidth` (number, default 1.0) |
| `capsule` | Capsule shape (rounded ends) | `width` (number), `height` (number), `color` (hex or named color) |

**Example:**
```json
{
  "type": "hstack",
  "spacing": 8,
  "children": [
    { "type": "circle", "size": 8, "color": "#00FF00" },
    { "type": "text", "content": "Active" }
  ]
}
```

**Stroked shape:**
```json
{
  "type": "rect",
  "width": 100,
  "height": 50,
  "color": "#007AFF",
  "cornerRadius": 8,
  "strokeColor": "#0055CC",
  "strokeWidth": 2
}
```

## Interactive Nodes

Interactive nodes respond to user input and can trigger commands.

| Type | Description | Properties |
|------|-------------|------------|
| `action` | Clickable menu-style row with icon and label | `label` (string, optional), `icon` (string, optional icon name), `command` (string, optional shell command to execute), `iconFont` (string, optional; accepted but not currently used in rendering) |
| `check` | Checkbox item | `label` (string, optional), `checked` (boolean, number, or template string; optional), `command` (string, optional command when checking), `uncheckedCommand` (string, optional command when unchecking) |
| `toggle` | Toggle switch | `label` (string, optional), `on` (boolean, number, or template string; optional), `command` (string, optional) |
| `button` | Button | `label` (string, optional), `icon` (string, optional icon name), `command` (string, optional), `style` (`default`/`bordered`/`borderless`/`plain`; accepted but currently renders as `borderless`) |

**Action Example:**
```json
{
  "type": "action",
  "label": "Open Settings",
  "icon": "gear",
  "command": "open -a 'System Settings'"
}
```

**Check Example:**
```json
{
  "type": "check",
  "label": "Enable notifications",
  "checked": "{notifications_enabled}",
  "command": "my-plugin --enable-notifications",
  "uncheckedCommand": "my-plugin --disable-notifications"
}
```

**Toggle Example:**
```json
{
  "type": "toggle",
  "label": "Dark Mode",
  "on": "{dark_mode_enabled}",
  "command": "my-plugin --toggle-dark-mode"
}
```

**Button Example:**
```json
{
  "type": "button",
  "label": "Refresh",
  "icon": "arrow-clockwise",
  "command": "my-plugin --refresh"
}
```

## Data Nodes

Data nodes control rendering based on data and conditions.

| Type | Description | Properties |
|------|-------------|------------|
| `foreach` | Iterate over a data collection | `items` (string, name of data array), `child` (object, single node template rendered for each item) |
| `if` | Conditional rendering | `condition` (string, variable name), `then` (object, single node rendered if true), `else` (object, optional single node rendered if false) |

> **Note:** Unlike layout nodes, `foreach` uses `items` (not `collection`) and `child` (a single node, not an array). Similarly, `if` uses `then` and `else` as single nodes, not arrays. Wrap multiple children in a `vstack` or `group` if needed.

**foreach Example:**
```json
{
  "type": "foreach",
  "items": "processes",
  "child": {
    "type": "hstack",
    "spacing": 8,
    "children": [
      { "type": "text", "content": "{name}" },
      { "type": "text", "content": "{cpu}", "style": "secondary" }
    ]
  }
}
```

**if Example:**
```json
{
  "type": "if",
  "condition": "is_charging",
  "then": {
    "type": "icon",
    "name": "bolt",
    "color": "#FFCC00"
  },
  "else": {
    "type": "icon",
    "name": "battery-half",
    "color": "#888888"
  }
}
```

## Advanced Nodes

Advanced nodes provide specialized UI components.

| Type | Description | Properties |
|------|-------------|------------|
| `progress` | Progress bar | `value` (string, template or number, 0.0 to 1.0), `color` (hex or named color), `trackColor` (hex or named color), `style` (`bar`/`ring`, default `bar`) |
| `gauge` | Gauge indicator | `value` (string, template or number), `min` (number, default 0.0), `max` (number, default 1.0), `label` (string), `color` (hex or named color) |
| `badge` | Badge label | `content` (string), `color` (hex or named color, background), `textColor` (hex or named color, foreground) |
| `grid` | Grid layout | `columns` (number, default 2), `spacing` (number, default 8), `children` (array) |

**Progress Example:**
```json
{
  "type": "vstack",
  "spacing": 4,
  "children": [
    { "type": "text", "content": "Download: {progress_percent}" },
    {
      "type": "progress",
      "value": "{progress_value}",
      "color": "#007AFF",
      "trackColor": "#E0E0E0",
      "style": "bar"
    }
  ]
}
```

**Ring Progress Example:**
```json
{
  "type": "progress",
  "value": "{cpu_usage}",
  "color": "#FF3B30",
  "style": "ring"
}
```

**Grid Example:**
```json
{
  "type": "grid",
  "columns": 3,
  "spacing": 8,
  "children": [
    { "type": "text", "content": "Item 1" },
    { "type": "text", "content": "Item 2" },
    { "type": "text", "content": "Item 3" },
    { "type": "text", "content": "Item 4" },
    { "type": "text", "content": "Item 5" },
    { "type": "text", "content": "Item 6" }
  ]
}
```

## Native Menu Rendering

When a view is rendered as a native `NSMenu` (via `click.type: menu` in native appearance mode), some node types are **not supported** and are silently skipped:

`spacer`, `icon` (standalone), `image`, `rect`, `circle`, `capsule`, `button`, `progress`, `gauge`, `badge`

In native menus, `hstack` children are composed into a single menu item: text before a spacer becomes the label, text after becomes right-aligned detail text. Shape nodes like `rect` within an `hstack` are not rendered but their `color` is extracted as an indicator colour (rendered as a small coloured bar on the left of the menu item). However, if an `hstack` contains interactive children (`action`, `check`, `toggle`, or `button`), it is flattened into individual menu items rather than composed.

For maximum compatibility across native and themed rendering, stick to `vstack`, `hstack`, `zstack`, `scroll`, `text`, `action`, `check`, `toggle`, `divider`, `header`, `foreach`, `if`, `grid`, and `group` nodes. Layout containers (`vstack`, `zstack`, `scroll`, `group`, `grid`) are flattened in native menus, with their children rendered as sequential menu items.

## Node Composition

All nodes can be freely composed. Layout nodes can contain other layout nodes, creating complex hierarchies:

```json
{
  "type": "vstack",
  "spacing": 12,
  "children": [
    {
      "type": "hstack",
      "spacing": 8,
      "children": [
        { "type": "icon", "name": "star" },
        { "type": "text", "content": "Header" }
      ]
    },
    {
      "type": "scroll",
      "axis": "vertical",
      "children": [
        { "type": "text", "content": "Scrollable content here..." }
      ]
    }
  ]
}
```
