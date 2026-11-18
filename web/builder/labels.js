// Labels for the keys of a config, for the builder's forms. A key is its
// own label, as words, unless one is given here. They are labels only:
// what the builder writes to a file keeps kantan's own keys.
import { spell } from "./spelling.js";

// A key's label, by the key alone or by `<what holds it>.<key>` where the
// same key means different things. What holds a module type's settings is
// the type, and what holds the bar's own settings is `bar`.
const LABELS = {
  fg: "Colour",
  bg: "Background",
  "text.fg": "Text colour",
  "icon.fg": "Icon colour",
  "fonts.text": "Text font",
  "fonts.icon": "Icon font",
  hover: "On hover",
  click: "On click",
  "command.interval": "Interval (s)",
  "command.timeout": "Timeout (s)",
  "clock.timezone": "Time zone",
  "text.value": "Text",
  "power.lowThreshold": "Low threshold (%)",
  plugged: "Plugged in",
  "workspace.type": "Window manager",
};

// Words written in capitals wherever they fall.
const CAPITALS = new Set(["cpu", "gpu", "ram", "ip", "vpn", "url", "ssid", "id"]);

// A key as words: `iconTextSpacing`, `color_target` and `show-cores` each
// split where their words join, the first capitalised.
export function humanise(key) {
  const words = String(key).replace(/([a-z0-9])([A-Z])/g, "$1 $2").split(/[\s_-]+/).filter(word => word !== "")
    .map(word => (CAPITALS.has(word.toLowerCase()) ? word.toUpperCase() : word.toLowerCase()).replace(/^color(s?)$/, "colour$1"));
  if (words.length === 0) return String(key);
  return [words[0][0].toUpperCase() + words[0].slice(1), ...words.slice(1)].join(" ");
}

// The label of `key`, held by `within` when something holds it.
export function labelOf(key, within) {
  const scoped = within === undefined ? undefined : LABELS[`${within}.${key}`];
  return spell(scoped ?? (Object.hasOwn(LABELS, key) ? LABELS[key] : humanise(key)));
}

// Whether a label says no more than its key does, give or take its
// capitals: `Format` for `format`.
export const sameAsKey = (label, key) => label.toLowerCase().replace(/\s+/g, "") === String(key).toLowerCase().replace(/[\s_-]+/g, "");

// The settings of each module type that the builder folds away: the ones
// most people never change.
export const ADVANCED = {
  command: ["timeout", "watch", "toggle", "settings", "launcher"],
  clock: ["formats"],
};

// The settings of its own a type is most often changed by. They are the
// ones shown where room is short.
export const QUICK = {
  text: ["value"],
  clock: ["format"],
  command: ["command"],
  power: ["showLevel"],
};

// Clock formats to pick from, each drawn as the time it writes.
export const CLOCK_FORMATS = ["HH:mm", "h:mm a", "EEE HH:mm", "EEE d MMM HH:mm", "d MMM yyyy"];

// What each thing a click can do is called and does. `only` names the one
// module type that can do it: `toggle` runs a command of the module's.
export const CLICKS = [
  { type: undefined, label: "None", about: "No click.", icon: "ban" },
  { type: "menu", label: "Menu", about: "Native macOS menu.", icon: "list" },
  { type: "popup", label: "Popup", about: "Themed panel.", icon: "app-window" },
  { type: "toggle", label: "Toggle", about: "Runs the toggle command, then refreshes.", icon: "player-play", only: "command" },
];
