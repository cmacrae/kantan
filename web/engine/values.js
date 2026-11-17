// Typed readers over parsed YAML or JSON, as kantan reads its config: a
// value of another type reads as missing, never coerced.

export const str = v => (typeof v === "string" ? v : undefined);
export const bool = v => (typeof v === "boolean" ? v : undefined);
export const num = v => (typeof v === "number" && Number.isFinite(v) ? v : undefined);
export const int = v => (Number.isInteger(v) ? v : undefined);
export const list = v => (Array.isArray(v) ? v : undefined);
export const dict = v => (v !== null && typeof v === "object" && !Array.isArray(v) ? v : undefined);
