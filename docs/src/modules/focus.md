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

The module polls every 2 seconds and hides itself when no Focus mode is active. A hidden module that masks the system Focus indicator releases its menu bar slot. How it knows which mode is active depends on what kantan may read.

### With Full Disk Access

Full Disk Access is optional, and only needed for `icons`, `style` and `{mode}`: it lets the module read the Do Not Disturb database in `~/Library/DoNotDisturb/DB`, which names the active mode.

- **Manually or automatically activated Focus** (Control Centre, Shortcuts, Sleep, Driving, smart activation) is recorded by macOS with the mode it activated. The active mode is known exactly.
- **Scheduled Focus** isn't recorded by macOS. kantan evaluates each mode's enabled schedules instead. Turning Focus off or switching modes ends a scheduled Focus until its next scheduled start, as macOS does.

When both apply, the most recently started one wins.

#### Granting Full Disk Access

In *System Settings → Privacy & Security → Full Disk Access*, click **+**, press ⌘⇧G and enter the path of kantan's binary, then restart kantan. This opens the pane and shows the running binary in Finder, ready to drag into the list:

```sh
open "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AllFiles"
open -R "$(ps -o comm= -p "$(pgrep -x kantan)")"
```

macOS ties the grant to that path. A Nix rebuild that changes the store path needs it repeated. kantan checks for access once at launch and never touches the database without it. No prompt or "would like to access data from other apps" notification appears either way.

### Without Full Disk Access

The module detects the system Focus indicator in the menu bar instead. The indicator shows whether Focus is on but not which mode. `icons`, `style` and `{mode}` have no effect. kantan asks for [Accessibility permission](/docs/configuration/masking#granting-accessibility) in this case. With it, the indicator is detected live. Without it:

- **macOS 15 and 26** detect the indicator's window, which isn't reliable on macOS 15.
- **macOS 27 and later** can only see the indicator's slot in the saved menu bar layout, not whether it's shown. The module shows whenever that slot exists.

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
