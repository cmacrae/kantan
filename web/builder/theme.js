// The changes the theme builder makes to a theme file, and to the document
// that holds it. A theme file is one of three kinds: "single", one palette
// for both appearances; "modes", a `light` and a `dark` palette; or
// "flavours", palettes by name with the two a bare reference defaults to.
import { parseHex } from "../engine/color.js";
import { parseThemeRef } from "../engine/theme.js";
import { dict, str } from "../engine/values.js";
import { getIn, setIn } from "./schema.js";
import { spell } from "./spelling.js";

export function themeKind(theme) {
  if (dict(theme?.flavours)) return "flavours";
  if (dict(theme?.light) || dict(theme?.dark)) return "modes";
  return "single";
}

// A theme's palettes in the order written, each `{ key, path }`: its
// name, empty for a single palette's, and where it sits in the file.
export function palettesOf(theme) {
  switch (themeKind(theme)) {
    case "flavours":
      return Object.keys(theme.flavours).map(key => ({ key, path: ["flavours", key] }));
    case "modes":
      return ["light", "dark"].filter(key => dict(theme[key])).map(key => ({ key, path: [key] }));
    default:
      return [{ key: "", path: [] }];
  }
}

const paletteAt = (theme, path) => dict(getIn(theme, path)) ?? {};

// `theme` with each of its palettes replaced by what `each` makes of it.
const mapPalettes = (theme, each) =>
  palettesOf(theme).reduce((next, { key, path }) => setIn(next, path, each(paletteAt(theme, path), key)), theme);

// `map` with the key `from` called `to`, where it was.
const renameKey = (map, from, to) => Object.fromEntries(Object.entries(map).map(([key, value]) => [key === from ? to : key, value]));

// The names of a theme's colours: those of its first palette, then any
// only a later one has.
export function colorNames(theme) {
  return [...new Set(palettesOf(theme).flatMap(({ path }) => Object.keys(dict(paletteAt(theme, path).colors) ?? {})))];
}

// `theme` with the colour `name` in every palette that lacks it: `color`,
// or without one each palette's own `fg`.
export function addColor(theme, name, color) {
  return mapPalettes(theme, palette => ({
    ...palette,
    colors: { ...palette.colors, [name]: palette.colors?.[name] ?? color ?? str(palette.fg) ?? "#888888" },
  }));
}

// `theme` with the colour `from` called `to` in every palette.
export function renameColor(theme, from, to) {
  return mapPalettes(theme, palette => (dict(palette.colors) ? { ...palette, colors: renameKey(palette.colors, from, to) } : palette));
}

export function removeColor(theme, name) {
  return mapPalettes(theme, palette => {
    if (!dict(palette.colors)) return palette;
    const { [name]: _, ...colors } = palette.colors;
    const { colors: __, ...rest } = palette;
    return Object.keys(colors).length ? { ...rest, colors } : rest;
  });
}

// `theme` with a flavour `name`, a copy of its flavour `from`.
export function addFlavour(theme, name, from) {
  return { ...theme, flavours: { ...theme.flavours, [name]: structuredClone(theme.flavours[from]) } };
}

// `theme` with the flavour `from` called `to`, and its defaults following.
export function renameFlavour(theme, from, to) {
  const next = { ...theme, flavours: renameKey(theme.flavours, from, to) };
  if (dict(theme.defaults)) {
    next.defaults = Object.fromEntries(Object.entries(theme.defaults).map(([mode, name]) => [mode, name === from ? to : name]));
  }
  return next;
}

// `theme` without the flavour `name`. A default that named it names the
// first flavour left. A theme keeps its last flavour.
export function removeFlavour(theme, name) {
  const { [name]: _, ...flavours } = theme.flavours;
  const left = Object.keys(flavours);
  if (left.length === 0) return theme;
  const next = { ...theme, flavours };
  if (dict(theme.defaults)) {
    next.defaults = Object.fromEntries(Object.entries(theme.defaults).map(([mode, each]) => [mode, each === name ? left[0] : each]));
  }
  return next;
}

