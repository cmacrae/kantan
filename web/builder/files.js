// A document's config as the YAML files kantan reads, and a YAML file
// someone wrote as the value kantan would load from it.
import { Document, parse, visit } from "yaml";
import { dict, list } from "../engine/values.js";
import { nameProblem, selectedThemes, themeKind } from "./theme.js";

// The order keys are written in: a config's and a module's own keys as the
// docs list them, and any others after, as they came.
const CONFIG_KEYS = ["theme", "displays", "height", "padding", "iconTextSpacing", "cornerRadius", "blur", "autohide", "menuBarSlots", "fonts", "style", "modules"];
const MODULE_KEYS = ["name", "type", "placement", "displays", "icon", "fonts", "style", "mask", "config", "interaction"];
const PALETTE_KEYS = ["fg", "bg", "shape", "colors"];
const MODE_KEYS = ["light", "dark"];

function ordered(value, keys) {
  if (!dict(value)) return value;
  const known = keys.filter(key => value[key] !== undefined);
  const others = Object.keys(value).filter(key => !keys.includes(key) && value[key] !== undefined);
  return Object.fromEntries([...known, ...others].map(key => [key, value[key]]));
}

const orderedModule = module => ordered(module, MODULE_KEYS);

// The strings kantan's parser reads as something else that YAML 1.1 leaves
// plain: `<<`, which as a key merges its mapping into the one around it,
// `=`, and an octal number written with `0o`.
const READ_AS_ANOTHER = /^(<<|=|[-+]?0o[0-7_]+)$/;

// YAML for `value` that kantan reads back as the same value. Its parser
// takes more plain words for numbers than YAML 1.2 does, so strings are
// quoted wherever YAML 1.1 would read them as anything else, keys
// included, and wherever kantan's parser would. A `<<` is a string like
// any other here, and never a merge.
const withoutMerge = tags => tags.filter(tag => tag.tag !== "tag:yaml.org,2002:merge");
function write(value) {
  const document = new Document(value, { version: "1.1", aliasDuplicateObjects: false, customTags: withoutMerge });
  visit(document, {
    Scalar(_, scalar) {
      if (typeof scalar.value === "string" && READ_AS_ANOTHER.test(scalar.value)) scalar.type = "QUOTE_DOUBLE";
    },
  });
  return document.toString({ lineWidth: 0 });
}

const orderedPalette = palette => ordered(palette, PALETTE_KEYS);

// The files a theme called `name` is written as, each `{ path, text }`
// from the config's directory: one file, or for a theme with flavours in
// the "dir" layout, a directory with a file for each flavour and one for
// its defaults. A theme or a flavour whose name can't be a file's is
// written to none, so every path stays within `themes`.
export function themeFiles(name, theme, layout = "file") {
  if (nameProblem(name) !== undefined) return [];
  const kind = themeKind(theme);
  if (kind === "single") return [{ path: `themes/${name}.yaml`, text: write(orderedPalette(theme)) }];
  if (kind === "modes") {
    const modes = MODE_KEYS.filter(mode => dict(theme[mode])).map(mode => write({ [mode]: orderedPalette(theme[mode]) }));
    return [{ path: `themes/${name}.yaml`, text: modes.join("\n") }];
  }
  const defaults = dict(theme.defaults) ? ordered(theme.defaults, MODE_KEYS) : undefined;
  const flavours = Object.entries(theme.flavours).map(([flavour, palette]) => [flavour, orderedPalette(palette)]);
  if (layout === "dir") {
    return [
      ...(defaults ? [{ path: `themes/${name}/defaults.yaml`, text: write(defaults) }] : []),
      ...flavours.filter(([flavour]) => nameProblem(flavour) === undefined)
        .map(([flavour, palette]) => ({ path: `themes/${name}/${flavour}.yaml`, text: write(palette) })),
    ];
  }
  // A blank line between the defaults and the flavours, and between each
  // flavour, as theme files are written by hand.
  const blocks = flavours.map(([flavour, palette]) => write({ [flavour]: palette }).replace(/^(?=.)/gm, "  "));
  const text = `${defaults ? `${write({ defaults })}\n` : ""}flavours:\n${blocks.join("\n")}`;
  return [{ path: `themes/${name}.yaml`, text }];
}

// A theme file's text for `variants`, what a shared theme can be drawn
// as, each `{ key, label, palette, uses }`. `key` names one of them, for
// its palette alone. "all" is for one file that holds them all: a palette
// for light and one for dark, or for a theme with flavours, each flavour
// by its label with the two the theme uses as its defaults.
export function variantsYaml(variants, key) {
  const own = ({ fg, bg, shape, colors }) => ({ fg, bg, ...(shape === undefined ? {} : { shape }), colors });
  const file = theme => themeFiles("theme", theme)[0].text;
  if (key !== "all") return file(own(variants.find(each => each.key === key).palette));
  const used = mode => variants.find(each => each.uses.includes(mode));
  if (variants.every(each => each.key === "light" || each.key === "dark")) return file({ light: own(used("light").palette), dark: own(used("dark").palette) });
  return file({
    defaults: { light: used("light").label, dark: used("dark").label },
    flavours: Object.fromEntries(variants.map(each => [each.label, own(each.palette)])),
  });
}

// The files a document's config is written as: `{ path, text }` for
// config.yaml, then for each file of modules.d in the order kantan loads
// them, then for each theme of the document's own that the config selects.
// Only the YAML files of modules.d are written, as only they are loaded,
// and only under a name that keeps them within it.
export function documentFiles(document) {
  const config = ordered(dict(document.config) ?? {}, CONFIG_KEYS);
  if (list(config.modules)?.length) config.modules = config.modules.map(orderedModule);
  else delete config.modules;
  const text = Object.keys(config).length === 0 ? "" : write(config);
  // A blank line before the modules and between them, as configs are
  // written by hand. The modules run to the next line that isn't
  // indented, where any keys after them start.
  const at = text.search(/^modules:\n/m);
  const from = at + "modules:\n".length;
  const end = at < 0 ? -1 : text.slice(from).search(/\n(?=\S)/);
  const to = end < 0 ? text.length : from + end;
  const spaced = at < 0
    ? text
    : `${text.slice(0, at)}${at > 0 ? "\n" : ""}modules:\n${text.slice(from, to).replace(/\n(  - )/g, "\n\n$1")}${text.slice(to)}`;
  const files = [{ path: "config.yaml", text: spaced }];
  for (const name of Object.keys(dict(document.modulesDir) ?? {}).sort()) {
    if (nameProblem(name) !== undefined || !/\.ya?ml$/.test(name)) continue;
    files.push({ path: `modules.d/${name}`, text: write(orderedModule(document.modulesDir[name])) });
  }
  for (const name of selectedThemes(document.config?.theme)) {
    if (dict(document.themes?.[name])) files.push(...themeFiles(name, document.themes[name]));
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
