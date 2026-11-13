# Menu Bar Masking

Menu bar masking places kantan modules directly over native macOS menu bar items. The module replaces the item visually. Clicks still reach the native item underneath.

## Overview

When a module is configured with masking, kantan:

1. Detects the position of the native menu bar item on each display
2. Positions the kantan module at the same coordinates, sized to the item's width
3. Overlays the native item with the custom module, passing clicks through to it

Unmasked modules with the same placement are laid out inward of the masked ones, clear of the native items being masked.

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

Third-party items are named by their app (see [Third-Party Items](#third-party-items)):

```yaml
- name: rift-indicator
  type: command
  placement: right
  mask:
    name: rift
  config:
    command: kantan-plugin-rift-indicator
    output: json
```

### By Index

Items are indexed right-to-left (index 0 is the rightmost item), across every item kantan detects on the display. When both `index` and `name` are set, `index` is used:

```yaml
- name: first-item
  type: text
  placement: right
  mask:
    index: 0
  config:
    value: ""
```

## Item Detection

How kantan finds native menu bar items depends on whether it has Accessibility permission:

- **With Accessibility** (any macOS release) -- kantan reads every status item, system and third-party, through the Accessibility API: its live position and width, and the item's name or owning app. Masks follow items as they appear, disappear, move or change width, within about a second.
- **Without Accessibility** -- only system items can be located:
  - **macOS 15 and 26** -- Each status item is its own WindowServer window. kantan reads their geometry with `CGWindowListCopyWindowInfo`.
  - **macOS 27 and later** -- MenuBarAgent draws every status item into a single menu bar surface. Individual items aren't windows. kantan reads the `NSStatusItem Preferred Position` values in `com.apple.controlcenter` defaults and lays Control Centre's items out right-to-left from the screen's right edge. They hold the layout carried over from macOS 26. macOS 27 doesn't update them. Masks don't follow items you rearrange there. Items that appear only while active (Focus, Now Playing, camera/microphone indicators) keep their slot even while they are not shown.

### Granting Accessibility

Once per launch, kantan asks for Accessibility permission when it loads a config in which any module has a `mask` (or a [focus module](../modules/focus.md#behavior) can't read the Focus database). macOS then lists kantan in *System Settings → Privacy & Security → Accessibility*. Switching it on moves masks to live positions within a second. kantan doesn't need a restart. kantan uses the permission only to read menu bar items.

macOS ties the permission to the binary it was granted to. A Nix rebuild that changes kantan's store path needs it granted again. kantan asks again on its next launch.

## Name Resolution

With Accessibility, or on macOS 27 and later, items carry names. `mask.name` (after alias resolution) is matched against them directly, ignoring case:

- **System items** match their Control Centre identifier (`WiFi`, `FocusModes`), their Accessibility identifier (`com.apple.menuextra.wifi`) or its last part (`wifi`), and the aliases below.
- **Third-party items** match their app's bundle identifier, name or executable name.

On macOS 15 and 26 without Accessibility, name-based masking uses a multi-step resolution chain:

1. **Preferred position match** -- The name is looked up in `com.apple.controlcenter` defaults via `NSStatusItem Preferred Position <name>`, then matched against detected menu bar items by position (tight tolerance).

2. **Rank-based fallback** -- When items shift (e.g. battery percentage changes width), absolute positions drift while their order holds. kantan builds a catalog of all visible Control Centre items sorted by preferred position and matches by rank.

3. **Owner name fallback** -- If neither position-based method works, kantan matches the window owner name, ignoring case.

## Maskable System Items

System items are named by their Control Centre identifier, the one used in `NSStatusItem Preferred Position <identifier>`. The following friendly names are supported via built-in aliases:

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

## Third-Party Items

With Accessibility, any app's menu bar item can be masked by naming the app, by its bundle identifier, its name or its executable name:

```yaml
mask:
  name: com.1password.1password   # or: 1Password
```

Apps without a bundle identifier, such as [Rift](https://github.com/acsandmann/rift), are named by executable (`rift`). When an app has several items, the rightmost is masked. Use `index` for another. kantan doesn't read background-only processes. They can't own status items.

### Clock Special Case

Without Accessibility on macOS 15 and 26, the `Clock` item has no preferred position in the plist. When the menu bar clock is enabled, it occupies the rightmost position (index 0 in the right-to-left sorted item list). kantan detects this by checking the `NSStatusItem VisibleCC Clock` defaults key.

## Default Click Behavior

A masked module is `passthrough` unless it sets a click type. Its clicks go to the native menu bar item underneath. A `hover` tooltip still shows. Clicking it opens the native system menu (e.g. clicking a masked WiFi module opens the WiFi system menu).

To have the module handle clicks in place of the native item, set an explicit click interaction:

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

Masking works per-screen in multi-display setups. Each display's menu bar shows the same items at the same distance from its right edge. Masked modules sit over them on every display the module appears on.

## Limitations

### Third-Party Menu Bar Items

Third-party items can only be masked with Accessibility permission. Without it, kantan can't tell them apart. On macOS 26 all status item windows are reported as owned by Control Centre, with no titles (FB18327911). On macOS 27 they aren't windows at all.

### Hidden Menu Bar

Masks sit over the native menu bar and don't line up when macOS hides it. kantan logs a warning at startup when the system menu bar is set to hide automatically on the desktop or in full screen.

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

2. **Mirror the item's width** -- A masked module is sized to the native item, so match what changes its width (see the battery percentage note above).

3. **Test on multiple displays** -- With several displays, check masking on each one.

4. **Consider fallback behavior** -- A masked module is hidden while its item can't be found: when the item isn't shown (e.g. Focus is off), or for a third-party item while kantan lacks Accessibility permission.