// `theme` written as `kind`. A single palette is made from the one the
// theme gives the dark appearance when `dark`, and the light otherwise.
export function toKind(theme, kind, dark = false) {
  const from = themeKind(theme);
  const flavour = name => dict(theme.flavours?.[name]);
  const names = Object.keys(dict(theme.flavours) ?? {});
  const light = from === "flavours" ? flavour(str(theme.defaults?.light)) ?? flavour(names[0])
    : from === "modes" ? dict(theme.light) ?? dict(theme.dark) : theme;
  const darker = from === "flavours" ? flavour(str(theme.defaults?.dark)) ?? flavour(names[names.length - 1])
    : from === "modes" ? dict(theme.dark) ?? dict(theme.light) : theme;
  if (kind === "single") return from === "single" ? theme : structuredClone(dark ? darker : light);
  if (kind === "modes") return { light: structuredClone(light), dark: structuredClone(darker) };
  if (from === "flavours") return theme;
  return { defaults: { light: "light", dark: "dark" }, flavours: { light: structuredClone(light), dark: structuredClone(darker) } };
}

// The theme a new one starts as.
export const newTheme = () => ({
  light: { fg: "#23262d", bg: "#f4f4f1", shape: "#e1e1dc", colors: { accent: "#3b6fd4", warning: "#c2701c", success: "#2f8f55" } },
  dark: { fg: "#e6e6e1", bg: "#1b1c20", shape: "#2d2f36", colors: { accent: "#7da7f2", warning: "#e8a25a", success: "#72c992" } },
});

// What's wrong with `theme`, as a list of sentences: empty when kantan
// loads every palette of it with every colour drawn.
export function themeProblems(theme) {
  const problems = [];
  const palettes = palettesOf(theme);
  const names = colorNames(theme);
  for (const { key, path } of palettes) {
    const palette = paletteAt(theme, path);
    const where = key === "" ? "" : ` in ${key}`;
    for (const name of ["fg", "bg"]) {
      if (str(palette[name]) === undefined) problems.push(`${name} is missing${where}`);
      else if (parseHex(palette[name]) === undefined) problems.push(spell(`${name} isn't a hex colour${where}`));
    }
    if (palette.shape !== undefined && parseHex(palette.shape) === undefined) problems.push(spell(`shape isn't a hex colour${where}`));
    const colors = dict(palette.colors) ?? {};
    for (const name of names) {
      if (colors[name] === undefined) problems.push(`${name} is missing${where}`);
      else if (parseHex(colors[name]) === undefined) problems.push(spell(`${name} isn't a hex colour${where}`));
    }
  }
  if (themeKind(theme) === "flavours") {
    for (const mode of ["light", "dark"]) {
      const name = str(theme.defaults?.[mode]);
      if (name === undefined) problems.push(spell(`No flavour is the default for ${mode}`));
      else if (!dict(theme.flavours[name])) problems.push(`The default for ${mode}, ${name}, ${spell("isn't a flavour")}`);
    }
  }
  return problems;
}

// A name no theme in `themes` has, starting from `wanted`.
export function freeThemeName(themes, wanted) {
  if (!Object.hasOwn(themes, wanted)) return wanted;
  for (let n = 2; ; n++) if (!Object.hasOwn(themes, `${wanted}-${n}`)) return `${wanted}-${n}`;
}

// Why `name` can't be a theme's or a flavour's name, or undefined when it
// can: it is written in a reference as `theme[flavour]`, and names a file,
// which has to be one within the directory it is written to.
export function nameProblem(name) {
  if (name.trim() === "") return "It needs a name";
  if (name !== name.trim() || /[[\]/\\]/.test(name)) return "A name can't hold brackets or slashes, nor start or end with a space";
  if (name === "." || name === ".." || /[\u0000-\u001f\u007f]/.test(name)) return "A name can't be . or .., nor hold a control character";
  return undefined;
}

const written = ({ name, flavour }) => (flavour === undefined ? name : `${name}[${flavour}]`);

// A config's `theme` with each reference in it replaced by what `each`
// makes of its `{ name, flavour }`.
export function mapSelection(selection, each) {
  const one = raw => (typeof raw === "string" ? written(each(parseThemeRef(raw))) : raw);
  if (typeof selection === "string") return one(selection);
  if (!dict(selection)) return selection;
  return Object.fromEntries(Object.entries(selection).map(([mode, raw]) => [mode, one(raw)]));
}

