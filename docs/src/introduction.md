# kantan · かんたん

A beautifully simple macOS status bar replacement, built with Swift and SwiftUI.

## Key Features

**Declarative Configuration**  
Bars are defined in simple YAML with hot-reloading and optional modular loading from separate `modules.d/` files.

**Multi-Display Support**  
Run kantan on your main display, all displays, or specific displays by name.

**Built-in Modules**
Clock, power/battery, volume, WiFi, Bluetooth, Focus mode, workspace integration (native macOS, Aerospace and Rift), text, icons, command output, and drawers for organising related modules.

**Plugin System**
Extend kantan with standalone executables written in any language. Plugins communicate via a JSON API and can run as long-lived background processes via watch mode for event-driven updates.

**View DSL**  
A declarative view description language builds rich tooltips, popups, and menus with checkboxes, toggles and separators, written in YAML in your config or returned as JSON by plugins.

**Menu Bar Masking**  
Places kantan modules over native macOS menu bar items and passes clicks through to the masked item, which keeps its native menu.

**Theme System**
Apply named colour palettes via theme files with support for flavours, light/dark mode, and `{theme(...)}` template syntax. kantan ships with a Catppuccin theme. With no theme, it uses the native macOS appearance.

**Builder**  
Build a bar, a theme or a single module in the browser with the [builder](https://kantan.bar/builder/). It draws the bar live, writes the config files, and makes a link and an image to share what you built.

**Auto-Hide, Blur & Shapes**
Hide the bar while the cursor is at the top of the screen (after an optional delay) to reach the native macOS menu bar underneath. Apply vibrancy blur, round the bar's corners and inset it with gaps. Give modules background shapes (pill, box, underline, overline).

## Next Steps

Ready to get started? Head to [Installation](getting-started/installation.md) to install kantan, then follow the [Quick Start](getting-started/quick-start.md) guide to create your first configuration.

Prefer to build a bar by clicking? Open the [builder](https://kantan.bar/builder/).

Want to see what's possible? Browse the [Built-in Modules](modules/index.md) and [Plugin System](plugins/index.md) documentation.
