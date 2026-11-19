# kantan-plugin-pomodoro

A pomodoro timer plugin for [kantan](https://github.com/cmacrae/kantan) that runs a work/break cycle timer with persistent state, configurable durations, and automatic transitions.

<!-- github-only -->
This page is also in the [kantan docs](https://kantan.bar/docs/plugins/pomodoro.html).
<!-- /github-only -->

## Installation

This plugin is bundled with kantan and requires no separate installation. It is included in both the [Nix flake](https://github.com/cmacrae/kantan) default package and the Homebrew `kantan` formula. The `kantan-without-plugins` variant (available via both Nix and Homebrew) does not include this plugin.

## Features

- **Work sessions** — Configurable work duration with countdown display
- **Break management** — Automatic short and long breaks based on session count
- **Pause/resume** — Pause and resume the timer at any point
- **Auto-transitions** — Optionally auto-start breaks after work and work after breaks
- **Session tracking** — Counts completed work sessions until the timer is reset
- **Persistent state** — Timer state survives restarts via on-disk JSON state file
- **Timer popup** — A ring that empties as the time runs out, a dot for each session of the round, and buttons that suit the state (start/pause/resume/skip/reset)
- **Customizable icons** — Override the icon for any state or action

### Template Variables

| Variable      | Example       | Description                                            |
|---------------|---------------|--------------------------------------------------------|
| `{remaining}` | `12:34`       | Time remaining in `MM:SS` format (`00:00` when idle)   |
| `{mode}`      | `Work`        | Human-readable mode: `Idle`, `Work`, `Short Break`, `Long Break` |
| `{sessions}`  | `3`           | Number of completed work sessions                      |
| `{status}`    | `work`        | Raw mode string: `idle`, `work`, `short_break`, `long_break` |

## Timer States

The pomodoro cycles through the following modes:

1. **Idle** — No timer running. The bar icon is `circle-filled`
2. **Work** — A work session is active. The bar icon is `hourglass`
3. **Short Break** — A short break between work sessions. The bar icon is `moon-filled`
4. **Long Break** — A longer break after every N work sessions. The bar icon is `moon-filled`

While a work session or break is paused, the bar icon is `player-pause-filled`.

When a work session completes, the session counter increments. If `auto_start_breaks` is enabled, the appropriate break starts automatically; otherwise the timer returns to idle. When a break completes, if `auto_start_work` is enabled, a new work session starts automatically; otherwise the timer returns to idle.

Long breaks occur every `long_break_interval` completed sessions (e.g. every 4th session by default); `0` disables long breaks.

A segment ends when the plugin next runs after its time is up. The transition happens on the next poll.

The plugin sets `active: true` in its output when a timer is running (any mode other than idle) and `active: false` when idle. This can be used with kantan's active/inactive styling to visually distinguish a running timer from an idle one.

## Subcommands

The plugin binary doubles as a CLI for controlling the timer. Each subcommand modifies the persistent state file and exits immediately (no output); an unknown flag exits with status 1. The popup's buttons call these subcommands followed by `kantan trigger <module> refresh` to update the bar.

`--start` and `--skip` read the segment durations from `KANTAN_SETTINGS`, which kantan also gives the popup's buttons.

| Flag       | Description                                          |
|------------|------------------------------------------------------|
| `--start`  | Start a new work session, replacing any current timer; the session count is kept |
| `--pause`  | Pause the running timer (no effect when idle or paused) |
| `--resume` | Resume a paused timer                                |
| `--skip`   | Skip to the next segment and start it running: work -> break (counting the session) or break -> work. No effect when idle |
| `--reset`  | Reset to idle, clearing all state including the session count |

## Polling Model

The plugin is polling-based by design and intentionally does not implement the optional `--watch` subcommand. A live countdown display requires the bar value to refresh every second, which is exactly what `interval: 1` does. A watch process would have to fire `kantan trigger` once per second to drive the same display, offering no benefit over polling.

## Persistent State

Timer state is stored at `$XDG_CACHE_HOME/kantan/pomodoro.json` (falls back to `~/.cache/kantan/pomodoro.json`). The state file tracks the current mode, start time, pause time, segment duration, and completed session count. A `pomodoro.lock` file beside it serialises concurrent updates from polls and the popup's buttons.

## Configuration

Copy the example config into your kantan `modules.d/` directory:

```yaml
name: pomodoro
type: command
placement: right
style:
  fg: "{theme(red)}"
config:
  command: kantan-plugin-pomodoro
  output: json
  interval: 1
  settings:
    format: "{remaining}"
    work_duration: 25
    short_break: 5
    long_break: 15
    long_break_interval: 4
    auto_start_breaks: true
    auto_start_work: false
interaction:
  hover:
    type: tooltip
    content: "{mode} — {remaining}"
  click:
    type: popup
```

### Plugin Settings

Settings are passed to the plugin via the `config.settings` block. All settings are optional; the plugin uses sensible defaults when omitted.

| Setting               | Default        | Description                                                    |
|-----------------------|----------------|----------------------------------------------------------------|
| `format`              | `{remaining}`  | Format string for the bar display value (see template variables). Only `{name}` substitution is supported; conditional sections and segment lists are not |
| `work_duration`       | `25`           | Work session duration in minutes                               |
| `short_break`         | `5`            | Short break duration in minutes                                |
| `long_break`          | `15`           | Long break duration in minutes                                 |
| `long_break_interval` | `4`            | Number of work sessions before a long break                    |
| `auto_start_breaks`   | `true`         | Automatically start breaks when a work session ends            |
| `auto_start_work`     | `false`        | Automatically start work when a break ends                     |
| `icons`               | (see below)    | Override icons for specific states or actions                  |
| `colors`              | (see below)    | Override colours of the popup                                  |

### Icon Overrides

Icons can be customized per state and action by providing an `icons` map in settings. Any key not specified falls back to its default.

| Key           | Default                    | Used for                 |
|---------------|----------------------------|--------------------------|
| `idle`        | `circle-filled`            | Bar icon when idle       |
| `work`        | `hourglass`                | Bar icon during work     |
| `short_break` | `moon-filled`              | Bar icon during short break |
| `long_break`  | `moon-filled`              | Bar icon during long break |
| `paused`      | `player-pause-filled`      | Bar icon while paused    |
| `start`       | `player-play-filled`       | Start button in popup    |
| `resume`      | `player-play-filled`       | Resume button in popup   |
| `pause`       | `player-pause-filled`      | Pause button in popup    |
| `skip`        | `player-track-next-filled` | Skip button in popup     |
| `reset`       | `x`                        | Reset button in popup    |

Example override in settings:

```yaml
settings:
  icons:
    work: "flame"
    idle: "circle-dashed"
```

### Colour Overrides

The popup's colours can be set by providing a `colors` map in settings. Each is a hex colour or a theme template such as `{theme(red)}`. Any key not specified keeps its default.

| Key           | Default              | Used for                              |
|---------------|----------------------|---------------------------------------|
| `work`        | red                  | The ring during work                  |
| `break`       | green                | The ring during a break               |
| `paused`      | grey                 | The ring while paused or idle         |
| `track`       | a faint track        | The part of the ring that has emptied |
| `dot`         | red                  | The dot of a session that is done     |
| `dot_outline` | grey                 | The outline of each session's dot     |
| `button`      | system accent colour | The buttons                           |

Example override in settings:

```yaml
settings:
  colors:
    work: "{theme(peach)}"
    break: "{theme(teal)}"
    button: "{theme(text)}"
```

### Module Options

| Field                       | Default | Description                                                 |
|-----------------------------|---------|-------------------------------------------------------------|
| `config.interval`           | `1`     | Polling interval in seconds (1s recommended for live countdown) |
| `interaction.hover.content` | --      | Template string for tooltip (see variables above)           |
| `interaction.click`         | --      | `popup` type to display the plugin's timer. A native `menu` has no rows for its ring and buttons |

## View DSL Output

The plugin generates a View DSL tree (via the `view` field in its JSON output), made for a click of type `popup`:

- A thick **ring** that empties as the segment's time runs out, around the time remaining and the mode (`Paused` while paused). It is red during work, green during a break and grey while paused or idle, unless `colors` says otherwise. Idle, it is full, around the length of a work session
- A **dot** for each work session of the round that ends in a long break (`long_break_interval`), filled once the session is done, over a line such as `Session 3 of 4`. They are left out when `long_break_interval` is `0`
- **Buttons**, centred, depending on state:
  - **Idle**: Start
  - **Running**: Pause, Skip, Reset
  - **Paused**: Resume, Skip, Reset

A click on a button leaves the popup open, so the timer can be paused, skipped and reset in one visit. The popup closes once the pointer leaves it.
