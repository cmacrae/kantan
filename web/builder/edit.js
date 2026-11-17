// The changes the builder makes to a document. The builder works on a
// document whose modules all sit in config.yaml, in the order the bar draws
// them, and writes them out to modules.d when that layout is chosen.
import { DOCUMENT_VERSION } from "../engine/document.js";
import { dict, list, str } from "../engine/values.js";
import { BUILT_INS, defaultStates, pluginOf } from "./catalog.js";
import { bindStates, settingDefaults } from "./settings.js";

const isRightSide = module => (str(module?.placement) ?? "").includes("right");

const yamlFiles = modulesDir =>
  Object.keys(dict(modulesDir) ?? {}).filter(name => name.endsWith(".yaml") || name.endsWith(".yml")).sort();

// The document's modules in the order kantan loads them: those of
// config.yaml at the screen's edges, with those of modules.d inside them.
export function modulesOf(document) {
  const base = list(document.config?.modules) ?? [];
  const extra = yamlFiles(document.modulesDir).map(name => document.modulesDir[name]);
  return [
    ...base.filter(m => !isRightSide(m)), ...extra.filter(m => !isRightSide(m)),
    ...extra.filter(isRightSide), ...base.filter(isRightSide),
  ];
}

// Which layout a document is in: "dir" when any module is in modules.d.
export const layoutOf = document => (yamlFiles(document.modulesDir).length ? "dir" : "single");

const withModules = (document, modules) => {
  const { modulesDir, ...rest } = document;
  return { ...rest, config: { ...document.config, modules } };
};

// The document with every module in config.yaml.
export const toSingle = document => withModules(document, modulesOf(document));

// The file a module is written to in modules.d: its place in the bar, so
// the files sort into the order drawn, then its name.
export function moduleFile(module, index, count) {
  const digits = Math.max(2, String(count - 1).length);
  const name = (str(module?.name) ?? "module").replace(/[^A-Za-z0-9._-]+/g, "-");
  return `${String(index).padStart(digits, "0")}-${name}.yaml`;
}

// The document with every module in a file of its own in modules.d.
export function toDir(document) {
  const modules = modulesOf(document);
  const { modules: _, ...config } = dict(document.config) ?? {};
  return {
    ...document,
    config,
    modulesDir: Object.fromEntries(modules.map((module, i) => [moduleFile(module, i, modules.length), module])),
  };
}

// A document in `layout`, "single" or "dir".
export const inLayout = (document, layout) => (layout === "dir" ? toDir(document) : toSingle(document));

// A name no module of `document` has, starting from `wanted`.
export function freeName(document, wanted) {
  const taken = new Set(modulesOf(document).map(module => module?.name));
  if (!taken.has(wanted)) return wanted;
  for (let n = 2; ; n++) if (!taken.has(`${wanted}-${n}`)) return `${wanted}-${n}`;
}

const setStates = (document, name, states) => {
  const { [name]: _, ...others } = document.states ?? {};
  return { ...document, states: states === undefined ? others : { ...others, [name]: states } };
};

// The document with `module` added at the end of its placement, under a
// name of its own, showing `states`. The functions here take and return
// documents with every module in config.yaml.
export function addModule(document, module, states) {
  const named = { ...module, name: freeName(document, str(module.name) ?? str(module.type) ?? "module") };
  const modules = [...modulesOf(document), named];
  return setStates(withModules(document, modules), named.name, states);
}

// A new module of a built-in type, with the states it starts with.
export function addBuiltIn(document, type) {
  const { module } = BUILT_INS[type];
  const { placement, ...rest } = module;
  return addModule(document, { name: type, type, placement, ...rest }, BUILT_INS[type].states);
}

// A new module running a bundled plugin, as the plugin's example has it.
export function addPlugin(document, plugin, catalog) {
  const { module, states } = catalog.plugins[plugin];
  return addModule(document, module, states);
}

// A module someone shared, `{ module, states }`, added under a name no
// module here has. Returns the document and the name the module took,
// `{ document, name }`.
export function addShared(document, shared) {
  const added = addModule(document, shared.module, shared.states);
  return { document: added, name: modulesOf(added).at(-1).name };
}

// A new command module for a plugin of someone's own, showing the output
// they pasted: JSON when it parses as a mapping, and text otherwise.
export function addPasted(document, name, pasted) {
  let output = pasted;
  try {
    const parsed = JSON.parse(pasted);
    if (dict(parsed)) output = parsed;
  } catch {
    // Text that isn't JSON is the output of a plugin that prints text.
  }
  const json = typeof output !== "string";
  const module = {
    name,
    type: "command",
    placement: "right",
    config: { command: name, ...(json ? { output: "json" } : {}) },
    ...(json && dict(output.view) ? { interaction: { click: { type: "menu" } } } : {}),
  };
  return addModule(document, module, [{ name: "Pasted", output }]);
}

// A new command module for a plugin someone is about to write, called
// `name`: one that prints JSON and opens a popup, showing an example of
// what the plugin might print.
export function addOwnPlugin(document, name) {
  const module = { name, type: "command", placement: "right", config: { command: name, output: "json" }, interaction: { click: { type: "popup" } } };
  return addModule(document, module, [{ name: "Example", output: { value: "Hello", icon: "sparkles" } }]);
}

