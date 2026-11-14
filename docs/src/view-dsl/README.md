# View DSL

The View DSL is a declarative, JSON-based language for describing views in kantan. Plugins and YAML configuration both use it to lay out tooltips, popups and menus.

## Overview

The View DSL is a tree-structured format where each node represents a UI component. These nodes are rendered natively as SwiftUI views, providing native performance and appearance.

**Key Features:**

- **Unified Interface Definition**: Use the same node types and patterns for tooltips, popups, and menus
- **Template Variables**: Substitute dynamic values using `{variable_name}` syntax
- **Data-Driven Rendering**: Iterate over collections with `foreach` and conditionally render with `if` nodes
- **Native SwiftUI Rendering**: Tooltips and popups are rendered as native SwiftUI components
- **Native Menu Rendering**: Menus are rendered as native NSMenu items for a system-native look
- **Theme Integration**: Reference theme palette colours with `{theme(name)}` templates
- **Commands**: Interactive nodes run a shell command, or open a URL (e.g., `https://...`)
- **Declarative Layout**: Describe what the UI should look like, not how to build it

## Usage Contexts

A view is shown in one of three places, chosen by the module's `interaction` config:

| Context | Config | Rendering |
|---------|--------|-----------|
| Tooltip | `interaction.hover.type: tooltip` with `hover.view` | SwiftUI panel; it doesn't take clicks, so interactive nodes can't be used |
| Popup | `interaction.click.type: popup` | SwiftUI panel; closes when it loses focus |
| Menu | `interaction.click.type: menu` | Native `NSMenu`; see [Native Menu Rendering](nodes.md#native-menu-rendering) for what it supports |

For `popup` and `menu`, a `click.view` in YAML takes priority over a `view` from plugin output. A tooltip only shows `hover.view`. A popup or menu follows the module's values while it's open, updating each time the module does. A tooltip shows the values the module had when it appeared.

**In Plugin Output:**
```json
{
  "value": "5 items",
  "variables": {
    "count": "5"
  },
  "view": {
    "type": "vstack",
    "children": [
      { "type": "text", "content": "Items: {count}" }
    ]
  }
}
```

**In YAML Configuration** (under a module):
```yaml
interaction:
  hover:
    type: tooltip
    view:
      type: vstack
      spacing: 4
      children:
        - type: text
          content: "Next: {next_title}"
```

## Documentation Sections

- **[Node Types](nodes.md)**: Complete reference of all available node types, organized by category
- **[Styling](styling.md)**: Common styling properties available on all nodes
- **[Templates & Data](templates.md)**: Variable substitution, data collections, and control flow
- **[Examples](examples.md)**: Annotated real-world examples

## Basic Structure

Every view definition is a tree of nodes. Each node has a `type` field that determines its behavior:

```json
{
  "type": "vstack",
  "spacing": 8,
  "children": [
    {
      "type": "text",
      "content": "Hello, World!",
      "weight": "bold"
    },
    {
      "type": "text",
      "content": "This is a simple view",
      "style": "secondary"
    }
  ]
}
```

Layout nodes like `vstack`, `hstack`, and `scroll` contain `children` arrays. Node and property names are case-sensitive. Content nodes like `text`, `icon`, and `image` render specific content. Interactive nodes like `action`, `check`, `toggle`, and `button` respond to user input.

Data nodes work differently: `foreach` takes `items` (collection name) and `child` (a single template node). `if` takes `condition`, `then` (a single node), and optionally `else` (a single node).

## Validation

Plugin JSON is decoded strictly. If any node in the tree has an unknown `type`, is missing a required property, or has a value of the wrong type or outside its allowed set (e.g. `"weight": "extrabold"`), the whole `view` is discarded and the module shows no view.

YAML views are parsed leniently: a node with an unknown `type` is dropped, an invalid enumerated value is ignored (the default applies), and a missing required string becomes empty. A `foreach` without `child` or an `if` without `then` is dropped.

In tooltips and popups, nodes nested deeper than 32 levels are not rendered.

## Getting Started

For a complete overview of available nodes, see [Node Types](nodes.md). For styling and layout options, see [Styling](styling.md). To learn about dynamic content and templates, see [Templates & Data](templates.md). For practical examples, see [Examples](examples.md).
