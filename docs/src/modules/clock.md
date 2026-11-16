# Clock

Type: `clock`

Displays the current date and time using a configurable format string.

## Configuration

These keys go under the module's `config` key:

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `format` | string | *(required)* | Date format string (DateFormatter syntax) |
| `timezone` | string | system default | IANA timezone identifier (e.g. `"America/New_York"`). An unrecognised identifier uses the system timezone |
| `formats` | object | -- | Variable name → format string, each exposed as a [template variable](#template-variables) |

The clock redraws every second.

## Format String

The `format` field accepts standard DateFormatter (Unicode TR 35) format specifiers:

- `HH` - Hour (24-hour format, 00-23)
- `hh` - Hour (12-hour format, 01-12)
- `mm` - Minute (00-59)
- `ss` - Second (00-59)
- `a` - AM/PM
- `E` - Abbreviated weekday name
- `EEEE` - Full weekday name
- `d` - Day of month
- `do` - Day of month with its English ordinal suffix (`1st`, `2nd`, `16th`)
- `dd` - Day of month (zero-padded)
- `MMM` - Abbreviated month name
- `MMMM` - Full month name
- `yyyy` - Year with century

Text in single quotes is shown as written, so `'do'` is the letters `do`.

## Template Variables

Each entry in `formats` sets a variable of that name to the current time in its format, for the module's [tooltip](../configuration/modules.md#hover-interaction) and views. They use the module's `timezone`.

```yaml
config:
  format: "HH:mm"
  formats:
    date: "E MMM do"   # Mon Nov 16th
```

## Examples

Basic time display:

```yaml
- name: clock
  type: clock
  placement: right
  config:
    format: "HH:mm"
```

Full date and time:

```yaml
- name: clock
  type: clock
  placement: right
  config:
    format: "E d MMM HH:mm"
```

With a specific timezone:

```yaml
- name: utc-clock
  type: clock
  placement: right
  config:
    format: "HH:mm"
    timezone: "UTC"
```

With menu bar item masking:

```yaml
- name: clock
  type: clock
  placement: right
  config:
    format: "HH:mm"
  mask:
    name: Clock
```

The time in the bar and the date as a tooltip:

```yaml
- name: clock
  type: clock
  placement: right
  config:
    format: "HH:mm"
    formats:
      date: "E MMM do"
  interaction:
    hover:
      type: tooltip
      content: "{date}"
```
