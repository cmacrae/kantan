// What the builder offers to add to a bar: kantan's module types, each
// with the module a new one starts as and the states it starts with, and
// the bundled plugins, whose modules and states the site's build supplies.
//
// A catalogue is `{ plugins, themes, example }`: `plugins` holds each
// bundled plugin's example `module` and the `states` its preview generator
// printed, by plugin name, `themes` the theme files kantan bundles, by
// name, and `example` the document of the example bar, when there is one.
// A plugin whose preview differs for some settings also holds `variants`:
// each those `settings`, the `states` printed with them, and the
// `interaction` a module needs with them, when it needs one.
import { dict, str } from "../engine/values.js";
import { sameValue } from "./equal.js";

export const EMPTY_CATALOG = { plugins: {}, themes: {} };

// Each module type, in the order the builder lists them: what it's called,
// the icon that stands for it, the module a new one starts as,
// and the states a new one shows, each a sample of what the module would
// read.
export const BUILT_INS = {
  workspace: {
    label: "Workspaces",
    icon: "layout-grid",
    module: { placement: "left", icon: "point-filled" },
    states: [{ name: "Four", output: { workspaces: [{ active: true, hasWindows: true }, { hasWindows: true }, {}, {}] } }],
  },
  clock: {
    label: "Clock",
    icon: "clock",
    module: { placement: "right", config: { format: "HH:mm" } },
  },
  power: {
    label: "Battery",
    icon: "battery-3",
    module: {
      placement: "right",
      config: {
        style: { charging: "{theme(yellow)}", plugged: "{theme(green)}", low: "{theme(red)}", lowPowerMode: "{theme(peach)}" },
      },
    },
    states: [
      { name: "Discharging", output: { level: 78 } },
      { name: "Charging", output: { level: 42, charging: true, plugged: true } },
      { name: "Plugged in, full", output: { level: 100, plugged: true } },
      { name: "Low Power Mode", output: { level: 54, lowPowerMode: true } },
      { name: "Low", output: { level: 9 } },
    ],
  },
  wifi: {
    label: "Wi-Fi",
    icon: "wifi",
    module: { placement: "right" },
    states: [
      { name: "Fair signal", output: { connected: true, rssi: -62 } },
      { name: "Weak signal", output: { connected: true, rssi: -82 } },
      { name: "Personal hotspot", output: { connected: true, rssi: -50, hotspot: true } },
      { name: "Disconnected", output: { connected: false } },
    ],
  },
  volume: {
    label: "Volume",
    icon: "volume",
    module: { placement: "right" },
    states: [
      { name: "64%", output: { volume: 0.64, device: "MacBook Pro Speakers" } },
      { name: "Muted", output: { volume: 0.64, muted: true, device: "MacBook Pro Speakers" } },
      { name: "AirPods", output: { volume: 0.4, device: "AirPods Pro" } },
    ],
  },
  bluetooth: {
    label: "Bluetooth",
    icon: "bluetooth",
    module: { placement: "right" },
    states: [
      { name: "Connected", output: { on: true, devices: [{ name: "AirPods Pro", connected: true }] } },
      { name: "Nothing connected", output: { on: true, devices: [{ name: "AirPods Pro", connected: false }] } },
      { name: "Off", output: { on: false, devices: [] } },
    ],
  },
  focus: {
    label: "Focus",
    icon: "brain",
    module: { placement: "right" },
    states: [
      { name: "Do Not Disturb", output: { active: true, mode: { identifier: "com.apple.donotdisturb.mode.default", name: "Do Not Disturb" } } },
      { name: "Inactive", output: { active: false } },
    ],
  },
  waveform: {
    label: "Waveform",
    icon: "wave-sine",
    module: { placement: "right" },
    states: [
      { name: "Playing", output: { levels: [0.5, 0.8, 0.65, 0.9, 0.55, 0.7, 0.4, 0.3] } },
      { name: "Silent", output: { levels: [] } },
    ],
  },
  drawer: {
    label: "Drawer",
    icon: "box-align-right",
    module: { placement: "right" },
  },
  text: {
    label: "Text",
    icon: "letter-case",
    module: { placement: "left", config: { value: "Hello" } },
  },
  icon: {
    label: "Icon",
    icon: "mood-smile",
    module: { placement: "left", icon: "mood-smile" },
  },
  command: {
    label: "Command",
    icon: "terminal-2",
    module: { placement: "right", icon: "terminal-2", config: { command: "echo hello" } },
    states: [{ name: "Output", output: "hello" }],
  },
};

