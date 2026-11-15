# Configuration

kantan is configured with YAML, in a single file or split across a `modules.d/` directory. It reloads the config when it changes.

## Config File Locations

kantan searches for configuration files in the following order (first found wins):

1. Path specified via `--config` flag
2. `$XDG_CONFIG_HOME/kantan/config.yaml`, or `~/.config/kantan/config.yaml` when `XDG_CONFIG_HOME` is unset or isn't an absolute path

If no config file is found, kantan shows a welcome bar and checks for one every 2 seconds.

## Reloading

kantan watches the config file and the `modules.d/` directory, and rebuilds the bar 0.2 seconds after the last change. When the config file is a symlink (as with Home Manager), repointing the link counts as a change too.

A config that fails to load (invalid YAML, an unknown theme, or, without a theme, a `style` block missing colours) is logged. At startup, kantan shows a bar naming the file and what's wrong with it. On a reload, it keeps the current bar. Either way, kantan loads the config again once a fix is saved. A module that fails to parse is skipped and logged, and the rest of the config still loads. See [Logs](../getting-started/installation.md#logs) for where to read them.

## Modular Configuration

For complex setups, kantan supports a `modules.d/` directory structure where individual module configurations can be split into separate files. This is the recommended approach for organizing multi-module configurations.

See [Modular Configuration](modules-d.md) for details.

## Configuration Sections

- [Bar Settings](bar.md) - Top-level bar appearance and behavior
- [Themes](themes.md) - Colour palettes for consistent styling
- [Icons](icons.md) - Bundled icon font and icon resolution
- [Modules](modules.md) - Individual status bar modules and their configuration
- [Modular Configuration](modules-d.md) - Using modules.d/ for organized setups
- [Menu Bar Masking](masking.md) - Positioning modules over native macOS menu bar items
