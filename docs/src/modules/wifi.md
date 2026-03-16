# WiFi

Type: `wifi`

Icon-only WiFi connection status indicator. Uses CoreWLAN with event-driven updates and reads the SSID from IOKit (no Location Services required). The icon reflects signal strength. No text is displayed.

## Configuration

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `icons.strength` | array | `["wifi-1", "wifi-2", "wifi"]` | Icons for signal strength levels (weak to strong) |
| `icons.disconnected` | string | `"wifi-off"` | Icon when disconnected |
| `icons.ssid` | object | -- | SSID-specific icon overrides |

### SSID Icons

The `icons.ssid` field maps network names to icons. When the current SSID matches a key exactly, that icon is shown instead of the signal-strength icon.

iPhone hotspot detection is always active: any SSID ending with "iPhone" (matching default hotspot names like "Alice's iPhone") automatically uses the `circles-relation` icon. You can override this by setting an `iPhone` key in the `icons.ssid` map.

```yaml
icons:
  ssid:
    "My Network": home
    iPhone: circles-relation   # Overrides the built-in default for iPhone hotspots
```

### Background Icon

When connected, the WiFi module renders a dimmed "full strength" icon behind the current signal-strength icon, providing a visual reference for signal quality. This background icon is automatically hidden when an SSID-specific icon override is active or when signal is at full strength.

## Behavior

The WiFi module is event-driven and updates automatically when:

- WiFi connection status changes (connected/disconnected)
- Connected network changes (SSID/BSSID)
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

With SSID-specific icons:

```yaml
- name: wifi
  type: wifi
  placement: right
  config:
    icons:
      disconnected: wifi-off
      strength:
        - wifi-1
        - wifi-2
        - wifi
      ssid:
        "Home Network": home-wifi
        iPhone: circles-relation
```

With menu bar item masking:

```yaml
- name: wifi
  type: wifi
  placement: right
  mask:
    name: WiFi
```
