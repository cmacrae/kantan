// What the shared cases can't reach, as kantan draws it with SwiftUI and
// has no model to compare: popup views, icons from the fonts, and the
// document itself.
import assert from "node:assert/strict";
import { test } from "node:test";
import { parseHex } from "../color.js";
import waveform from "../modules/waveform.js";
import {
  createResolver, fillTooltip, menuRows, decodeJsonView, formatDate, iconTable, ordinalSuffix, resolveBar, resolveOverlap, resolveTuck, resolveView, tuckHides,
  validateDocument,
} from "../index.js";

const icons = iconTable({
  bell: { font: "icons", char: "", scale: 1.1333 },
  "bell-filled": { font: "icons-filled", char: "", scale: 1.6 },
});

// The view `json` resolves to, with `variables` and `data`.
function view(json, { variables = {}, data = {}, fg = "#111111" } = {}) {
  const { node, problem } = decodeJsonView(json);
  assert.equal(problem, undefined);
  return resolveView(node, { resolver: createResolver({ variables, data }), native: false, fg, icons });
}

test("a view resolves its text, colours and icons", () => {
  const [stack] = view({
    type: "vstack",
    alignment: "topTrailing",
    children: [
      { type: "text", content: "{title}", color: "#FF0000", style: "secondary", weight: "bold" },
      { type: "text", content: "plain" },
      { type: "icon", name: "bell", size: 20, color: "red" },
      { type: "icon", name: "bell-filled" },
      { type: "badge", content: "3" },
      { type: "progress", value: "{load}", trackColor: "nonsense" },
      { type: "rect", width: 3, color: "{missing}", strokeColor: "#00FF00" },
    ],
  }, { variables: { title: "Hello", load: "1.5" } });

  assert.equal(stack.align, "trailing");
  const [text, plain, icon, filled, badge, progress, rect] = stack.children;
  assert.deepEqual(
    { text: text.text, color: text.color, secondary: text.secondary, weight: text.weight, size: text.size },
    { text: "Hello", color: "#ff0000", secondary: true, weight: "bold", size: 13 });
  assert.equal(plain.color, "#111111");
  assert.deepEqual(icon.icon, { name: "bell", glyph: "", font: "icons", size: 23 });
  assert.equal(icon.color, "red");
  assert.equal(filled.icon.size, 21);
  assert.deepEqual([badge.color, badge.textColor], ["accent", "white"]);
  assert.deepEqual([progress.value, progress.color, progress.track], [1, "accent", "track"]);
  assert.deepEqual([rect.color, rect.stroke], ["clear", { color: "#00ff00", width: 1 }]);
});

test("visible, if and foreach decide which nodes a view comes to", () => {
  const nodes = view({
    type: "vstack",
    children: [
      { type: "text", content: "hidden", visible: false },
      { type: "text", content: "shown", visible: true },
      { type: "text", content: "by variable", visible: "on" },
      { type: "text", content: "by missing variable", visible: "off" },
      { type: "if", condition: "on", then: { type: "text", content: "then" }, else: { type: "text", content: "else" } },
      { type: "foreach", items: "rows", child: { type: "text", content: "{name}" } },
    ],
  }, { variables: { on: "yes" }, data: { rows: [{ name: "a" }, { name: "b" }] } });
  assert.deepEqual(nodes[0].children.map(node => node.text), ["shown", "by variable", "then", "a", "b"]);
});

test("what the preview can't draw is marked, never left out", () => {
  const [stack] = view({
    type: "vstack",
    children: [
      { type: "gauge", value: 0.5 },
      { type: "image", url: "https://example.com/a.png" },
      { type: "icon", name: "star.fill" },
      { type: "icon", name: "★" },
      { type: "action", label: "Go", icon: "gear" },
    ],
  });
  const [gauge, image, symbol, glyph, action] = stack.children;
  assert.deepEqual(gauge, { type: "unsupported", what: "gauge", source: ["children", 0] });
  assert.deepEqual(image, { type: "unsupported", what: "image", source: ["children", 1] });
  assert.deepEqual(symbol.icon, { type: "unsupported", what: "SF Symbol" });
  assert.equal(glyph.icon.text, "★");
  assert.equal(action.icon.type, "unsupported");
});

