# Templates & Data

The View DSL supports dynamic content through template variable substitution and data-driven rendering.

## Template Variables

Any string value in a view node can contain placeholders in the form `{variable_name}`. These placeholders are resolved from (in priority order, highest first):

1. **Scoped variables**: Fields of the current `foreach` item (innermost scope takes priority; see [Variable Scoping](#variable-scoping) below)
2. **Top-level variables**: The module's template variables (for command modules, the `variables` object in plugin JSON output) plus the built-in `{value}` and `{icon}`, which replace any variables of the same name
3. **Theme templates**: `{theme(name)}` patterns resolved via the theme palette (see [Theme Colour Templates](#theme-colour-templates))

A placeholder that matches none of these is replaced with an empty string. There is no escape for literal braces: any `{` followed later by `}` is treated as a placeholder. Placeholders within a substituted value are resolved too, up to 8 levels deep. A variable can hold a `{theme(name)}` template.

The only template syntax is `{name}` and `{theme(name)}`. Conditionals like `{?name:...}` in plugin `format` settings are expanded by the plugin before output, not by the View DSL.

### Basic Usage

**Plugin output:**
```json
{
  "value": "42%",
  "variables": {
    "cpu": "42%",
    "memory": "8.2 GB",
    "swap": "1.1 GB"
  },
  "view": {
    "type": "vstack",
    "spacing": 4,
    "children": [
      { "type": "text", "content": "CPU: {cpu}" },
      { "type": "text", "content": "Memory: {memory}" },
      { "type": "text", "content": "Swap: {swap}" }
    ]
  }
}
```

The rendered view will show:
```
CPU: 42%
Memory: 8.2 GB
Swap: 1.1 GB
```

### In YAML Configuration

**Module config:**
```yaml
modules:
  - name: clock
    type: clock
    placement: right
    interaction:
      hover:
        type: tooltip
        view:
          type: text
          content: "Current time: {value}"
```

The `{value}` variable is automatically available for all modules and contains the module's current display value.

### Template Expressions in Properties

Templates can be used in any string property, including styling properties:

```json
{
  "type": "text",
  "content": "{status_message}",
  "color": "{status_color}",
  "visible": "show_status"
}
```

The `visible` property and the `if` node's `condition` take a bare variable name (without braces). Other string properties use the `{variable}` brace syntax.

## Data Collections

Plugins can output structured data collections in the `data` field. These collections can be iterated over using the `foreach` node.

**Plugin output with data:**
```json
{
  "value": "5 processes",
  "data": {
    "processes": [
      { "name": "Safari", "cpu": "12.3%", "memory": "1.2 GB" },
      { "name": "Xcode", "cpu": "8.1%", "memory": "3.4 GB" },
      { "name": "Terminal", "cpu": "1.2%", "memory": "256 MB" }
    ],
    "warnings": [
      { "message": "High CPU usage", "severity": "medium" }
    ]
  }
}
```

The `data` object can contain multiple named arrays. Each array holds flat objects with arbitrary fields. Field values that aren't strings are converted to text: numbers keep their value (`3` becomes `"3"`), and booleans become `"1"` and `"0"`, which still evaluate as true and false.

Every value in `variables` must be a string. Every entry in `data` must be an array of objects. Otherwise that whole field is ignored.

## foreach Node

The `foreach` node iterates over a data collection and renders its `child` node once for each item.

**Syntax** (pseudocode — comments are illustrative, not part of the protocol):
```jsonc
{
  "type": "foreach",
  "items": "collection_name",
  "child": {
    // Single node template with access to item fields
  }
}
```

> **Note:** `foreach` uses `items` (the name of the data collection) and `child` (a single node, not an array). If you need multiple elements per iteration, wrap them in a `vstack` or `group`.

**Example:**
```json
{
  "type": "foreach",
  "items": "processes",
  "child": {
    "type": "hstack",
    "spacing": 8,
    "children": [
      {
        "type": "text",
        "content": "{name}",
        "weight": "medium",
        "frame": { "w": 120 }
      },
      {
        "type": "text",
        "content": "{cpu}",
        "style": "secondary",
        "frame": { "w": 60 }
      },
      {
        "type": "text",
        "content": "{memory}",
        "style": "secondary",
        "frame": { "w": 80 }
      }
    ]
  }
}
```

### Variable Scoping

Inside a `foreach` block, template variables refer to fields from the current item, which shadow top-level variables of the same name. Variables from parent scopes remain accessible:

```json
{
  "variables": {
    "total_cpu": "45%"
  },
  "data": {
    "processes": [
      { "name": "Safari", "cpu": "12.3%" }
    ]
  },
  "view": {
    "type": "vstack",
    "children": [
      { "type": "text", "content": "Total: {total_cpu}" },
      {
        "type": "foreach",
        "items": "processes",
        "child": {
          "type": "text",
          "content": "{name}: {cpu} of {total_cpu}"
        }
      }
    ]
  }
}
```

### Nested foreach

`foreach` nodes can be nested. Each `items` value must reference a top-level key in the `data` object. Inner foreach scopes **can** access variables from parent foreach scopes. The innermost scope wins when variable names collide.

```json
{
  "data": {
    "categories": [
      { "name": "Development" },
      { "name": "Browsers" }
    ],
    "apps": [
      { "name": "Xcode", "cpu": "8.1%", "category": "Development" },
      { "name": "Terminal", "cpu": "1.2%", "category": "Development" },
      { "name": "Safari", "cpu": "12.3%", "category": "Browsers" }
    ]
  },
  "view": {
    "type": "vstack",
    "spacing": 12,
    "children": [
      {
        "type": "foreach",
        "items": "categories",
        "child": {
          "type": "vstack",
          "children": [
            {
              "type": "text",
              "content": "{name}",
              "weight": "bold"
            },
            {
              "type": "foreach",
              "items": "apps",
              "child": {
                "type": "text",
                "content": "{name}: {cpu}"
              }
            }
          ]
        }
      }
    ]
  }
}
```

In this example, `{name}` inside the inner `foreach` resolves to the app name (inner scope), shadowing the category name from the outer scope. If the inner item lacks a field, the resolver falls back to the outer scope. The inner `foreach` renders the whole `apps` collection under every category: collections can't be filtered by the outer item. Emit one collection per group (e.g. `apps_development`, `apps_browsers`) when you need grouping.

> **Note:** Since nested arrays within data items are not supported, each collection must be a top-level key in the `data` object. Flatten your data structure accordingly.

## if Node

The `if` node conditionally renders a node based on a variable value.

**Syntax** (pseudocode — comments are illustrative, not part of the protocol):
```jsonc
{
  "type": "if",
  "condition": "variable_name",
  "then": {
    // Single node rendered if condition is truthy
  },
  "else": {
    // Optional single node rendered if condition is falsy
  }
}
```

> **Note:** `if` uses `then` and `else` as single node objects, not arrays. Wrap multiple children in a `vstack` or `group` if needed.

The `condition` is a bare variable name, looked up as if written `{variable_name}`. Don't wrap it in braces: `"condition": "{is_charging}"` is always truthy.

**Boolean evaluation (for `if` conditions):**
- `"true"`, `"1"`, `"yes"`, and other non-empty strings: truthy
- `"false"`, `"0"`, `"no"`, `""`, and unresolved variables: falsy

Comparisons are case-insensitive. The same rules decide `check`'s `checked` and `toggle`'s `on`, which take a template such as `"{done}"` (or a literal boolean).

> The `visible` property on nodes uses the same truthiness rules, including for unresolved variables. An unresolved template resolves to `""`, which is falsy. The node is **hidden**. See [Styling — Visibility](styling.md#visibility).

**Example:**
```json
{
  "variables": {
    "is_charging": "true",
    "percentage": "87%"
  },
  "view": {
    "type": "hstack",
    "spacing": 4,
    "children": [
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
          "color": "#34C759"
        }
      },
      { "type": "text", "content": "{percentage}" }
    ]
  }
}
```

### if with foreach

`if` nodes can be used inside `foreach` to conditionally render items:

```json
{
  "type": "foreach",
  "items": "processes",
  "child": {
    "type": "if",
    "condition": "is_high_cpu",
    "then": {
      "type": "hstack",
      "children": [
        { "type": "text", "content": "{name}", "color": "#FF3B30" },
        { "type": "text", "content": "{cpu}", "weight": "bold" }
      ]
    },
    "else": {
      "type": "text",
      "content": "{name}: {cpu}",
      "style": "secondary"
    }
  }
}
```

## Theme Colour Templates

When a [theme](../configuration/themes.md) is configured, colours from the theme palette can be referenced using `{theme(name)}` syntax in any colour property:

```json
{
  "type": "text",
  "content": "Themed text",
  "color": "{theme(accent)}"
}
```

```json
{
  "type": "vstack",
  "background": "{theme(bg)}",
  "children": [
    { "type": "text", "content": "On theme background", "color": "{theme(fg)}" }
  ]
}
```

The special names `fg`, `bg`, and `shape` resolve to the palette's top-level values. Any custom colour key defined in the theme's `colors` map is also available (e.g., `{theme(blue)}`, `{theme(surface0)}`).

Theme templates resolve against the palette for the current appearance mode. The same template produces different colours in light and dark mode.

A name the palette doesn't define (`shape` when the palette doesn't set it), or any name without a configured theme, is left as written. The property then uses its default colour. Theme templates resolve inside `foreach` items too.

## Built-in Template Variables

All modules automatically expose these variables for use in view templates:

- `{value}`: The module's current display value (e.g., the formatted time for a clock module, the battery percentage for a power module)
- `{icon}`: The module's current icon, as the resolved glyph character rather than its name

**Command module** plugins (with `output: json`) can add variables through the `variables` object in their JSON output, and collections through `data`. These are merged into the template scope alongside the built-in variables. Some built-in modules also set variables of their own; see each [module's](../modules/index.md) page.

## Best Practices

- Use descriptive variable names in plugin output: `cpu_percentage` instead of `c`
- Provide sensible defaults in your plugin when variables might be empty
- Use `if` nodes for data that may be missing
- Combine `foreach` with `if` to filter items
- Keep data structures flat when possible for easier template writing
- Document available variables and data structures in your plugin's README
