// Assembles a whole bar's preview document from a config, the states its
// built-in modules show and the states its plugins' generators printed,
// and checks the preview is whole.
//
// usage: bar.js <out> <config.json> <themes.json> <states.json> <module-config.schema.json>
//          <module>=<named.json>=<plain.json>=<settings.schema.json>...
//
// <states.json> holds a document's `states` for the modules that read the
// system: a sample of what each would read. <named.json> is what the
// generator of the plugin behind <module> printed for the module's
// settings with their colours and icons replaced by their names, and
// <plain.json> what it printed for the settings as written.
//
// Writes <out>/document.json, <out>/named.json, the same document with
// its plugins' states by setting name, and <out>/icons.txt, naming every
// icon the bar draws. Fails on a document that isn't valid, a command module with
// no generated states, anything the preview can't draw, or a generator
// naming a command no state runs.
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { DOCUMENT_VERSION, resolveBar } from "../engine/index.js";
import { addGeneratedStates, checkDocument, readGenerated, withTransitions } from "./states.js";

const [out, configPath, themesPath, statesPath, sharedPath, ...generated] = process.argv.slice(2);
const read = path => JSON.parse(readFileSync(path, "utf8"));

const problems = [];
const document = { version: DOCUMENT_VERSION, config: read(configPath), themes: read(themesPath), states: read(statesPath) };

const shared = read(sharedPath);
const named = {};
for (const each of generated) {
  const [name, namedPath, plain, schema] = each.split("=");
  const problem = message => problems.push(`${name}: ${message}`);
  const settings = (document.config.modules ?? []).find(module => module?.name === name)?.config?.settings;
  const printed = readGenerated({ named: namedPath, plain, schema }, shared, settings, problem);
  addGeneratedStates(document, name, printed.bound, problem);
  named[name] = withTransitions(printed.named, document.states?.[name]);
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
writeFileSync(`${out}/named.json`, JSON.stringify({ ...document, states: { ...document.states, ...named } }));
writeFileSync(`${out}/icons.txt`, [...icons].sort().join("\n") + "\n");
