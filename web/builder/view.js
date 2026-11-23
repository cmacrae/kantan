// A module's views, built node by node: where a view is held, the nodes
// within it and the changes made to them.
//
// A view is held in one of three places, which `where` names:
//
//   { slot: "click" }         the module's `interaction.click.view`
//   { slot: "hover" }         the module's `interaction.hover.view`
//   { slot: "state", state }  the `view` in the output of the module's
//                             state of that name
//
// A node within a view is found by its path: the keys that lead to it from
// the view's root, such as `["children", 2, "then"]`. The engine gives
// what it draws the same paths.
import { NODE_SLOTS } from "../engine/index.js";
import { dict } from "../engine/values.js";
import { unescapeKey } from "./settings.js";
import { prune, setIn } from "./schema.js";
import { exampleRows, listFields, listsOf, mainValue, printingJson, withList } from "./values.js";
import { spell } from "./spelling.js";

const slotsOf = node => (Object.hasOwn(NODE_SLOTS, node?.type ?? "") ? NODE_SLOTS[node.type] : { one: [], many: [] });

// Whether a node holds a list of nodes.
export const holdsNodes = node => slotsOf(node).many.length > 0;

// The view `where` names, as written, or undefined when there is none.
export function viewOf(module, states, where) {
  if (where.slot === "state") {
    const state = (states ?? []).find(each => each.name === where.state);
    return dict(dict(state?.output)?.view);
  }
  return dict(dict(dict(module?.interaction)?.[where.slot])?.view);
}

// `module` with `view` as its click's or hover's, or without one when
// `view` is undefined. A click that shows no view becomes a menu, and a
// hover a tooltip.
export function withView(module, slot, view) {
  const interaction = dict(module.interaction) ?? {};
  const held = dict(interaction[slot]) ?? {};
  const shows = slot === "click" ? ["menu", "popup"] : ["tooltip"];
  const { view: _, ...rest } = held;
  const next = view === undefined ? rest : { ...rest, type: shows.includes(held.type) ? held.type : shows[0], view };
  return prune({ ...module, interaction: { ...interaction, [slot]: next } });
}

// `states` with `view` in the output of the state named `name`, or with
// none there when `view` is undefined.
export function withStateView(states, name, view) {
  return states.map(state => {
    if (name !== undefined && state.name !== name) return state;
    // Output printed as text becomes JSON holding that text as its value.
    const { view: _, ...rest } = typeof state.output === "string" ? { value: state.output } : dict(state.output) ?? {};
    return { ...state, output: view === undefined ? rest : { ...rest, view } };
  });
}

// A view moved between the two places that hold a click's: `to` is
// `config` for the module's own, or `output` for what its command prints
// in every state. Returns the module and its states, `{ module, states }`.
// A module whose command prints a view prints JSON. With `keep`, a view
// moved to the config stays in the states too: a bundled plugin goes on
// printing its view. The config's is shown in its place.
export function moveView(module, states, view, to, { keep = false } = {}) {
  if (to === "config") return { module: withView(module, "click", view), states: keep ? states : withStateView(states ?? [], undefined, undefined) };
  const config = { ...dict(module.config), output: "json" };
  return { module: { ...withView(module, "click", undefined), config }, states: withStateView(states ?? [], undefined, view) };
}

// A script to start a plugin from: one that prints `output`, the JSON a
// state shows.
export function starterScript(output) {
  return [
    "#!/bin/sh",
    "# Prints what kantan shows for the module. Replace the values with",
    "# real ones.",
    "cat <<'JSON'",
    JSON.stringify(output, null, 2),
    "JSON",
    "",
  ].join("\n");
}

// The node at `path` within `view`.
export const nodeAt = (view, path) => path.reduce((at, key) => (at === null || at === undefined ? undefined : at[key]), view);

// The path of the node holding the one at `path`, and the key and place
// it is held at: `{ parent, key, index }`, with no `index` for a node held
// on its own. Undefined for the root.
export function holderOf(path) {
  if (path.length === 0) return undefined;
  const last = path[path.length - 1];
  return typeof last === "number"
    ? { parent: path.slice(0, -2), key: path[path.length - 2], index: last }
    : { parent: path.slice(0, -1), key: last };
}

