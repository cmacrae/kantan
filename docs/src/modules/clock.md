# Clock

Type: `clock`

Displays the current date and time using a configurable format string.

## Configuration

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `format` | string | *(required)* | Date format string (DateFormatter syntax) |
| `timezone` | string | system default | IANA timezone identifier (e.g. `"America/New_York"`). An unrecognised identifier uses the system timezone |

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
- `dd` - Day of month (zero-padded)
- `MMM` - Abbreviated month name
- `MMMM` - Full month name
- `yyyy` - Year with century

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
