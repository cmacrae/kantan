# Configuration

kantan is configured with YAML, in a single file or split across a `modules.d/` directory. It reloads the config when it changes.

## Config File Locations

kantan searches for configuration files in the following order (first found wins):

1. Path specified via `--config` flag
2. `./config.yaml` (current working directory)
3. `$XDG_CONFIG_HOME/kantan/config.yaml` (defaults to `~/.config/kantan/config.yaml`)

## Hot-Reload

Configuration changes are detected automatically and applied in real-time. Edits to the config file or modules.d/ directory are picked up with a 0.2-second debounce to prevent excessive reloads during rapid changes.

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
