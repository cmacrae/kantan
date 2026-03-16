# Examples

Annotated examples of common View DSL patterns.

## Example 1: Simple Tooltip

A basic tooltip showing upcoming calendar event details.

**YAML Configuration:**
```yaml
modules:
  - type: command
    command: next-event-plugin
    interaction:
      hover:
        type: tooltip
        view:
          type: vstack
          spacing: 4
          padding: 8
          children:
            - type: text
              content: "Next: {next_title}"
              weight: medium
              size: 13
            - type: text
              content: "{next_countdown}"
              style: secondary
              size: 11
```

**What this demonstrates:**
- Simple vertical layout with spacing and padding
- Template variable substitution for dynamic content
- Text styling with weight and semantic styles
- Tooltip interaction type in YAML config

**Expected output:**
```
Next: Team Standup
in 15 minutes
```

---

## Example 2: System Monitor Popup

A comprehensive system monitoring popup with process list and actions.

**Plugin JSON Output:**
```json
{
  "value": "CPU 23%",
  "icon": "\udb81\udf5b",
  "variables": {
    "cpu": "23%",
    "mem": "67%",
    "disk": "45%",
    "thermal": "Nominal"
  },
  "data": {
    "top_processes": [
      { "name": "Safari", "cpu": "12.3%", "mem": "1.2 GB", "pid": "1234" },
      { "name": "Xcode", "cpu": "8.1%", "mem": "3.4 GB", "pid": "5678" },
      { "name": "Terminal", "cpu": "1.8%", "mem": "256 MB", "pid": "9012" },
      { "name": "Mail", "cpu": "0.9%", "mem": "512 MB", "pid": "3456" }
    ]
  },
  "view": {
    "type": "vstack",
    "spacing": 8,
    "padding": 12,
    "frame": {
      "minW": 300
    },
    "children": [
      {
        "type": "header",
        "content": "System Monitor"
      },
      {
        "type": "hstack",
        "spacing": 16,
        "children": [
          {
            "type": "vstack",
            "spacing": 2,
            "alignment": "leading",
            "children": [
              { "type": "text", "content": "CPU", "style": "secondary", "size": 11 },
              { "type": "text", "content": "{cpu}", "weight": "semibold", "size": 14 }
            ]
          },
          {
            "type": "vstack",
            "spacing": 2,
            "alignment": "leading",
            "children": [
              { "type": "text", "content": "Memory", "style": "secondary", "size": 11 },
              { "type": "text", "content": "{mem}", "weight": "semibold", "size": 14 }
            ]
          },
          {
            "type": "vstack",
            "spacing": 2,
            "alignment": "leading",
            "children": [
              { "type": "text", "content": "Disk", "style": "secondary", "size": 11 },
              { "type": "text", "content": "{disk}", "weight": "semibold", "size": 14 }
            ]
          }
        ]
      },
      {
        "type": "divider"
      },
      {
        "type": "text",
        "content": "Top Processes",
        "weight": "semibold",
        "size": 12
      },
      {
        "type": "scroll",
        "axis": "vertical",
        "children": [
          {
            "type": "vstack",
            "spacing": 4,
            "children": [
              {
                "type": "foreach",
                "items": "top_processes",
                "child": {
                  "type": "hstack",
                  "spacing": 8,
                  "padding": [4, 0, 4, 0],
                  "children": [
                    {
                      "type": "text",
                      "content": "{name}",
                      "weight": "medium",
                      "frame": {
                        "w": 100
                      }
                    },
                    {
                      "type": "text",
                      "content": "{cpu}",
                      "style": "secondary",
                      "frame": {
                        "w": 50
                      }
                    },
                    {
                      "type": "text",
                      "content": "{mem}",
                      "style": "secondary",
                      "frame": {
                        "w": 70
                      }
                    }
                  ]
                }
              }
            ]
          }
        ]
      },
      {
        "type": "divider"
      },
      {
        "type": "hstack",
        "spacing": 8,
        "children": [
          {
            "type": "action",
            "label": "Activity Monitor",
            "command": "open -a 'Activity Monitor'"
          },
          {
            "type": "spacer"
          },
          {
            "type": "text",
            "content": "Thermal: {thermal}",
            "style": "secondary",
            "size": 11
          }
        ]
      }
    ]
  }
}
```

**What this demonstrates:**
- Complex multi-section layout with headers and dividers
- Grid-like layout using hstack with aligned columns
- `foreach` iteration over process data with `items` and `child`
- Scrollable content area for variable-length lists
- Action node with `label` and `command` for launching external apps
- Combination of variables and data collections
- Frame sizing with short property names (`w`, `minW`)
- Edge-specific padding as an array `[top, leading, bottom, trailing]`
- Text styles for visual hierarchy

---

## Example 3: Reminders Checklist Menu

A to-do list style menu with interactive checkboxes.