// Every node of `view` in the order written, each with its `path`, how
// `deep` it is nested and the `key` it is held under.
export function outline(view) {
  const rows = [];
  const walk = (node, path, deep, key) => {
    rows.push({ node, path, deep, key });
    if (!dict(node)) return;
    const { one, many } = slotsOf(node);
    for (const each of one) if (node[each] !== undefined && node[each] !== null) walk(node[each], [...path, each], deep + 1, each);
    for (const each of many) (Array.isArray(node[each]) ? node[each] : []).forEach((child, i) => walk(child, [...path, each, i], deep + 1, each));
  };
  if (view !== undefined) walk(view, [], 0);
  return rows;
}

// `view` with `node` in place of the one at `path`.
export const replaceNode = (view, path, node) => (path.length === 0 ? node : setIn(view, path, node));

// `view` without the node at `path`: undefined when it is the root.
export function removeNode(view, path) {
  const held = holderOf(path);
  if (!held) return undefined;
  const holder = nodeAt(view, held.parent);
  if (held.index === undefined) {
    const { [held.key]: _, ...rest } = holder;
    return replaceNode(view, held.parent, rest);
  }
  return replaceNode(view, held.parent, { ...holder, [held.key]: holder[held.key].filter((_, i) => i !== held.index) });
}

// `view` with `node` added to the list the node at `parent` holds under
// `key`, at `index` or at its end.
export function insertNode(view, parent, node, index, key = "children") {
  const holder = nodeAt(view, parent);
  const list = Array.isArray(holder[key]) ? holder[key] : [];
  const at = index === undefined ? list.length : Math.max(0, Math.min(index, list.length));
  return replaceNode(view, parent, { ...holder, [key]: [...list.slice(0, at), node, ...list.slice(at)] });
}

const within = (path, other) => other.length <= path.length && other.every((key, i) => path[i] === key);

// `view` with the node at `from` moved into the list the node at `parent`
// holds, to sit where the node at `index` is now, or at the list's end.
// Returns the view and the path the node ends at, `{ view, path }`, or
// undefined for a move that can't be made: of the root, or of a node into
// itself.
export function moveNode(view, from, parent, index, key = "children") {
  const held = holderOf(from);
  if (!held || within(parent, from) || !holdsNodes(nodeAt(view, parent))) return undefined;
  const node = nodeAt(view, from);
  // The node's old place is kept until it is set down, so paths stay good.
  const gone = {};
  const added = insertNode(replaceNode(view, from, gone), parent, node, index, key);
  const strip = value => (Array.isArray(value) ? value.filter(each => each !== gone).map(strip)
    : dict(value) ? Object.fromEntries(Object.entries(value).filter(([, each]) => each !== gone).map(([name, each]) => [name, strip(each)]))
    : value);

  // Taking the old place away moves what came after it in its list.
  let at = nodeAt(added, [...parent, key]).indexOf(node);
  const to = [...parent];
  const list = [...held.parent, held.key];
  if (held.index !== undefined) {
    if (list.length === parent.length + 1 && within(list, parent) && held.key === key) {
      if (held.index < at) at -= 1;
    } else if (within(parent, list) && parent[list.length] > held.index) {
      to[list.length] -= 1;
    }
  }
  return { view: strip(added), path: [...to, key, at] };
}

// `view` with the node at `path` one place earlier or later among the
// nodes it sits with. Returns `{ view, path }`, or undefined when it has
// nowhere to go.
export function nudgeNode(view, path, by) {
  const held = holderOf(path);
  if (!held || held.index === undefined) return undefined;
  const list = nodeAt(view, held.parent)[held.key];
  const to = held.index + by;
  if (to < 0 || to >= list.length) return undefined;
  const next = [...list];
  [next[held.index], next[to]] = [next[to], next[held.index]];
  return { view: replaceNode(view, [...held.parent, held.key], next), path: [...held.parent, held.key, to] };
}

// `view` with the node at `path` set inside a new stack of `type` in its
// place.
export const wrapNode = (view, path, type) => replaceNode(view, path, { type, children: [nodeAt(view, path)] });

