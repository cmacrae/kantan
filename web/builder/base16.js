// Base16 and Base24 schemes, the palettes of sixteen or twenty-four
// colours the tinted-theming project keeps for hundreds of colour themes:
// reading one, the kantan theme it makes, and a config written for
// Catppuccin's names brought over to a scheme's.
import { parseHex } from "../engine/color.js";
import { dict, list, str } from "../engine/values.js";
import { loadTheme } from "../engine/theme.js";
import { sameValue } from "./equal.js";
import { freeThemeName, mapSelection, missingColors, renameColorRefs, setTheme } from "./theme.js";

// A scheme's slots, in order: sixteen, and Base24's eight more.
const hexDigits = "0123456789ABCDEF";
const BASE16 = [...hexDigits].map(digit => `base0${digit}`);
const BASE24 = [...BASE16, ...[...hexDigits.slice(0, 8)].map(digit => `base1${digit}`)];
export const SLOTS = BASE24;

// The scheme a parsed YAML file holds, or undefined when it isn't one:
// `{ name, system, variant, palette }`, with `palette` each slot's colour
// as `#rrggbb`. A scheme lists its slots under `palette`, or beside its
// name as older ones do.
export function readScheme(value) {
  if (!dict(value)) return undefined;
  const source = dict(value.palette) ?? value;
  const palette = {};
  for (const slot of BASE24) {
    const color = typeof source[slot] === "string" ? parseHex(source[slot]) : undefined;
    if (color === undefined) break;
    palette[slot] = color.slice(0, 7);
  }
  const count = Object.keys(palette).length;
  if (count !== 16 && count !== 24) return undefined;
  const variant = str(value.variant);
  return {
    name: str(value.name) ?? str(value.scheme) ?? "",
    system: count === 24 ? "base24" : "base16",
    variant: variant === "light" || variant === "dark" ? variant : undefined,
    palette,
  };
}

// The name of the theme file a scheme called `name` makes.
export const schemeFileName = name => name.toLowerCase().replace(/[^\p{L}\p{N}]+/gu, "-").replace(/^-|-$/g, "");

// The kantan theme a scheme makes: one palette, with the scheme's default
// background and foreground as the bar's, its selection background behind
// shapes, and every slot a colour by its own name.
export function schemeTheme(scheme) {
  const { base00, base02, base05 } = scheme.palette;
  return { fg: base05, bg: base00, shape: base02, colors: { ...scheme.palette } };
}

// A config's `theme` that draws the theme `name` in `mode`: "both"
// appearances, or "light" or "dark" alone beside what `selection`, the
// config's `theme` so far, draws the other in. A config with no theme has
// nothing for the other, and gets the theme in both.
export function selectFor(selection, name, mode) {
  if (mode === "both") return name;
  const other = mode === "light" ? "dark" : "light";
  const kept = typeof selection === "string" ? selection : str(dict(selection)?.[other]);
  return kept === undefined ? name : { [mode]: name, [other]: kept };
}

// The document holding the themes picked for its appearances, with its
// config selecting them, and the `names` each is held under by
// appearance. `picks` holds `{ name, theme }` for `light`, for `dark` or
// for both: an appearance left out keeps the theme the config has for
// it, and one theme picked for both is held once. A name `taken`, the
// themes there already are, has, is passed over for a free one.
export function importSchemes(document, picks, taken = {}) {
  let next = document;
  const names = {};
  for (const mode of ["light", "dark"]) {
    const pick = picks[mode];
    if (pick === undefined) continue;
    if (mode === "dark" && picks.light?.theme === pick.theme) {
      names.dark = names.light;
      continue;
    }
    names[mode] = freeThemeName({ ...taken, ...next.themes }, pick.name);
    next = setTheme(next, names[mode], pick.theme);
  }
  const current = document.config.theme;
  const theme = names.light === undefined || names.dark === undefined
    ? selectFor(current, names.light ?? names.dark, names.light === undefined ? "dark" : "light")
    : names.light === names.dark ? names.light : { light: names.light, dark: names.dark };
  return { document: { ...next, config: { ...next.config, theme } }, names };
}

