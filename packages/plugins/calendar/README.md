# kantan-plugin-calendar

A native Apple Calendar plugin for [kantan](https://github.com/cmacrae/kantan) that displays upcoming events from your calendars using EventKit,
with a rich popup view showing today's and tomorrow's schedule.

<!-- github-only -->
This page is also in the [kantan docs](https://kantan.bar/docs/plugins/calendar.html).
<!-- /github-only -->

## Installation

This plugin is bundled with kantan and requires no separate installation. It is included in both the [Nix flake](https://github.com/cmacrae/kantan) default package and the Homebrew `kantan` formula. The `kantan-without-plugins` variant (available via both Nix and Homebrew) does not include this plugin.

## Features

- **Event-driven updates** — Responds to EventKit changes via a background watcher process, and updates at the start of every minute so countdowns stay exact
- **Calendar filtering** — Include or exclude specific calendars by name
- **Upcoming window** — Only show the bar module when an event is ongoing or starts within a configurable time window
- **Countdown display** — Shows time remaining until the next event (e.g. `42m`, `1h 15m`, `now`)
- **Rich popup view** — Today's and tomorrow's events with calendar-colored sidebar indicators, time ranges, and past events shown with strikethrough
- **Full calendar** — With `mode: full`, a month to browse and pick a day from, over that day's events
- **Configurable icons** — Override the bar icon and popup action icon via settings
- **Empty states** — Shows "No events today" when today has no events; auto-hides the module when all calendars are filtered out
- **Format string** — Customise the bar display with template variables and conditional sections
- **Permissions** — Automatically requests Calendar access on first run

### Template Variables

| Variable            | Example      | Description                                                 |
|---------------------|--------------|-------------------------------------------------------------|
| `{next_title}`      | `Team sync`  | Title of the next upcoming or ongoing event                 |
| `{next_countdown}`  | `42m`        | Time until the next event starts: `now` if ongoing, `<1m` if under a minute away |
| `{next_time}`       | `14:30`      | Start time of the next event (24-hour format)               |
| `{next_color}`      | `#1BADF8`   | Colour of the next event: its calendar's, unless `colors` gives another |
| `{next_calendar}`   | `Work`       | Calendar name of the next event                             |
| `{today_count}`     | `5`          | Total number of events today (all-day + timed)              |
| `{tomorrow_count}`  | `3`          | Total number of events tomorrow (all-day + timed)           |
| `{has_allday}`      | `true` / ``  | Truthy when there are all-day events today                  |
| `{has_tomorrow}`    | `true` / ``  | Truthy when there are events tomorrow (all-day or timed)    |
| `{has_past}`        | `true` / ``  | Truthy when there are past (ended) events today             |
| `{active}`          | `true` / ``  | Truthy when the next event is currently ongoing             |
| `{upcoming}`        | `true` / ``  | Truthy when the next event has not started yet              |

### Conditional Sections

The format string supports conditional sections that appear only when a variable is truthy:

- `{?var:text}` — Include `text` when `var` is non-empty
- `{?!var:text}` — Include `text` when `var` is empty

The next event is the timed event not yet ended whose start is nearest now, so a long event underway gives way to one about to start. Cancelled events and invitations you've declined are left out.

Example: `"{next_title}{?upcoming: in} {next_countdown}"` shows `Team sync in 42m` for an upcoming event and `Team sync now` for an ongoing one.

### Coloured Segments

`format` can also be a list of segments, each in its own colour, to set parts of the value apart:

```yaml
format:
  - text: "{next_title} "
    fg: "{theme(blue)}"
  - text: "in {next_countdown}"
    fg: "{theme(overlay1)}"
    when: upcoming
  - text: now
    fg: "{theme(red)}"
    when: active
```

This shows the title in blue, then `in 42m` in overlay1 while the event is upcoming, or `now` in red once it's under way.

| Key    | Description                                                                                          |
|--------|------------------------------------------------------------------------------------------------------|
| `text` | Template for the segment, with the same variables and conditional sections as a `format` string      |
| `fg`   | Colour of the segment: a hex colour or `{theme(name)}` template. Without it, it takes the module's text colour |
| `when` | A variable the segment shows only while truthy, or, as `!name`, only while empty                       |

Segments that come out empty are left out.

## Configuration

Copy the example config into your kantan `modules.d/` directory:

```yaml
name: calendar
type: command
placement: right
style:
  fg: "{theme(blue)}"
config:
  command: kantan-plugin-calendar
  output: json
  watch: kantan-plugin-calendar --watch
  settings:
    format:
      - text: "{next_title} "
        fg: "{theme(blue)}"
      - text: "in {next_countdown}"
        fg: "{theme(overlay1)}"
        when: upcoming
      - text: now
        fg: "{theme(red)}"
        when: active
    upcoming: 1h
    calendars:
      include:
        - Work
        - Personal
interaction:
  hover:
    type: tooltip
    view:
      type: vstack
      spacing: 4
      children:
        - type: text
          content: "Next: {next_title}"
          weight: medium
        - type: text
          content: "{next_countdown}"
          style: secondary
  click:
    type: menu
```

### Plugin Settings

Settings are passed to the plugin via the `config.settings` block. All settings are optional; the plugin uses sensible defaults when omitted.

| Setting     | Default                                          | Description                                                         |
|-------------|--------------------------------------------------|---------------------------------------------------------------------|
| `format`    | `{next_title}{?upcoming: in} {next_countdown}`   | Format string, or list of [coloured segments](#coloured-segments), for the bar display value (see template variables) |
| `upcoming`  | —                                                | Time window for bar visibility, in minutes, hours or days (e.g. `30m`, `1h`, `2d`). When set, the module is hidden unless the next event starts within this window or is currently ongoing. When omitted, the module is shown whenever there is an upcoming event or today has all-day events |
| `calendars` | —                                                | Calendar filter (see [Calendar Filtering](#calendar-filtering))     |
| `icons`     | see below                                        | Icon overrides (see [Icon Settings](#icon-settings))                |
| `mode`      | `compact`                                        | What a click opens: `compact` lists today's and tomorrow's events, and `full` shows a month over the events of the day picked in it (see [Full Calendar](#full-calendar)) |
| `colors`    | —                                                | Colours of the full calendar (see [Colour Settings](#colour-settings)) |

#### Calendar Filtering

The `calendars` setting supports two formats:

**Include/exclude object:**
```yaml
calendars:
  include:
    - Work
    - Personal
```
```yaml
calendars:
  exclude:
    - Birthdays
```

**Shorthand array (treated as include list):**
```yaml
calendars:
  - Work
  - Personal
```

When omitted, all calendars are shown. If `include` is specified, only those calendars are used. If `exclude` is specified, those calendars are filtered out. `include` takes priority over `exclude`.

#### Icon Settings

| Setting        | Default                  | Description                              |
|----------------|--------------------------|------------------------------------------|
| `icons.icon`   | `calendar-event-filled`  | Icon name for the bar module; it takes the place of the module's own `icon` |
| `icons.action` | `calendar-event-filled`  | Icon name for the "Calendar" action      |
| `icons.previous` | `chevron-left`         | Icon name for the full calendar's button that shows the month before |
| `icons.next`   | `chevron-right`          | Icon name for the full calendar's button that shows the month after |

Icon values are resolved by kantan's bundled icon font system (e.g. tabler-icons glyph names). Raw Unicode glyphs are also accepted.

#### Colour Settings

Each is a hex colour or a theme template such as `{theme(red)}`. `colors.event` and `colors.calendars` apply in both modes; the rest are the full calendar's.

An event's colour is that of the strip beside it, its dot in the month, and `{next_color}`. It starts as the colour the event's calendar has in the Calendar app, which `inherit` stands for. `colors.event` sets it for every calendar, and `colors.calendars` for one calendar at a time, by name:

```yaml
colors:
  event: "{theme(overlay1)}"    # every other calendar's events
  calendars:
    Work: "{theme(blue)}"
    Personal: inherit           # as in the Calendar app
```

| Setting             | Default              | Description                           |
|---------------------|----------------------|---------------------------------------|
| `colors.event`      | `inherit`            | The colour of events: a colour, or `inherit` for each calendar's own |
| `colors.calendars`  | —                    | The colour of each calendar's events, by the calendar's name, in place of `colors.event`: a colour, or `inherit` |
| `colors.today`      | system accent colour | The circle behind today               |
| `colors.today_text` | white                | Today's number, on its circle         |
| `colors.selected`   | a faint grey         | The circle behind the day picked      |
| `colors.now`        | system accent colour | The badge on an event under way       |
| `colors.now_text`   | white                | The text of that badge                |
| `colors.navigation` | system accent colour | The buttons for the months before and after, and **Today** |
| `colors.action`     | system accent colour | The **Calendar** button, its icon and its text |
| `colors.dot`        | the event's colour   | The dot under a day with events. Left out, it takes the colour of the day's first event |

### Module Options

| Field                       | Value                            | Description                                                    |
|-----------------------------|----------------------------------|----------------------------------------------------------------|
| `config.watch`              | `kantan-plugin-calendar --watch` | Background process that prints updates on EventKit changes and each minute |
| `interaction.hover`         | —                                | Supports `tooltip` with a `view` subtree or flat `content` string |
| `interaction.click`         | —                                | `menu` type to display the plugin's view tree popup. `mode: full` needs the `popup` type |

### Format Examples

```yaml
# Default: show title with contextual countdown
format: "{next_title}{?upcoming: in} {next_countdown}"

# Show just the countdown
format: "{next_countdown}"

# Show count of today's events
format: "{today_count} events"

# Show title with start time
format: "{next_title} at {next_time}"

# Show calendar name with title
format: "{next_calendar}: {next_title}"

# Active vs upcoming distinction
format: "{?active:Now:}{?upcoming:Next:} {next_title}"
```

## How It Works

The plugin operates in two modes, besides the [subcommands](#full-calendar) the full calendar's buttons run:

- **Default mode** — Fetches events from EventKit for today and tomorrow, partitions them into all-day, past, active/upcoming, and tomorrow categories, then outputs JSON with the bar value, template variables, data collections, and a rich view tree for the popup menu.
- **Watch mode** (`--watch`) — Long-lived background process that keeps one EventKit store open and prints the module's output for kantan to show: once a burst of `EKEventStoreChanged` notifications settles, and at the start of every minute for the countdowns. It prints only when the output changes. Without calendar access it prints hidden output and waits. Managed by kantan's watch process lifecycle.

### Popup View

The popup view displays a structured agenda:

1. **Today** header
2. All-day events, with `All day` where the time range goes
3. Past events with strikethrough styling and muted colours
4. Active/upcoming events with calendar-coloured sidebar, title, time range, and countdown
5. **Tomorrow** section (if events exist) with a divider, header, and tomorrow's events
6. **Calendar** action button at the bottom to open Apple Calendar

### Full Calendar

With `mode: full`, a click opens a month in place of the agenda. It needs a click of type `popup`: a native menu has no rows for its grid and buttons.

<!-- preview: calendar-full -->

```yaml
config:
  settings:
    mode: full
    colors:
      today: "{theme(red)}"
interaction:
  click:
    type: popup
```

The popup shows:

1. The month's name and year, with buttons for the month before, **Today**, and the month after
2. The month, a column for each day of the week, starting on the day the system's region starts its week. Today's number is white on a filled circle, and a day with events has a dot under it in the colour of its first event's calendar
3. The events of the day picked, under its name: all-day events first, with `All day` where the time range goes, then timed events with their calendar's colour and time range. For today, events that have ended are struck through, the one under way has a `now` badge, and the rest count down. More than four events scroll
4. **Calendar** button at the bottom to open Apple Calendar

Clicking a day picks it, which puts a faint circle behind it and lists its events. The popup stays open while its days and buttons are clicked, and closes once the pointer leaves it. The day picked and the month shown last until the end of the day, after which the calendar opens on today again.

The bar's value, the template variables and the module's visibility are the same in both modes.

Each button runs a subcommand of the plugin, then refreshes the module:

| Flag                  | Description                                          |
|-----------------------|------------------------------------------------------|
| `--select <yyyy-MM-dd>` | Pick a day, and show its month                     |
| `--month <n>`         | Show the month `n` months after the one shown, or before it when `n` is negative |
| `--today`             | Go back to today                                     |

The view is kept at `$XDG_CACHE_HOME/kantan/calendar.json` (falls back to `~/.cache/kantan/calendar.json`).

### Opening an Event

Clicking an event, in either mode, closes the menu or popup and shows the event in Calendar. The row runs `open` on an `ical://ekevent/` address that names the event and when it starts. Calendar doesn't document these addresses; if it stops reading them, a click still brings Calendar forward.

### Data Collections

The plugin outputs these data collections for use with the `foreach` view DSL node:

| Collection        | Fields                              | Description                        |
|-------------------|-------------------------------------|------------------------------------|
| `allday_events`   | `title`, `time`, `color`, `calendar`| Today's all-day events, with `time` `All day` |
| `past_events`     | `title`, `time`, `color`, `calendar`| Today's events that have ended     |
| `today_events`    | `title`, `time`, `color`, `calendar`, `countdown` | Today's active/upcoming events |
| `tomorrow_events` | `title`, `time`, `color`, `calendar`| Tomorrow's events, all-day ones first with `time` `All day` |

Each event also has `open_cmd`, the command that shows it in Calendar.

With `mode: full`, it also outputs the events of the day picked:

| Collection        | Fields                              | Description                        |
|-------------------|-------------------------------------|------------------------------------|
| `agenda_allday`   | `title`, `time`, `color`, `calendar`| The day's all-day events, with `time` `All day` |
| `agenda_past`     | `title`, `time`, `color`, `calendar`| Today's events that have ended, when today is picked |
| `agenda_events`   | `title`, `time`, `color`, `calendar`, and for today `now`, `countdown` | The day's other timed events. `now` is truthy for one under way, and `countdown` is the time until one starts |

### Permissions

On first run, the plugin requests full access to Apple Calendar via EventKit. If access is denied or restricted, the module is hidden. Grant access in **System Settings > Privacy & Security > Calendars**.
