// kantan's themes: a config's `theme` picks one of the theme files by name,
// and optionally a flavour of it, giving a palette for each appearance.
import { dict, str } from "./values.js";

// A palette from a theme file's mapping: `fg` and `bg`, an optional `shape`
// and its named `colors`. Undefined without both `fg` and `bg`.
function parsePalette(value) {
  const fg = str(value?.fg), bg = str(value?.bg);
  if (fg === undefined || bg === undefined) return undefined;
  const colors = {};
  for (const [name, color] of Object.entries(dict(value.colors) ?? {})) {
    if (typeof color === "string") colors[name] = color;
  }
  return { fg, bg, shape: str(value.shape), colors };
}

// A theme reference: `name`, or `name[flavour]`.
function parseThemeRef(raw) {
  const open = raw.indexOf("["), close = raw.lastIndexOf("]");
  if (open < 0 || close <= open) return { name: raw.trim() };
  return { name: raw.slice(0, open).trim(), flavour: raw.slice(open + 1, close).trim() || undefined };
}

// The palettes of the theme `ref` names for both appearances.
function loadUniform(ref, themes) {
  const file = dict(themes[ref.name]);
  if (!file) return undefined;
  if (dict(file.flavours)) {
    if (ref.flavour) {
      const palette = parsePalette(file.flavours[ref.flavour]);
      return palette && { light: palette, dark: palette };
    }
    const light = parsePalette(file.flavours[str(file.defaults?.light)]);
    const dark = parsePalette(file.flavours[str(file.defaults?.dark)]);
    return light && dark && { light, dark };
  }
  if (dict(file.light) || dict(file.dark)) {
    const light = parsePalette(file.light) ?? parsePalette(file.dark);
    const dark = parsePalette(file.dark) ?? parsePalette(file.light);
    return light && dark && { light, dark };
  }
  const palette = parsePalette(file);
  return palette && { light: palette, dark: palette };
}

// The palette of the theme `ref` names for the appearance `mode`.
function loadForMode(ref, mode, themes) {
  const file = dict(themes[ref.name]);
  if (!file) return undefined;
  if (dict(file.flavours)) {
    const flavour = ref.flavour ?? str(file.defaults?.[mode]);
    return flavour === undefined ? undefined : parsePalette(file.flavours[flavour]);
  }
  if (dict(file.light) || dict(file.dark)) {
    return parsePalette(file[mode]) ?? parsePalette(file[mode === "light" ? "dark" : "light"]);
  }
  return parsePalette(file);
}

// The light and dark palettes a config's `theme` selects from `themes`, the
// theme files by name: one theme for both appearances, or a `light` and a
// `dark` one. Undefined when it selects nothing loadable.
export function loadTheme(selection, themes = {}) {
  if (typeof selection === "string") return loadUniform(parseThemeRef(selection), themes) || undefined;
  if (dict(selection)) {
    const light = str(selection.light), dark = str(selection.dark);
    if (light === undefined || dark === undefined) return undefined;
    const lightPalette = loadForMode(parseThemeRef(light), "light", themes);
    const darkPalette = loadForMode(parseThemeRef(dark), "dark", themes);
    return lightPalette && darkPalette ? { light: lightPalette, dark: darkPalette } : undefined;
  }
  return undefined;
}

// `value` resolved against `palette` when it is exactly a `{theme(name)}`
// template the palette has: `fg`, `bg` and `shape` name the palette's own.
// Anything else stays as written.
export function resolveThemeTemplate(value, palette) {
  if (!value.startsWith("{theme(") || !value.endsWith(")}") || value.length <= 9) return value;
  const name = value.slice(7, -2);
  if (name === "fg") return palette.fg;
  if (name === "bg") return palette.bg;
  if (name === "shape" && palette.shape !== undefined) return palette.shape;
  return palette.colors[name] ?? value;
}

// `input` with every `{theme(name)}` template within it resolved.
export function resolveAllThemeTemplates(input, palette) {
  let result = "";
  let rest = input;
  for (;;) {
    const open = rest.indexOf("{theme(");
    const close = open < 0 ? -1 : rest.indexOf(")}", open + 7);
    if (close < 0) return result + rest;
    result += rest.slice(0, open) + resolveThemeTemplate(rest.slice(open, close + 2), palette);
    rest = rest.slice(close + 2);
  }
}
