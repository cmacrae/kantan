// What the scripts assembling a preview share: turning the states a
// plugin's generator printed into a document's states, and checking the
// engine can draw the document whole.
//
// A generator prints `{ "states": [{ name, output, after }] }`: each state's
// name, the output the plugin prints in it, and `after`, the output each
// command leads to when run from it. A command a state runs that leads to
// another state's output becomes a transition to that state.
import { readFileSync } from "node:fs";
import { isDeepStrictEqual } from "node:util";
import { bindSettings, bundleSchema, settingDefaults } from "../builder/settings.js";
import { moduleCommands, resolveBar, validateDocument } from "../engine/index.js";

const read = path => JSON.parse(readFileSync(path, "utf8"));

// What a plugin's generator printed for one module, read from the files
// `paths` names: the states `named`, printed from settings whose colours
// and icons are their names, the states `plain`, printed from the
// settings as written, and the plugin's settings `schema`. `shared` is
// the module config schema and `settings` the module's.
//
// Returns the plugin's `schema` standing alone, the `named` states, and
// the states `bound` to the settings. `problem` is told when the bound
// states aren't the plain ones: the plugin doesn't print a colour or an
// icon as it was given it, or the schema's default isn't the plugin's.
export function readGenerated({ named, plain, schema }, shared, settings, problem) {
  const bundled = bundleSchema(read(schema), shared);
  const states = read(named).states;
  const bound = bindSettings(states, settings ?? {}, settingDefaults(bundled));
  const printed = read(plain).states;
  if (!isDeepStrictEqual(bound, printed)) {
    const at = Array.isArray(printed) && Array.isArray(bound) ? printed.findIndex((state, i) => !isDeepStrictEqual(state, bound[i])) : -1;
    problem(`its preview doesn't follow its settings${at < 0 ? "" : `: in the state ${printed[at]?.name}, its generator printed\n${JSON.stringify(printed[at])}\nfor the settings as written, and for the settings by name\n${JSON.stringify(bound[at])}`}`);
  }
  return { schema: bundled, named: states, bound };
}

// `named` states with the transitions of the states at the same places in
// `states`.
export function withTransitions(named, states) {
  return named.map(({ name, output }, i) => (states?.[i]?.transitions ? { name, output, transitions: states[i].transitions } : { name, output }));
}

// Everything within `value` the engine marked as something it can't draw.
function unsupportedWithin(value) {
  if (Array.isArray(value)) return value.flatMap(unsupportedWithin);
  if (value === null || typeof value !== "object") return [];
  const own = value.type === "unsupported" ? [value.what] : typeof value.unsupported === "string" ? [value.unsupported] : [];
  return [...own, ...Object.values(value).flatMap(unsupportedWithin)];
}

// The module named `name` as `document` draws it in each appearance while
// in its state `state`, the other modules in their first. Every icon
// looked up is added to `icons`, and `problem` is told what the preview
// can't show as kantan would.
function drawn(document, name, state, icons, problem) {
  const modules = [false, true].flatMap(dark => {
    const bar = resolveBar(document, { dark, states: { [name]: state }, icons: icon => void icons.add(icon) });
    if (bar.problem !== undefined) problem(`its config doesn't load: ${bar.problem}`);
    return Object.values(bar.placements).flat().filter(module => module.name === name);
  });
  if (modules.length === 0) problem(`${state}: the module isn't in the bar`);
  for (const what of new Set(unsupportedWithin(modules))) problem(`${state}: the preview can't draw its ${what}`);
  for (const module of modules) {
    if (module.viewProblem !== undefined) problem(`${state}: kantan would reject its view: ${module.viewProblem}`);
  }
  return modules;
}

// Gives `document` the states `generated` holds for its module `name`,
// with the transitions between them. `problem` is told of a generator
// that printed no states or names a command no state runs.
export function addGeneratedStates(document, name, generated, problem) {
  if (!Array.isArray(generated) || generated.length === 0) {
    problem("its generator printed no states");
    return;
  }
  document.states = { ...document.states, [name]: generated.map(({ name, output }) => ({ name, output })) };

  const quiet = () => {};
  const commands = generated.map(state => new Set(drawn(document, name, state.name, new Set(), quiet).flatMap(moduleCommands)));
  const everyCommand = new Set(commands.flatMap(set => [...set]));
  generated.forEach((state, i) => {
    const transitions = {};
    for (const [command, output] of Object.entries(state.after ?? {})) {
      if (!everyCommand.has(command)) problem(`${state.name}: no state runs the command ${command}`);
      const target = generated.find(other => isDeepStrictEqual(other.output, output));
      if (commands[i].has(command) && target && target !== state) transitions[command] = target.name;
    }
    if (Object.keys(transitions).length) document.states[name][i].transitions = transitions;
  });
}

// Checks `document` is one the engine draws whole: valid, with every
// module in the bar in each of its states and nothing the preview can't
// draw. `problem(module, message)` is told of anything else. Returns the
// icons the document draws.
export function checkDocument(document, problem) {
  const icons = new Set();
  for (const message of validateDocument(document)) problem(undefined, message);
  const bar = resolveBar(document);
  if (bar.problem !== undefined) problem(undefined, `its config doesn't load: ${bar.problem}`);
  for (const module of Object.values(bar.placements).flat()) {
    const states = document.states?.[module.name] ?? [{ name: undefined }];
    for (const state of states) drawn(document, module.name, state.name, icons, message => problem(module.name, message));
  }
  // A drawer shows another icon once opened, which no listed state need show.
  const drawers = Object.values(bar.placements).flat().filter(module => module.type === "drawer");
  const open = Object.fromEntries(drawers.map(drawer => [drawer.name, { open: true }]));
  for (const dark of [false, true]) resolveBar(document, { dark, samples: open, icons: icon => void icons.add(icon) });
  return icons;
}
