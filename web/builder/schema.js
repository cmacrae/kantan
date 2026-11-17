// Reading the module config schema the docs publish, for the builder's
// forms, and changing values held deep within a module.
import { dict } from "../engine/values.js";

// `node` with a `$ref` followed to what it names in `schema`. The node's
// own description stays.
export function deref(schema, node) {
  const ref = node?.$ref;
  if (typeof ref !== "string" || !ref.startsWith("#/")) return node;
  const target = ref.slice(2).split("/").reduce((at, key) => at?.[key], schema);
  const { $ref, ...own } = node;
  return { ...deref(schema, target), ...own, ref: ref.split("/").pop() };
}

// The schema of the `config` block of a module of `type`, or undefined for
// a type the schema doesn't describe.
export function configSchema(schema, type) {
  const rule = (schema.allOf ?? []).find(each => each.if?.properties?.type?.const === type);
  const config = rule?.then?.properties?.config;
  return config === undefined ? undefined : { ...deref(schema, config), requiredByType: rule.then.required?.includes("config") ?? false };
}

// `value` without what says nothing: undefined entries and mappings left
// with no entries.
export function prune(value) {
  if (Array.isArray(value)) return value.map(prune).filter(item => item !== undefined);
  if (!dict(value)) return value;
  const entries = Object.entries(value).map(([key, item]) => [key, prune(item)]).filter(([, item]) => item !== undefined);
  return entries.length ? Object.fromEntries(entries) : undefined;
}

// The value at `path`, a list of keys, within `value`.
export const getIn = (value, path) => path.reduce((at, key) => (at === null || at === undefined ? undefined : at[key]), value);

// `value` with `next` at `path`, making mappings on the way. An undefined
// `next` removes the entry.
export function setIn(value, path, next) {
  if (path.length === 0) return next;
  const [key, ...rest] = path;
  if (Array.isArray(value)) {
    const copy = [...value];
    copy[key] = setIn(copy[key], rest, next);
    return copy;
  }
  const base = dict(value) ?? {};
  const child = setIn(base[key], rest, next);
  if (child === undefined) {
    const { [key]: _, ...others } = base;
    return others;
  }
  return { ...base, [key]: child };
}
