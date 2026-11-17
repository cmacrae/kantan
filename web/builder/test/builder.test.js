// The builder's logic: document edits, YAML files and share links.
import assert from "node:assert/strict";
import { test } from "node:test";
import { loadConfig, resolveBar, validateDocument } from "../../engine/index.js";
import { BUILT_INS, pluginOf } from "../catalog.js";
import { addBuiltIn, addPasted, addPlugin, emptyDocument, inLayout, layoutOf, modulesOf, toDir, toSingle, updateModule } from "../edit.js";
import { documentFiles, readYaml } from "../files.js";
import { decodeLink, encodeLink, readFragment } from "../share.js";
import { configSchema, deref } from "../schema.js";
import { WORDS } from "../words.js";
import { zip } from "../zip.js";

const catalog = {
  themes: {},
  plugins: {
    caffeine: {
      module: {
        name: "caffeine", type: "command", placement: "right", icon: "mug",
        config: { command: "kantan-plugin-caffeine", output: "json", toggle: "kantan-plugin-caffeine --toggle" },
        interaction: { click: { type: "toggle" } },
      },
      states: [
        { name: "On", output: { icon: "mug-filled", active: true }, transitions: { "kantan-plugin-caffeine --toggle": "Off" } },
        { name: "Off", output: { icon: "mug", active: false }, transitions: { "kantan-plugin-caffeine --toggle": "On" } },
      ],
    },
  },
};

const names = document => modulesOf(document).map(module => module.name);
const drawn = document => {
  const bar = resolveBar(document);
  return Object.fromEntries(Object.entries(bar.placements).map(([placement, modules]) => [placement, modules.map(m => m.name)]));
};

// A bar with a module of every built-in type and a bundled plugin.
function everything() {
  let document = emptyDocument();
  for (const type of Object.keys(BUILT_INS)) document = addBuiltIn(document, type);
  return addPlugin(document, "caffeine", catalog);
}

test("every built-in type starts as a module kantan loads, in states it draws", () => {
  const document = everything();
  assert.deepEqual(validateDocument(document), []);
  assert.equal(loadConfig(document).modules.length, Object.keys(BUILT_INS).length + 1);
  for (const [name, states] of Object.entries(document.states)) {
    for (const state of states) {
      const bar = resolveBar(document, { states: { [name]: state.name } });
      const module = Object.values(bar.placements).flat().find(m => m.name === name);
      assert.equal(module.unsupported, undefined, `${name} in ${state.name}`);
    }
  }
});

test("adding a module gives it a name of its own and its starting states", () => {
  let document = addBuiltIn(addBuiltIn(emptyDocument(), "power"), "power");
  assert.deepEqual(names(document), ["power", "power-2"]);
  assert.deepEqual(document.states["power-2"], BUILT_INS.power.states);
  document = addPlugin(document, "caffeine", catalog);
  assert.equal(pluginOf(modulesOf(document)[2], catalog), "caffeine");
  assert.deepEqual(document.states.caffeine, catalog.plugins.caffeine.states);
});

test("either layout draws the same bar", () => {
  const single = everything();
  const dir = toDir(single);
  assert.equal(layoutOf(single), "single");
  assert.equal(layoutOf(dir), "dir");
  assert.equal(dir.config.modules, undefined);
  assert.deepEqual(Object.keys(dir.modulesDir).slice(0, 2), ["00-workspace.yaml", "01-text.yaml"]);
  assert.deepEqual(drawn(dir), drawn(single));
  assert.deepEqual(toSingle(dir), single);
  assert.deepEqual(inLayout(single, "dir"), dir);
});

test("the files read back as the config they were written from", () => {
  const document = updateModule(everything(), 0, {
    ...modulesOf(everything())[0],
    style: { fg: "{theme(red)}" },
    config: { note: "yes", count: "12", flag: "true", none: "null", big: "1_000", real: true, n: 3 },
  });
  const [config, ...others] = documentFiles(document);
  assert.equal(config.path, "config.yaml");
  assert.equal(others.length, 0);
  assert.deepEqual(readYaml(config.text).value, document.config);
  assert.match(config.text, /^modules:\n  - name: workspace\n    type: workspace\n    placement: left\n/);
  assert.match(config.text, /note: "yes"/);
  assert.match(config.text, /big: "1_000"/);
  assert.match(config.text, /\n\n  - name: text\n/);

  const files = documentFiles(toDir(document));
  assert.equal(files[0].text, "");
  assert.equal(files[1].path, "modules.d/00-workspace.yaml");
  const clock = files.find(file => file.path.endsWith("-clock.yaml"));
  assert.match(clock.text, /^name: clock\ntype: clock\nplacement: right\nconfig:\n  format: HH:mm\n$/);
});

