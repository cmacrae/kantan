# Bluetooth

Type: `bluetooth`

Icon-only Bluetooth status indicator. Shows whether Bluetooth is powered on or off and whether any devices are connected. No text is displayed.

## Configuration

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `icon` | string | `"bluetooth"` | Icon when Bluetooth is on |
| `disabledIcon` | string | `"bluetooth-off"` | Icon when Bluetooth is off |

These go under `config`. The module-level `icon` field has no effect on this module.

## Behavior

The Bluetooth module is event-driven and updates automatically when:

- A Bluetooth device connects or disconnects
- Bluetooth power state changes (on/off)

Reading Bluetooth state needs kantan's Bluetooth permission. macOS asks for it the first time the module starts. Until it is answered, the module shows `icon` dimmed.

The module uses an inactive (dimmed) state to indicate status:

- **Bluetooth off**: Shows the `disabledIcon` in a dimmed state
- **Bluetooth on, no devices connected**: Shows the `icon` in a dimmed state
- **Bluetooth on, devices connected**: Shows the `icon` in an active (full brightness) state

## Examples

Basic Bluetooth status indicator:

```yaml
- name: bluetooth
  type: bluetooth
  placement: right
```

Custom icons for on/off states:

```yaml
- name: bluetooth
  type: bluetooth
  placement: right
  config:
    icon: bluetooth
    disabledIcon: bluetooth-off
```

With menu bar item masking:

```yaml
- name: bluetooth
  type: bluetooth
  placement: right
  mask:
    name: Bluetooth
```
