# Text

Type: `text`

Displays static text content. Useful for labels, separators, or custom status messages.

## Configuration

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `value` | string | *(required)* | The text to display |

## Behavior

The text module displays a static text value. It does not update or poll any system state.

## Examples

Simple text label:

```yaml
- name: greeting
  type: text
  placement: left
  config:
    value: "Hello, world"
```

Visual separator:

```yaml
- name: separator
  type: text
  placement: right
  config:
    value: "|"
```

Custom styled text:

```yaml
- name: status
  type: text
  placement: left
  config:
    value: "Status"
  style:
    fg: "#FF9500"
```

Multiple text modules:

```yaml
- name: label-system
  type: text
  placement: left
  config:
    value: "System"

- name: separator
  type: text
  placement: left
  config:
    value: "|"

- name: label-info
  type: text
  placement: left
  config:
    value: "Info"
```
