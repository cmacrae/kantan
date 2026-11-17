// The View DSL: decoding a view tree as kantan does, and resolving one
// against a module's variables and data into a tree ready to draw.
import { viewColor } from "./color.js";
import { isSymbolName, resolveIcon } from "./icons.js";
import { bool, dict, int, list, num, str } from "./values.js";

const ALIGNMENTS = [
  "leading", "trailing", "center", "top", "bottom",
  "topLeading", "topTrailing", "bottomLeading", "bottomTrailing",
];
const WEIGHTS = ["ultraLight", "thin", "light", "regular", "medium", "semibold", "bold", "heavy", "black"];

// Field kinds: a string, number, boolean, integer, a string that may be
// written as a number or boolean, one of a set of words, a node, or nodes.
const S = "string", N = "number", B = "boolean", I = "integer", F = "flexible", K = "node", C = "nodes";
const E = (...values) => ({ values });
// A field that must be present. From YAML, it takes `fallback` instead.
const required = (kind, fallback) => ({ kind, required: true, fallback });
// A field that takes `fallback` when YAML leaves it out.
const defaulted = (kind, fallback) => ({ kind, fallback });

// Each node type's own fields.
const NODES = {
  vstack: { spacing: N, alignment: E(...ALIGNMENTS), children: C },
  hstack: { spacing: N, alignment: E(...ALIGNMENTS), children: C, command: S },
  zstack: { alignment: E(...ALIGNMENTS), children: C },
  scroll: { axis: defaulted(E("vertical", "horizontal"), "vertical"), children: C },
  spacer: { minLength: N },
  group: { children: C },
  text: {
    content: required(S, ""), size: N, weight: E(...WEIGHTS),
    style: E("normal", "italic", "monospaced", "secondary"), color: S,
    align: E("leading", "center", "trailing"), strikethrough: B,
  },
  icon: { name: required(S, ""), size: N, color: S, style: E("regular", "filled") },
  image: { url: required(S, ""), width: N, height: N, cornerRadius: N },
  divider: {},
  header: { content: required(S, "") },
  rect: { width: N, height: N, color: S, cornerRadius: N, strokeColor: S, strokeWidth: N },
  circle: { size: N, color: S, strokeColor: S, strokeWidth: N },
  capsule: { width: N, height: N, color: S },
  action: { label: defaulted(S, ""), icon: S, command: S },
  check: { label: defaulted(S, ""), checked: defaulted(F, "false"), command: S, uncheckedCommand: S },
  toggle: { label: defaulted(S, ""), on: defaulted(F, "false"), command: S },
  button: { label: defaulted(S, ""), icon: S, command: S, style: E("default", "bordered", "borderless", "plain") },
  foreach: { items: required(S, ""), child: required(K) },
  if: { condition: required(S, ""), then: required(K), else: K },
  progress: { value: required(F, "0"), color: S, trackColor: S, style: E("bar", "ring") },
  gauge: { value: required(F, "0"), min: N, max: N, label: S, color: S },
  badge: { content: required(S, ""), color: S, textColor: S },
  grid: { columns: defaulted(I, 2), spacing: N, children: C },
};

export const NODE_TYPES = Object.keys(NODES);

// The names of each node type's own fields.
export const NODE_FIELDS = Object.fromEntries(Object.entries(NODES).map(([type, fields]) => [type, Object.keys(fields)]));

// The fields of each node type that hold a node, and those that hold a
// list of them.
export const NODE_SLOTS = Object.fromEntries(Object.entries(NODES).map(([type, fields]) => [type, {
  one: Object.keys(fields).filter(key => (fields[key].kind ?? fields[key]) === K),
  many: Object.keys(fields).filter(key => (fields[key].kind ?? fields[key]) === C),
}]));

// A boolean as the views read one back: `true` or `false`.
const canonicalBool = value => (value ? "true" : "false");

