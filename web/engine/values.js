// Typed readers over parsed YAML or JSON, as kantan reads its config: a
// value of another type reads as missing, never coerced.

export const str = v => (typeof v === "string" ? v : undefined);
export const bool = v => (typeof v === "boolean" ? v : undefined);
export const num = v => (typeof v === "number" && Number.isFinite(v) ? v : undefined);
export const int = v => (Number.isInteger(v) ? v : undefined);
export const list = v => (Array.isArray(v) ? v : undefined);
export const dict = v => (v !== null && typeof v === "object" && !Array.isArray(v) ? v : undefined);

// What the mapping `map` holds under `key`: a key of its own, and never
// one every object inherits, such as `constructor`. A document names its
// modules, variables and colours as it likes, and looks them up by name.
export const own = (map, key) => (dict(map) !== undefined && Object.hasOwn(map, key) ? map[key] : undefined);