// The slot of a scheme that holds each of Catppuccin's colours, first
// choice first. The first sixteen are where Catppuccin's own Base16
// scheme puts them, and those after are where its Base24 scheme does,
// with the nearest of the sixteen behind them. The last five have no slot
// of their own, and take the scheme's dimmer foregrounds.
const CATPPUCCIN_SLOTS = {
  base: ["base00"], mantle: ["base01"], surface0: ["base02"], surface1: ["base03"], surface2: ["base04"],
  text: ["base05"], rosewater: ["base06"], lavender: ["base07"], red: ["base08"], peach: ["base09"],
  yellow: ["base0A"], green: ["base0B"], teal: ["base0C"], blue: ["base0D"], mauve: ["base0E"], flamingo: ["base0F"],
  crust: ["base11", "base01"], maroon: ["base12", "base08"], sky: ["base15", "base0C"],
  sapphire: ["base16", "base0D"], pink: ["base17", "base0E"],
  subtext1: ["base04"], subtext0: ["base04"], overlay2: ["base03"], overlay1: ["base03"], overlay0: ["base03"],
};

// The document with the Catppuccin colours its config names, and its
// theme lacks, written as the slots that hold them: only where
// `palettes`, the light and dark palettes its theme loads to, both have
// the slot.
export function adoptSlots(document, palettes) {
  const has = slot => palettes.light.colors[slot] !== undefined && palettes.dark.colors[slot] !== undefined;
  return missingColors(document, palettes).reduce((next, name) => {
    const slot = (CATPPUCCIN_SLOTS[name] ?? []).find(has);
    return slot === undefined ? next : renameColorRefs(next, name, slot);
  }, document);
}

// The document drawn in a theme someone shared, `{ selection, themes }`:
// it holds the theme's files, its config selects them, and the Catppuccin
// colours its config names follow them. A file whose name a different
// theme has, among the document's or those `bundled`, takes a free one.
export function withSharedTheme(document, shared, bundled = {}) {
  let next = document, selection = shared.selection;
  for (const [name, theme] of Object.entries(shared.themes)) {
    const held = sameValue(next.themes?.[name], theme);
    const to = held ? name : freeThemeName({ ...bundled, ...next.themes }, name);
    next = setTheme(next, to, theme);
    if (to !== name) selection = mapSelection(selection, ref => (ref.name === name ? { ...ref, name: to } : ref));
  }
  next = { ...next, config: { ...next.config, theme: selection } };
  const palettes = loadTheme(selection, { ...bundled, ...next.themes });
  return palettes ? adoptSlots(next, palettes) : next;
}

// Where the tinted-theming project lists its schemes: GitHub's listing of
// each system's directory.
export const GALLERY = {
  base16: "https://api.github.com/repos/tinted-theming/schemes/contents/base16",
  base24: "https://api.github.com/repos/tinted-theming/schemes/contents/base24",
};
const RAW = "https://raw.githubusercontent.com/tinted-theming/schemes/";

// The schemes a directory listing names, each `{ name, url }` with the
// address of its file, or undefined when the listing isn't laid out as it
// was when this was written: a list of files, the schemes among them YAML
// files with an address in the project's own repository.
export function readListing(listing) {
  if (!list(listing)) return undefined;
  const schemes = [];
  for (const entry of listing) {
    if (!dict(entry) || typeof entry.name !== "string") return undefined;
    if (entry.type !== "file" || !/\.ya?ml$/.test(entry.name)) continue;
    if (typeof entry.download_url !== "string" || !entry.download_url.startsWith(RAW)) return undefined;
    schemes.push({ name: entry.name.replace(/\.ya?ml$/, ""), url: entry.download_url });
  }
  return schemes.length ? schemes : undefined;
}