// The reason a view can't be decoded, at the node `path` leads to.
class ViewProblem extends Error {}
const fail = (path, message) => {
  throw new ViewProblem(path.length ? `${path.join(".")}: ${message}` : message);
};

// A scalar of `kind` from JSON, which must have that type, or from YAML,
// where a value of another type reads as missing.
function scalar(kind, value, strict, path) {
  const wrong = expected => (strict ? fail(path, `expected ${expected}`) : undefined);
  if (kind === S) return str(value) ?? wrong("a string");
  if (kind === N) return num(value) ?? wrong("a number");
  if (kind === B) return bool(value) ?? wrong("true or false");
  if (kind === I) return int(value) ?? wrong("a whole number");
  if (kind === F) {
    if (typeof value === "string") return value;
    if (typeof value === "boolean") return canonicalBool(value);
    if (typeof value === "number") return String(value);
    return wrong("a string, number or boolean");
  }
  return kind.values.includes(value) ? value : wrong(`one of ${kind.values.join(", ")}`);
}

// A node's padding: a number for every edge, or a mapping of edges.
function decodePadding(value, strict, path) {
  if (typeof value === "number") return { top: value, leading: value, bottom: value, trailing: value };
  if (!dict(value)) {
    return strict ? fail(path, "expected a number or a mapping of top, leading, bottom and trailing") : undefined;
  }
  const edge = name => (value[name] == null ? 0 : scalar(N, value[name], strict, [...path, name]) ?? 0);
  return { top: edge("top"), leading: edge("leading"), bottom: edge("bottom"), trailing: edge("trailing") };
}

// The properties every node takes.
function decodeCommon(node, strict, path) {
  const present = key => node[key] != null;
  const field = (kind, key) => (present(key) ? scalar(kind, node[key], strict, [...path, key]) : undefined);
  const common = {
    padding: present("padding") ? decodePadding(node.padding, strict, [...path, "padding"]) : undefined,
    opacity: field(N, "opacity"),
    background: field(S, "background"),
    cornerRadius: field(N, "cornerRadius"),
  };
  if (present("frame")) {
    if (dict(node.frame)) {
      common.frame = {};
      for (const key of ["w", "h", "maxW", "maxH", "minW", "minH"]) {
        if (node.frame[key] != null) common.frame[key] = scalar(N, node.frame[key], strict, [...path, "frame", key]);
      }
    } else if (strict) {
      fail([...path, "frame"], "expected a mapping");
    }
  }
  // A literal `true` always shows the node and a literal `false` never
  // does. Anything else names the variable that decides.
  if (typeof node.visible === "boolean") common.visible = node.visible ? undefined : "";
  else common.visible = field(S, "visible");
  return common;
}

function decodeNode(value, strict, path) {
  const node = dict(value);
  if (!node) return strict ? fail(path, "expected a mapping") : undefined;
  const type = str(node.type);
  if (type === undefined) return strict ? fail([...path, "type"], "expected a string") : undefined;
  const fields = Object.hasOwn(NODES, type) ? NODES[type] : undefined;
  if (!fields) return strict ? fail([...path, "type"], `unknown node type ${type}`) : undefined;

  // `path` is where the node sits in the view as written, for whoever
  // draws it to say which node a drawn one came from.
  const decoded = { type, path, common: decodeCommon(node, strict, path) };
  for (const [key, spec] of Object.entries(fields)) {
    const { kind = spec, required: needed = false, fallback } = spec.kind ? spec : {};
    const at = [...path, key];
    const present = node[key] != null;

    if (kind === C) {
      const children = present ? list(node[key]) : [];
      if (!children && strict) fail(at, "expected a list");
      decoded[key] = (children ?? [])
        .map((child, i) => decodeNode(child, strict, [...at, i]))
        .filter(child => child !== undefined);
    } else if (kind === K) {
      if (!present && needed && strict) fail(at, "is required");
      decoded[key] = present ? decodeNode(node[key], strict, at) : undefined;
      // YAML drops a node whose own child can't be read.
      if (needed && decoded[key] === undefined) return undefined;
    } else {
      if (!present && needed && strict) fail(at, "is required");
      decoded[key] = (present ? scalar(kind, node[key], strict, at) : undefined) ?? (strict ? undefined : fallback);
    }
  }
  return decoded;
}

