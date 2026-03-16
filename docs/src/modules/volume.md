# Volume

Type: `volume`

Icon-only system audio volume indicator. Uses CoreAudio with real-time callbacks for immediate updates. The icon reflects the current volume level and output device. No text is displayed.

## Configuration

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `icons.level` | array | `["volume-4", "volume-2", "volume"]` | Icons for volume levels (low to high) |
| `icons.muted` | string | `"volume-off"` | Icon when muted |
| `icons.device` | object | see below | Device-specific icon overrides |

### Device Icons

The `icons.device` field maps audio device name substrings (case-insensitive) to icon names. When the current output device name contains a matching key, that icon is used instead of the level-based icons.

Default device icons:

```yaml
icons:
  device:
    AirPods: device-airpods
    Headphones: headphones
```

Set `device: {}` to disable device-specific icons entirely.

## Behavior

The volume module is event-driven and updates automatically when:

- Volume level changes (via keyboard, control center, etc.)
- Mute state changes
- Default audio output device changes

Updates are triggered via CoreAudio property listener callbacks.

## Examples

Basic volume indicator:

```yaml
- name: volume
  type: volume
  placement: right
```

Custom icons for different volume levels:

```yaml
- name: volume
  type: volume
  placement: right
  config:
    icons:
      muted: volume-off
      level:
        - volume-4    # Low
        - volume-2    # Medium
        - volume      # High
```

With device-specific overrides:

```yaml
- name: volume
  type: volume
  placement: right
  config:
    icons:
      muted: volume-off
      level:
        - volume-4
        - volume-2
        - volume
      device:
        AirPods: device-airpods
        Headphones: headphones
```

With menu bar item masking:

```yaml
- name: volume
  type: volume
  placement: right
  mask:
    name: Sound
```
