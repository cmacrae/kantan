// The volume module: the output volume, whether it is muted and the device
// it plays through. Its sample is `{ volume, muted, device }`, the volume
// from 0 to 1.
import { plainState } from "../output.js";
import { dict, num, str } from "../values.js";
import { floatPercent, iconForLevel, iconList, stringEntries } from "./levels.js";

const DEVICE_ICONS = { AirPods: "device-airpods", Headphones: "headphones" };

// The icon configured for a device: that of the longest key its name
// contains, ignoring case, and of equally long keys the first in order.
function deviceIcon(name, icons) {
  const lowered = name.toLowerCase();
  const keys = Object.keys(icons).filter(key => key !== "" && lowered.includes(key.toLowerCase()));
  keys.sort((a, b) => [...b].length - [...a].length || (a < b ? -1 : a > b ? 1 : 0));
  return keys.length ? icons[keys[0]] : undefined;
}

export default {
  // A volume module needs at least one level icon.
  load(config) {
    const levelIcons = iconList(config?.icons?.level, ["volume-4", "volume-2", "volume"]);
    if (!levelIcons.length) return undefined;
    return {
      levelIcons,
      mutedIcon: str(config?.icons?.muted) ?? "volume-off",
      deviceIcons: dict(config?.icons?.device) ? stringEntries(config.icons.device) : DEVICE_ICONS,
    };
  },

  state(loaded, sample) {
    const state = plainState("");
    const muted = sample?.muted === true, device = str(sample?.device) ?? "";
    const level = Math.max(0, Math.min(100, floatPercent(num(sample?.volume) ?? 0)));
    const ownIcon = deviceIcon(device, loaded.deviceIcons);
    const levelIcon = iconForLevel(level, loaded.levelIcons);
    state.icon = muted ? loaded.mutedIcon : ownIcon ?? levelIcon;

    // The full-volume icon sits dimmed behind a quieter level's, whose
    // speaker is drawn where its own is.
    const fullIcon = loaded.levelIcons.at(-1);
    if (!muted && ownIcon === undefined && loaded.levelIcons.length > 1 && levelIcon !== fullIcon) {
      state.backgroundIcon = fullIcon;
      state.backgroundIconLeading = true;
    }
    state.variables = { level: String(level), state: muted ? "Muted" : `${level}%`, device };
    return state;
  },
};