const document = {
  version: 1,
  config: { theme: "t" },
  modulesDir: {
    "00-bell.yaml": {
      name: "bell", type: "command", placement: "right", icon: "bell",
      fonts: { icon: "tabler-icons:regular:20" },
      config: { command: "x", output: "json", toggle: "bell --toggle" },
      interaction: { click: { type: "popup" } },
    },
    "10-clock.yaml": { name: "clock", type: "clock", placement: "right", config: { format: "QQQ yyyy" } },
  },
  themes: { t: { fg: "#111111", bg: "#eeeeee" } },
  states: {
    bell: [
      {
        name: "Quiet",
        output: { value: "", view: { type: "vstack", children: [{ type: "action", label: "Ring", command: "bell --ring" }, { type: "check", label: "Mute", checked: false, command: "bell --mute", uncheckedCommand: "bell --unmute" }] } },
        transitions: { "bell --ring": "Ringing" },
      },
      { name: "Ringing", output: { value: "ring", icon: "bell-filled", view: { type: "toggle", label: "Ring", on: true, command: "bell --stop" } } },
    ],
  },
};

test("a date pattern writes its fields, its quoted text and the ordinal day", () => {
  const time = Date.parse("2026-07-03T15:04:05.678Z");
  const write = (pattern, timezone = "America/New_York") => formatDate(time, pattern, { timezone, locale: "en_US" });
  assert.deepEqual(write("EEEE, MMMM do yyyy 'at' hh:mm:ss.SS 'o''clock'"), { text: "Friday, July 3rd 2026 at 11:04:05.67 o'clock" });
  assert.deepEqual(write("y-M-d H:m:s K k ZZZ ZZZZ", "Asia/Kolkata"), { text: "2026-7-3 20:34:5 8 20 +0530 GMT+05:30" });
  assert.deepEqual(write("LLLL ddo doo"), { unsupported: "o" });
  assert.deepEqual(write("d MMM", "Nowhere/Unknown"), formatDate(time, "d MMM", { locale: "en_US" }));
  assert.deepEqual([1, 2, 3, 4, 11, 12, 13, 21, 22, 23, 30, 31].map(ordinalSuffix),
    ["st", "nd", "rd", "th", "th", "th", "th", "st", "nd", "rd", "th", "st"]);
});

const builtIns = {
  version: 1,
  config: {
    fonts: { text: "system:Menlo:10" },
    modules: [
      { name: "spaces", type: "workspace", placement: "left", icon: "bell", config: { icons: ["literal"] } },
      { name: "note", type: "text", placement: "left", config: { value: "outside" } },
      { name: "left-drawer", type: "drawer", placement: "left" },
      { name: "folded", type: "text", placement: "left", config: { value: "inside" } },
      { name: "wifi", type: "wifi", placement: "right", config: { icons: { strength: ["bell", "bell-filled"] } } },
      { name: "right-drawer", type: "drawer", placement: "right" },
      { name: "second-drawer", type: "drawer", placement: "right" },
    ],
  },
  states: {
    spaces: [{ name: "Two", output: { workspaces: [{ active: true }, {}] } }],
    wifi: [{ name: "Weak", output: { connected: true, rssi: -80 } }],
    "right-drawer": [{ name: "Closed" }, { name: "Open", output: { open: true } }],
    "second-drawer": [{ name: "Open", output: { open: true } }],
  },
};

test("a drawer folds the modules beyond it away until its side's first drawer opens", () => {
  const folded = bar => Object.fromEntries(
    [...bar.placements.left, ...bar.placements.right].map(module => [module.name, module.folded]));
  assert.deepEqual(folded(resolveBar(builtIns)), {
    spaces: undefined, note: undefined, "left-drawer": undefined, folded: true,
    wifi: true, "right-drawer": undefined, "second-drawer": undefined,
  });
  const open = resolveBar(builtIns, { states: { "right-drawer": "Open" } });
  assert.equal(folded(open).wifi, false);
  assert.equal(folded(open).folded, true);
});

