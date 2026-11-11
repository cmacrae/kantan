# kantan · かんたん

A beautifully simple status bar for macOS

## About

kantan is a macOS status bar that replaces or overlays the native menu bar. It's built with Swift and SwiftUI, configured in YAML, and extended with plugins written in any language.

## Features

- Declarative YAML configuration with hot-reload
- Multi-display support with per-screen positioning
- Built-in modules: clock, power, wifi, bluetooth, volume, workspace switching, and more
- Plugin system using a simple JSON protocol (any language)
- View DSL for rich popups, menus and tooltips (stacks, buttons, checkboxes, toggles, progress bars), from config or plugin output
- Menu bar masking to overlay native system items
- Modular configuration via `modules.d/` directory
- Native and themed appearance modes
- Theme system with named palettes, light/dark flavours, and bundled Catppuccin theme
- Distributed through Nix, Homebrew and an install script

## Quick Start

```bash
# Via Nix
nix run github:cmacrae/kantan

# Via Homebrew
brew tap cmacrae/kantan && brew install kantan
kantan
```

For configuration, module setup, and plugin development, read the [documentation](https://kantan.bar/docs).

## Building

```bash
nix build
```

The binary is built to `result/bin/kantan`.

## Documentation

Read the [documentation](https://kantan.bar/docs) for:

- Configuration guides
- Module reference
- Plugin development
- API reference
- Examples

## Philosophy

kantan aims to be simple to use and to extend. Configure your bar in YAML. Build plugins as standalone executables, with no SDK or framework: a plugin reads environment variables and prints JSON.
