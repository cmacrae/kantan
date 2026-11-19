// A bundled plugin's settings: the schema that describes them, and how a
// preview follows them. A plugin prints a colour or an icon from its
// settings as it was given it. A preview's states are printed from
// settings whose colours and icons are their own names, `{setting(path)}`,
// and bound to a module's settings before they are drawn.
import { dict } from "../engine/values.js";
import { deref } from "./schema.js";

// The schema file the plugins' schemas share definitions with.
const SHARED = "module-config.schema.json#/$defs/";
const LOCAL = "#/$defs/";

// A plugin's settings schema standing alone: each definition it takes from
// `shared`, the module config schema, is copied into its own.
export function bundleSchema(schema, shared) {
  const wanted = new Set();
  const local = node => {
    if (Array.isArray(node)) return node.map(local);
    if (!dict(node)) return node;
    const copy = Object.fromEntries(Object.entries(node).map(([key, value]) => [key, local(value)]));
    if (typeof node.$ref === "string" && node.$ref.startsWith(SHARED)) {
      copy.$ref = LOCAL + node.$ref.slice(SHARED.length);
      wanted.add(node.$ref.slice(SHARED.length));
    }
    return copy;
  };
  // The definitions a shared definition names in turn come with it.
  const within = node => {
    if (Array.isArray(node)) return node.forEach(within);
    if (!dict(node)) return undefined;
    if (typeof node.$ref === "string" && node.$ref.startsWith(LOCAL)) wanted.add(node.$ref.slice(LOCAL.length));
    return Object.values(node).forEach(within);
  };

  const bundled = local(schema);
  const defs = { ...bundled.$defs };
  for (const name of wanted) {
    if (Object.hasOwn(schema.$defs ?? {}, name)) throw new Error(`The schema defines ${name}, which the module config schema defines too`);
    if (!Object.hasOwn(shared.$defs ?? {}, name)) throw new Error(`The module config schema has no definition named ${name}`);
    defs[name] = shared.$defs[name];
    within(defs[name]);
  }
  return Object.keys(defs).length ? { ...bundled, $defs: defs } : bundled;
}

const ESCAPED = { "%": "%25", ".": "%2E", "(": "%28", ")": "%29", "{": "%7B", "}": "%7D" };
const escapeKey = key => String(key).replace(/[%.(){}]/g, char => ESCAPED[char]);

// The name standing for the setting at `path`, a list of keys.
export const settingName = path => `{setting(${path.map(escapeKey).join(".")})}`;

const NAME = /\{setting\(([^(){}]*)\)\}/g;
// A name followed by what it falls back to: more names, or a value with
// no space in it.
const ALTERNATIVES = /^\{setting\([^(){}]*\)\}(\|(\{setting\([^(){}]*\)\}|[^\s|{}]+))+$/;
const pathOf = name => name.split(".").map(decodeURIComponent);

// Whether `node` describes a colour or an icon, which a plugin prints as
// given.
const followed = node => node.ref === "Color" || node.ref === "Icon";

// The branch of a schema's alternatives that `value` is written as.
function branchFor(schema, branches, value) {
  const all = branches.map(branch => deref(schema, branch));
  if (typeof value === "string") return all.find(followed);
  if (Array.isArray(value)) return all.find(branch => branch.type === "array");
  if (!dict(value)) return undefined;
  return all.find(branch => !followed(branch) && (branch.type === "object" || branch.properties !== undefined)
    && (dict(branch.additionalProperties) !== undefined || Object.keys(value).every(key => Object.hasOwn(branch.properties ?? {}, key))));
}