// What a new node of each type starts as: one kantan accepts and draws.
const NEW = {
  vstack: { children: [] },
  hstack: { children: [] },
  zstack: { children: [] },
  scroll: { children: [] },
  group: { children: [] },
  grid: { columns: 2, children: [] },
  spacer: {},
  divider: {},
  text: { content: "Text" },
  icon: { name: "star" },
  image: { url: "" },
  header: { content: "Header" },
  rect: { width: 24, height: 24, color: "#888888", cornerRadius: 4 },
  circle: { size: 12, color: "#888888" },
  capsule: { width: 40, height: 12, color: "#888888" },
  action: { label: "Action", command: "open -a Calculator" },
  check: { label: "Done", checked: false },
  toggle: { label: "Toggle", on: false },
  button: { label: "Button" },
  foreach: { items: "", child: { type: "text", content: "{name}" } },
  if: { condition: "", then: { type: "text", content: "Shown when it holds" } },
  progress: { value: "0.5" },
  gauge: { value: "0.5" },
  badge: { content: "New" },
};

// What each node type is called and does, in plain words.
export const NODE_INFO = {
  vstack: ["Column", "Stacks what it holds from top to bottom"],
  hstack: ["Row", "Sets what it holds side by side. In a menu it is one row"],
  zstack: ["Layers", "Draws what it holds one over another"],
  grid: ["Grid", "Lays what it holds out in columns"],
  scroll: ["Scroll area", "Scrolls what it holds when there is too much"],
  group: ["Group", "Holds nodes together without drawing anything itself"],
  spacer: ["Spacer", "Pushes what is either side of it apart"],
  divider: ["Divider", "A thin line between sections"],
  text: ["Text", "A line of text"],
  header: ["Heading", "A bold title for a section"],
  icon: ["Icon", "An icon from kantan's icon font"],
  badge: ["Badge", spell("A short label in a coloured capsule")],
  image: ["Image", "A picture loaded from an address"],
  action: ["Action", "A row that runs a command when clicked"],
  check: ["Checkbox", "A row that ticks and unticks"],
  toggle: ["Switch", "A row with an on and off switch"],
  button: ["Button", "A button that runs a command"],
  rect: ["Rectangle", "A filled or outlined box"],
  circle: ["Circle", "A filled or outlined dot"],
  capsule: ["Capsule", "A rounded bar"],
  progress: ["Progress", "A bar or ring filled part of the way"],
  gauge: ["Gauge", "A dial showing a reading"],
  foreach: ["Repeat", "Draws what it holds once for each item of a list"],
  if: ["Show if", "Draws one node when a value is set, and another when it isn't"],
};

// The node types in the order the builder offers them, by kind.
export const NODE_KINDS = [
  ["Layout", ["vstack", "hstack", "zstack", "grid", "scroll", "group", "spacer", "divider"]],
  ["Content", ["text", "header", "icon", "badge", "image"]],
  ["Controls", ["action", "check", "toggle", "button"]],
  ["Shapes and meters", ["rect", "circle", "capsule", "progress", "gauge"]],
  ["Logic", ["foreach", "if"]],
];

// A new node of `type`. A `foreach` starts over `collection`, the name of
// one of the state's data collections, when there is one.
export function newNode(type, collection) {
  const node = { type, ...structuredClone(NEW[type] ?? {}) };
  return type === "foreach" && collection !== undefined ? { ...node, items: collection } : node;
}

// Room at a row's sides, for a view with none around it: an action, a
// check and a toggle have as much of their own.
const SIDES = { leading: 14, trailing: 14 };

// Room around a whole view: a popup has its own above and below.
const ROOM = { leading: 14, bottom: 4, trailing: 14 };

const heading = content => ({ type: "header", content, padding: SIDES });

const row = (icon, label, value, padding) => ({
  type: "hstack",
  ...(padding && { padding }),
  children: [{ type: "icon", name: icon }, { type: "text", content: label }, { type: "spacer" }, { type: "text", content: value, style: "secondary" }],
});

const meter = (label, value) => ({
  type: "vstack",
  spacing: 3,
  children: [
    { type: "hstack", children: [{ type: "text", content: label, size: 12 }, { type: "spacer" }, { type: "text", content: "50%", size: 12, style: "secondary" }] },
    { type: "progress", value },
  ],
});

