// The document every preview, builder and share link holds: a user's config
// files as parsed YAML, and the states its modules show.
//
//   version     the format's version
//   config      config.yaml
//   modulesDir  the files of modules.d, by filename
//   themes      the theme files the config selects from, by theme name
//   states      what each module shows, by module name: a list of named
//               states, each holding the `output` its command printed and
//               the `transitions` from it, the state each command leads to
//   view        how the bar is being looked at: `dark` for the dark
//               appearance, `notch` for a screen with one, and `shown`, the
//               state each module shows, by module name
import { dict, list, own } from "./values.js";

export const DOCUMENT_VERSION = 1;

// What's wrong with `document`, as a list of sentences: empty when it is a
// document the engine can draw.
export function validateDocument(document) {
  if (!dict(document)) return ["The document isn't a mapping"];
  const problems = [];
  if (document.version !== DOCUMENT_VERSION) problems.push(`The document's version isn't ${DOCUMENT_VERSION}`);
  if (!dict(document.config)) problems.push("config isn't a mapping");

  for (const key of ["modulesDir", "themes", "states", "view"]) {
    if (document[key] !== undefined && !dict(document[key])) problems.push(`${key} isn't a mapping`);
  }
  for (const [file, module] of Object.entries(dict(document.modulesDir) ?? {})) {
    if (!dict(module)) problems.push(`modulesDir's ${file} isn't a mapping`);
  }
  for (const [name, theme] of Object.entries(dict(document.themes) ?? {})) {
    if (!dict(theme)) problems.push(`The theme ${name} isn't a mapping`);
  }

  const view = dict(document.view) ?? {};
  for (const key of ["dark", "notch"]) {
    if (view[key] !== undefined && typeof view[key] !== "boolean") problems.push(`view's ${key} isn't true or false`);
  }
  if (view.shown !== undefined && !dict(view.shown)) problems.push("view's shown isn't a mapping");
  for (const [module, state] of Object.entries(dict(view.shown) ?? {})) {
    if (typeof state !== "string") problems.push(`view shows ${module} in a state that isn't a name`);
  }

  for (const [module, states] of Object.entries(dict(document.states) ?? {})) {
    if (!list(states)) {
      problems.push(`${module}'s states aren't a list`);
      continue;
    }
    const names = states.map(state => state?.name);
    states.forEach((state, i) => {
      const label = `${module}'s state ${typeof state?.name === "string" ? state.name : i + 1}`;
      if (!dict(state) || typeof state.name !== "string" || state.name === "") {
        problems.push(`${label} has no name`);
        return;
      }
      if (names.indexOf(state.name) !== i) problems.push(`${label} shares its name with another`);
      if (state.output !== undefined && typeof state.output !== "string" && !dict(state.output)) {
        problems.push(`${label}'s output is neither text nor a mapping`);
      }
      if (state.transitions === undefined) return;
      if (!dict(state.transitions)) {
        problems.push(`${label}'s transitions aren't a mapping`);
        return;
      }
      for (const [command, target] of Object.entries(state.transitions)) {
        if (!names.includes(target)) problems.push(`${label} leads to ${target}, which isn't a state, by ${command}`);
      }
    });
  }
  return problems;
}

// The state the module named `module` moves to when `command` runs while it
// shows the state named `state`, or undefined when the command leads
// nowhere.
export function nextState(document, module, state, command) {
  const states = (list(own(document.states, module)) ?? []).filter(dict);
  const current = states.find(s => s.name === state) ?? states[0];
  return own(current?.transitions, command);
}
