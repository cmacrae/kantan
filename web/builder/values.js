// The example values a command module is previewed with: its value, its
// variables and its lists, as its command would print them in JSON. A view
// names a value in braces, and a `foreach` repeats over a list.
import { dict, list } from "../engine/values.js";

// What a command printed, as the JSON object it would print: text becomes
// that object's value.
export const jsonOutput = output => (typeof output === "string" ? { value: output } : dict(output) ?? {});

const without = (object, key) => {
  const { [key]: _, ...rest } = object;
  return rest;
};

// `output` with only the entries of `object` under `key` that say
// something.
function withEntries(output, key, object) {
  return Object.keys(object).length ? { ...output, [key]: object } : without(output, key);
}

// `output` with the value called `name` holding `value`, or without it
// when `value` is undefined. `value` is the module's own text. Any other
// name is one of its variables.
export function withValue(output, name, value) {
  const json = jsonOutput(output);
  if (name === "value") return value === undefined ? without(json, "value") : { ...json, value };
  const variables = dict(json.variables) ?? {};
  return withEntries(json, "variables", value === undefined ? without(variables, name) : { ...variables, [name]: value });
}

// The names `output` gives values: `value`, then its variables.
export const valueNames = output => ["value", ...Object.keys(dict(jsonOutput(output).variables) ?? {})];

// The lists `output` holds, by name: each a list of items.
export function listsOf(output) {
  const data = dict(jsonOutput(output).data) ?? {};
  return Object.fromEntries(Object.entries(data).filter(([, rows]) => list(rows)?.every(dict)));
}

// `output` with the list called `name` holding `rows`, or without it when
// `rows` is undefined.
export function withList(output, name, rows) {
  const json = jsonOutput(output);
  const data = dict(json.data) ?? {};
  return withEntries(json, "data", rows === undefined ? without(data, name) : { ...data, [name]: rows });
}

// `output` with its list `from` called `to`. A name another list has, or
// an empty one, changes nothing.
export function renameList(output, from, to) {
  const json = jsonOutput(output);
  const data = dict(json.data) ?? {};
  if (to === "" || from === to || !Object.hasOwn(data, from) || Object.hasOwn(data, to)) return json;
  return { ...json, data: Object.fromEntries(Object.entries(data).map(([name, rows]) => [name === from ? to : name, rows])) };
}

// A name no value or list of `output` has, starting from `wanted`.
export function freeValueName(output, wanted) {
  const taken = new Set([...valueNames(output), ...Object.keys(listsOf(output))]);
  if (!taken.has(wanted)) return wanted;
  for (let n = 2; ; n++) if (!taken.has(`${wanted}${n}`)) return `${wanted}${n}`;
}

// The fields the items of a list have between them, in the order met.
export const listFields = rows => [...new Set(rows.flatMap(row => Object.keys(row)))];

// `rows` with one more item, holding each field the others have, empty.
export const addRow = rows => [...rows, Object.fromEntries(listFields(rows).map(field => [field, ""]))];

export const removeRow = (rows, index) => rows.filter((_, i) => i !== index);

// `rows` with `value` in the `field` of the item at `index`.
export const setCell = (rows, index, field, value) => rows.map((row, i) => (i === index ? { ...row, [field]: value } : row));

// `rows` with every item holding `field`. A list with no items gains one
// to hold it.
export function addField(rows, field) {
  if (field === "" || listFields(rows).includes(field)) return rows;
  return (rows.length ? rows : [{}]).map(row => ({ ...row, [field]: "" }));
}

// `rows` with the field `from` called `to` in every item, in its place.
export function renameField(rows, from, to) {
  if (to === "" || from === to || listFields(rows).includes(to)) return rows;
  return rows.map(row => Object.fromEntries(Object.entries(row).map(([field, value]) => [field === from ? to : field, value])));
}

export const removeField = (rows, field) => rows.map(row => without(row, field));

// A list to start from: a few items, each with a title and a detail.
export const exampleRows = () => [
  { title: "First item", detail: "A detail" },
  { title: "Second item", detail: "Another" },
  { title: "Third item", detail: "And one more" },
];

// A command module and its states once the command prints JSON. A command
// gives more than one value only as JSON. Text a state held is the value
// of the JSON it now holds. Returns `{ module, states }`: the ones given
// when the command printed JSON already.
export function printingJson(module, states = []) {
  const config = dict(module.config) ?? {};
  const textual = states.some(state => typeof state.output === "string");
  if (config.output === "json" && !textual) return { module, states };
  return {
    module: config.output === "json" ? module : { ...module, config: { ...config, output: "json" } },
    states: states.map(state => (typeof state.output === "string" ? { ...state, output: jsonOutput(state.output) } : state)),
  };
}

// What a command has to print for its module to show `output`: the output
// without its view when `ownView` says kantan builds the view from the
// config.
export const printedBy = (output, ownView) => (ownView ? without(jsonOutput(output), "view") : jsonOutput(output));

// The text a new view shows a module's reading with: `{value}` when the
// module has text. A module with none gets the first of its variables
// that holds something. `placeholders` are a drawn module's.
export function mainValue(placeholders) {
  const variables = placeholders?.variables ?? {};
  if (typeof variables.value === "string" && variables.value !== "") return "{value}";
  const name = Object.keys(variables).find(each => each !== "value" && each !== "icon" && variables[each] !== "");
  return name === undefined ? "{value}" : `{${name}}`;
}
