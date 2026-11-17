// What the builder offers to add to a bar: kantan's module types, each
// with the module a new one starts as and the states it starts with, and
// the bundled plugins, whose modules and states the site's build supplies.
//
// A catalogue is `{ plugins, themes, example }`: `plugins` holds each
// bundled plugin's example `module` and the `states` its preview generator
// printed, by plugin name, `themes` the theme files kantan bundles, by
// name, and `example` the document of the example bar, when there is one.
import { dict, str } from "../engine/values.js";

export const EMPTY_CATALOG = { plugins: {}, themes: {} };

// Each module type, in the order the builder lists them: what it's called,
// the icon that stands for it, the module a new one starts as, and the
// states a new one shows, each a sample of what the module would read.
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
    module: { placement: "right" },
    states: [
      { name: "Discharging", output: { level: 78 } },
      { name: "Charging", output: { level: 42, charging: true, plugged: true } },
      { name: "Low", output: { level: 9 } },
    ],
  },
  wifi: {
    label: "Wi-Fi",
    icon: "wifi",
    module: { placement: "right" },
    states: [
      { name: "Fair signal", output: { connected: true, rssi: -62 } },
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
    ],
  },
  bluetooth: {
    label: "Bluetooth",
    icon: "bluetooth",
    module: { placement: "right" },
    states: [
      { name: "Connected", output: { on: true, devices: [{ name: "AirPods Pro", connected: true }] } },
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

// The bundled plugin behind a module: the one its command runs, or
// undefined when the command is someone's own.
export function pluginOf(module, catalog) {
  const command = str(dict(module?.config)?.command);
  const program = command?.trim().split(/\s+/)[0].split("/").pop() ?? "";
  const name = program.startsWith("kantan-plugin-") ? program.slice("kantan-plugin-".length) : undefined;
  return name !== undefined && Object.hasOwn(catalog.plugins, name) ? name : undefined;
}

// The states a module starts with: its bundled plugin's, or its type's.
// Undefined for a module that needs none.
export function defaultStates(module, catalog) {
  const plugin = pluginOf(module, catalog);
  if (plugin !== undefined) return catalog.plugins[plugin].states;
  const type = str(module?.type);
  return type !== undefined && Object.hasOwn(BUILT_INS, type) ? BUILT_INS[type].states : undefined;
}