// `settings` with each colour and icon the bundled `schema` describes
// replaced by its name, those left unset among them. A setting written as
// one of several alternatives is named as written, and as the first of
// them when unset.
export function nameSettings(settings, schema) {
  const name = (value, raw, path) => {
    const node = deref(schema, raw);
    if (followed(node)) return value === undefined || typeof value === "string" ? settingName(path) : value;
    const branches = node.oneOf ?? node.anyOf;
    if (branches) {
      const branch = value === undefined ? branches[0] : branchFor(schema, branches, value);
      return branch === undefined ? value : name(value, branch, path);
    }
    if (node.type === "array") {
      return Array.isArray(value) && node.items ? value.map((item, i) => name(item, node.items, [...path, i])) : value;
    }
    if (node.type !== "object" && node.properties === undefined) return value;
    if (value !== undefined && !dict(value)) return value;

    const named = { ...value };
    for (const [key, child] of Object.entries(node.properties ?? {})) {
      const next = name(named[key], child, [...path, key]);
      if (next !== undefined) named[key] = next;
    }
    if (dict(node.additionalProperties)) {
      for (const key of Object.keys(value ?? {})) {
        if (!Object.hasOwn(node.properties ?? {}, key)) named[key] = name(value[key], node.additionalProperties, [...path, key]);
      }
    }
    return value === undefined && Object.keys(named).length === 0 ? undefined : named;
  };
  return name(dict(settings) ?? {}, schema, []) ?? {};
}

// The default of each colour and icon the bundled `schema` gives one, by
// the name's path.
export function settingDefaults(schema) {
  const defaults = {};
  const walk = (raw, path) => {
    const node = deref(schema, raw);
    if (followed(node)) {
      if (typeof node.default === "string") defaults[path.map(escapeKey).join(".")] = node.default;
      return;
    }
    for (const [key, child] of Object.entries(node.properties ?? {})) walk(child, [...path, key]);
  };
  walk(schema, []);
  return defaults;
}

// Whether `value` holds a setting's name anywhere within it.
export function namesSettings(value) {
  if (typeof value === "string") return value.search(NAME) >= 0;
  if (value === null || typeof value !== "object") return false;
  return Object.values(value).some(namesSettings);
}

// `value` with each setting's name replaced by what `settings` holds for
// it, or its entry in `defaults`. A string that is one name alone is left
// out when the setting is unset and has no default, as a plugin leaves
// out what it wasn't given, and so is a mapping that held nothing else.
// A string of alternatives, `{setting(a)}|{setting(b)}|#1e66f5`, is the
// first of them that says something: a name does when its setting is set,
// and anything else does as it is. A setting set to `inherit` says the
// last of them, which is the thing's own.
export function bindSettings(value, settings, defaults = {}) {
  const lookup = name => {
    const set = pathOf(name).reduce((at, key) => (at === null || at === undefined ? undefined : at[key]), settings);
    return typeof set === "string" && set !== "" ? set : defaults[name];
  };
  const bind = item => {
    if (typeof item === "string") {
      if (ALTERNATIVES.test(item)) {
        const each = item.split("|");
        for (const one of each) {
          const name = one.match(/^\{setting\(([^(){}]*)\)\}$/);
          const said = name ? lookup(name[1]) : one;
          if (said === "inherit") return each[each.length - 1];
          if (said !== undefined) return said;
        }
        return undefined;
      }
      const whole = item.match(/^\{setting\(([^(){}]*)\)\}$/);
      return whole ? lookup(whole[1]) : item.replace(NAME, (_, name) => lookup(name) ?? "");
    }
    if (Array.isArray(item)) return item.map(bind).filter(each => each !== undefined);
    if (!dict(item)) return item;
    const entries = Object.entries(item).map(([key, each]) => [key, bind(each)]).filter(([, each]) => each !== undefined);
    // A mapping left with nothing is left out too.
    return entries.length === 0 && Object.keys(item).length > 0 ? undefined : Object.fromEntries(entries);
  };
  return bind(value);
}

// A module's `states` as drawn: each state's output bound to `settings`.
export function bindStates(states, settings, defaults) {
  if (!Array.isArray(states) || !namesSettings(states)) return states;
  return states.map(state => (dict(state) && state.output !== undefined ? { ...state, output: bindSettings(state.output, settings, defaults) } : state));
}
