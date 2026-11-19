// Assembles each bundled plugin's preview document from its example config
// and the states its generator printed, and checks the preview is whole.
//
// usage: assemble.js <out> <themes.json> <module-config.schema.json>
//          <name>=<example.json>=<named.json>=<plain.json>=<settings.schema.json>
//            [=<variant.json>=<named.json>=<plain.json>]...
//
// <named.json> is what the plugin's generator printed for the example's
// settings with their colours and icons replaced by their names, and
// <plain.json> what it printed for the settings as written. Each
// <variant.json> holds `settings` the preview differs for, the
// `interaction` the module needs with them when it needs one, and the
// `name` its preview goes by when it has one of its own, followed by what
// the generator printed with those settings over the example's.
//
// Writes <out>/<name>.json for each plugin, <out>/<name>-<variant>.json
// for each of its variants that has a name, <out>/icons.txt naming every
// icon the previews draw, and <out>/plugins.json, holding each plugin's
// example module, its states by setting name, those of each of its
// variants, and its settings schema. Fails
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
  const [name, examplePath, named, plain, schema, ...rest] = plugin.split("=");
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

  // The module in each variant's settings, checked as the example is.
  const variants = [];
  for (let at = 0; at < rest.length; at += 3) {
    const { name: variant, settings, interaction } = read(rest[at]);
    const varied = {
      ...module,
      config: { ...module.config, settings: { ...module.config?.settings, ...settings } },
      interaction: { ...module.interaction, ...interaction },
    };
    const { states: _, ...base } = document;
    const drawn = { ...base, modulesDir: { [`00-${name}.yaml`]: varied } };
    const printed = readGenerated({ named: rest[at + 1], plain: rest[at + 2], schema }, shared, varied.config.settings, problem);
    addGeneratedStates(drawn, module.name, printed.bound, problem);
    for (const icon of checkDocument(drawn, (_, message) => problem(message))) icons.add(icon);
    if (variant !== undefined) writeFileSync(`${out}/${name}-${variant}.json`, JSON.stringify(drawn));
    variants.push({ settings, ...(interaction ? { interaction } : {}), states: withTransitions(printed.named, drawn.states?.[module.name]) });
  }
  if (variants.length) catalog[name].variants = variants;
}

if (problems.length) {
  console.error(problems.join("\n"));
  process.exit(1);
}
writeFileSync(`${out}/plugins.json`, JSON.stringify(catalog));
writeFileSync(`${out}/icons.txt`, [...icons].sort().join("\n") + "\n");
