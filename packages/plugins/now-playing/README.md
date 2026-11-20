# kantan-plugin-now-playing

A now-playing plugin for [kantan](https://github.com/cmacrae/kantan) that shows the track playing on your Mac, from any app that reports one to macOS: music apps such as Spotify and Music, and media playing in a browser.

<!-- github-only -->
This page is also in the [kantan docs](https://kantan.bar/docs/plugins/now-playing.html).
<!-- /github-only -->

## Installation

This plugin is bundled with kantan and requires no separate installation. It is included in both the [Nix flake](https://github.com/cmacrae/kantan) default package and the Homebrew `kantan` formula. The `kantan-without-plugins` variant (available via both Nix and Homebrew) does not include this plugin.

## Features

- **Any source** — Shows whatever macOS itself counts as now playing, as Control Centre does
- **Yours to lay out** — Choose which of the icon, artist, title and album show while playing, while paused and on a hover, or write the text with a `format` template
- **An icon for each app** — Spotify's icon while Spotify plays, a browser's while it does
- **Popup** — Album art, title, artist, album, position and previous, play/pause and next buttons, staying open while you use them. Click or drag the position bar to move through the track, in players that allow it
- **Open the source** — Clicking the track in the popup brings the app playing it to the front
- **Hides itself** — Leaves the bar in any state you show nothing for, sliding behind the notch when it sits beside it
- **Event-driven** — Updates as the track or its state changes, with no polling

### Template Variables

| Variable     | Example                 | Description                                         |
|--------------|-------------------------|-----------------------------------------------------|
| `{title}`    | `Alberto Balsalm`       | The track's title                                   |
| `{artist}`   | `Aphex Twin`            | The artist; empty when the source gives none        |
| `{album}`    | `…I Care Because You Do` | The album; empty when the source gives none        |
| `{app}`      | `Spotify`               | The app the track plays from                        |
| `{state}`    | `Playing`               | `Playing`, `Live`, `Paused` or `Stopped`            |
| `{elapsed}`  | `1:24`                  | The position in the track; empty for a live stream  |
| `{duration}` | `5:10`                  | The track's length; empty when the source gives none |
| `{artwork}`  | `file:///…/artwork.jpg` | The album art's file, for an `image` in a view of your own |

## Configuration

Copy the example config into your kantan `modules.d/` directory:

```yaml
name: now-playing
type: command
placement: right
style:
  icon:
    fg: "{theme(green)}"
config:
  command: kantan-plugin-now-playing
  output: json
  watch: kantan-plugin-now-playing --watch
  settings:
    icon: music
    icons:
      Spotify: brand-spotify
      Music: brand-apple
    show:
      playing: [icon, title]
      paused: [icon]
      hover: [artist]
interaction:
  hover:
    type: reveal
    persist: true
  click:
    type: popup
```

This one shows the icon and the title while a track plays, the icon alone while it is paused, and nothing while no player has a track. A hover slides the artist out beside the title, and it stays out while the popup is open. The icon is Spotify's or Music's while they play, and the note otherwise. It dims while the track is paused.

### Settings

| Setting     | Type            | Default            | Description                                                                              |
|-------------|-----------------|--------------------|------------------------------------------------------------------------------------------|
| `show`      | object          | see below          | The parts each state shows                                                               |
| `icon`      | string          | `music`            | The module's icon, where a state shows one                                               |
| `icons`     | object          | —                  | An icon for each app, and optionally its colour, by the app's name or bundle identifier  |
| `format`    | string or array | artist, then title | What the `text` part writes: a template, or a list of segments                           |
| `separator` | string          | `" · "`            | What goes between the `artist`, `title` and `album` parts                                |
| `exclude`   | array           | —                  | Apps whose playing is never shown, by name or bundle identifier                          |
| `colors`    | object          | see below          | The colour of the popup's live dot, as `live`                                            |
| `maxChars`  | integer         | `40`               | Most characters of text in the bar before a hover. `0` sets no limit                     |
| `drop`      | array           | `[album, artist]`  | The parts left out of text longer than `maxChars`, the first listed going first          |

### What Each State Shows

`show` lists the parts the module shows in each state. The parts are `icon`, `artist`, `title`, `album` and `text`, and are always drawn in that order.

| State     | Default        | When                                              |
|-----------|----------------|---------------------------------------------------|
| `playing` | `[icon, text]` | A track is playing                                |
| `paused`  | `[icon, text]` | A track is paused                                 |
| `live`    | `playing`'s    | A live stream is playing                          |
| `stopped` | `[]`           | No player has a track loaded                      |
| `hover`   | `[]`           | Added to the state's parts while the pointer is over the module |

A state with an empty list takes the module out of the bar.

```yaml
# The title alone while playing, and nothing otherwise.
show:
  playing: [title]
  paused: []

# The title, with the app's icon and the artist sliding out on a hover.
show:
  playing: [title]
  paused: []
  hover: [icon, artist]
```

The `hover` parts need the module's hover to reveal, as the example's does:

```yaml
interaction:
  hover:
    type: reveal
    persist: true   # keep them out while the popup is open
```

Set the icon with the `icon` setting, not the module's own `icon` field: kantan always draws a module's own icon, so no state could leave it out.

### Long Text

`maxChars` limits the text the bar shows before a hover. Text longer than it loses the parts `drop` lists, one at a time until it fits. With the defaults, `Artist · Title · Album` loses the album first and then the artist, leaving the title. Text still too long with nothing left to drop is cut short, ending in `...`.

A part the text loses comes back on a hover when `hover` lists it, as a hover shows its parts whatever the length:

```yaml
# The artist and title, or the title alone when they pass 80 characters.
# A hover always shows both.
show:
  playing: [icon, artist, title]
  hover: [artist]
maxChars: 80
drop: [artist]
```

The `text` part can be dropped whole but not in pieces, so list `artist` and `title` as parts for this.

### Icons for Apps

`icons` gives an app its own icon, shown wherever a state shows the icon. A key is the app's name, such as `Spotify`, or its bundle identifier, such as `com.spotify.client`, in any case. An app without an entry gets `icon`.

```yaml
icon: music
icons:
  Spotify: brand-spotify
  Music: brand-apple
  com.google.Chrome: brand-chrome
```

An entry can also give the icon its colour while that app plays, as `icon` and `fg`. Either can be left out: the default `icon`, or the module's colour.

```yaml
icons:
  Spotify:
    icon: brand-spotify
    fg: "{theme(green)}"
  Arc:
    icon: brand-arc
    fg: "{theme(pink)}"
```

### The Text Part

`text` is what `format` writes, for more than the `artist`, `title` and `album` parts give. A `format` of segments gives each its own colour and condition, and a segment with `reveal` waits for a hover:

```yaml
show:
  playing: [icon, text]
format:
  - text: "{artist} "
    fg: "{theme(subtext0)}"
    when: artist
    reveal: true
  - text: "{title}"
```

### Live Streams

A stream with no end, such as one on Twitch, is in the `Live` state while it plays and `Paused` while it doesn't. Its popup has no position bar or times, as there is no length to be a position in: a `● LIVE` mark sits in their place, and only the play button stays, as there is no track before or after it to skip to. `show.live` sets what the bar shows for it, and `colors.live` the colour of the mark's dot:

```yaml
show:
  playing: [icon, text]
  live: [icon, artist]   # a stream's channel, without its title
colors:
  live: "{theme(red)}"
```

macOS says only that the stream has no end, not where it plays from: a stream in a browser has the browser's icon from `icons`.

### Which Player Shows

With several apps holding a track, the module shows the one that most recently started playing, and with none playing, the one that most recently stopped. Music started while a stream plays takes over, and once it is paused, the stream still playing shows again. The app shown while it plays becomes the one macOS counts as current too, so Control Centre and the media keys follow it.

With more than one app holding a track, the popup has a switcher at its top: a button for each app, with its icon from `icons`. Picking one pins it: the module shows it and the popup's buttons control it. The pin lasts until the app stops playing, another app starts playing, or the app has no track.

macOS sends a command only to the app it counts as current, so a button pressed for another app makes that app the current one first, for Control Centre and the media keys too.

`exclude` passes apps over, by name or bundle identifier in any case:

```yaml
exclude: [Safari, com.google.Chrome]
```

### Click Actions

The example opens the popup on a click. To have a click act directly instead, set `config.toggle` to one of the plugin's commands and the click's type to `toggle`:

```yaml
config:
  toggle: kantan-plugin-now-playing --open   # or --toggle, --next, --previous
interaction:
  click:
    type: toggle
```

| Command          | Does                                                    |
|------------------|---------------------------------------------------------|
| `--open`         | Brings the app that is playing to the front             |
| `--toggle`       | Plays or pauses                                         |
| `--next`         | Skips to the next track                                 |
| `--previous`     | Goes back to the previous track                         |
| `--select <app>` | Pins an app, by bundle identifier, as the switcher does |
| `--seek <n>`     | Moves through the track: 0 its start, 1 its end         |

## Update Model

The module is driven by its watch process: `--watch` writes the module's output whenever the track, its state or its artwork changes, and once a second while a track plays so the popup's position keeps time. kantan runs no timer for it.

## How It Works

macOS keeps what each app is playing in MediaRemote, a private framework that has answered only Apple's own programs since macOS 15.4. The plugin reads it by loading a small library into `/usr/bin/perl`, which macOS ships and treats as its own. The library writes every player's track and state as a line of JSON whenever one changes, and sends the play, pause and skip commands to the player that is showing.

This rests on behaviour Apple doesn't document and may change. If a macOS release closes it, the module stays hidden, and nothing else in kantan is affected.

Album art is kept in `~/Library/Caches/kantan/now-playing/`, one file at a time.
