// Assembles each bundled plugin's preview document from its example config
// and the states its generator printed, and checks the preview is whole.
//
// usage: assemble.js <out> <themes.json> <name>=<example.json>=<states.json>...
//
// Writes <out>/<name>.json for each plugin, and <out>/icons.txt naming every
// icon the previews draw. Fails on a preview that isn't a valid document,
// whose module isn't drawn, that holds something the preview can't draw, or
// whose generator names a command no state runs.
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { DOCUMENT_VERSION } from "../engine/index.js";
import { addGeneratedStates, checkDocument } from "./states.js";

const [out, themesPath, ...plugins] = process.argv.slice(2);
const read = path => JSON.parse(readFileSync(path, "utf8"));
const themes = read(themesPath);

const icons = new Set();
const problems = [];
mkdirSync(out, { recursive: true });

for (const plugin of plugins) {
  const [name, examplePath, statesPath] = plugin.split("=");
  const problem = message => problems.push(`${name}: ${message}`);
  const module = read(examplePath);
  const document = {
    version: DOCUMENT_VERSION,
    config: { theme: Object.keys(themes)[0] },
    modulesDir: { [`00-${name}.yaml`]: module },
    themes,
  };
  addGeneratedStates(document, module.name, read(statesPath).states, problem);
  const before = problems.length;
  for (const icon of checkDocument(document, (_, message) => problem(message))) icons.add(icon);
  if (problems.length === before && !document.states?.[module.name]) problem("the module isn't in the bar");
  writeFileSync(`${out}/${name}.json`, JSON.stringify(document));
}

if (problems.length) {
  console.error(problems.join("\n"));
  process.exit(1);
}
writeFileSync(`${out}/icons.txt`, [...icons].sort().join("\n") + "\n");