// The document with the module at `index` replaced by `module`. A new name
// takes the module's states with it.
export function updateModule(document, index, module) {
  const modules = [...modulesOf(document)];
  const before = str(modules[index]?.name);
  modules[index] = module;
  let next = withModules(document, modules);
  const after = str(module.name);
  if (before !== undefined && after !== undefined && before !== after && next.states?.[before] !== undefined) {
    next = setStates(setStates(next, after, next.states[before]), before, undefined);
  }
  return next;
}

export function removeModule(document, index) {
  const modules = modulesOf(document);
  const next = withModules(document, modules.filter((_, i) => i !== index));
  const name = str(modules[index]?.name);
  return name === undefined || next.config.modules.some(m => m?.name === name) ? next : setStates(next, name, undefined);
}

// The document with the module at `from` moved to sit at `to`.
export function moveModule(document, from, to) {
  const modules = [...modulesOf(document)];
  if (from < 0 || from >= modules.length || to < 0 || to >= modules.length) return document;
  const [module] = modules.splice(from, 1);
  modules.splice(to, 0, module);
  return withModules(document, modules);
}

export const setModuleStates = setStates;

// `states` with the state named `from` called `to`, and the transitions
// that led to it following.
export function renameState(states, from, to) {
  return states.map(state => {
    const renamed = state.name === from ? { ...state, name: to } : state;
    if (!renamed.transitions) return renamed;
    const transitions = Object.fromEntries(Object.entries(renamed.transitions).map(([command, target]) => [command, target === from ? to : target]));
    return { ...renamed, transitions };
  });
}

// `states` without the one named `name`, nor the transitions that led to it.
export function removeState(states, name) {
  return states.filter(state => state.name !== name).map(state => {
    if (!state.transitions) return state;
    const kept = Object.entries(state.transitions).filter(([, target]) => target !== name);
    const { transitions, ...rest } = state;
    return kept.length ? { ...rest, transitions: Object.fromEntries(kept) } : rest;
  });
}

// `states` with `command`, run from the state named `name`, leading to the
// state named `target`, or nowhere when that is undefined.
export function setTransition(states, name, command, target) {
  return states.map(state => {
    if (state.name !== name) return state;
    const { [command]: _, ...others } = state.transitions ?? {};
    const transitions = target === undefined ? others : { ...others, [command]: target };
    const { transitions: __, ...rest } = state;
    return Object.keys(transitions).length ? { ...rest, transitions } : rest;
  });
}

// The document with the module at `from` moved to sit just before the
// module at `to`, or just after it when `after`, taking its placement.
export function placeModule(document, from, to, after = false) {
  const modules = modulesOf(document);
  if (from === to || !dict(modules[from]) || !dict(modules[to])) return document;
  const moved = { ...modules[from], placement: modules[to].placement };
  const order = modulesOf(updateModule(document, from, moved)).filter(module => module !== moved);
  order.splice(order.indexOf(modules[to]) + (after ? 1 : 0), 0, moved);
  return withModules(document, order);
}

// The document with the module at `from` placed in `placement`: before the
// modules already there when `start`, and after them otherwise.
export function placeAtEdge(document, from, placement, start) {
  const modules = modulesOf(document);
  if (!dict(modules[from])) return document;
  const moved = { ...modules[from], placement };
  const order = modulesOf(updateModule(document, from, moved)).filter(module => module !== moved);
  const there = order.map((module, i) => (module?.placement === placement ? i : -1)).filter(i => i >= 0);
  const at = there.length === 0 ? order.length : start ? there[0] : there[there.length - 1] + 1;
  order.splice(at, 0, moved);
  return withModules(document, order);
}

// A document for `config`, a parsed config.yaml, whose modules show the
// states they start with.
export function documentFromConfig(config, catalog) {
  let document = { version: DOCUMENT_VERSION, config: dict(config) ?? {} };
  for (const module of modulesOf(document)) {
    const name = str(module?.name);
    const states = dict(module) ? defaultStates(module, catalog) : undefined;
    if (name !== undefined && states !== undefined && document.states?.[name] === undefined) {
      document = setStates(document, name, states);
    }
  }
  return document;
}

// An empty bar: a config with no modules.
export const emptyDocument = () => ({ version: DOCUMENT_VERSION, config: { modules: [] } });

// The document as the engine draws it: each command module's states bound
// to the module's settings, a bundled plugin's with its schema's defaults.
// A state that names no setting is drawn as it is.
export function boundDocument(document, catalog) {
  const states = dict(document.states);
  if (!states) return document;
  let bound;
  for (const module of modulesOf(document)) {
    const own = dict(module) && states[module.name];
    if (!own) continue;
    const plugin = pluginOf(module, catalog);
    const schema = plugin === undefined ? undefined : catalog.plugins[plugin].settings;
    const next = bindStates(own, dict(module.config)?.settings ?? {}, schema === undefined ? {} : settingDefaults(schema));
    if (next !== own) bound = { ...(bound ?? states), [module.name]: next };
  }
  return bound === undefined ? document : { ...document, states: bound };
}
