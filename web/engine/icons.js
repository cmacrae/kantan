// Icons as kantan resolves them: a name the icon fonts have is that Tabler
// glyph, drawn in its font at a size scaled so every icon looks as tall;
// any other string is drawn as written.
//
// Measuring glyphs needs the fonts, so the engine is given a lookup built
// from them when the site is: a function from an icon's name to its
// `{ font, char, scale }`, or to undefined for a name the fonts lack.

// The lookup with no icons, where every icon is the name it was given.
export const noIcons = () => undefined;

// A lookup over `table`, mapping each icon's name to its entry.
export const iconTable = table => name => (Object.hasOwn(table, name) ? table[name] : undefined);

// An icon size in points scaled by `scale`, rounded, between 1 and 1000.
export function scaledSize(size, scale) {
  const scaled = size * scale;
  return Number.isFinite(scaled) ? Math.round(Math.min(Math.max(scaled, 1), 1000)) : 13;
}

// The icon `name` at `size` points: a glyph of the icon font, or `text` to
// draw in the surrounding font.
export function resolveIcon(name, size, icons = noIcons) {
  const entry = icons(name);
  return entry
    ? { name, glyph: entry.char, font: entry.font, size: scaledSize(size, entry.scale) }
    : { name, text: name, size };
}

// Whether a view draws `name`, which the icon fonts lack, as an SF Symbol:
// kantan takes any ASCII name for one.
export const isSymbolName = name => name !== "" && /^[\x00-\x7f]*$/.test(name);
