# kantan-plugin-reminders

A native Apple Reminders plugin for [kantan](https://github.com/cmacrae/kantan) that tracks reminders in real time using EventKit,
with complete/uncomplete support directly from the bar menu.

## Installation

This plugin is bundled with kantan and requires no separate installation. It is included in both the [Nix flake](https://github.com/cmacrae/kantan) default package and the Homebrew `kantan` formula. The `kantan-without-plugins` variant (available via both Nix and Homebrew) does not include this plugin.

## Features

- **Event-driven updates** — Responds instantly to EventKit changes via a background watcher process
- **Multiple lists** — Monitor reminders from one or more Reminders lists simultaneously
- **Lookahead filtering** — Only show reminders due within a configurable time window
- **Overdue reminders** — Optionally include past-due reminders
- **Undated reminders** — Optionally include reminders with no due date
- **Completed retention** — Show recently completed reminders for a configurable duration
- **Complete/Uncomplete** — Toggle reminder completion directly from the bar menu
- **Format string** — Customise the bar display with template variables
- **Auto-hide** — Module hides automatically when there are no incomplete reminders
- **Dynamic bar icon** — Bar icon changes to match the displayed reminder's list icon
- **Permissions** — Automatically requests Reminders access on first run

### Template Variables

| Variable       | Example         | Description                                       |
|----------------|-----------------|---------------------------------------------------|
| `{title}`      | `Buy groceries` | Title of the next incomplete reminder (truncated) |
| `{full_title}` | `Buy groceries` | Full title without truncation                     |
| `{count}`      | `3`             | Number of incomplete reminders                    |
| `{total}`      | `5`             | Total reminders (incomplete + recently completed) |
| `{list}`       | `Shopping`      | Reminders list name of the displayed reminder     |
| `{list_icon}`  | (icon)          | Icon configured for the displayed reminder's list |
| `{due}`        | `in 5 min.`     | Relative due date of the displayed reminder       |

## Configuration

Copy the example config into your kantan `modules.d/` directory:

```yaml
name: todo
type: command
placement: right
icon: "\uf0ae"
style:
  light:
    icon:
      fg: "#ca9ee6"
    fg: "#c6d0f5"
    shape: box
    bg: "#414559"
  dark:
    icon:
      fg: "#cba6f7"
    fg: "#cdd6f4"
    shape: box
    bg: "#313244"
config:
  command: kantan-plugin-reminders
  output: json
  watch: kantan-plugin-reminders --watch
  settings:
    format: "{title}"
    lists:
      - name: Reminders
        icon: "\uf0ae"
        lookahead: 10m
        overdue: true
        undated: false
        completedRetention: 1h
        maxChars: 30
interaction:
  hover:
    type: tooltip
    content: "{count} reminders"
  click:
    type: menu
```

### Plugin Settings

Settings are passed to the plugin via the `config.settings` block. All settings are optional; the plugin uses sensible defaults when omitted.

| Setting  | Default   | Description                                                            |
|----------|-----------|------------------------------------------------------------------------|
| `format` | `{title}` | Format string for the bar display value                                |
| `lists`  | `[]`      | Reminders lists to monitor (see [List Settings](#list-settings) below) |
| `icons`  | —         | Icon overrides (see [Icon Settings](#icon-settings) below)             |

#### Icon Settings

The optional `icons` block lets you override the icons used in the plugin's menu view:

| Setting  | Default      | Description                                                                  |
|----------|--------------|------------------------------------------------------------------------------|
| `action` | `list-check` | Icon for the "Reminders" action at the bottom of the menu (icon name or glyph) |

#### List Settings

Each entry in the `lists` array configures a Reminders list to monitor:

| Setting              | Default | Description                                              |
|----------------------|---------|----------------------------------------------------------|
| `name`               | —       | **Required.** Name of the Reminders list                 |
| `icon`               | —       | Icon glyph to display when this list's reminder is shown |
| `lookahead`          | `10m`   | Time window for upcoming reminders (e.g. `10m`, `1h`, `2d`) |
| `overdue`            | `true`  | Include reminders past their due date                    |
| `undated`            | `false` | Include reminders with no due date                       |
| `completedRetention` | `0`     | How long to show completed reminders (e.g. `30m`, `1h`, `2d`) |
| `maxChars`           | `30`    | Maximum characters for reminder titles before truncation |

### Module Options

| Field                       | Value                             | Description                                                    |
|-----------------------------|-----------------------------------|----------------------------------------------------------------|
| `config.watch`              | `kantan-plugin-reminders --watch` | Background process that triggers refreshes on EventKit changes |
| `interaction.hover.content` | —                                 | Template string for tooltip (see variables above)              |
| `interaction.click`         | —                                 | `menu` type renders the plugin's view tree as a native menu    |

### Menu View

The dynamic menu adapts to the current state:

- **Multiple items** — Grouped check-items organised by list (with list headers when multiple lists are configured). Each item can be completed or uncompleted inline
- **Single item** — A simple "Complete" action button instead of a check-item list
- **No items** — Shows "No reminders" text

Every menu view includes a persistent "Reminders" action at the bottom that launches Apple Reminders (using the `icons.action` icon).

### Format Examples

```yaml
# Default: show the next reminder title
format: "{title}"

# Show count of incomplete reminders
format: "{count} reminders"

# Show title with due date
format: "{title} ({due})"

# Show count and list name
format: "{count} in {list}"
```

## How It Works

The plugin operates in three modes:

- **Default mode** — Fetches reminders from EventKit and outputs JSON with the current state. Called by kantan on each refresh cycle.
- **Watch mode** (`--watch`) — Long-lived background process that keeps one EventKit store open and prints the module's output for kantan to show: once a burst of `EKEventStoreChanged` notifications settles, and at the start of every minute as reminders come due. It prints only when the output changes. Without lists or reminders access it prints hidden output and waits. Managed by kantan's watch process lifecycle.
- **Complete/Uncomplete** (`--complete <id>` / `--uncomplete <id>`) — Toggles a reminder's completion state by its identifier. Used by menu check-items to provide inline complete/uncomplete actions, which then refresh the module by its name.

### Permissions

On first run, the plugin requests full access to Apple Reminders via EventKit. If access is denied or restricted, the module is hidden. Grant access in **System Settings > Privacy & Security > Reminders**.
