// A document's config as the YAML files kantan reads, and a YAML file
// someone wrote as the value kantan would load from it.
import { parse, stringify } from "yaml";
import { dict, list } from "../engine/values.js";

// The order keys are written in: a config's and a module's own keys as the
// docs list them, and any others after, as they came.
const CONFIG_KEYS = ["theme", "displays", "height", "padding", "iconTextSpacing", "cornerRadius", "blur", "autohide", "fonts", "style", "modules"];
const MODULE_KEYS = ["name", "type", "placement", "displays", "icon", "fonts", "style", "mask", "config", "interaction"];

function ordered(value, keys) {
  if (!dict(value)) return value;
  const known = keys.filter(key => value[key] !== undefined);
  const others = Object.keys(value).filter(key => !keys.includes(key) && value[key] !== undefined);
  return Object.fromEntries([...known, ...others].map(key => [key, value[key]]));
}

const orderedModule = module => ordered(module, MODULE_KEYS);

// YAML for `value` that kantan reads back as the same value. Its parser
// takes more plain words for numbers than YAML 1.2 does, so strings are
// quoted wherever YAML 1.1 would read them as anything else.
const write = value => stringify(value, { version: "1.1", lineWidth: 0, aliasDuplicateObjects: false });

// The files a document's config is written as: `{ path, text }` for
// config.yaml, then for each file of modules.d in the order kantan loads
// them.
export function documentFiles(document) {
  const config = ordered(dict(document.config) ?? {}, CONFIG_KEYS);
  if (list(config.modules)?.length) config.modules = config.modules.map(orderedModule);
  else delete config.modules;
  const text = Object.keys(config).length === 0 ? "" : write(config);
  // A blank line before the modules and between them, as configs are
  // written by hand.
  const at = text.search(/^modules:\n/m);
  const spaced = at < 0
    ? text
    : `${text.slice(0, at)}${at > 0 ? "\n" : ""}modules:\n${text.slice(at + "modules:\n".length).replace(/\n(  - )/g, "\n\n$1")}`;
  const files = [{ path: "config.yaml", text: spaced }];
  for (const name of Object.keys(dict(document.modulesDir) ?? {}).sort()) {
    files.push({ path: `modules.d/${name}`, text: write(orderedModule(document.modulesDir[name])) });
  }
  return files;
}

// The value a YAML file holds, or `{ problem }` saying why it can't be
// read. Comments are dropped.
export function readYaml(text) {
  try {
    return { value: parse(text, { version: "1.2", merge: true }) };
  } catch (error) {
    return { problem: error.message };
  }
}

export const writeYaml = write;
