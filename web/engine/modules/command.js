// The command module: shows what a command prints, as text or as the JSON
// a plugin prints.
import { parseOutput, plainState } from "../output.js";
import { dict, str } from "../values.js";

export default {
  // A command module needs a `command`.
  load(config) {
    if (str(config?.command) === undefined) return undefined;
    return { json: str(config.output) === "json", toggle: str(config.toggle) };
  },

  // The state for `output`, what the command printed: text, or the JSON
  // object a plugin's output parses to. In JSON mode, output that isn't a
  // JSON object shows as the text it is.
  state(loaded, output) {
    if (output === undefined) return plainState("");
    const raw = typeof output === "string" ? output : JSON.stringify(output);
    if (!loaded.json) return plainState(raw);
    let json = output;
    if (typeof output === "string") {
      try {
        json = JSON.parse(output);
      } catch {
        return plainState(raw);
      }
    }
    return dict(json) && raw !== "" ? parseOutput(json, raw) : plainState(raw);
  },

  toggle: loaded => loaded.toggle,
};
