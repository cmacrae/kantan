// Colours as the engine reports them: `#rrggbb` or `#rrggbbaa` in lower
// case, or a token naming a colour the system supplies, such as `label`
// for the native text colour or `clear` for none.

const edges = /^[^\p{L}\p{N}]+|[^\p{L}\p{N}]+$/gu;

// The colour `hex` writes as RRGGBB or RRGGBBAA, with or without a leading
// `#`, or undefined for anything else.
export function parseHex(hex) {
  const cleaned = String(hex).replace(edges, "");
  return /^([0-9a-f]{6}|[0-9a-f]{8})$/i.test(cleaned) ? `#${cleaned.toLowerCase()}` : undefined;
}

// A bar colour: `hex` parsed, or `clear` when it isn't a colour.
export const barColor = hex => parseHex(hex) ?? "clear";

// The colours a view names instead of writing as hex.
const NAMED = new Set([
  "primary", "secondary", "accent", "red", "orange", "yellow", "green", "blue",
  "purple", "pink", "gray", "white", "black", "clear",
]);

// A view colour: a named system colour, a hex colour, or `fallback` for
// anything else, nothing included.
export function viewColor(color, fallback) {
  if (color === undefined || color === "") return fallback;
  const name = color.toLowerCase();
  if (name === "grey") return "gray";
  return NAMED.has(name) ? name : parseHex(color) ?? fallback;
}

// `color` with its opacity multiplied by `opacity`, for a hex colour.
export function withOpacity(color, opacity) {
  if (!color.startsWith("#")) return color;
  const alpha = color.length === 9 ? parseInt(color.slice(7), 16) / 255 : 1;
  const scaled = Math.round(alpha * opacity * 255).toString(16).padStart(2, "0");
  return color.slice(0, 7) + scaled;
}
