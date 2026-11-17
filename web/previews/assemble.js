// Assembles each bundled plugin's preview document from its example config
// and the states its generator printed, and checks the preview is whole.
//
// usage: assemble.js <out> <themes.json> <name>=<example.json>=<states.json>...
//
// A generator prints `{ "states": [{ name, output, after }] }`: each state's
// name, the output the plugin prints in it, and `after`, the output each
// command leads to when run from it. A command a state runs that leads to
// another state's output becomes a transition to that state.
//
// Writes <out>/<name>.json for each plugin, and <out>/icons.txt naming every
// icon the previews draw. Fails on a preview that isn't a valid document,
// whose module isn't drawn, that holds something the preview can't draw, or
// whose generator names a command no state runs.
import { isDeepStrictEqual } from "node:util";
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { DOCUMENT_VERSION, moduleCommands, resolveBar, validateDocument } from "../engine/index.js";

const [out, themesPath, ...plugins] = process.argv.slice(2);
const read = path => JSON.parse(readFileSync(path, "utf8"));
const themes = read(themesPath);

// Everything within `value` the engine marked as something it can't draw.
function unsupportedWithin(value) {
  if (Array.isArray(value)) return value.flatMap(unsupportedWithin);
  if (value === null || typeof value !== "object") return [];
  const own = value.type === "unsupported" ? [value.what] : typeof value.unsupported === "string" ? [value.unsupported] : [];
  return [...own, ...Object.values(value).flatMap(unsupportedWithin)];
}

const icons = new Set();
const problems = [];
mkdirSync(out, { recursive: true });

for (const plugin of plugins) {
  const [name, examplePath, statesPath] = plugin.split("=");
  const problem = message => problems.push(`${name}: ${message}`);
  const module = read(examplePath);
  const generated = read(statesPath).states;
  if (!Array.isArray(generated) || generated.length === 0) {
    problem("its generator printed no states");
    continue;
  }

  const document = {
    version: DOCUMENT_VERSION,
    config: { theme: Object.keys(themes)[0] },
    modulesDir: { [`00-${name}.yaml`]: module },
    themes,
    states: { [module.name]: generated.map(({ name, output }) => ({ name, output })) },
  };

  // Each state's module as the engine resolves it, noting the icons it
  // looks up along the way.
  const resolved = generated.map(state => {
    const modules = [false, true].flatMap(dark => {
      const bar = resolveBar(document, {
        dark,
        states: { [module.name]: state.name },
        icons: icon => void icons.add(icon),
      });
      if (bar.problem !== undefined) problem(`its config doesn't load: ${bar.problem}`);
      return Object.values(bar.placements).flat();
    });
    if (modules.length === 0) problem(`${state.name}: the module isn't in the bar`);
    for (const what of new Set(unsupportedWithin(modules))) problem(`${state.name}: the preview can't draw its ${what}`);
    for (const drawn of modules) {
      if (drawn.viewProblem !== undefined) problem(`${state.name}: kantan would reject its view: ${drawn.viewProblem}`);
    }
    return new Set(modules.flatMap(moduleCommands));
  });

  const everyCommand = new Set(resolved.flatMap(commands => [...commands]));
  generated.forEach((state, i) => {
    const transitions = {};
    for (const [command, output] of Object.entries(state.after ?? {})) {
      if (!everyCommand.has(command)) problem(`${state.name}: no state runs the command ${command}`);
      const target = generated.find(other => isDeepStrictEqual(other.output, output));
      if (resolved[i].has(command) && target && target !== state) transitions[command] = target.name;
    }
    if (Object.keys(transitions).length) document.states[module.name][i].transitions = transitions;
  });

  for (const message of validateDocument(document)) problem(message);
  writeFileSync(`${out}/${name}.json`, JSON.stringify(document));
}

if (problems.length) {
  console.error(problems.join("\n"));
  process.exit(1);
}
writeFileSync(`${out}/icons.txt`, [...icons].sort().join("\n") + "\n");
