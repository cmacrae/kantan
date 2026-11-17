// The words share links write as tokens: the keys and values nearly every
// config uses. A word's place in the list is its token, so the list only
// ever grows at its end. The earliest words get the shortest tokens.
const COLORS = [
  "rosewater", "flamingo", "pink", "mauve", "red", "maroon", "peach", "yellow", "green", "teal", "sky", "sapphire",
  "blue", "lavender", "text", "subtext1", "subtext0", "overlay2", "overlay1", "overlay0", "surface2", "surface1",
  "surface0", "base", "mantle", "crust",
];

export const WORDS = [
  // A module's own keys and their commonest values
  "name", "type", "placement", "right", "left", "icon", "style", "fg", "config", "interaction", "hover", "click",
  "tooltip", "content", "mask", "command", "output", "json", "menu", "modules", "theme", "light", "dark", "interval",
  "settings", "toggle", "watch", "shape", "bg", "icons", "format", "formats", "date", "enabled", "colors", "rainbow",
  "level", "popup", "view", "children", "label", "value", "active", "hidden", "variables", "data", "color", "size",
  "spacing", "padding", "weight", "detail", "checked", "uncheckedCommand", "transitions", "workspaces", "hasWindows",
  "connected", "devices", "volume", "device", "rssi",
  // Module types and placements
  "workspace", "clock", "power", "wifi", "bluetooth", "focus", "drawer", "notchleft", "notchright", "left|notchleft",
  "right|notchright", "notchleft|left", "notchright|right",
  // The rest of a config
  "height", "iconTextSpacing", "cornerRadius", "blur", "fonts", "displays", "main", "all", "autohide", "box", "pill",
  "underline", "overline", "passthrough", "complete", "index", "timeout", "launcher", "path", "args", "timezone",
  "showLevel", "lowThreshold", "charging", "plugged", "lowPowerMode", "low", "strength", "disconnected", "hotspot",
  "muted", "disabledIcon", "random", "overflow", "max", "scrolling", "native", "aerospace", "rift", "show", "hide",
  "lists", "completedRetention", "mode", "identifier", "on", "open", "time", "locale", "scroll", "app",
  "bundleIdentifier", "selected", "shown", "notch",
  // The system's menu bar items
  "Clock", "Battery", "WiFi", "Bluetooth", "Volume", "Focus", "ControlCenter",
  // Views
  "vstack", "hstack", "row", "divider", "header", "action", "check", "badge", "progress", "rect", "spacer", "section",
  "secondary", "bold", "semibold", "alignment", "leading", "trailing", "center", "width", "strokeColor", "trackColor",
  // The bundled plugins and theme
  "kantan-plugin-system-monitor", "kantan-plugin-reminders", "kantan-plugin-reminders --watch",
  "kantan-plugin-caffeine", "kantan-plugin-caffeine --toggle", "kantan-plugin-calendar", "kantan-plugin-pomodoro",
  "kantan-plugin-tailscale", "kantan-plugin-rift-indicator", "catppuccin", "catppuccin[latte]", "catppuccin[frappe]",
  "catppuccin[macchiato]", "catppuccin[mocha]",
  ...COLORS.map(color => `{theme(${color})}`),
];
