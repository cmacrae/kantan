# Menu Bar Masking

Menu bar masking allows kantan modules to be positioned directly over native macOS menu bar items, effectively replacing them visually while maintaining functionality through custom interaction handlers.

## Overview

When a module is configured with masking, kantan:

1. Detects the position of the native menu bar item on each display
2. Positions the kantan module at the same coordinates
3. Overlays the native item with the custom module

This creates a seamless integration where kantan modules appear to replace system items.

## Configuration

Add a `mask:` section to any module to enable masking:

### By Name

```yaml
- name: clock
  type: clock
  placement: right
  mask:
    name: Clock
  config:
    format: "HH:mm"
```

### By Index

Items are indexed right-to-left (index 0 is the rightmost item):

```yaml
- name: first-item
  type: text
  placement: right
  mask:
    index: 0
  config:
    value: ""
```

## Name Resolution

Name-based masking uses a multi-step resolution chain:

1. **Preferred position match** -- The name is looked up in `com.apple.controlcenter` defaults via `NSStatusItem Preferred Position <name>`, then matched against detected menu bar items by position (tight tolerance).

2. **Rank-based fallback** -- When items shift (e.g. battery percentage changes width), absolute positions drift while their order holds. kantan builds a catalog of all visible Control Centre items sorted by preferred position and matches by rank.

3. **Owner name fallback** -- If neither position-based method works, kantan matches the window owner name, ignoring case.

## Maskable System Items

Only **system menu bar items** (Control Centre items) can be reliably masked. The following friendly names are supported via built-in aliases that map to the internal plist identifiers used in `NSStatusItem Preferred Position <identifier>`:

| Friendly Name | Plist Identifier | System Item |
|---------------|------------------|-------------|
| `Clock` | *(special)* | Menu bar clock |
| `ControlCenter` | `BentoBox-0` | Control Centre icon |
| `Volume` | `Sound` | Volume/Sound |
| `Focus` | `FocusModes` | Focus modes |
| `Camera` | `AudioVideoModule` | Camera indicator |
| `Microphone` | `AudioVideoModule` | Microphone indicator |

A name missing from the alias table is passed through as a plist identifier, which makes any raw plist identifier a valid mask name. For example, `Battery`, `WiFi`, and `Bluetooth` work because they are already the plist identifiers themselves.

Additional known identifiers: `NowPlaying`, `Display`, `ScreenMirroring`, `UserSwitcher`, `AccessibilityShortcuts`, `Hearing`, `KeyboardBrightness`, `AirDrop`, `StageManager`.

### Clock Special Case

The `Clock` item has no preferred position in the plist. When the menu bar clock is enabled, it occupies the rightmost position (index 0 in the right-to-left sorted item list). kantan detects this by checking the `NSStatusItem VisibleCC Clock` defaults key.

## Default Click Behavior

Masked modules automatically receive `passthrough` click behavior, so clicks pass through to the underlying native menu bar item. This means clicking a masked module opens the native system menu (e.g. clicking a masked WiFi module opens the WiFi system menu).

To override this, set an explicit click interaction:

```yaml
mask:
  name: Battery
interaction:
  click:
    type: popup
    view:
      type: vstack
      children:
        - type: text
          content: "Custom battery popup"
```

## Multi-Display Support

Masking works per-screen in multi-display setups. Each display's menu bar is analyzed independently, and modules are positioned according to the item locations on that specific display.

## Limitations

### Third-Party Menu Bar Items

Third-party menu bar items **cannot** currently be masked due to macOS system limitations.

**Technical background:** On macOS 26 (Tahoe) and later, all status bar items (including third-party apps) are reported by the system as owned by Control Centre. Window titles are nil, and per-process queries return the same full list for every application. This makes it impossible to distinguish third-party items from system items programmatically.

The only workaround would be the Accessibility API (`AXExtrasMenuBar`), which requires Accessibility permission. However, kantan is distributed as a bare Nix binary (not an .app bundle), so it cannot request or receive this permission through System Settings.

This limitation has been documented in Apple Feedback Assistant as FB18327911.

### Future Improvements

If Apple fixes the underlying API or if kantan moves to .app bundle distribution, third-party masking may become feasible. For now, only system items can be masked. Users can hack around this limitation by placing 3rd party menubar items in their native menubar and placing a masked module over it by smartly configuring its position, but this'll only work if the 3rd party icon stays at a fixed position.

## Example Configurations

**Replace system clock:**
```yaml
- name: clock
  type: clock
  placement: right
  mask:
    name: Clock
  config:
    format: "HH:mm"
  interaction:
    click:
      type: popup
      view:
        type: vstack
        children:
          - type: text
            content: "Current Time"
          - type: text
            content: "{time}"
```

**Replace battery indicator:**
```yaml
- name: battery
  type: power
  placement: right
  mask:
    name: Battery
  config:
    showLevel: true
```

> With `showLevel` enabled in kantan, show the percentage on the native indicator too (Settings > Menu Bar > 'Battery Options' > 'Show Percentage'). It sets the native indicator's width and position.

**Replace WiFi indicator:**
```yaml
- name: wifi
  type: wifi
  placement: right
  mask:
    name: WiFi
```

**Replace volume indicator:**
```yaml
- name: volume
  type: volume
  placement: right
  mask:
    name: Volume
```

## Best Practices

1. **Use the same placement as the native item** -- System items sit on the right. Use `placement: right` for masked modules.

2. **Provide equivalent functionality** -- If masking a system item, ensure your module provides similar or enhanced functionality through interaction handlers.

3. **Test on multiple displays** -- With several displays, check masking on each one.

4. **Consider fallback behavior** -- If the system item is not present (e.g., user disabled it), the module will still appear at its placement position without masking.