test("a link holds the whole document", async () => {
  const document = {
    ...addPasted(everything(), "mine", '{"value":"^caret","icon":"bell"}'),
    themes: { mine: { palettes: { day: { fg: "#000000", bg: "#ffffff" } } } },
    view: { dark: true, shown: { power: "Low" } },
  };
  for (const layout of ["single", "dir"]) {
    const laid = inLayout(document, layout);
    const fragment = await encodeLink(laid, catalog);
    assert.match(fragment, /^1\.[A-Za-z0-9_-]+$/);
    assert.deepEqual(await decodeLink(fragment, catalog), laid);
  }
});

test("links made before still open", async () => {
  // A link made when the codec was written: the word list may only grow.
  const fragment = "1.q1ZKVrKqVorLUrKKBlIGSlZKSYklJalFlUo6SnGGQG6coRGIaQRiGivVxtbqKCUBFcOVxdYCAA";
  assert.deepEqual(await decodeLink(fragment, catalog), {
    version: 1,
    config: { modules: [{ name: "battery", type: "power", placement: "right" }] },
    states: { battery: BUILT_INS.power.states },
  });
  assert.equal(WORDS[0], "name");
  assert.equal(new Set(WORDS).size, WORDS.length);
});

test("a fragment names a shared bar or a config to fetch", () => {
  assert.deepEqual(readFragment("#1.abc"), { link: "1.abc" });
  assert.deepEqual(readFragment("#from=https%3A%2F%2Fexample.com%2Fconfig.yaml"), { url: "https://example.com/config.yaml" });
  assert.equal(readFragment("#from=javascript:alert(1)"), undefined);
  assert.deepEqual(readFragment("#gh=someone/dotfiles/kantan/config.yaml"), {
    url: "https://raw.githubusercontent.com/someone/dotfiles/HEAD/kantan/config.yaml",
  });
  assert.equal(readFragment("#gh=someone/dotfiles"), undefined);
  assert.deepEqual(readFragment("#gist=0123abcd"), { url: "https://api.github.com/gists/0123abcd", gist: true });
  assert.equal(readFragment(""), undefined);
  assert.equal(readFragment("#install"), undefined);
});

test("a ZIP archive lists its files with their contents stored", () => {
  const bytes = zip([{ path: "config.yaml", text: "height: 30\n" }, { path: "modules.d/00-a.yaml", text: "name: a\n" }]);
  const view = new DataView(bytes.buffer);
  const text = new TextDecoder().decode(bytes);
  assert.equal(view.getUint32(0, true), 0x04034b50);
  // The CRC-32 of "height: 30\n"
  assert.equal(view.getUint32(14, true), 0xe6475190);
  assert.ok(text.includes("config.yamlheight: 30\n"));
  assert.ok(text.includes("modules.d/00-a.yamlname: a\n"));
  const end = bytes.length - 22;
  assert.equal(view.getUint32(end, true), 0x06054b50);
  assert.equal(view.getUint16(end + 10, true), 2);
  assert.equal(view.getUint32(view.getUint32(end + 16, true), true), 0x02014b50);
});

test("the schema gives each type's config, with references followed", () => {
  const schema = {
    $defs: { Color: { type: "string" }, PowerConfig: { type: "object", properties: { tint: { $ref: "#/$defs/Color", description: "Its tint" } } } },
    allOf: [
      { if: { properties: { type: { const: "power" } } }, then: { properties: { config: { $ref: "#/$defs/PowerConfig" } } } },
      { if: { properties: { type: { const: "text" } } }, then: { required: ["config"], properties: { config: { type: "object" } } } },
    ],
  };
  const power = configSchema(schema, "power");
  assert.equal(power.ref, "PowerConfig");
  assert.equal(power.requiredByType, false);
  assert.deepEqual(deref(schema, power.properties.tint), { type: "string", description: "Its tint", ref: "Color" });
  assert.equal(configSchema(schema, "text").requiredByType, true);
  assert.equal(configSchema(schema, "nonsense"), undefined);
});
