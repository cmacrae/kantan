# Configuration

kantan is configured with YAML, in a single file or split across a `modules.d/` directory. It reloads the config when it changes.

## Config File Locations

kantan searches for configuration files in the following order (first found wins):

1. Path specified via `--config` flag
2. `./config.yaml` (current working directory)
3. `$XDG_CONFIG_HOME/kantan/config.yaml` (defaults to `~/.config/kantan/config.yaml`)

If no config file is found, kantan shows a welcome bar and checks for one every 2 seconds. It loads the file as soon as one appears.

If the config file exists but fails to load (invalid YAML, an unknown theme, or, without a theme, a `style` block missing colours), kantan logs the error and shows a bar naming the file and what's wrong with it. kantan keeps watching the file and loads it once a fix is saved. A module that fails to parse is skipped with a logged error. The rest of the config still loads.

## Hot-Reload

Configuration changes are detected automatically and applied in real-time. Edits to the config file or modules.d/ directory are picked up with a 0.2-second debounce to prevent excessive reloads during rapid changes. Each reload rebuilds the bar.

If the edited config fails to load, kantan logs the error and keeps the current bar until the next valid edit. When the config file is a symlink (as with Home Manager), kantan also notices the link being repointed.

## Modular Configuration

For complex setups, kantan supports a `modules.d/` directory structure where individual module configurations can be split into separate files. This is the recommended approach for organizing multi-module configurations.

See [Modular Configuration](/docs/configuration/modules-d) for details.

## Configuration Sections

- [Bar Settings](/docs/configuration/bar) - Top-level bar appearance and behavior
- [Themes](/docs/configuration/themes) - Colour palettes for consistent styling
- [Icons](/docs/configuration/icons) - Bundled icon font and icon resolution
- [Modules](/docs/configuration/modules) - Individual status bar modules and their configuration
- [Modular Configuration](/docs/configuration/modules-d) - Using modules.d/ for organized setups
- [Menu Bar Masking](/docs/configuration/masking) - Positioning modules over native macOS menu bar items
