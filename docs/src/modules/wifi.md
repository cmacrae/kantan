# WiFi

Type: `wifi`

Icon-only WiFi connection status indicator. Uses CoreWLAN with event-driven updates. The icon reflects signal strength, or shows that the Mac is connected to a personal hotspot. No text is displayed.

## Configuration

These keys go under the module's `config` key:

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `icons.strength` | array | `["wifi-1", "wifi-2", "wifi"]` | Icons for signal strength levels (weak to strong). Must not be empty |
| `icons.disconnected` | string | `"wifi-off"` | Icon when disconnected |
| `icons.hotspot` | string | `"circles-relation"` | Icon while connected to a personal hotspot |

Signal strength maps RSSI from -90 dBm (weakest) to -30 dBm (strongest), split evenly across the `icons.strength` entries. The module shows `disconnected` while WiFi is off or not associated with a network.

### Hotspot Icon

While the Mac is connected to a personal hotspot, such as an iPhone's, the module shows `icons.hotspot` in place of the signal-strength icon. kantan recognises a hotspot as a WiFi network macOS treats as expensive (metered). macOS marks an iPhone's Personal Hotspot this way whatever its name. kantan doesn't read the network's name, so no Location Services access is needed.

```yaml
icons:
  hotspot: device-mobile   # Replaces the default circles-relation
```

### Background Icon

When connected, the WiFi module renders a dimmed copy of the last `icons.strength` icon behind the current signal-strength icon, providing a visual reference for signal quality. This background icon is hidden while on a hotspot or at full signal strength.

## Behavior

The WiFi module is event-driven and updates automatically when:

- WiFi connection status changes (connected/disconnected)
- Connected network changes (BSSID)
- The network becomes or stops being a personal hotspot
- Signal strength (RSSI) changes (only when crossing an icon threshold)
- WiFi power state changes

## Examples

Basic WiFi status indicator:

```yaml
- name: wifi
  type: wifi
  placement: right
```

Custom signal strength icons:

```yaml
- name: wifi
  type: wifi
  placement: right
  config:
    icons:
      disconnected: wifi-off
      strength:
        - wifi-1    # Weak
        - wifi-2    # Fair
        - wifi       # Strong
```

With a custom hotspot icon:

```yaml
- name: wifi
  type: wifi
  placement: right
  config:
    icons:
      hotspot: device-mobile
```

With menu bar item masking:

```yaml
- name: wifi
  type: wifi
  placement: right
  mask:
    name: WiFi
```
