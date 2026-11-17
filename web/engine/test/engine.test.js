// What the shared cases can't reach, as kantan draws it with SwiftUI and
// has no model to compare: popup views, icons from the fonts, and the
// document itself.
import assert from "node:assert/strict";
import { test } from "node:test";
import { createResolver, decodeJsonView, iconTable, resolveBar, resolveView, validateDocument } from "../index.js";

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
  assert.deepEqual(gauge, { type: "unsupported", what: "gauge" });
  assert.deepEqual(image, { type: "unsupported", what: "image" });
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
    "10-clock.yaml": { name: "clock", type: "clock", placement: "right" },
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

test("a module type the preview can't draw yet is marked in the bar", () => {
  const [, clock] = resolveBar(document).placements.right;
  assert.deepEqual(clock, { name: "clock", type: "clock", hidden: false, unsupported: "clock module" });
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
});
