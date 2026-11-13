# Volume

Type: `volume`

Icon-only system audio volume indicator. Uses CoreAudio with real-time callbacks for immediate updates. The icon reflects the current volume level and output device. No text is displayed.

## Configuration

These keys go under the module's `config` key:

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `icons.level` | array | `["volume-4", "volume-2", "volume"]` | Icons for volume levels (low to high), split evenly across 0–100%. Must not be empty |
| `icons.muted` | string | `"volume-off"` | Icon when muted |
| `icons.device` | object | see below | Device-specific icon overrides |

### Device Icons

The `icons.device` field maps audio device name substrings (case-insensitive) to icon names. While the audio output is a device whose name contains a key, the module shows that key's icon in place of the volume level icons. For example, put your AirPods in and macOS switches the output to them. Their name (such as "AirPods Pro") contains `AirPods`. The module then shows `device-airpods`. Take them out and it goes back to the level icons. The `muted` icon takes precedence over device icons.

Default device icons:

```yaml
icons:
  device:
    AirPods: device-airpods
    Headphones: headphones
```

Setting `icons.device` replaces these defaults rather than adding to them. Set `device: {}` to disable device-specific icons entirely.

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
