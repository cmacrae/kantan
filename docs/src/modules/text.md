# Text

Type: `text`

Displays static text content. Useful for labels, separators, or custom status messages.

## Configuration

These keys go under the module's `config` key:

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `value` | string | *(required)* | The text to display. Quote values YAML would otherwise read as a number or boolean (e.g. `"42"`), or the module is skipped |

## Behavior

The text module displays a static text value. It does not update or poll any system state.

`kantan trigger <name> set value=...` replaces the text until the module next refreshes, such as on a space change or wake. Add `duration=<seconds>` to hold it for that long instead.

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
    fg: "{theme(peach)}"
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