const figure = (label, value) => ({
  type: "vstack",
  spacing: 2,
  alignment: "leading",
  padding: 10,
  background: "#80808026",
  cornerRadius: 8,
  frame: { w: 104 },
  children: [{ type: "text", content: label, size: 11, style: "secondary" }, { type: "text", content: value, size: 20, weight: "bold" }],
});

const legend = (color, label) => ({
  type: "hstack",
  spacing: 6,
  children: [{ type: "capsule", width: 14, height: 6, color }, { type: "text", content: label, size: 11, style: "secondary" }],
});

// Views to start from, each for the `kinds` of view it suits: a menu shows
// plain rows, a popup lays out anything, and a tooltip is small and takes
// no clicks. `view(main)` makes one showing `main`, the text that reads
// the module's own value. One that `repeats` is made over a list:
// `view(main, list, fields)` repeats over the list called `list`, showing
// the first two of its items' `fields`.
export const STARTERS = [
  {
    name: "A list of actions",
    kinds: ["menu", "popup"],
    view: () => ({
      type: "vstack",
      children: [
        heading("Shortcuts"),
        { type: "action", label: "Activity Monitor", icon: "dashboard", command: "open -a 'Activity Monitor'" },
        { type: "action", label: "System Settings", icon: "settings", command: "open -a 'System Settings'" },
        { type: "divider" },
        { type: "action", label: "kantan's docs", icon: "book", command: "https://kantan.bar/docs/" },
      ],
    }),
  },
  {
    name: "Rows of readings",
    kinds: ["menu", "popup"],
    view: (main = "{value}") => ({
      type: "vstack",
      spacing: 8,
      padding: ROOM,
      frame: { w: 240 },
      children: [{ type: "header", content: "Overview" }, row("activity", "Now", main), row("clock", "Checked", "just now")],
    }),
  },
  {
    name: "A list of items",
    kinds: ["menu", "popup"],
    repeats: true,
    view: (main = "{value}", list = "items", fields = ["title", "detail"]) => ({
      type: "vstack",
      spacing: 6,
      padding: ROOM,
      frame: { w: 260 },
      children: [
        { type: "header", content: main },
        {
          type: "foreach",
          items: list,
          child: {
            type: "hstack",
            children: [
              { type: "text", content: `{${fields[0] ?? "title"}}` },
              ...(fields[1] === undefined ? [] : [{ type: "spacer" }, { type: "text", content: `{${fields[1]}}`, style: "secondary" }]),
            ],
          },
        },
      ],
    }),
  },
  {
    name: "Switches",
    kinds: ["menu", "popup"],
    view: () => ({
      type: "vstack",
      children: [
        heading("Settings"),
        { type: "toggle", label: "Do Not Disturb", on: false, command: "true" },
        { type: "toggle", label: "Keep awake", on: true, command: "true" },
        { type: "divider" },
        { type: "action", label: "Open Settings", icon: "settings", command: "open -a 'System Settings'" },
      ],
    }),
  },
  {
    name: "A checklist",
    kinds: ["menu", "popup"],
    repeats: true,
    view: (main = "{value}", list = "items", fields = ["title"]) => ({
      type: "vstack",
      children: [
        heading(main),
        { type: "foreach", items: list, child: { type: "check", label: `{${fields[0] ?? "title"}}`, checked: false, command: `echo {${fields[0] ?? "title"}}` } },
        { type: "divider" },
        { type: "action", label: "Add another", icon: "plus", command: "true" },
      ],
    }),
  },
  {
    name: "Shown on a condition",
    kinds: ["menu", "popup"],
    view: (main = "{value}") => ({
      type: "vstack",
      children: [
        heading("Status"),
        {
          type: "if",
          condition: main.slice(1, -1),
          then: { type: "group", children: [row("circle-check", "Reading", main, SIDES), row("clock", "Checked", "just now", SIDES)] },
          else: { type: "text", content: "Nothing to show", style: "secondary", padding: SIDES },
        },
        { type: "divider" },
        { type: "action", label: "Refresh", icon: "refresh", command: "kantan trigger" },
      ],
    }),
  },
  {
    name: "Meters",
    about: "A label over a bar for each reading.",
    kinds: ["popup"],
    view: () => ({
      type: "vstack",
      spacing: 10,
      padding: ROOM,
      frame: { w: 220 },
      children: [{ type: "header", content: "Usage" }, meter("Processor", "0.5"), meter("Memory", "0.5")],
    }),
  },
  {
    name: "A grid of figures",
    kinds: ["popup"],
    view: (main = "{value}") => ({
      type: "grid",
      columns: 2,
      spacing: 8,
      padding: 12,
      frame: { w: 240 },
      children: [figure("Now", main), figure("Today", "128"), figure("Week", "904"), figure("Month", "3.6k")],
    }),
  },
  {
    name: "Now playing",
    kinds: ["popup"],
    view: (main = "{value}") => ({
      type: "vstack",
      spacing: 10,
      padding: 14,
      frame: { w: 250 },
      children: [
        {
          type: "hstack",
          spacing: 12,
          children: [
            {
              type: "zstack",
              children: [{ type: "rect", width: 48, height: 48, color: "accent", cornerRadius: 8 }, { type: "icon", name: "music", size: 22, color: "white" }],
            },
            {
              type: "vstack",
              spacing: 2,
              alignment: "leading",
              children: [{ type: "text", content: main, weight: "semibold" }, { type: "text", content: "Artist", size: 11, style: "secondary" }],
            },
            { type: "spacer" },
          ],
        },
        { type: "progress", value: "0.4", color: "accent" },
        {
          type: "hstack",
          spacing: 6,
          children: [
            { type: "spacer" },
            { type: "button", icon: "player-skip-back", command: "true", style: "borderless" },
            { type: "button", icon: "player-pause", command: "true", style: "bordered" },
            { type: "button", icon: "player-skip-forward", command: "true", style: "borderless" },
            { type: "spacer" },
          ],
        },
      ],
    }),
  },
  {
    name: "A list with badges",
    kinds: ["popup"],
    repeats: true,
    view: (main = "{value}", list = "items", fields = ["title", "detail"]) => ({
      type: "vstack",
      spacing: 8,
      padding: ROOM,
      frame: { w: 270 },
      children: [
        { type: "hstack", children: [{ type: "header", content: "Services" }, { type: "spacer" }, { type: "badge", content: main, color: "accent", textColor: "white" }] },
        {
          type: "foreach",
          items: list,
          child: {
            type: "hstack",
            spacing: 8,
            children: [
              { type: "circle", size: 8, color: "green" },
              { type: "text", content: `{${fields[0] ?? "title"}}` },
              { type: "spacer" },
              ...(fields[1] === undefined ? [] : [{ type: "badge", content: `{${fields[1]}}`, color: "#8080803a" }]),
            ],
          },
        },
      ],
    }),
  },
  {
    name: "A scrolling list",
    kinds: ["popup"],
    repeats: true,
    view: (main = "{value}", list = "items", fields = ["title", "detail"]) => ({
      type: "vstack",
      spacing: 8,
      padding: ROOM,
      frame: { w: 260 },
      children: [
        { type: "header", content: main },
        {
          type: "scroll",
          axis: "vertical",
          frame: { h: 64 },
          children: [
            {
              type: "foreach",
              items: list,
              child: {
                type: "hstack",
                padding: { top: 3, bottom: 3 },
                children: [
                  {
                    type: "vstack",
                    spacing: 1,
                    alignment: "leading",
                    children: [
                      { type: "text", content: `{${fields[0] ?? "title"}}`, weight: "medium" },
                      ...(fields[1] === undefined ? [] : [{ type: "text", content: `{${fields[1]}}`, size: 11, style: "secondary" }]),
                    ],
                  },
                  { type: "spacer" },
                ],
              },
            },
          ],
        },
        { type: "divider" },
        { type: "button", label: "Open", icon: "external-link", command: "true", style: "bordered" },
      ],
    }),
  },
  {
    name: "A ring with a legend",
    kinds: ["popup"],
    view: (main = "{value}") => ({
      type: "hstack",
      spacing: 14,
      padding: 14,
      children: [
        { type: "progress", value: "0.72", style: "ring", color: "blue", frame: { w: 52, h: 52 } },
        {
          type: "vstack",
          spacing: 5,
          alignment: "leading",
          children: [{ type: "text", content: main, size: 16, weight: "bold" }, legend("blue", "Used"), legend("gray", "Free")],
        },
      ],
    }),
  },
  {
    name: "A title and a detail",
    about: "Two lines: what it is, and a quieter line under it.",
    kinds: ["tooltip"],
    view: (main = "{value}") => ({
      type: "vstack",
      spacing: 2,
      alignment: "leading",
      children: [{ type: "text", content: main, weight: "medium" }, { type: "text", content: "Updated just now", size: 11, style: "secondary" }],
    }),
  },
  {
    name: "A reading with a bar",
    about: "A line of text over a bar filled part of the way.",
    kinds: ["tooltip"],
    view: (main = "{value}") => ({
      type: "vstack",
      spacing: 4,
      frame: { w: 140 },
      children: [{ type: "text", content: main }, { type: "progress", value: "0.5" }],
    }),
  },
  {
    name: "An icon and a line",
    kinds: ["tooltip"],
    view: (main = "{value}") => ({ type: "hstack", spacing: 6, children: [{ type: "icon", name: "info-circle", color: "accent" }, { type: "text", content: main }] }),
  },
  {
    name: "Labels and values",
    kinds: ["tooltip"],
    view: (main = "{value}") => ({
      type: "grid",
      columns: 2,
      spacing: 4,
      children: [
        { type: "text", content: "Now", size: 11, style: "secondary" },
        { type: "text", content: main, size: 11, style: "monospaced" },
        { type: "text", content: "Peak", size: 11, style: "secondary" },
        { type: "text", content: "98", size: 11, style: "monospaced" },
      ],
    }),
  },
  {
    name: "A ring and a line",
    kinds: ["tooltip"],
    view: (main = "{value}") => ({
      type: "hstack",
      spacing: 8,
      children: [{ type: "progress", value: "0.6", style: "ring", frame: { w: 18, h: 18 } }, { type: "text", content: main }],
    }),
  },
  {
    name: "A single line",
    kinds: ["menu", "popup", "tooltip"],
    view: (main = "{value}") => ({ type: "vstack", children: [{ type: "text", content: main }] }),
  },
];