test("masked modules take their menu bar items' places, a hidden one giving its up", () => {
  const masked = (name, type, mask, extra = {}) => ({ name, type, placement: "right", mask, config: { value: "x", format: "HH" }, ...extra });
  const document = {
    version: 1,
    config: { modules: [
      masked("clock", "clock", { name: "Clock" }), masked("other", "text", { name: "Some App" }),
      { name: "plain", type: "text", placement: "right", config: { value: "x" } },
      masked("focus", "focus", { name: "focus" }), masked("battery", "text", { name: "Battery" }, { placement: "left" }),
      masked("numbered", "text", { index: 2 }), masked("unmasked", "text", {}),
    ] },
    states: { focus: [{ name: "Off" }, { name: "On", output: { active: true } }] },
  };
  const bar = resolveBar(document);
  assert.deepEqual(bar.menuBar, { trailing: 12, modules: ["battery", "other", "numbered", "clock"] });
  const slot = name => Object.values(bar.placements).flat().find(module => module.name === name).slot;
  assert.deepEqual([slot("clock"), slot("battery"), slot("other"), slot("plain"), slot("unmasked"), slot("focus")],
    [{ width: 54 }, { width: 44 }, { width: 36 }, undefined, undefined, undefined]);
  assert.deepEqual(resolveBar(document, { states: { focus: "On" } }).menuBar.modules, ["battery", "other", "focus", "numbered", "clock"]);
  assert.deepEqual(resolveBar(builtIns).menuBar, { trailing: 0, modules: [] });
});

test("an unmasked module listed after a masked one keeps its place over the menu bar", () => {
  const module = (name, mask) => ({ name, type: "text", placement: "right", config: { value: "x" }, ...(mask ? { mask: { name: mask } } : {}) });
  const modules = [
    module("monitor"), module("bluetooth", "Bluetooth"), module("caffeine"), module("clock", "Clock"),
    module("volume", "Volume"), module("control", "ControlCenter"), module("date"),
  ];
  const over = config => {
    const bar = resolveBar({ version: 1, config });
    return [bar.menuBar.modules, bar.placements.right.filter(each => each.fixed).map(each => each.name)];
  };
  // The clock and Control Centre stay at the right end, and nothing sits right of them.
  assert.deepEqual(over({ modules }), [["bluetooth", "caffeine", "volume", "control", "clock"], ["clock", "control"]]);
  assert.deepEqual(over({ modules, menuBarSlots: false })[0], ["bluetooth", "volume", "control", "clock"]);
});

test("a document is checked before it's drawn", () => {
  assert.deepEqual(validateDocument(document), []);
  assert.deepEqual(validateDocument([]), ["The document isn't a mapping"]);
  assert.deepEqual(validateDocument({ version: 2, config: {} }), ["The document's version isn't 1"]);
  const broken = {
    version: 1,
    config: "text",
    modulesDir: { "a.yaml": 5 },
    states: {
      a: "none",
      b: [{ name: "x" }, { name: "x", output: 5, transitions: { go: "nowhere" } }, { output: {} }],
    },
  };
  assert.deepEqual(validateDocument(broken), [
    "config isn't a mapping",
    "modulesDir's a.yaml isn't a mapping",
    "a's states aren't a list",
    "b's state x shares its name with another",
    "b's state x's output is neither text nor a mapping",
    "b's state x leads to nowhere, which isn't a state, by go",
    "b's state 3 has no name",
  ]);
  assert.deepEqual(validateDocument({ version: 1, config: {}, view: { dark: true, notch: false, shown: { a: "x" } } }), []);
  assert.deepEqual(validateDocument({ version: 1, config: {}, view: { dark: "yes", shown: { a: 1 } } }), [
    "view's dark isn't true or false",
    "view shows a in a state that isn't a name",
  ]);
});

test("where a drawer and the notch's modules meet, whichever is in use keeps its place", () => {
  const resolve = state => resolveOverlap({ collides: true, drawerOpen: true, engaged: false, displaced: false, yielded: false, ...state });
  assert.equal(resolve({}), "displace");
  assert.equal(resolve({ collides: false }), "none");
  assert.equal(resolve({ displaced: true }), "none");
  assert.equal(resolve({ drawerOpen: false, displaced: true }), "restore");
  assert.equal(resolve({ collides: false, displaced: true }), "restore");
  assert.equal(resolve({ engaged: true }), "closeDrawer");
  assert.equal(resolve({ drawerOpen: false, engaged: true, yielded: true }), "none");
  assert.equal(resolve({ drawerOpen: false, yielded: true }), "reopenDrawer");
});

