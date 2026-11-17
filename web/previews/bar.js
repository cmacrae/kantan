// Assembles a whole bar's preview document from a config, the states its
// built-in modules show and the states its plugins' generators printed,
// and checks the preview is whole.
//
// usage: bar.js <out> <config.json> <themes.json> <states.json> <module>=<generated.json>...
//
// <states.json> holds a document's `states` for the modules that read the
// system: a sample of what each would read. Each <generated.json> is what
// the generator of the plugin behind <module> printed.
//
// Writes <out>/document.json and <out>/icons.txt, naming every icon the
// bar draws. Fails on a document that isn't valid, a command module with
// no generated states, anything the preview can't draw, or a generator
// naming a command no state runs.
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { DOCUMENT_VERSION, resolveBar } from "../engine/index.js";
import { addGeneratedStates, checkDocument } from "./states.js";

const [out, configPath, themesPath, statesPath, ...generated] = process.argv.slice(2);
const read = path => JSON.parse(readFileSync(path, "utf8"));

const problems = [];
const document = { version: DOCUMENT_VERSION, config: read(configPath), themes: read(themesPath), states: read(statesPath) };

for (const pair of generated) {
  const [name, path] = pair.split("=");
  addGeneratedStates(document, name, read(path).states, message => problems.push(`${name}: ${message}`));
}

const modules = Object.values(resolveBar(document).placements).flat();
for (const module of modules) {
  if (module.type === "command" && !document.states[module.name]) problems.push(`${module.name}: no generator gives its states`);
}
for (const name of Object.keys(document.states)) {
  if (!modules.some(module => module.name === name)) problems.push(`${name}: has states but isn't in the bar`);
}
const icons = checkDocument(document, (module, message) => problems.push(module ? `${module}: ${message}` : message));

if (problems.length) {
  console.error(problems.join("\n"));
  process.exit(1);
}
mkdirSync(out, { recursive: true });
writeFileSync(`${out}/document.json`, JSON.stringify(document));
writeFileSync(`${out}/icons.txt`, [...icons].sort().join("\n") + "\n");
