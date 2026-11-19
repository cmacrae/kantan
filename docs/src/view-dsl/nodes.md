# Node Types

This page documents all available node types in the View DSL, organized by category. Every node also accepts the [common styling properties](styling.md) (`padding`, `frame`, `opacity`, `background`, `cornerRadius`, `visible`).

Properties marked **required** must be present in plugin JSON, or the whole view is discarded (see [Validation](index.md#validation)). Any string property can contain [templates](templates.md) such as `{name}`, except the enumerated ones (`weight`, `style`, `alignment`, `axis`, `align`). Number and boolean properties take literal values. Only `progress`/`gauge` `value`, `check` `checked`, and `toggle` `on` also accept a template string.

## Layout Nodes

Layout nodes arrange their children in specific patterns. All layout nodes except `spacer` have a `children` property containing an array of child nodes (default empty).

| Type | Description | Properties |
|------|-------------|------------|
| `vstack` | Vertical stack | `spacing` (number, default system spacing), `alignment` (`leading`/`center`/`trailing`, default `leading`), `children` (array) |
| `hstack` | Horizontal stack | `spacing` (number, default system spacing), `alignment` (`top`/`center`/`bottom`, default `center`), `children` (array), `command` (string, optional; makes the row clickable) |
| `zstack` | Overlay stack (children layered on top of each other) | `alignment` (`leading`/`trailing`/`center`/`top`/`bottom`/`topLeading`/`topTrailing`/`bottomLeading`/`bottomTrailing`, default `center`), `children` (array) |
| `scroll` | Scrollable container; children are stacked with no spacing along the axis | `axis` (`vertical`/`horizontal`, default `vertical`), `children` (array) |
| `spacer` | Flexible spacing element | `minLength` (number, optional minimum size) |
| `group` | Logical grouping without visual impact | `children` (array) |

`vstack` and `hstack` also accept any of the nine `zstack` alignments, using the part that applies to their axis (e.g. `topLeading` aligns a `vstack` to `leading` and an `hstack` to `top`).

A popup or tooltip sizes itself to fit its content. A popup resizes as its content changes while it's open. A `scroll` scrolls only when `frame` gives it a height (e.g. `"frame": { "maxH": 300 }`).

An `hstack` with a `command` highlights on hover; clicking it closes the popup and runs the command.

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
| `text` | Text display | `content` (string, **required**), `size` (number, default 13), `weight` (`ultraLight`/`thin`/`light`/`regular`/`medium`/`semibold`/`bold`/`heavy`/`black`), `style` (`normal`/`secondary`/`italic`/`monospaced`), `color` (hex or named colour, default the theme's foreground, or the system label colour in native appearance), `align` (`leading`/`center`/`trailing`; aligns the lines of multi-line text), `strikethrough` (boolean) |
| `icon` | Icon from bundled icon fonts or SF Symbols | `name` (string, **required**; icon name or glyph), `size` (number, default 13), `color` (hex or named colour), `style` (`regular`/`filled`) |
| `image` | Image loaded from a URL | `url` (string, **required**), `width` (number), `height` (number), `cornerRadius` (number) |
| `divider` | Horizontal separator line, inset 8pt horizontally and 4pt vertically | No specific properties |
| `header` | Section header text (12pt bold, 22pt tall) | `content` (string, **required**) |

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

Icons are resolved by name from bundled icon fonts (tabler-icons). Use the `-filled` suffix convention (e.g., `"bell-filled"`) for filled variants. An ASCII name that isn't a tabler icon is shown as the SF Symbol of that name (e.g., `"gear"`). Any other name is drawn as literal text. A glyph character can be used directly. The `style` property (`regular`/`filled`) is accepted but does not currently have a visual effect; use the `-filled` name suffix instead.

kantan fetches an image's `url` whenever the view shows it, so the image's server learns when you looked and from where. An image `url` built from outside text, such as an invitation or a feed item, lets whoever wrote that text track you. Only show images from sources you trust. A spinner shows while an image loads. An image that fails to load shows a placeholder `photo` symbol. The image fills its `width`×`height`, cropping to keep its aspect ratio. `cornerRadius` here also rounds the node's `background`.

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
| `rect` | Rectangle | `width` (number), `height` (number), `color` (hex or named colour, fill), `cornerRadius` (number), `strokeColor` (hex or named colour), `strokeWidth` (number, default 1.0) |
| `circle` | Circle | `size` (number, diameter), `color` (hex or named colour, fill), `strokeColor` (hex or named colour), `strokeWidth` (number, default 1.0) |
| `capsule` | Capsule shape (rounded ends) | `width` (number), `height` (number), `color` (hex or named colour, fill) |

Shapes have no fill unless `color` is set. The stroke is drawn inside the shape's edge, and only when `strokeColor` is set. A shape with no size expands to fill the space it is given. On `rect`, `cornerRadius` also rounds the node's `background`.

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

Interactive nodes respond to user input and can trigger commands. A command is run with `/bin/sh -c` (its output is discarded), unless it is a URL with no spaces (such as `https://...`, `raycast://...` or `x-apple.systempreferences:...`), which is opened. A URL's scheme is a letter followed by letters, digits, `+`, `-` or `.`. Templates in commands are resolved first: `"my-plugin --complete {id}"` works. Each value is quoted for where its placeholder sits: bare, inside single quotes, or inside double quotes. There, it stays one argument and can't run anything, whatever it contains:

| Command | Value of `title` | Runs |
|---------|------------------|------|
| `open-note {title}` | `a; rm x` | `open-note 'a; rm x'` |
| `open-note '{title}'` | `it's` | `open-note 'it'\''s'` |
| `open-note "{title}"` | `$HOME` | `open-note "\$HOME"` |

Only those three positions are covered. Don't put a placeholder for outside text inside `$'…'`, or inside a command substitution (`$(…)` or backticks), where its value can run commands. A value can also start with `-`, which the command may read as an option. Put `--` before it where the command accepts that.

A bare placeholder whose value is empty leaves nothing. A command that is a single placeholder, such as `"command": "{complete_cmd}"`, runs as the value, exactly as written: placeholders within it aren't resolved. The plugin builds that command itself and quotes what it puts in it. In a URL command, values are percent-encoded instead.

| Type | Description | Properties |
|------|-------------|------------|
| `action` | Clickable menu-style row with icon and label | `label` (string, optional), `icon` (string, optional icon name), `command` (string, optional) |
| `check` | Checkbox item | `label` (string, optional), `checked` (boolean, number, or template string; default false), `command` (string, optional; run when checking), `uncheckedCommand` (string, optional; run when unchecking, falling back to `command`) |
| `toggle` | Toggle switch | `label` (string, optional), `on` (boolean, number, or template string; default false), `command` (string, optional; run whenever it is switched, either way) |
| `button` | Button | `label` (string, optional), `icon` (string, optional icon name), `command` (string, optional), `style` (`default`/`bordered`/`borderless`/`plain`; accepted but currently renders as `borderless`) |

`checked` and `on` are evaluated as booleans: `true`, `1`, `yes`, and any other non-empty value are on; `false`, `0`, `no`, and empty are off.

Clicking an `action`, `button`, or `toggle` closes the popup. Clicking a `check` flips its checkmark (the label is struck through while checked) and keeps the popup or menu open, so several items can be checked in turn. The item shows the click until the module reports a new `checked` value for it, or the row shows another item. In a menu, an `action` without a `command` is shown disabled.

**Action Example:**
```json
{
  "type": "action",
  "label": "Open Settings",
  "icon": "settings",
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
  "icon": "refresh",
  "command": "my-plugin --refresh"
}
```

## Data Nodes

Data nodes control rendering based on data and conditions.

| Type | Description | Properties |
|------|-------------|------------|
| `foreach` | Iterate over a data collection | `items` (string, **required**; name of a collection in `data`), `child` (object, **required**; single node template rendered for each item) |
| `if` | Conditional rendering | `condition` (string, **required**; bare variable name, without braces), `then` (object, **required**; single node rendered if truthy), `else` (object, optional single node rendered if falsy) |

> **Note:** Unlike layout nodes, `foreach` uses `items` (not `collection`) and `child` (a single node, not an array). Similarly, `if` uses `then` and `else` as single nodes, not arrays. Wrap multiple children in a `vstack` or `group` if needed.

A `foreach` whose collection doesn't exist renders nothing. See [Templates & Data](templates.md) for scoping and truthiness rules.

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
    "name": "battery-2",
    "color": "#888888"
  }
}
```

## Advanced Nodes

Advanced nodes provide specialized UI components.

| Type | Description | Properties |
|------|-------------|------------|
| `progress` | Progress bar or ring | `value` (number or template, **required**; 0.0 to 1.0, clamped), `color` (hex or named colour, default accent), `trackColor` (hex or named colour), `style` (`bar`/`ring`, default `bar`), `strokeWidth` (number, the width of a ring's stroke, default 4) |
| `gauge` | Gauge indicator | `value` (number or template, **required**), `min` (number, default 0.0), `max` (number, default 1.0), `label` (string), `color` (hex or named colour, default accent) |
| `badge` | Capsule-shaped label (11pt medium) | `content` (string, **required**), `color` (hex or named colour, background, default accent), `textColor` (hex or named colour, foreground, default white) |
| `grid` | Grid of equal-width columns, filled row by row | `columns` (integer, default 2), `spacing` (number, default 8; between rows and columns), `children` (array) |

A `progress` or `gauge` value that isn't a number is treated as 0. The `bar` style is 6pt tall and fills the available width. The `ring` style fills the space it is given, with a stroke 4pt wide unless `strokeWidth` says otherwise. The stroke is centred on the ring's edge, so half its width falls outside the frame. Give the ring a size with `frame`. `gauge` uses the system gauge, with `label` shown in 11pt text. It spans `min` to `max` whichever order they come in: `min: 20` alone spans 1 to 20.

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
  "value": "{cpu_fraction}",
  "color": "#FF3B30",
  "style": "ring",
  "frame": { "w": 24, "h": 24 }
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

A view opened by `click.type: menu` is always rendered as a native `NSMenu`, in both native and themed appearance. In themed appearance, menu text uses the theme's foreground colour. While the menu is open, its items update each time the module does. An item keeps its highlight unless the update adds or removes items. An `NSMenu` is a flat list of items. The tree is converted as follows:

| Node | In a native menu |
|------|------------------|
| `vstack`, `zstack`, `scroll`, `group`, `grid` | Flattened: each child becomes its own item(s), in order |
| `hstack` | Composed into one item (see below); clickable when it has a `command` |
| `text` | A read-only item. `style: secondary` and `strikethrough` apply; `weight` of `semibold`, `bold`, `heavy` or `black` is shown bold; `size` and `color` are ignored |
| `header` | A bold section header |
| `divider` | A menu separator |
| `action` | A menu item with its icon and label; disabled when it has no `command` |
| `check` | A check item; clicking it doesn't close the menu |
| `toggle` | A switch |
| `foreach`, `if` | Expanded in place |
| `progress` | A bar as wide as the menu, in its `color` and `trackColor`. The `ring` style, and a `progress` inside an `hstack`, are skipped |
| `spacer`, `icon`, `image`, `rect`, `circle`, `capsule`, `button`, `gauge`, `badge` | Skipped (except inside an `hstack`, below) |

Native menus ignore the common styling properties (`padding`, `frame`, `opacity`, `background`, `cornerRadius`) and `visible`. Use an `if` node to hide items in a menu.

An `hstack` is composed into a single menu item from its `text` and `icon` children, including those inside nested `vstack`, `hstack`, and `group` nodes. Content before the first `spacer` becomes the label; content after it becomes right-aligned, secondary detail text. The `color` of the first `rect` child is shown as a small coloured bar on the left of the item (hex or `{theme(name)}` colours only, not named colours). Other children, including `foreach` and `if`, are not rendered inside a composed `hstack`. If an `hstack` contains an interactive child (`action`, `check`, `toggle`, or `button`), it is flattened into individual menu items instead.

For views that work both as menus and popups, stick to `vstack`, `hstack`, `text`, `header`, `divider`, `action`, `check`, `toggle`, `foreach`, `if`, and `group`.

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