// The names of the themes a config's `theme` selects.
export function selectedThemes(selection) {
  const refs = typeof selection === "string" ? [selection] : Object.values(dict(selection) ?? {}).filter(raw => typeof raw === "string");
  return [...new Set(refs.map(raw => parseThemeRef(raw).name))];
}

const withThemes = (document, themes) => {
  const { themes: _, ...rest } = document;
  return Object.keys(themes).length ? { ...rest, themes } : rest;
};

const withSelection = (document, selection) => {
  const { theme: _, ...config } = document.config;
  return { ...document, config: selection === undefined ? config : { theme: selection, ...config } };
};

// The document with `theme` held as the theme file `name`.
export const setTheme = (document, name, theme) => withThemes(document, { ...document.themes, [name]: theme });

// The document with its theme `from` called `to`, and its config's
// references following.
export function renameTheme(document, from, to) {
  const next = withThemes(document, renameKey(document.themes, from, to));
  return withSelection(next, mapSelection(document.config.theme, ref => (ref.name === from ? { ...ref, name: to } : ref)));
}

// The document with the flavour `from` of its theme `name` called `to`,
// and its config's references following.
export function renameThemeFlavour(document, name, from, to) {
  const next = setTheme(document, name, renameFlavour(document.themes[name], from, to));
  return withSelection(next, mapSelection(document.config.theme, ref => (ref.name === name && ref.flavour === from ? { ...ref, flavour: to } : ref)));
}

// The document without its theme `name`. A config that selected it goes
// without a theme, unless `bundled`, the themes kantan ships, has one of
// that name to take its place.
export function removeTheme(document, name, bundled = {}) {
  const { [name]: _, ...themes } = document.themes ?? {};
  const next = withThemes(document, themes);
  return selectedThemes(document.config.theme).includes(name) && !Object.hasOwn(bundled, name) ? withSelection(next, undefined) : next;
}

// `value` with `each` applied to every string within it, keys aside.
function mapValues(value, each) {
  if (typeof value === "string") return each(value);
  if (Array.isArray(value)) return value.map(item => mapValues(item, each));
  if (!dict(value)) return value;
  return Object.fromEntries(Object.entries(value).map(([key, item]) => [key, mapValues(item, each)]));
}

// The document with every `{theme(from)}` in its config written as
// `{theme(to)}`.
export function renameColorRefs(document, from, to) {
  const rename = text => text.replaceAll(`{theme(${from})}`, `{theme(${to})}`);
  const { theme, ...config } = document.config;
  const next = { ...document, config: { ...(theme === undefined ? {} : { theme }), ...mapValues(config, rename) } };
  return dict(document.modulesDir) ? { ...next, modulesDir: mapValues(document.modulesDir, rename) } : next;
}

// The colours the document's config names with `{theme(name)}` that
// `palettes`, the light and dark palettes its theme loads to, lack in
// either appearance.
export function missingColors(document, palettes) {
  const named = new Set();
  const collect = text => {
    for (const [, name] of text.matchAll(/\{theme\(([^)]+)\)\}/g)) named.add(name);
    return text;
  };
  const { theme: _, ...config } = document.config;
  mapValues(config, collect);
  mapValues(dict(document.modulesDir) ?? {}, collect);
  const has = (palette, name) => name === "fg" || name === "bg" || (name === "shape" ? palette.shape !== undefined : palette.colors[name] !== undefined);
  return [...named].filter(name => !has(palettes.light, name) || !has(palettes.dark, name)).sort();
}

// The palette of `theme` being edited, by its key: its two palettes
// follow the appearance, `dark` or not, and among flavours it is the one
// `wanted`, or the appearance's default.
export function paletteFor(theme, wanted, dark) {
  const keys = palettesOf(theme).map(palette => palette.key);
  const mode = dark ? "dark" : "light";
  if (themeKind(theme) === "modes") return keys.includes(mode) ? mode : keys[0];
  if (keys.includes(wanted)) return wanted;
  const fallback = str(theme.defaults?.[mode]);
  return keys.includes(fallback) ? fallback : keys[0];
}

// The reference that draws the bar in the palette `key` of the theme
// `name`: a flavour by name, and any other theme as the appearance has it.
export const previewRef = (name, theme, key) => (themeKind(theme) === "flavours" ? `${name}[${key}]` : name);
