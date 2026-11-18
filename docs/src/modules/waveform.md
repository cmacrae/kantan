# Waveform

Type: `waveform`

Draws the sound the Mac is playing as it plays, from any app: a music app, a video in a browser, a game. It pairs with the [now-playing plugin](../plugins/now-playing.md), each in its own place in the bar.

## Configuration

These keys go under the module's `config` key:

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `style` | string | `bars` | `bars` or `wave` |
| `bars` | number | `8` | How many bars the `bars` style draws, up to 256 |
| `width` | number | `40` | Width of the `wave` style's line in points |
| `height` | number | `14` | Height in points |
| `hide` | string | `silent` | `silent` hides the module while there is no sound; `never` keeps it |
| `silenceDelay` | number | `0.3` | Seconds of quiet before the sound counts as stopped |
| `matchWidth` | string | -- | Name of a module whose width this one follows |
| `sensitivity` | number | follows the bars | How much taller than measured the sound is drawn |
| `sources` | string | `apps` | Whose sound is drawn: `apps` or `all` |
| `exclude` | array | -- | Apps whose sound isn't drawn, by name or bundle identifier |
| `rainbow.enabled` | bool | `false` | Colour the bars from a palette |
| `rainbow.random` | bool | `true` | Shuffle the palette (the same way each time, no two alike side by side) |
| `rainbow.colors` | array | -- | The palette (hex or `{theme(name)}`) |
| `gradient.low` | string | -- | Colour of the lowest frequency's bar |
| `gradient.high` | string | -- | Colour of the highest frequency's bar |

```yaml
- name: waveform
  type: waveform
  placement: notchleft
  style:
    icon:
      fg: "{theme(green)}"
  config:
    style: bars
    bars: 8
  interaction:
    click:
      type: toggle
```

### Styles

`bars` draws the sound's spectrum: a bar for each band of frequencies, the lowest on the left, each as tall as its band is loud. `wave` draws the wave of the sound itself as a line, `width` points wide, fading out toward each end.

Both are drawn in the colour of the module's icon, set with `style.icon.fg` or `style.fg`, unless the bars have colours of their own.

### Following Another Module's Width

`matchWidth` names a module for the waveform to be as wide as, such as a now-playing module on the other side of the notch:

```yaml
- name: waveform
  type: waveform
  placement: notchleft
  config:
    matchWidth: now-playing
    bars: 8          # the fewest bars it draws
```

The waveform draws as many bars as fit the other module's width, or as wide a wave, and grows and shrinks with it: as the track's text changes, and as a hover slides more of it out. `bars` and `width` are the least it draws. A short title doesn't shrink it away. They are also what it draws while the other module is out of the bar, or when no module has that name. It draws 256 bars at most.

### Whose Sound

By default the waveform draws the sound of apps: those in the Dock, and the helpers that play for them, as a browser's do. The system's own sounds, such as a notification's, aren't drawn, and neither are apps that live in the menu bar alone. `sources: all` draws every sound the Mac plays.

`exclude` leaves apps out, by name or bundle identifier in any case:

```yaml
config:
  sources: apps
  exclude: [Zoom, com.apple.FaceTime]
```

An app plays its own notification sounds as it plays anything else, so those are drawn unless the app is excluded.

### Detail and Sensitivity

The sound is measured in 256 bands of frequency. A waveform shows as many of them as it has bars: 8 bars each take the loudest of 32 bands, and 128 bars show two bands each. So a wider waveform shows more of the sound's detail rather than a smoother copy of it. The lowest bands are closer together than the sound can be told apart in the moment, so the bars at the low end of a very wide waveform rise and fall together.

A band that covers less of the sound holds less of it, so a wide waveform's bars would be shorter than a narrow one's. `sensitivity` is how much taller than measured the sound is drawn: `2` twice as tall, up to the module's height. Left out, it follows the number of bars as they change: 1 up to 8 bars, and a quarter more for each doubling past that, so 1.5 at 32 bars and 2 at 128. Set it to hold it at one value. The `wave` style draws at 1 unless set.

### Colours

The bars can each have their own colour, in one of three ways:

```yaml
# From low to high: the lowest frequency's bar is `low`, the highest's
# `high`, and those between pass from one to the other.
gradient:
  low: "{theme(blue)}"
  high: "{theme(pink)}"

# A rainbow, shuffled as the workspace module shuffles its own.
rainbow:
  enabled: true
  colors: ["{theme(red)}", "{theme(peach)}", "{theme(yellow)}", "{theme(green)}", "{theme(blue)}", "{theme(mauve)}"]

# A strict order: the bars take the colours as listed, going round again
# past the last.
rainbow:
  enabled: true
  random: false
  colors: ["{theme(red)}", "{theme(peach)}", "{theme(yellow)}"]
```

A `gradient` comes before a `rainbow` when a module has both. The `wave` style's line passes through the same colours from left to right. With the native appearance the module's own colour is used.

### Hiding

The module leaves the bar as the sound stops, and returns as soon as something sounds again. `silenceDelay` is how long the quiet lasts, in seconds, before it counts as stopped: `0.3` by default, which passes over the briefest gaps within the sound. With `0` the module goes the moment playback pauses, and also at any gap, such as between two tracks. Set `hide: never` to keep it in the bar.

### Opening the Source

A click of type `toggle` brings the app making the sound to the front. When several apps are playing at once, it is the loudest of them at that moment. For sound from a browser, that is the browser, not the tab.

## Template Variables

| Variable | Example | Description |
|----------|---------|-------------|
| `{state}` | `Playing` | `Playing` while there is sound, `Silent` otherwise |

## How It Works

kantan listens to the Mac's output through a Core Audio tap, which reads what apps play without changing it. macOS may ask for permission to record system audio the first time. Without it the module stays hidden.

### The Recording Indicator

While the waveform is listening, macOS shows its purple dot in the menu bar, at the right of the bar, as it does for any app reading the Mac's sound. This is expected. The dot is drawn by macOS, not kantan, and an app can't hide or move it: it is how macOS tells you something is listening. kantan only measures the sound to draw it, and keeps and sends none of it.

kantan listens only while an app it would draw is playing. The dot comes and goes with the sound: it appears as playback starts and goes about three seconds after the last app stops. An app that keeps its output open while silent, as some do, keeps the dot too. `exclude` it to let the dot go.
