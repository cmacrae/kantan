// What the page of a shared module or theme draws, for the page and for
// the image that goes with its link.
import { withSharedTheme } from "./base16.js";
import { boundDocument, modulesOf } from "./edit.js";

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