**Plugin JSON Output:**
```json
{
  "value": "3",
  "icon": "\udb81\udd32",
  "data": {
    "items": [
      {
        "label": "Buy groceries",
        "done": false,
        "id": "abc123",
        "due": "Today"
      },
      {
        "label": "Review PR #42",
        "done": true,
        "id": "def456",
        "due": "Yesterday"
      },
      {
        "label": "Write documentation",
        "done": false,
        "id": "ghi789",
        "due": "Tomorrow"
      },
      {
        "label": "Call dentist",
        "done": false,
        "id": "jkl012",
        "due": "Friday"
      }
    ]
  },
  "view": {
    "type": "vstack",
    "spacing": 0,
    "padding": 4,
    "frame": {
      "minW": 280
    },
    "children": [
      {
        "type": "hstack",
        "spacing": 8,
        "padding": 8,
        "children": [
          {
            "type": "text",
            "content": "Reminders",
            "weight": "bold",
            "size": 14
          },
          {
            "type": "spacer"
          },
          {
            "type": "badge",
            "content": "3",
            "color": "#007AFF"
          }
        ]
      },
      {
        "type": "divider"
      },
      {
        "type": "foreach",
        "items": "items",
        "child": {
          "type": "vstack",
          "spacing": 2,
          "padding": [6, 8, 6, 8],
          "children": [
            {
              "type": "check",
              "label": "{label}",
              "checked": "{done}",
              "command": "reminders-plugin --complete {id}",
              "uncheckedCommand": "reminders-plugin --uncomplete {id}"
            },
            {
              "type": "text",
              "content": "Due: {due}",
              "style": "secondary",
              "size": 10
            }
          ]
        }
      },
      {
        "type": "divider"
      },
      {
        "type": "action",
        "label": "Open Reminders",
        "icon": "plus",
        "command": "open -a Reminders"
      }
    ]
  }
}
```

**What this demonstrates:**
- Menu-style interface with interactive checkboxes
- Header with badge showing count
- `check` nodes with separate `command` and `uncheckedCommand` for toggle
- Template variables in command strings (`{id}`)
- Boolean template variables (`{done}`)
- `foreach` with `items` and `child` (singular node)
- `action` node with `label`, `icon`, and `command` properties
- Zero spacing for compact menu appearance
- Badge component for notifications

---

## Example 4: Conditional Weather Display

A weather module that changes appearance based on conditions.

**Plugin JSON Output:**
```json
{
  "value": "72\u00b0",
  "variables": {
    "temp": "72\u00b0",
    "condition": "Sunny",
    "feels_like": "70\u00b0",
    "humidity": "45%",
    "is_raining": "false",
    "is_sunny": "true",
    "alert_active": "false",
    "alert_message": ""
  },
  "view": {
    "type": "vstack",
    "spacing": 8,
    "padding": 12,
    "children": [
      {
        "type": "hstack",
        "spacing": 8,
        "alignment": "center",
        "children": [
          {
            "type": "if",
            "condition": "is_sunny",
            "then": {
              "type": "icon",
              "name": "sun",
              "size": 32
            },
            "else": {
              "type": "if",
              "condition": "is_raining",
              "then": {
                "type": "icon",
                "name": "cloud-rain",
                "size": 32
              },
              "else": {
                "type": "icon",
                "name": "cloud",
                "size": 32
              }
            }
          },
          {
            "type": "vstack",
            "spacing": 2,
            "alignment": "leading",
            "children": [
              {
                "type": "text",
                "content": "{temp}",
                "weight": "bold",
                "size": 24
              },
              {
                "type": "text",
                "content": "{condition}",
                "style": "secondary"
              }
            ]
          }
        ]
      },
      {
        "type": "divider"
      },
      {
        "type": "hstack",
        "spacing": 16,
        "children": [
          {
            "type": "vstack",
            "spacing": 2,
            "children": [
              { "type": "text", "content": "Feels like", "style": "secondary", "size": 11 },
              { "type": "text", "content": "{feels_like}", "weight": "medium" }
            ]
          },
          {
            "type": "vstack",
            "spacing": 2,
            "children": [
              { "type": "text", "content": "Humidity", "style": "secondary", "size": 11 },
              { "type": "text", "content": "{humidity}", "weight": "medium" }
            ]
          }
        ]
      },
      {
        "type": "if",
        "condition": "alert_active",
        "then": {
          "type": "vstack",
          "spacing": 4,
          "padding": 8,
          "background": "#FF3B30",
          "cornerRadius": 6,
          "children": [
            {
              "type": "text",
              "content": "Weather Alert",
              "weight": "semibold",
              "color": "#FF3B30",
              "size": 12
            },
            {
              "type": "text",
              "content": "{alert_message}",
              "size": 11
            }
          ]
        }
      }
    ]
  }
}
```

**What this demonstrates:**
- Nested `if` nodes for multi-way conditional rendering with `then`/`else` single nodes
- Dynamic icon selection using icon names (not emoji)
- Conditional sections (weather alert only shown when active)
- Styled alert box with background color and corner radius
- Combination of large display text and detail metrics
- Semantic colour usage for alerts

---

## Best Practices Illustrated

These examples demonstrate several best practices:

1. **Text styles**: Use `style: "secondary"` for de-emphasized text rather than hardcoded colours
2. **Consistent spacing**: Apply spacing at the container level for uniform layouts
3. **Frame sizing**: Use `frame.w` for column-based layouts
4. **Template clarity**: Use descriptive variable names like `{next_title}` rather than `{t}`
5. **Scrollable content**: Wrap variable-length lists in `scroll` nodes
6. **Action nodes**: Use `action` with `label`, `icon`, and `command` for clickable rows
7. **Dividers for sections**: Use `divider` nodes to visually separate content areas
8. **Conditional rendering**: Use `if` nodes with `then`/`else` to handle optional content
9. **Data iteration**: Use `foreach` with `items` and `child` for lists
10. **Minimum widths**: Apply `minW` in the `frame` to prevent overly narrow popups