// A module and its states once `starter` is the view `where` names, opening
// as `kind`: a menu, a popup or a tooltip. `shown` names the state showing
// and `placeholders` are the drawn module's. A starting point that repeats
// over a list uses the first list the state has. A command with no list
// gains an example one in every state, and prints JSON from then on.
// Returns `{ module, states }`.
export function startView(module, states = [], where, kind, starter, { shown, placeholders } = {}) {
  let next = { module, states };
  let name, fields;
  if (starter.repeats) {
    const current = states.find(state => state.name === shown) ?? states[0];
    const lists = listsOf(current?.output);
    [name] = Object.keys(lists);
    if (name === undefined) {
      name = "items";
      next = printingJson(module, states.length ? states : [{ name: "Example", output: {} }]);
      next.states = next.states.map(state => (Object.hasOwn(listsOf(state.output), name) ? state : { ...state, output: withList(state.output, name, exampleRows()) }));
    }
    fields = listFields(listsOf((next.states.find(state => state.name === shown) ?? next.states[0]).output)[name]);
  }
  const view = starter.view(mainValue(placeholders), name, fields);
  if (where.slot === "state") {
    const config = { ...dict(next.module.config), output: "json" };
    const click = { ...dict(dict(next.module.interaction)?.click), type: kind };
    return {
      module: { ...next.module, config, interaction: { ...dict(next.module.interaction), click } },
      states: withStateView(printingJson(next.module, next.states).states, where.state, view),
    };
  }
  const held = withView(next.module, where.slot, view);
  return {
    module: where.slot === "click" ? { ...held, interaction: { ...held.interaction, click: { ...held.interaction.click, type: kind } } } : held,
    states: next.states,
  };
}