// How many objects deep `value` nests.
function nesting(value) {
  if (Array.isArray(value)) return Math.max(0, ...value.map(nesting));
  if (dict(value)) return 1 + Math.max(0, ...Object.values(value).map(nesting));
  return 0;
}

export const MAX_VIEW_NESTING = 64;

// A plugin's `view`, decoded as kantan decodes JSON: a field of the wrong
// type, or a node type it doesn't know, rejects the whole view. Returns
// `{ node }`, or `{ problem }` saying what's wrong.
export function decodeJsonView(value) {
  if (nesting(value) > MAX_VIEW_NESTING) {
    return { problem: `nested deeper than ${MAX_VIEW_NESTING} objects` };
  }
  try {
    return { node: decodeNode(value, true, []) };
  } catch (error) {
    if (error instanceof ViewProblem) return { problem: error.message };
    throw error;
  }
}

// A config's view, decoded as kantan reads YAML: a field of the wrong type
// reads as missing, and a node it can't read is left out. Undefined when
// the root is one.
export function decodeYamlView(value) {
  return decodeNode(value, false, []);
}

const HORIZONTAL = {
  leading: "leading", topLeading: "leading", bottomLeading: "leading",
  center: "center", top: "center", bottom: "center",
  trailing: "trailing", topTrailing: "trailing", bottomTrailing: "trailing",
};
const VERTICAL = {
  top: "top", topLeading: "top", topTrailing: "top",
  center: "center", leading: "center", trailing: "center",
  bottom: "bottom", bottomLeading: "bottom", bottomTrailing: "bottom",
};

const MAX_DEPTH = 32;

// Something kantan draws that the preview can't yet, to mark in its place.
export const unsupported = what => ({ type: "unsupported", what });

