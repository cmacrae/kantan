# Focus

Type: `focus`

Displays a Focus mode indicator that appears when a macOS Focus mode is active, with an optional icon and style per mode.

## Configuration

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `icons` | object | -- | Focus mode → icon overrides |
| `style` | object | -- | Focus mode → style overrides |

The module's top-level `icon` field is shown for any mode without an entry in `icons` (defaults to `"brain"` if not specified).

### Mode Icons

The `icons` field maps Focus modes to icons. Keys match a mode's name as shown in System Settings (e.g. `Do Not Disturb`, or the name of a custom Focus), or its identifier (e.g. `com.apple.donotdisturb.mode.default`).

```yaml
icons:
  Mindfulness: flower-filled
  Do Not Disturb: moon-filled
  Sleep: bed-filled
  Work: briefcase-filled
```

### Mode Styles

The `style` field maps Focus modes to style overrides, keyed the same way as `icons`. Modes without an entry use the module's `style`. Like the [power module's state styles](/docs/modules/power#style-overrides), each value is either a colour string (sets `fg`) or an object with `fg`, `bg`, `icon.fg` and `text.fg`. Colours can be hex or `{theme(name)}` templates.

```yaml
style:
  Mindfulness: '{theme(teal)}'   # Shorthand: sets fg
  Do Not Disturb: '{theme(mauve)}'
  Work:                          # Expanded form
    icon:
      fg: '{theme(peach)}'
    bg: '{theme(surface0)}'
```

### Template Variables

| Variable | Description |
|----------|-------------|
| `{mode}` | Name of the active Focus mode |

## Behavior

With [Full Disk Access](/docs/configuration/masking#granting-full-disk-access), the focus module reads the Do Not Disturb database in `~/Library/DoNotDisturb/DB`:

- **Manually or automatically activated Focus** (Control Centre, Shortcuts, Sleep, Driving, smart activation) is recorded by macOS with the mode it activated. The active mode is known exactly.
- **Scheduled Focus** isn't recorded by macOS. kantan evaluates each mode's enabled schedules instead. Turning Focus off or switching modes ends a scheduled Focus until its next scheduled start, as macOS does.

When both apply, the most recently started one wins. The module polls every 2 seconds and hides itself when no Focus mode is active; when masking the system Focus indicator, a hidden module releases its menu bar slot.

Without Full Disk Access, the module falls back to detecting the system FocusModes menu bar indicator. That fallback reports whether Focus is on but not which mode, so `icons`, `style` and `{mode}` have no effect. On macOS 27 and later the indicator's presence can't be observed either, so the fallback shows the module whenever the Focus indicator has a slot in the menu bar layout.

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

Per-mode icons and colours with the mode name as a tooltip, masking the system indicator:

```yaml
- name: focus
  type: focus
  placement: right
  mask:
    name: Focus
  style:
    fg: '{theme(pink)}'
  config:
    icons:
      Mindfulness: flower-filled
      Do Not Disturb: moon-filled
      Sleep: bed-filled
    style:
      Mindfulness: '{theme(teal)}'
      Do Not Disturb: '{theme(mauve)}'
  interaction:
    hover:
      type: tooltip
      content: "{mode}"
```
