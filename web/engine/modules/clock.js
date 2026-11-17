// The clock module: the time in its `format`, with each of its `formats`
// as a variable. Its sample is `{ time, locale, timezone }`: the moment as
// an ISO 8601 date or milliseconds since 1970, and the system's locale and
// time zone. Without a time it shows the present.
import { formatDate } from "../dates.js";
import { plainState } from "../output.js";
import { num, str } from "../values.js";
import { stringEntries } from "./levels.js";

export default {
  // A clock module needs a `format`.
  load(config) {
    const format = str(config?.format);
    if (format === undefined) return undefined;
    return { format, timezone: str(config.timezone), formats: stringEntries(config.formats) };
  },

  state(loaded, sample) {
    const parsed = num(sample?.time) ?? Date.parse(str(sample?.time) ?? "");
    const time = Number.isFinite(parsed) ? parsed : Date.now();
    const zone = { timezone: loaded.timezone ?? str(sample?.timezone), locale: str(sample?.locale) };
    const state = plainState("");
    const value = formatDate(time, loaded.format, zone);
    if (value.unsupported !== undefined) return { ...state, unsupported: `clock format "${value.unsupported}"` };
    state.value = value.text;
    for (const [name, pattern] of Object.entries(loaded.formats)) {
      const written = formatDate(time, pattern, zone);
      if (written.unsupported !== undefined) return { ...state, unsupported: `clock format "${written.unsupported}"` };
      state.variables[name] = written.text;
    }
    return state;
  },
};
