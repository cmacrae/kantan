# kantan (簡単)

A beautifully simple macOS status bar replacement, built with Swift and SwiftUI.

## Key Features

**Declarative Configuration**  
Bars are defined in simple YAML with hot-reloading and optional modular loading from separate `modules.d/` files.

**Multi-Display Support**  
Run kantan on your main display, all displays, or specific displays by name.

**Built-in Modules**
Clock, power/battery, volume, WiFi, Bluetooth, Focus mode, workspace integration (native macOS and Aerospace), text, icons, command output, and drawers for organising related modules.

**Plugin System**
Extend kantan with standalone executables written in any language. Plugins communicate via a JSON API and can run as long-lived background processes via watch mode for event-driven updates.

**View DSL**  
A JSON-based view description language enables plugins to create rich UIs including tooltips, popups, and menus with checkboxes and separators.

**Menu Bar Masking**  
Places kantan modules over native macOS menu bar items and passes clicks through to the masked item, which keeps its native menu.

**Theme System**
Apply named colour palettes via theme files with support for flavours, light/dark mode, and `{theme(...)}` template syntax. kantan ships with a Catppuccin theme. With no theme, it uses the native macOS appearance.

**Auto-Hide, Blur & Shapes**
Auto-hide the bar after a configurable delay, apply vibrancy blur, and add per-module background shapes (pill, box, underline, overline) with configurable gaps and corner radius.

## Next Steps

Ready to get started? Head to [Installation](getting-started/installation.md) to install kantan, then follow the [Quick Start](getting-started/quick-start.md) guide to create your first configuration.

Want to see what's possible? Browse the [Built-in Modules](modules/README.md) and [Plugin System](plugins/README.md) documentation.
