// The bluetooth module: whether Bluetooth is on and which devices are
// connected. Its sample is `{ on, devices: [{ name, connected }] }`;
// without one, Bluetooth is on with nothing paired.
import { plainState } from "../output.js";
import { list, str } from "../values.js";

export default {
  load(config) {
    return { icon: str(config?.icon) ?? "bluetooth", disabledIcon: str(config?.disabledIcon) ?? "bluetooth-off" };
  },

  state(loaded, sample) {
    const state = plainState("");
    const on = sample?.on !== false;
    const connected = on
      ? (list(sample?.devices) ?? []).filter(device => device?.connected === true).map(device => str(device.name) ?? "")
      : [];
    state.icon = on ? loaded.icon : loaded.disabledIcon;
    // The icon is dimmed unless a device is connected.
    state.active = connected.length > 0;
    state.variables = { state: !on ? "Off" : connected.length ? "Connected" : "On", devices: connected.join(", ") };
    return state;
  },
};
