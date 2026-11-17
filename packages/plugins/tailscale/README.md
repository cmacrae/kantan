# kantan-plugin-tailscale

A [Tailscale](https://tailscale.com/) connection indicator for [kantan](https://github.com/cmacrae/kantan). Shows a single icon that reflects whether the machine is connected to your tailnet, with an optional dimmed style when disconnected and a hover tooltip carrying the tailnet name.

<!-- github-only -->
This page is also in the [kantan docs](https://kantan.bar/docs/plugins/tailscale.html).
<!-- /github-only -->

## Installation

This plugin is bundled with kantan and requires no separate installation. It is included in both the [Nix flake](https://github.com/cmacrae/kantan) default package and the Homebrew `kantan` formula. The `kantan-without-plugins` variant (available via both Nix and Homebrew) does not include this plugin.

## Features

- **Distinct connected/disconnected icons** — Configurable
- **Optional dimming** — Render the icon in the inactive style when disconnected
- **Tailnet tooltip** — Hover shows the active tailnet name, or `Disconnected`
- **No `PATH` dependency** — Talks to `tailscaled` over its Unix socket, or runs the CLI bundled inside Tailscale.app; the `tailscale` binary does not need to be on `PATH`

## How It Works

The plugin reads the Tailscale [LocalAPI](https://tailscale.com/kb/1080/cli) status on each poll (giving up after 5 seconds) and reduces it to a binary connected/disconnected state, using the first installed backend that answers:

1. **`tailscaled` Unix socket** at `/var/run/tailscaled.socket` — used when you run the open-source `tailscaled` daemon (e.g. installed via Homebrew).
2. **Tailscale.app's bundled CLI** (`Tailscale.app/Contents/MacOS/Tailscale status --json` in `/Applications` or `~/Applications`) — used for the Mac App Store and direct-download Tailscale apps. The app keeps its LocalAPI credentials in its own container, which macOS lets only Tailscale's signed binaries read. The plugin asks the app's CLI rather than reading them itself. This needs no permissions and raises no "would like to access data from other apps" prompt.

If no backend is reachable, the plugin treats the machine as disconnected.

The machine is considered **connected** only when the daemon reports `BackendState: "Running"`.

### Template Variables

| Variable    | Example          | Description                                                                     |
|-------------|------------------|---------------------------------------------------------------------------------|
| `{status}`  | `connected`      | Raw state string: `connected` or `disconnected`                                 |
| `{tailnet}` | `example.ts.net` | Active tailnet name, or the MagicDNS suffix when the tailnet has no name (empty when disconnected) |
| `{tooltip}` | `example.ts.net` | Convenience tooltip: the tailnet name when connected (`Connected` if it has none), otherwise `Disconnected` |

## Configuration

Copy the example config into your kantan `modules.d/` directory:

```yaml
name: tailscale
type: command
placement: right
config:
  command: kantan-plugin-tailscale
  output: json
  interval: 5
  settings:
    dimming: true
    icons:
      connected: affiliate-filled
      disconnected: affiliate
interaction:
  hover:
    type: tooltip
    content: "{tooltip}"
  click:
    type: passthrough
```

### Plugin Settings

| Setting              | Default     | Description                                                                                               |
|----------------------|-------------|-----------------------------------------------------------------------------------------------------------|
| `dimming`            | `true`      | Set `active: false` on the module output when disconnected, so kantan applies the inactive (dimmed) style |
| `icons.connected`    | `world`     | Icon shown when connected to the tailnet; an empty value uses the default                                 |
| `icons.disconnected` | `world-off` | Icon shown when disconnected                                                                              |

### Module Options

| Field                       | Value   | Description                                                                 |
|-----------------------------|---------|-----------------------------------------------------------------------------|
| `config.interval`           | `5`     | Polling interval in seconds (5s is plenty — tailnet state changes are rare) |
| `interaction.hover.content` | --      | Template string for the tooltip; use `{tooltip}` for the built-in label     |

## Polling Model

This plugin is polling-based by design and intentionally does not implement a `--watch` subcommand. Tailscale's LocalAPI does not expose an event stream a third-party process can subscribe to without holding open a long-lived LocalAPI watch connection, and connection-state changes are infrequent enough that a 5-second poll is a fine trade-off for simplicity.
