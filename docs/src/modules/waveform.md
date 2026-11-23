# Waveform

Type: `waveform`

Draws the sound the Mac is playing as it plays, from any app: a music app, a video in a browser, a game. It pairs with the [now-playing plugin](../plugins/now-playing.md), each in its own place in the bar.

## Configuration

These keys go under the module's `config` key:

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `style` | string | `bars` | `bars`, `wave`, `flow`, `scroll`, `spectrogram`, `line` or `dots` |
| `bars` | number | `8` | How many bars the `bars` style draws, or columns the `dots` style, up to 256 |
| `width` | number | `40` | Width in points of every style but `bars` and `dots` |
| `speed` | number | `15` | How fast the `scroll` and `spectrogram` styles scroll, in points a second |
| `wave.lock` | bool | `false` | Hold a steady sound's wave still |
| `wave.glow` | bool | `false` | Leave the waves just drawn fading beneath the newest |
| `wave.loudness` | bool | `false` | Draw a louder sound with a thicker line |
| `wave.tone` | bool | `false` | Colour the line by where the sound sits between low and high |
| `wave.curve` | bool | `false` | Draw the wave as a smooth curve |
| `wave.fill` | bool | `false` | Fill faintly between the wave and its middle |
| `wave.stereo` | bool | `false` | Draw the left and right sides as a line each |
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
| `gradient.colors` | array | -- | Two or more colours the bars pass through, in place of `low` and `high` |

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

| Style | What it draws |
|-------|---------------|
| `bars` | The sound's spectrum: a bar for each band of frequencies, the lowest on the left, each as tall as its band is loud |
| `dots` | The same spectrum as columns of dots, as many lit from the bottom as the band is loud |
| `line` | The same spectrum as one curve, filled faintly beneath |
| `wave` | The wave of the sound itself as a line, fading out toward each end |
| `flow` | Three ribbons, for the low, middle and high frequencies, each as tall as its frequencies are loud and moving along at its own pace |
| `scroll` | How loud the sound has been, as bars scrolling from right to left |
| `spectrogram` | The spectrum over time, scrolling from right to left: the lowest frequencies at the bottom, each point brighter the louder its frequencies were |

`bars` and `dots` are as wide as their bars. The others are `width` points wide.

All are drawn in the colour of the module's icon, set with `style.icon.fg` or `style.fg`, unless the module has [colours of its own](#colours).

With *Reduce motion* on (*System Settings → Accessibility → Display*), `flow` stops moving along, `scroll` and `spectrogram` move a whole step at a time, and the `wave` style's `glow` is left out.

`scroll` and `spectrogram` move at `speed` points a second, 15 unless set. A 40 point module then shows under three seconds of the sound, and a wider one more: set `width`, or follow another module with `matchWidth`.

### The Wave

The `wave` style draws a plain line unless told otherwise. Each of these, under `wave`, adds to it, and they can be used together:

```yaml
config:
  style: wave
  wave:
    lock: true
    glow: true
    loudness: true
```

| Key | What it does |
|-----|--------------|
| `lock` | Begins the wave where the sound rises through zero, as an oscilloscope does. A steady note then stands still, and changes shape as the sound does, where it would otherwise shimmer sideways |
| `glow` | Leaves the last few waves fading beneath the newest. It suits `lock`, which keeps them in step |
| `loudness` | Draws a louder sound with a thicker line. The wave is always drawn at its full height, so this is what tells loud from quiet |
| `tone` | Colours the whole line by the sound's tone. See [Tone](#tone) |
| `curve` | Draws a smooth curve in place of straight strokes, with less of the wave's fine detail |
| `fill` | Fills faintly between the wave and its middle |
| `stereo` | Draws the left and right sides of the sound as a line each: in a gradient's first and last colours, or without one, the right side fainter. They part where the sound is wide and lie together where it isn't. `tone` has no effect with it |

### Tone

With `wave.tone`, the line is one colour that follows where the sound sits between its low and high frequencies: toward the first of the module's colours while the bass carries it, toward the last while it is bright. It needs a `gradient` or a `rainbow` to take its colours from.

The tone is judged against the last fifteen seconds of the sound, not on a fixed scale. The lowest the sound has lately sat is the first colour and the highest the last. Every track then moves through all of the colours. A colour doesn't stand for a fixed pitch. It eases to each new colour over about half a second, following the parts of a song more than its beats.

Colours near each other suit it best, since the line passes through each on the way to the next:

```yaml
config:
  style: wave
  wave:
    tone: true
  gradient:
    colors: ["{theme(pink)}", "{theme(mauve)}", "{theme(blue)}", "{theme(teal)}", "{theme(green)}"]
```

A `rainbow` gives its colours once each, in their order. Set `random: false` to keep them as listed.

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

The waveform draws as many bars as fit the other module's width, or is as wide itself in a style without bars, and grows and shrinks with it: as the track's text changes, and as a hover slides more of it out. `bars` and `width` are the least it draws. A short title doesn't shrink it away. They are also what it draws while the other module is out of the bar, or when no module has that name. It draws 256 bars at most.

### Whose Sound

By default the waveform draws the sound of apps: those in the Dock, and the helpers that play for them, as a browser's do. The system's own sounds, such as a notification's, aren't drawn, and neither are apps that live in the menu bar alone. `sources: all` draws every sound the Mac plays.

`exclude` leaves apps out, by name or bundle identifier in any case:

```yaml
config:
  sources: apps
  exclude: [Zoom, com.apple.FaceTime]
```

An app plays its own notification sounds as it plays anything else, so those are drawn unless the app is excluded.

kantan listens once for every waveform module, so they all draw the same sound. An app any of them excludes is left out of them all. `sources: all` takes effect only when every waveform module sets it: one left at `apps` keeps them all to the sound of apps.

### Detail and Sensitivity

The sound is measured in 256 bands of frequency. A waveform shows as many of them as it has bars: 8 bars each take the loudest of 32 bands, and 128 bars show two bands each. So a wider waveform shows more of the sound's detail rather than a smoother copy of it. The lowest bands are closer together than the sound can be told apart in the moment, so the bars at the low end of a very wide waveform rise and fall together.

A band that covers less of the sound holds less of it, so a wide waveform's bars would be shorter than a narrow one's. `sensitivity` is how much taller than measured the sound is drawn: `2` twice as tall, up to the module's height. Left out, it follows the number of bars as they change: 1 up to 8 bars, and a quarter more for each doubling past that, so 1.5 at 32 bars and 2 at 128. Set it to hold it at one value. The styles without bars draw at 1 unless set.

### Colours

The bars can each have their own colour, in one of four ways:

```yaml
# From low to high: the lowest frequency's bar is `low`, the highest's
# `high`, and those between pass from one to the other.
gradient:
  low: "{theme(blue)}"
  high: "{theme(pink)}"

# Through several colours, from the lowest frequency's bar to the highest's.
gradient:
  colors: ["{theme(pink)}", "{theme(mauve)}", "{theme(blue)}"]

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

A `gradient` comes before a `rainbow` when a module has both, and its `colors` before its `low` and `high`.

The other styles use the same colours. `dots` colours its columns as `bars` does its bars. `wave`, `line` and `scroll` pass through them from left to right. `flow` draws its low ribbon in the first, its high ribbon in the last and its middle one between. `spectrogram` passes through them from its quietest points to its loudest.

With the native appearance the module's own colour is used.

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
