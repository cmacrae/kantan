// The power module: the battery's level and whether it is charging. Its
// sample is `{ level, charging, plugged, lowPowerMode }`; without one, the
// Mac has no battery.
import { plainState } from "../output.js";
import { bool, int, str } from "../values.js";
import { iconForLevel, iconList, stateStyle } from "./levels.js";

const LEVEL_ICONS = ["battery-filled", "battery-1-filled", "battery-2-filled", "battery-3-filled", "battery-4-filled"];

export default {
  // A power module needs at least one level icon.
  load(config) {
    const levelIcons = iconList(config?.icons?.level, LEVEL_ICONS);
    if (!levelIcons.length) return undefined;
    return {
      showLevel: bool(config?.showLevel) ?? false,
      lowThreshold: int(config?.lowThreshold) ?? 20,
      levelIcons,
      chargingIcon: str(config?.icons?.charging) ?? "bolt-filled",
      pluggedIcon: str(config?.icons?.plugged) ?? "plug",
      styles: {
        charging: stateStyle(config?.style?.charging),
        plugged: stateStyle(config?.style?.plugged),
        lowPowerMode: stateStyle(config?.style?.lowPowerMode),
        low: stateStyle(config?.style?.low),
      },
    };
  },

  state(loaded, sample) {
    const state = plainState("");
    const level = int(sample?.level);
    if (level === undefined || level < 0) {
      state.icon = loaded.levelIcons[0];
      state.variables = { level: "", state: "" };
      return state;
    }
    const charging = sample.charging === true, plugged = sample.plugged === true;
    if (loaded.showLevel) state.value = `${level}%`;
    state.icon = charging ? loaded.chargingIcon : plugged ? loaded.pluggedIcon : iconForLevel(level, loaded.levelIcons);
    state.variables = { level: String(level), state: charging ? "Charging" : plugged ? "Plugged" : "Discharging" };

    // The style of the first state the battery is in that has one.
    const { styles } = loaded;
    state.style = (charging && styles.charging)
      || (plugged && styles.plugged)
      || (!plugged && sample.lowPowerMode === true && styles.lowPowerMode)
      || (!plugged && level < loaded.lowThreshold && styles.low)
      || undefined;
    return state;
  },
};
