// Assembles each bundled plugin's preview document from its example config
// and the states its generator printed, and checks the preview is whole.
//
// usage: assemble.js <out> <themes.json> <module-config.schema.json>
//          <name>=<example.json>=<named.json>=<plain.json>=<settings.schema.json>...
//
// <named.json> is what the plugin's generator printed for the example's
// settings with their colours and icons replaced by their names, and
// <plain.json> what it printed for the settings as written.
//
// Writes <out>/<name>.json for each plugin, <out>/icons.txt naming every
// icon the previews draw, and <out>/plugins.json, holding each plugin's
// example module, its states by setting name and its settings schema. Fails
// on a preview that isn't a valid document, whose module isn't drawn, that
// holds something the preview can't draw, whose generator names a command
// no state runs, or whose states don't follow the plugin's settings.
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { DOCUMENT_VERSION } from "../engine/index.js";
import { addGeneratedStates, checkDocument, readGenerated, withTransitions } from "./states.js";

const [out, themesPath, sharedPath, ...plugins] = process.argv.slice(2);
const read = path => JSON.parse(readFileSync(path, "utf8"));
const themes = read(themesPath);
const shared = read(sharedPath);
const catalog = {};

const icons = new Set();
const problems = [];
mkdirSync(out, { recursive: true });

for (const plugin of plugins) {
  const [name, examplePath, named, plain, schema] = plugin.split("=");
  const problem = message => problems.push(`${name}: ${message}`);
  const module = read(examplePath);
  const document = {
    version: DOCUMENT_VERSION,
    config: { theme: Object.keys(themes)[0] },
    modulesDir: { [`00-${name}.yaml`]: module },
    themes,
  };
  const generated = readGenerated({ named, plain, schema }, shared, module.config?.settings, problem);
  addGeneratedStates(document, module.name, generated.bound, problem);
  const before = problems.length;
  for (const icon of checkDocument(document, (_, message) => problem(message))) icons.add(icon);
  if (problems.length === before && !document.states?.[module.name]) problem("the module isn't in the bar");
  writeFileSync(`${out}/${name}.json`, JSON.stringify(document));
  catalog[name] = { module, states: withTransitions(generated.named, document.states?.[module.name]), settings: generated.schema };
}

if (problems.length) {
  console.error(problems.join("\n"));
  process.exit(1);
}
writeFileSync(`${out}/plugins.json`, JSON.stringify(catalog));
writeFileSync(`${out}/icons.txt`, [...icons].sort().join("\n") + "\n");