test("a module that gives way waits behind the notch while another on its side shows", () => {
  assert.equal(resolveTuck({ tucking: true, holding: false, revealing: false }), "idle");
  assert.equal(resolveTuck({ tucking: false, holding: true, revealing: true }), "idle");
  assert.equal(resolveTuck({ tucking: true, holding: true, revealing: false }), "tucked");
  assert.equal(resolveTuck({ tucking: true, holding: true, revealing: true }), "revealed");
  assert.deepEqual(["idle", "tucked", "revealed"].map(phase => [tuckHides(phase, true), tuckHides(phase, false)]),
    [[false, false], [true, false], [false, true]]);
});

test("a waveform's gradient passes through each of its colours, and a wave following the tone takes a palette's once", () => {
  const waveform = config => resolveBar({
    version: 1, config: { theme: "t", modules: [{ name: "sound", type: "waveform", placement: "left", config }] },
    themes: { t: { fg: "#111111", bg: "#eeeeee" } },
    states: { sound: [{ name: "Playing", output: { levels: [0.5, 0.9, 0.4] } }] },
  }).placements.left[0].waveform;
  assert.deepEqual(waveform({ bars: 5, gradient: { colors: ["#000000", "#FFFFFF", "#FF0000"] } }).colors,
    ["#000000", "#808080", "#FFFFFF", "#FF8080", "#FF0000"]);
  const rainbow = { enabled: true, random: false, colors: ["#FF0000", "#00FF00"] };
  assert.deepEqual(waveform({ bars: 4, rainbow }).colors, ["#ff0000", "#00ff00", "#ff0000", "#00ff00"]);
  assert.deepEqual(waveform({ style: "wave", wave: { tone: true }, rainbow }).colors, ["#ff0000", "#00ff00"]);
  assert.equal(waveform({ style: "spectrogram" }).style, "spectrogram");
  assert.equal(waveform({ style: "unknown" }).style, "bars");
});

test("a colour is read in a time that grows with its length", { timeout: 5000 }, () => {
  assert.equal(parseHex("##FF0000;"), "#ff0000");
  assert.equal(parseHex(" «11223344» "), "#11223344");
  assert.equal(parseHex("ff00"), undefined);
  assert.equal(parseHex(`a${"#".repeat(1_000_000)}a`), undefined);
  assert.equal(parseHex(`${"#".repeat(1_000_000)}ff0000${"\u{1F600}".repeat(500_000)}`), "#ff0000");
});

// A `foreach` over `rows`, nested `depth` deep around a text node.
function nestedForeach(depth) {
  let node = { type: "text", content: "{n}" };
  for (let i = 0; i < depth; i++) node = { type: "foreach", items: "rows", child: node };
  return node;
}

test("a view comes to no more nodes than a popup could show", { timeout: 5000 }, () => {
  const data = { rows: [{ n: "1" }, { n: "2" }, { n: "3" }, { n: "4" }] };
  assert.equal(view(nestedForeach(3), { data }).length, 64);
  // Twenty deep is four to the twentieth: a million million text nodes.
  const nodes = view(nestedForeach(20), { data });
  assert.ok(nodes.length > 0 && nodes.length <= 10_000, `${nodes.length} nodes`);
  const { node } = decodeJsonView(nestedForeach(20));
  const rows = menuRows(node, createResolver({ data }), icons);
  assert.ok(rows.length > 0 && rows.length <= 10_000, `${rows.length} rows`);
  const [grid] = view({ type: "grid", columns: 1e15, children: [] });
  assert.equal(grid.columns, 64);
});

test("a plain tooltip fills each placeholder once, with the value as written", () => {
  const variables = Object.fromEntries(Array.from({ length: 40 }, (_, i) => [`v${i}`, `{v${i + 1}}{v${i + 1}}`]));
  assert.equal(fillTooltip("{v0}", { variables }), "{v1}{v1}");
  assert.equal(fillTooltip("vol {value}! {icon} {status} {unknown}", { value: "$& and $' and $`", icon: "$$", variables: { status: "{value}" } }),
    "vol $& and $' and $`! $$ {value} {unknown}");
  assert.equal(fillTooltip("{value} {icon}", { variables: { value: "x" } }), "x {icon}");
  assert.equal(fillTooltip("{a{b}", { variables: { b: "B" } }), "{aB");
});

test("a waveform is no larger than a bar could hold", () => {
  const { width, height } = waveform.load({ width: 1e13, height: 3e6 });
  assert.deepEqual({ width, height }, { width: 2000, height: 200 });
  assert.deepEqual(waveform.load({}).width, 40);
});