// Resolves a decoded view into the tree a popup or rich tooltip draws:
// placeholders filled, `foreach` expanded, `if` and `visible` decided,
// colours and icons resolved. `context` holds the module's `resolver`, the
// `native` flag, the default text colour `fg` and the `icons` lookup.
// Returns the nodes the view comes to, as a list, each with its `source`:
// the path of the node it came from in the view as written.
export function resolveView(node, context, depth = 0) {
  if (!node || depth > MAX_DEPTH) return [];
  const { resolver: r, icons } = context;
  const { common } = node;
  if (common.visible !== undefined && !r.truthy(common.visible)) return [];

  const color = (value, fallback) => viewColor(value === undefined ? undefined : r.resolve(value), fallback);
  const children = () => (node.children ?? []).flatMap(child => resolveView(child, context, depth + 1));
  const command = value => (value === undefined || value === "" ? undefined : r.resolveCommand(value));
  // An icon in a view: a glyph of the icon font, an SF Symbol the preview
  // can't draw, or a character drawn as text.
  const icon = (name, size) => {
    const resolved = resolveIcon(name, size, icons);
    return resolved.glyph === undefined && isSymbolName(name) ? unsupported("SF Symbol") : resolved;
  };

  // The frame, background and so on a node carries, which a node that
  // draws nothing itself passes to each node it comes to.
  const box = {
    padding: common.padding,
    frame: common.frame,
    background: common.background === undefined ? undefined : color(common.background, "clear"),
    cornerRadius: common.cornerRadius,
    opacity: common.opacity,
  };
  const boxed = Object.values(box).some(v => v !== undefined);
  const wrap = nodes => (boxed ? nodes.map(n => ({ ...n, boxes: [...(n.boxes ?? []), box] })) : nodes);
  const one = resolved => wrap([{ ...resolved, source: node.path }]);

  switch (node.type) {
    case "vstack":
      return one({ type: "vstack", align: HORIZONTAL[node.alignment] ?? "leading", spacing: node.spacing, children: children() });
    case "hstack":
      return one({
        type: "hstack", align: VERTICAL[node.alignment] ?? "center", spacing: node.spacing,
        command: command(node.command) || undefined, children: children(),
      });
    case "zstack":
      return one({ type: "zstack", align: node.alignment ?? "center", children: children() });
    case "scroll":
      return one({ type: "scroll", axis: node.axis === "horizontal" ? "horizontal" : "vertical", children: children() });
    case "spacer":
      return one({ type: "spacer", minLength: node.minLength });
    case "group":
      return wrap(children());
    case "text":
      return one({
        type: "text", text: r.resolve(node.content), size: node.size ?? 13,
        weight: node.weight ?? "regular", strikethrough: node.strikethrough === true,
        color: color(node.color, context.fg), secondary: node.style === "secondary",
        align: node.align ?? "leading",
      });
    case "icon":
      return one({ type: "icon", icon: icon(r.resolve(node.name), node.size ?? 13), color: color(node.color, context.fg) });
    case "image":
      return one(unsupported("image"));
    case "divider":
      return one({ type: "divider" });
    case "header":
      return one({ type: "header", text: r.resolve(node.content), color: context.fg });
    case "rect":
    case "circle":
    case "capsule": {
      const stroke = node.strokeColor === undefined ? undefined
        : { color: color(node.strokeColor, "clear"), width: node.strokeWidth ?? 1 };
      const size = node.type === "circle" ? { width: node.size, height: node.size } : { width: node.width, height: node.height };
      return one({
        type: node.type, ...size, color: color(node.color, "clear"),
        cornerRadius: node.type === "rect" ? node.cornerRadius ?? 0 : undefined, stroke,
      });
    }
    case "action": {
      const name = node.icon === undefined ? "" : r.resolve(node.icon);
      return one({
        type: "action", label: r.resolve(node.label ?? ""),
        icon: name === "" ? undefined : icon(name, 13), command: command(node.command),
      });
    }
    case "check":
      return one({
        type: "check", label: r.resolve(node.label ?? ""),
        checked: node.checked === undefined ? false : r.resolveBool(node.checked),
        command: node.command === undefined ? undefined : r.resolveCommand(node.command),
        uncheckedCommand: node.uncheckedCommand === undefined ? undefined : r.resolveCommand(node.uncheckedCommand),
      });
    case "toggle":
      return one({
        type: "toggle", label: r.resolve(node.label ?? ""),
        on: node.on === undefined ? false : r.resolveBool(node.on), command: command(node.command),
      });
    case "button": {
      const name = node.icon === undefined ? "" : r.resolve(node.icon);
      return one({
        type: "button", label: node.label === undefined ? undefined : r.resolve(node.label),
        icon: name === "" ? undefined : icon(name, 12), command: command(node.command),
      });
    }
    case "foreach":
      return wrap((r.data[node.items] ?? []).flatMap(element =>
        resolveView(node.child, { ...context, resolver: r.scoped(element) }, depth + 1)));
    case "if":
      return wrap(resolveView(r.truthy(node.condition) ? node.then : node.else, context, depth + 1));
    case "progress": {
      const value = Number(r.resolve(node.value));
      return one({
        type: "progress", style: node.style === "ring" ? "ring" : "bar",
        value: Number.isFinite(value) ? Math.min(Math.max(value, 0), 1) : 0,
        color: color(node.color, "accent"), track: color(node.trackColor, "track"),
      });
    }
    case "gauge":
      return one(unsupported("gauge"));
    case "badge":
      return one({
        type: "badge", text: r.resolve(node.content),
        color: color(node.color, "accent"), textColor: color(node.textColor, "white"),
      });
    case "grid":
      return one({ type: "grid", columns: Math.max(1, node.columns ?? 2), spacing: node.spacing ?? 8, children: children() });
    default:
      return [];
  }
}
