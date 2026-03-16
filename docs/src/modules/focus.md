# Focus

Type: `focus`

Displays a Focus mode indicator that appears when a macOS Focus mode is active.

## Configuration

The focus module has no type-specific configuration fields. The displayed icon is set via the module's top-level `icon` field (defaults to `"brain"` if not specified).

## Behavior

The focus module detects whether a macOS Focus mode is active by checking for the system FocusModes indicator window in the menu bar. This uses the same fast mechanism (~1ms) that kantan uses for menu bar masking and requires no special permissions.

The module polls every 2 seconds. When no Focus mode is active, the module hides itself automatically.

> **Note:** macOS Tahoe removed the distributed notifications for Do Not Disturb state changes, so event-driven detection is not possible. Polling the menu bar indicator window is the only viable approach that requires no permissions.

## Examples

Basic focus indicator:

```yaml
- name: focus
  type: focus
  placement: right
```

With a custom icon:

```yaml
- name: focus
  type: focus
  placement: right
  icon: moon-filled
```

Custom styled focus indicator:

```yaml
- name: focus
  type: focus
  placement: right
  icon: moon-filled
  style:
    fg: "#AF52DE"
```
