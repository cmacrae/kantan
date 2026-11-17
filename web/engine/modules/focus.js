// The focus module: shown while a Focus is on, naming its mode when kantan
// can read it. Its sample is `{ active, mode: { identifier, name } }`;
// without one, no Focus is on.
import { plainState } from "../output.js";
import { dict, str } from "../values.js";
import { stateStyle, stringEntries } from "./levels.js";

export default {
  load(config) {
    const styles = {};
    for (const [mode, value] of Object.entries(dict(config?.style) ?? {})) {
      const style = stateStyle(value);
      if (style) styles[mode] = style;
    }
    return { icons: stringEntries(config?.icons), styles };
  },

  state(loaded, sample) {
    const state = plainState("");
    const mode = dict(sample?.mode) && str(sample.mode.identifier) !== undefined
      ? { identifier: sample.mode.identifier, name: str(sample.mode.name) ?? sample.mode.identifier }
      : undefined;
    state.hidden = !(sample?.active === true || (sample?.active === undefined && mode !== undefined));
    // An entry for the mode, by its name and then its identifier.
    const entry = map => (mode === undefined ? undefined
      : Object.hasOwn(map, mode.name) ? map[mode.name]
      : Object.hasOwn(map, mode.identifier) ? map[mode.identifier] : undefined);
    state.icon = entry(loaded.icons) ?? "";
    state.style = entry(loaded.styles);
    state.variables = { mode: mode?.name ?? "" };
    return state;
  },
};
