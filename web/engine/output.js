// What a module shows at one moment: its value, icon, variables and so on.
// A command module's state comes from the output its command printed; the
// built-in modules make theirs from a sample of what they would read.
import { parseDynamicStyle } from "./style.js";
import { dict, list, str } from "./values.js";
import { decodeJsonView } from "./view.js";

// A state showing `value` and nothing else.
export function plainState(value) {
  return { value, icon: "", variables: {}, segments: [], data: {}, hidden: false, active: true };
}

// A truth value as kantan reads one from JSON: `true` or `false`, or the
// numbers 1 and 0.
function jsonBool(value) {
  if (typeof value === "boolean") return value;
  return value === 1 ? true : value === 0 ? false : undefined;
}

// A data field as the views read it back: a string as written, a number in
// digits, and a truth value as 1 or 0.
function dataString(value) {
  if (typeof value === "boolean") return value ? "1" : "0";
  return typeof value === "string" ? value : JSON.stringify(value);
}

// The state a command module shows for the JSON object `json` its command
// printed, `raw` being the text it printed. Each field is read on its own:
// one of the wrong type is ignored, leaving the rest.
export function parseOutput(json, raw) {
  const state = plainState(str(json.value) ?? raw);
  state.icon = str(json.icon) ?? "";

  if (dict(json.variables) && Object.values(json.variables).every(v => typeof v === "string")) {
    state.variables = json.variables;
  }

  if (list(json.segments)?.every(dict)) {
    state.segments = json.segments
      .filter(segment => typeof segment.text === "string")
      .map(segment => ({ text: segment.text, fg: str(segment.fg) }));
  }

  if (json.view != null) {
    const { node, problem } = decodeJsonView(json.view);
    state.view = node;
    state.viewProblem = problem;
  }

  if (dict(json.data) && Object.values(json.data).every(rows => list(rows)?.every(dict))) {
    state.data = Object.fromEntries(Object.entries(json.data).map(([key, rows]) => [
      key,
      // A null field is left out, so it reads as missing.
      rows.map(row => Object.fromEntries(
        Object.entries(row).filter(([, v]) => v !== null).map(([k, v]) => [k, dataString(v)]))),
    ]));
  }

  state.hidden = jsonBool(json.hidden) ?? false;
  state.active = jsonBool(json.active) ?? true;
  state.style = parseDynamicStyle(json.style);
  return state;
}
