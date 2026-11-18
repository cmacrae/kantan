// What the page of a shared module or theme draws, for the page and for
// the image that goes with its link.
import { parseHex } from "../engine/color.js";
import { loadTheme } from "../engine/theme.js";
import { withSharedTheme } from "./base16.js";
import { boundDocument, modulesOf } from "./edit.js";
import { sameValue } from "./equal.js";
import { selectedThemes, themeKind } from "./theme.js";

// The document that draws a shared module, `{ module, states, theme }`,
// alone: at the left of the example's bar, where a panel has the most
// room, in the theme that came with it or the example's.
export function moduleDocument(shared, catalog) {
  const { modules: _, ...settings } = catalog.example.config;
  const { mask: __, ...unmasked } = shared.module;
  const alone = {
    version: catalog.example.version,
    config: { ...settings, modules: [{ ...unmasked, placement: "left" }] },
    ...(shared.states?.length ? { states: { [shared.module.name]: shared.states } } : {}),
  };
  return boundDocument(shared.theme === undefined ? alone : withSharedTheme(alone, shared.theme, catalog.themes), catalog);
}

// The document that draws a shared theme, `{ selection, themes }`: the
// example bar in it.
export const themeDocument = (shared, catalog) => boundDocument(withSharedTheme(catalog.example, shared, catalog.themes), catalog);

// The samples that hold every drawer of `document` open.
export const openDrawers = document =>
  Object.fromEntries(modulesOf(document).filter(each => each?.type === "drawer").map(each => [each.name, { open: true }]));

// The panels a module as drawn opens, by the slot that opens each: `click`
// for a menu or popup, `hover` for a tooltip.
export const panelSlots = drawn => [["menu", "popup"].includes(drawn?.click?.type) && "click", drawn?.tooltip && "hover"].filter(Boolean);

// Whether a colour, `#rrggbb`, is nearer black than white.
function isDark(color) {
  const hex = parseHex(color) ?? "#000000";
  const [red, green, blue] = [1, 3, 5].map(at => parseInt(hex.slice(at, at + 2), 16));
  return 0.299 * red + 0.587 * green + 0.114 * blue < 128;
}

// What a shared theme, `{ selection, themes }`, can be drawn as. A theme
// with flavours gives each of them, and any other gives its light and its
// dark. Each is `{ key, label, selection, palette, dark, uses }`:
// `selection` is the config's `theme` that draws it, `dark` the
// appearance it is drawn in, and `uses` the appearances the shared
// selection picks it for. Empty when the selection loads nothing.
// `bundled` are the themes kantan has by name.
export function themeVariants(shared, bundled = {}) {
  const themes = { ...bundled, ...shared.themes };
  const chosen = loadTheme(shared.selection, themes);
  if (!chosen) return [];
  const uses = palette => ["light", "dark"].filter(mode => sameValue(palette, chosen[mode]));
  const names = selectedThemes(shared.selection);
  if (!names.some(name => themeKind(themes[name]) === "flavours")) {
    return ["light", "dark"].map(mode => (
      { key: mode, label: mode === "dark" ? "Dark" : "Light", selection: shared.selection, palette: chosen[mode], dark: mode === "dark", uses: [mode] }
    ));
  }
  const titled = text => (names.length > 1 ? text : text.split(" ").slice(1).join(" "));
  return names.flatMap(name => {
    const refs = themeKind(themes[name]) === "flavours"
      ? Object.keys(themes[name].flavours).map(flavour => [`${name}[${flavour}]`, `${name} ${flavour}`, "light"])
      : [[name, `${name} light`, "light"], [name, `${name} dark`, "dark"]];
    return refs.flatMap(([selection, label, mode]) => {
      const palette = loadTheme(selection, themes)?.[mode];
      return palette ? [{ key: label, label: titled(label), selection, palette, dark: isDark(palette.bg), uses: uses(palette) }] : [];
    });
  });
}