// `view` with every `foreach` over the list `from` repeating over `to`.
export function renameListIn(view, from, to) {
  if (Array.isArray(view)) return view.map(each => renameListIn(each, from, to));
  if (!dict(view)) return view;
  const walked = Object.fromEntries(Object.entries(view).map(([key, value]) => [key, renameListIn(value, from, to)]));
  return walked.type === "foreach" && walked.items === from ? { ...walked, items: to } : walked;
}

// `view` with the field `from` of the list `list` called `to`: wherever a
// `foreach` over that list names the field in braces.
export function renameFieldIn(view, list, from, to) {
  const named = value => (typeof value === "string" ? value.split(`{${from}}`).join(`{${to}}`)
    : Array.isArray(value) ? value.map(named)
    : dict(value) ? Object.fromEntries(Object.entries(value).map(([key, each]) => [key, named(each)]))
    : value);
  const walk = value => {
    if (Array.isArray(value)) return value.map(walk);
    if (!dict(value)) return value;
    if (value.type === "foreach" && value.items === list) return { ...value, child: named(value.child) };
    return Object.fromEntries(Object.entries(value).map(([key, each]) => [key, walk(each)]));
  };
  return walk(view);
}

// What each kind of view is, in a sentence.
export const VIEW_KINDS = {
  menu: "Native: a macOS menu. It shows plain rows only: text, icons, actions and checkboxes.",
  popup: spell("Themed: a panel in your bar's colours. It lays out anything: columns, rows, colours, shapes and meters."),
  tooltip: "A small panel shown while the pointer is over the module. Nothing in it can be clicked.",
};

