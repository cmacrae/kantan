# Icon

Type: `icon`

Displays a static icon. Useful for visual indicators, decorative elements, or masking native menu bar items with custom icons.

## Configuration

The icon module has no type-specific configuration fields. The displayed icon is set via the module's top-level `icon` field.

## Behavior

The icon module displays a static icon. It does not update or poll any system state.

The `icon` field can contain:
- Tabler icon names (e.g. `bell`, `star-filled`)
- Unicode characters
- Emoji characters

## Examples

Simple icon display:

```yaml
- name: dot
  type: icon
  placement: right
  icon: point-filled
```

Masking a native menu bar item:

```yaml
- name: focus
  type: icon
  placement: right
  icon: moon-filled
  mask:
    name: FocusModes
```

Custom styled icon:

```yaml
- name: notification
  type: icon
  placement: right
  icon: bell
  style:
    fg: "#FF9500"
```

Multiple icons as visual separators:

```yaml
- name: separator1
  type: icon
  placement: right
  icon: point-filled

- name: separator2
  type: icon
  placement: right
  icon: point-filled
```

## Common Use Cases

The icon module is commonly used with masking to replace native macOS menu bar items with custom icons while maintaining visual consistency with your theme.
