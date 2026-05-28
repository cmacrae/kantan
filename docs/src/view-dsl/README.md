# View DSL

The View DSL is a declarative, JSON-based language for describing views in kantan. Plugins and YAML configuration both use it to lay out tooltips, popups and menus.

## Overview

The View DSL is a tree-structured format where each node represents a UI component. These nodes are rendered natively as SwiftUI views, providing native performance and appearance.

**Key Features:**

- **Unified Interface Definition**: Use the same node types and patterns for tooltips, popups, and menus
- **Template Variables**: Substitute dynamic values using `{variable_name}` syntax
- **Data-Driven Rendering**: Iterate over collections with `foreach` and conditionally render with `if` nodes
- **Native SwiftUI Rendering**: All views are rendered as native SwiftUI components
- **Native Menu Rendering**: Views can also be rendered as native NSMenu items for a system-native look
- **Theme Integration**: Reference theme palette colours with `{theme(name)}` templates
- **URL Scheme Commands**: Interactive nodes accept shell commands or URL schemes (e.g., `https://...`)
- **Declarative Layout**: Describe what the UI should look like, not how to build it

## Usage Contexts

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

**In YAML Configuration:**
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

- **[Node Types](/docs/view-dsl/nodes)**: Complete reference of all available node types, organized by category
- **[Styling](/docs/view-dsl/styling)**: Common styling properties available on all nodes
- **[Templates & Data](/docs/view-dsl/templates)**: Variable substitution, data collections, and control flow
- **[Examples](/docs/view-dsl/examples)**: Annotated real-world examples

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

Layout nodes like `vstack`, `hstack`, and `scroll` contain `children` arrays. Content nodes like `text`, `icon`, and `image` render specific content. Interactive nodes like `action`, `check`, `toggle`, and `button` respond to user input.

Data nodes work differently: `foreach` takes `items` (collection name) and `child` (a single template node). `if` takes `condition`, `then` (a single node), and optionally `else` (a single node).

## Getting Started

For a complete overview of available nodes, see [Node Types](/docs/view-dsl/nodes). For styling and layout options, see [Styling](/docs/view-dsl/styling). To learn about dynamic content and templates, see [Templates & Data](/docs/view-dsl/templates). For practical examples, see [Examples](/docs/view-dsl/examples).
