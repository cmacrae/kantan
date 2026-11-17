// Helpers the built-in modules share.
import { dict, list, str } from "../values.js";

// The icon of `icons` for a level from 0 to 100: the table is split into
// equal steps, the last taking what's left over.
export function iconForLevel(level, icons) {
  if (!icons.length) return "";
  const step = Math.max(1, Math.trunc(100 / icons.length));
  return icons[Math.min(Math.trunc(level / step), icons.length - 1)];
}

// A list of icon names from a config, keeping only the strings, or
// `fallback` when the config has no list.
export const iconList = (value, fallback) => list(value)?.filter(item => typeof item === "string") ?? fallback;

// The string entries of a config mapping.
export const stringEntries = value =>
  Object.fromEntries(Object.entries(dict(value) ?? {}).filter(([, v]) => typeof v === "string"));

// The style a config gives one of a module's states: a colour, which sets
// `fg`, or a mapping with `fg`, `bg`, `icon.fg` and `text.fg`.
export function stateStyle(value) {
  if (typeof value === "string") return { fg: value };
  if (!dict(value)) return undefined;
  const style = { fg: str(value.fg), bg: str(value.bg), iconFg: str(value.icon?.fg), textFg: str(value.text?.fg) };
  return Object.values(style).some(v => v !== undefined) ? style : undefined;
}

// A 32-bit float product truncated to an integer, as kantan computes a
// percentage from a reading.
export const floatPercent = fraction => Math.trunc(Math.fround(Math.fround(fraction) * 100));
