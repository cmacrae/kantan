// The wifi module: whether WiFi is connected and how strong its signal is.
// Its sample is `{ connected, rssi, hotspot }`, the signal in dBm.
import { plainState } from "../output.js";
import { int, str } from "../values.js";
import { iconForLevel, iconList } from "./levels.js";

export default {
  // A wifi module needs at least one strength icon.
  load(config) {
    const strengthIcons = iconList(config?.icons?.strength, ["wifi-1", "wifi-2", "wifi"]);
    if (!strengthIcons.length) return undefined;
    return {
      strengthIcons,
      disconnectedIcon: str(config?.icons?.disconnected) ?? "wifi-off",
      hotspotIcon: str(config?.icons?.hotspot) ?? "circles-relation",
    };
  },

  state(loaded, sample) {
    const state = plainState("");
    const connected = sample?.connected === true, hotspot = sample?.hotspot === true;
    state.variables = { state: connected ? "Connected" : "Disconnected" };
    if (!connected) {
      state.icon = loaded.disconnectedIcon;
      return state;
    }
    // The signal's quality: -30 dBm and stronger is all of it, -90 none.
    const clamped = Math.max(-90, Math.min(-30, int(sample.rssi) ?? 0));
    const quality = Math.trunc(Math.fround(Math.fround((clamped + 90) / 60) * 100));
    const strengthIcon = iconForLevel(quality, loaded.strengthIcons);
    state.icon = hotspot ? loaded.hotspotIcon : strengthIcon;

    // The full-strength icon sits dimmed behind a weaker signal's.
    const fullIcon = loaded.strengthIcons.at(-1);
    if (!hotspot && loaded.strengthIcons.length > 1 && strengthIcon !== fullIcon) state.backgroundIcon = fullIcon;
    return state;
  },
};