// What each bundled plugin is for, in a few words.
export const PLUGIN_ABOUT = {
  caffeine: "Keep-awake toggle",
  calendar: "Upcoming events",
  "now-playing": "Track playing now",
  pomodoro: "Pomodoro timer",
  reminders: "Due reminders",
  "rift-indicator": "Rift layout",
  "system-monitor": "CPU, memory, disk",
  tailscale: "Tailscale status",
};

// The icon that stands for each bundled plugin.
export const PLUGIN_ICONS = {
  caffeine: "mug",
  calendar: "calendar-event",
  "now-playing": "music",
  pomodoro: "alarm",
  reminders: "bell",
  "rift-indicator": "layout-board-split",
  "system-monitor": "activity",
  tailscale: "network",
};

// The icon that stands for what a module is: its bundled plugin's, or its
// type's.
export function kindIcon(module, catalog) {
  const plugin = pluginOf(module, catalog);
  return (plugin !== undefined && PLUGIN_ICONS[plugin]) || BUILT_INS[str(module?.type)]?.icon || "puzzle";
}

// The bundled plugin behind a module: the one its command runs, or
// undefined when the command is someone's own.
export function pluginOf(module, catalog) {
  const command = str(dict(module?.config)?.command);
  const program = command?.trim().split(/\s+/)[0].split("/").pop() ?? "";
  const name = program.startsWith("kantan-plugin-") ? program.slice("kantan-plugin-".length) : undefined;
  return name !== undefined && Object.hasOwn(catalog.plugins, name) ? name : undefined;
}

// The variant of its bundled plugin's preview a module is in: the last
// whose settings the module has, a setting left out having the default
// the plugin's schema gives it. A variant's setting that holds settings of
// its own, such as `show`, asks only for those it names. Undefined for a
// module in none.
export function variantOf(module, catalog) {
  const plugin = pluginOf(module, catalog);
  if (plugin === undefined) return undefined;
  const { variants = [], settings: schema } = catalog.plugins[plugin];
  const settings = dict(dict(module?.config)?.settings) ?? {};
  const has = (value, schema, wanted) => (dict(wanted)
    ? Object.entries(wanted).every(([key, each]) => has(dict(value)?.[key], dict(dict(schema)?.properties)?.[key], each))
    : sameValue(value ?? dict(schema)?.default, wanted));
  return variants.findLast(each => has(settings, schema, each.settings));
}

// `module`, changed from `before`, with the interaction its variant needs
// when the change brought it into that variant: a popup, say, for a view a
// menu has no rows for.
export function inVariant(before, module, catalog) {
  const variant = variantOf(module, catalog);
  if (variant?.interaction === undefined || variant === variantOf(before, catalog)) return module;
  const interaction = { ...module.interaction };
  for (const [slot, needed] of Object.entries(variant.interaction)) interaction[slot] = { ...interaction[slot], ...needed };
  return { ...module, interaction };
}

// The states a module starts with: its bundled plugin's, or its type's.
// A plugin's are those of the variant the module is in, or its own.
// Undefined for a module that needs none.
export function defaultStates(module, catalog) {
  const plugin = pluginOf(module, catalog);
  if (plugin !== undefined) return variantOf(module, catalog)?.states ?? catalog.plugins[plugin].states;
  const type = str(module?.type);
  return type !== undefined && Object.hasOwn(BUILT_INS, type) ? BUILT_INS[type].states : undefined;
}
