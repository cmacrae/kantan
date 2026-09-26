# kantan-plugin-calendar

A native Apple Calendar plugin for [kantan](https://github.com/cmacrae/kantan) that displays upcoming events from your calendars using EventKit,
with a rich popup view showing today's and tomorrow's schedule.

## Installation

This plugin is bundled with kantan and requires no separate installation. It is included in both the [Nix flake](https://github.com/cmacrae/kantan) default package and the Homebrew `kantan` formula. The `kantan-without-plugins` variant (available via both Nix and Homebrew) does not include this plugin.

## Features

- **Event-driven updates** — Responds to EventKit changes via a background watcher process, and updates at the start of every minute so countdowns stay exact
- **Calendar filtering** — Include or exclude specific calendars by name
- **Upcoming window** — Only show the bar module when an event is ongoing or starts within a configurable time window
- **Countdown display** — Shows time remaining until the next event (e.g. `42m`, `1h 15m`, `now`)
- **Rich popup view** — Today's and tomorrow's events with calendar-colored sidebar indicators, time ranges, all-day badges, and past events shown with strikethrough
- **Configurable icons** — Override the bar icon and popup action icon via settings
- **Empty states** — Shows "No events today" in the popup when there are no timed events (all-day events are still shown as badges above); auto-hides the module when all calendars are filtered out
- **Format string** — Customise the bar display with template variables and conditional sections
- **Permissions** — Automatically requests Calendar access on first run

### Template Variables

| Variable            | Example      | Description                                                 |
|---------------------|--------------|-------------------------------------------------------------|
| `{next_title}`      | `Team sync`  | Title of the next upcoming or ongoing event                 |
| `{next_countdown}`  | `42m`        | Time until the next event starts: `now` if ongoing, `<1m` if under a minute away |
| `{next_time}`       | `14:30`      | Start time of the next event (24-hour format)               |
| `{next_color}`      | `#1BADF8`   | Hex colour of the next event's calendar                     |
| `{next_calendar}`   | `Work`       | Calendar name of the next event                             |
| `{today_count}`     | `5`          | Total number of events today (all-day + timed)              |
| `{tomorrow_count}`  | `3`          | Total number of events tomorrow                             |
| `{has_allday}`      | `true` / ``  | Truthy when there are all-day events today                  |
| `{has_tomorrow}`    | `true` / ``  | Truthy when there are events tomorrow                       |
| `{has_past}`        | `true` / ``  | Truthy when there are past (ended) events today             |
| `{is_active}`       | `true` / ``  | Truthy when the next event is currently ongoing             |
| `{is_upcoming}`     | `true` / ``  | Truthy when the next event has not started yet              |

### Conditional Sections

The format string supports conditional sections that appear only when a variable is truthy:

- `{?var:text}` — Include `text` when `var` is non-empty
- `{?!var:text}` — Include `text` when `var` is empty

Example: `"{next_title}{?is_upcoming: in} {next_countdown}"` shows `Team sync in 42m` for an upcoming event and `Team sync now` for an ongoing one.

## Configuration

Copy the example config into your kantan `modules.d/` directory:

```yaml
name: calendar
type: command
placement: right
icon: "\uf073"
style:
  light:
    fg: "#8caaee"
  dark:
    fg: "#89b4fa"
config:
  command: kantan-plugin-calendar
  output: json
  watch: kantan-plugin-calendar --watch
  settings:
    format: "{next_title}{?is_upcoming: in} {next_countdown}"
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
| `format`    | `{next_title}{?is_upcoming: in} {next_countdown}` | Format string for the bar display value (see template variables)    |
| `upcoming`  | —                                                | Time window for bar visibility (e.g. `30m`, `1h`, `2d`). When set, the module is hidden unless the next event starts within this window or is currently ongoing. When omitted, the module is shown whenever there is an upcoming event or today has all-day events |
| `calendars` | —                                                | Calendar filter (see [Calendar Filtering](#calendar-filtering))     |
| `icons`     | see below                                        | Icon overrides (see [Icon Settings](#icon-settings))                |

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
| `icons.icon`   | `calendar-event-filled`  | Icon name for the bar module             |
| `icons.action` | `calendar-event-filled`  | Icon name for the "Calendar" action      |

Icon values are resolved by kantan's bundled icon font system (e.g. tabler-icons glyph names). Raw Unicode glyphs are also accepted.

### Module Options

| Field                       | Value                            | Description                                                    |
|-----------------------------|----------------------------------|----------------------------------------------------------------|
| `config.watch`              | `kantan-plugin-calendar --watch` | Background process that triggers refreshes on EventKit changes |
| `interaction.hover`         | —                                | Supports `tooltip` with a `view` subtree or flat `content` string |
| `interaction.click`         | —                                | `menu` type to display the plugin's view tree popup            |

### Format Examples

```yaml
# Default: show title with contextual countdown
format: "{next_title}{?is_upcoming: in} {next_countdown}"

# Show just the countdown
format: "{next_countdown}"

# Show count of today's events
format: "{today_count} events"

# Show title with start time
format: "{next_title} at {next_time}"

# Show calendar name with title
format: "{next_calendar}: {next_title}"

# Active vs upcoming distinction
format: "{?is_active:Now:}{?is_upcoming:Next:} {next_title}"
```

## How It Works

The plugin operates in two modes:

- **Default mode** — Fetches events from EventKit for today and tomorrow, partitions them into all-day, past, active/upcoming, and tomorrow categories, then outputs JSON with the bar value, template variables, data collections, and a rich view tree for the popup menu.
- **Watch mode** (`--watch`) — Long-lived background process that keeps one EventKit store open and prints the module's output for kantan to show: once a burst of `EKEventStoreChanged` notifications settles, and at the start of every minute for the countdowns. It prints only when the output changes. Without calendar access it prints hidden output and waits. Managed by kantan's watch process lifecycle.

### Popup View

The popup view displays a structured agenda:

1. **Today** header
2. All-day events as coloured badges
3. Past events with strikethrough styling and muted colours
4. Active/upcoming events with calendar-coloured sidebar, title, time range, and countdown
5. **Tomorrow** section (if events exist) with a divider, header, and event list
6. **Calendar** action button at the bottom to open Apple Calendar

### Data Collections

The plugin outputs these data collections for use with the `foreach` view DSL node:

| Collection        | Fields                              | Description                        |
|-------------------|-------------------------------------|------------------------------------|
| `allday_events`   | `title`, `color`, `calendar`        | Today's all-day events             |
| `past_events`     | `title`, `time`, `color`, `calendar`| Today's events that have ended     |
| `today_events`    | `title`, `time`, `color`, `calendar`, `countdown` | Today's active/upcoming events |
| `tomorrow_events` | `title`, `time`, `color`, `calendar`| Tomorrow's timed events            |

### Permissions

On first run, the plugin requests full access to Apple Calendar via EventKit. If access is denied or restricted, the module is hidden. Grant access in **System Settings > Privacy & Security > Calendars**.
