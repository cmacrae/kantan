// What the system supplies when kantan draws: the colours the engine names
// rather than writes out, and the fonts of menus, popups and tooltips.

const SYSTEM_COLORS = {
  label: ["rgba(0,0,0,0.85)", "rgba(255,255,255,0.92)"],
  primary: ["rgba(0,0,0,0.85)", "rgba(255,255,255,0.92)"],
  secondary: ["rgba(0,0,0,0.5)", "rgba(255,255,255,0.55)"],
  track: ["rgba(0,0,0,0.13)", "rgba(255,255,255,0.14)"],
  accent: ["#007aff", "#0a84ff"],
  red: ["#ff3b30", "#ff453a"],
  orange: ["#ff9500", "#ff9f0a"],
  yellow: ["#ffcc00", "#ffd60a"],
  green: ["#28cd41", "#32d74b"],
  blue: ["#007aff", "#0a84ff"],
  purple: ["#af52de", "#bf5af2"],
  pink: ["#ff2d55", "#ff375f"],
  gray: ["#8e8e93", "#98989d"],
  white: ["#ffffff", "#ffffff"],
  black: ["#000000", "#000000"],
  clear: ["transparent", "transparent"],
};

// The CSS colour for a colour the engine resolved: a hex colour as it is,
// or the system's colour of that name for the appearance.
export function cssColor(color, dark) {
  if (color === undefined) return undefined;
  if (color.startsWith("#")) return color;
  return SYSTEM_COLORS[color]?.[dark ? 1 : 0];
}

// `color` at `opacity` of its own.
export function faded(color, opacity) {
  return `color-mix(in srgb, ${color} ${Math.round(opacity * 100)}%, transparent)`;
}

// The system font, which kantan's menus, popups and tooltips are set in.
export const SYSTEM_FONT = "-apple-system, BlinkMacSystemFont, 'Helvetica Neue', Helvetica, Arial, sans-serif";

// The CSS for a font the config names, falling back to the bar's default.
export const fontFamily = name => `'${name.replaceAll("'", "")}', 'Helvetica Neue', Helvetica, Arial, sans-serif`;