// Whether the states print views that differ: a plugin whose view changes
// shape with what it reads.
export function viewVaries(states = []) {
  const views = states.map(state => dict(dict(state.output)?.view)).filter(view => view !== undefined);
  return new Set(views.map(view => JSON.stringify(view))).size > 1;
}

// A few words saying what a node is, for a list of them. A setting a
// plugin's view names is said as its path in the module's settings.
export function describeNode(node) {
  if (!dict(node)) return "Not a node";
  const said = node.content ?? node.label ?? node.name ?? node.items ?? node.condition ?? node.url;
  if (node.type === "foreach") return `each of ${node.items || "…"}`;
  if (node.type === "if") return `if ${node.condition || "…"}`;
  if (typeof said !== "string") return "";
  return said.replace(/\{setting\(([^(){}]*)\)\}/g, (_, path) => `settings.${path.split(".").map(unescapeKey).join(".")}`);
}

// The paths of the nodes the drawn module `model` shows in its `slot`, as
// text: each node that came to something on screen. A menu's rows name
// their own nodes and the nodes that went into them.
export function drawnPaths(model, slot) {
  const paths = new Set();
  const add = path => path && paths.add(JSON.stringify(path));
  const walk = nodes => {
    for (const node of nodes ?? []) {
      add(node.source);
      walk(node.children);
    }
  };
  if (slot === "hover") walk(model?.tooltip?.view);
  else if (model?.click?.type === "menu") {
    for (const each of model.click.rows) {
      add(each.source);
      (each.sources ?? []).forEach(add);
    }
  } else walk(model?.click?.view);
  return paths;
}

// The path that stands for the node at `path` on screen: its own when it
// is drawn as itself, or the nearest node holding it that is, as an
// hstack's row stands for the text within it. Undefined when none is.
export function markedPath(model, slot, path) {
  const own = new Set();
  const walk = nodes => {
    for (const node of nodes ?? []) {
      if (node.source) own.add(JSON.stringify(node.source));
      walk(node.children);
    }
  };
  if (slot === "hover") walk(model?.tooltip?.view);
  else if (model?.click?.type === "menu") model.click.rows.forEach(each => each.source && own.add(JSON.stringify(each.source)));
  else walk(model?.click?.view);
  for (let end = path.length; end >= 0; end--) {
    // A path ends at a node: after a place in a list, or a key held alone.
    if (end < path.length && typeof path[end] === "number") continue;
    if (own.has(JSON.stringify(path.slice(0, end)))) return path.slice(0, end);
  }
  return undefined;
}

// Whether the node at `path` shows: it, or a node within it, is among the
// `drawn` paths.
export function shows(drawn, path) {
  const prefix = JSON.stringify(path).slice(0, -1);
  if (drawn.has(JSON.stringify(path))) return true;
  for (const each of drawn) if (path.length === 0 || each.startsWith(`${prefix},`)) return true;
  return false;
}
