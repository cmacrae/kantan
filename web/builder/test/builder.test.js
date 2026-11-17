// The builder's logic: document edits, YAML files and share links.
import assert from "node:assert/strict";
import { test } from "node:test";
import { loadConfig, loadTheme, resolveBar, validateDocument } from "../../engine/index.js";
import { SLOTS, readScheme, schemeFileName, schemeTheme } from "../base16.js";
import { BUILT_INS, pluginOf } from "../catalog.js";
import { addBuiltIn, addPasted, addPlugin, emptyDocument, inLayout, layoutOf, modulesOf, toDir, toSingle, updateModule } from "../edit.js";
import { documentFiles, readYaml, themeFiles } from "../files.js";
import { decodeLink, encodeLink, readFragment } from "../share.js";
import { configSchema, deref } from "../schema.js";
import { newTheme, paletteFor, palettesOf, previewRef, themeKind, themeProblems, toKind } from "../theme.js";
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

const flavoured = () => ({
  defaults: { light: "day", dark: "night" },
  flavours: {
    day: { fg: "#111111", bg: "#eeeeee", colors: { accent: "#0000ff" } },
    night: { fg: "#eeeeee", bg: "#111111", shape: "#222222", colors: { accent: "#8888ff" } },
  },
});

test("a new theme loads, and reads the same in each kind it is written as", () => {
  const theme = newTheme();
  assert.deepEqual(themeProblems(theme), []);
  assert.equal(themeKind(theme), "modes");
  const loaded = loadTheme("mine", { mine: theme });
  assert.equal(loaded.light.colors.accent, "#3b6fd4");

  const flavours = toKind(theme, "flavours");
  assert.equal(themeKind(flavours), "flavours");
  assert.deepEqual(loadTheme("mine", { mine: flavours }), loaded);
  assert.deepEqual(loadTheme("mine", { mine: toKind(flavours, "modes") }), loaded);
  assert.deepEqual(toKind(flavours, "single", true), theme.dark);
  assert.deepEqual(toKind(flavours, "single"), theme.light);
  assert.equal(toKind(flavours, "flavours"), flavours);
  assert.deepEqual(palettesOf(toKind(theme, "single")), [{ key: "", path: [] }]);

  assert.equal(paletteFor(theme, "light", true), "dark");
  assert.equal(paletteFor(flavoured(), "gone", true), "night");
  assert.equal(paletteFor(flavoured(), "day", true), "day");
  assert.equal(paletteFor(toKind(theme, "single"), "day", true), "");
  assert.equal(previewRef("mine", flavoured(), "day"), "mine[day]");
  assert.equal(previewRef("mine", theme, "dark"), "mine");
});

test("a theme's files read back as the theme, in either layout", () => {
  const theme = flavoured();
  const [file, ...rest] = themeFiles("mine", theme);
  assert.equal(file.path, "themes/mine.yaml");
  assert.equal(rest.length, 0);
  assert.deepEqual(readYaml(file.text).value, theme);
  assert.equal(file.text, [
    "defaults:", "  light: day", "  dark: night", "", "flavours:",
    "  day:", '    fg: "#111111"', '    bg: "#eeeeee"', "    colors:", '      accent: "#0000ff"', "",
    "  night:", '    fg: "#eeeeee"', '    bg: "#111111"', '    shape: "#222222"', "    colors:", '      accent: "#8888ff"', "",
  ].join("\n"));

  const dir = themeFiles("mine", theme, "dir");
  assert.deepEqual(dir.map(each => each.path), ["themes/mine/defaults.yaml", "themes/mine/day.yaml", "themes/mine/night.yaml"]);
  assert.deepEqual(readYaml(dir[0].text).value, theme.defaults);
  assert.deepEqual(readYaml(dir[2].text).value, theme.flavours.night);

  const modes = toKind(theme, "modes");
  assert.deepEqual(readYaml(themeFiles("mine", modes)[0].text).value, modes);
  assert.match(themeFiles("mine", modes)[0].text, /\n\ndark:\n/);
  const single = toKind(theme, "single");
  assert.equal(themeFiles("mine", single)[0].text, 'fg: "#111111"\nbg: "#eeeeee"\ncolors:\n  accent: "#0000ff"\n');
});

const mocha16 = () => ({
  system: "base16", name: "Catppuccin Mocha", variant: "dark",
  palette: {
    base00: "#1e1e2e", base01: "#181825", base02: "#313244", base03: "#45475a", base04: "#585b70", base05: "#cdd6f4",
    base06: "#f5e0dc", base07: "#b4befe", base08: "#f38ba8", base09: "#fab387", base0A: "#f9e2af", base0B: "#a6e3a1",
    base0C: "#94e2d5", base0D: "#89b4fa", base0E: "#cba6f7", base0F: "#f2cdcd",
  },
});

test("a Base16 or Base24 scheme is read, however it lists its slots", () => {
  const scheme = readScheme(mocha16());
  assert.equal(scheme.system, "base16");
  assert.equal(scheme.variant, "dark");
  assert.equal(scheme.palette.base0F, "#f2cdcd");
  // A scheme as read is itself a scheme, as a browser keeps it.
  assert.deepEqual(readScheme(JSON.parse(JSON.stringify(scheme))), scheme);

  // An older scheme names itself with `scheme` and writes bare hex.
  const older = { scheme: "Old One", author: "someone", ...Object.fromEntries(Object.entries(mocha16().palette).map(([slot, hex]) => [slot, hex.slice(1).toUpperCase()])) };
  assert.deepEqual(readScheme(older), { name: "Old One", system: "base16", variant: undefined, palette: mocha16().palette });

  const more = { ...mocha16(), system: "base24", palette: { ...mocha16().palette } };
  for (const slot of SLOTS.slice(16)) more.palette[slot] = "#123456";
  assert.equal(readScheme(more).system, "base24");
  assert.equal(SLOTS.length, 24);

  const { base0F: _, ...short } = mocha16().palette;
  assert.equal(readScheme({ palette: short }), undefined);
  assert.equal(readScheme({ palette: { ...mocha16().palette, base03: "blue" } }), undefined);
  assert.equal(readScheme({ fg: "#111111", bg: "#eeeeee" }), undefined);
  assert.equal(readScheme("text"), undefined);
  assert.equal(schemeFileName("Catppuccin Mocha"), "catppuccin-mocha");
  assert.equal(schemeFileName("Rosé Pine (Dawn)"), "rosé-pine-dawn");
});

test("a scheme makes a theme kantan loads", () => {
  const theme = schemeTheme(readScheme(mocha16()));
  assert.deepEqual(themeProblems(theme), []);
  assert.equal(themeKind(theme), "single");
  const loaded = loadTheme("mocha", { mocha: theme });
  assert.deepEqual([loaded.dark.fg, loaded.dark.bg, loaded.dark.shape], ["#cdd6f4", "#1e1e2e", "#313244"]);
  assert.equal(loaded.light.colors.base08, "#f38ba8");
});
