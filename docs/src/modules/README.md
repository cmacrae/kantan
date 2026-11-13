# Built-in Modules

kantan includes a variety of built-in modules for displaying system information and custom content in your status bar.

## Available Modules

| Type | Description |
|------|-------------|
| `clock` | Date/time display |
| `power` | Battery level and charging state |
| `volume` | System audio volume |
| `wifi` | WiFi connection status |
| `bluetooth` | Bluetooth status |
| `workspace` | Window manager workspace indicator (native macOS, aerospace or rift) |
| `focus` | Focus mode indicator |
| `text` | Static text display |
| `icon` | Static icon display |
| `drawer` | Expandable module group |
| `command` | [Shell command / plugin output](command.md) |

## Common Configuration

All modules share common configuration fields documented in the Configuration section. `name`, `type` and `placement` are required. A module missing any of them, or whose `config` is invalid, is skipped.

- `name` - Module identifier, used by `kantan trigger <name> ...`
- `type` - Module type (from the table above)
- `placement` - Position on the bar (`left`, `right`, `notchleft`, `notchright`). Supports or-wise specs like `"right|notchright"` for screens with/without a notch
- `config` - Type-specific options, documented on each module's page
- `icon` - Icon to display
- `style` - Visual styling overrides
- `interaction` - Click/hover behavior
- `mask` - Hide native menu bar items
- `displays` - Restrict module to specific displays (see [Bar Configuration](../configuration/bar.md))
- `fonts.text` / `fonts.icon` - Per-module font overrides

Each module type has additional type-specific configuration options documented on its individual page.
