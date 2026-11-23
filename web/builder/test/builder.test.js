// The builder's logic: document edits, YAML files and share links.
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import { NODE_FIELDS, NODE_TYPES, decodeJsonView, loadConfig, loadTheme, resolveBar, validateDocument } from "../../engine/index.js";
import { SLOTS, readScheme, schemeFileName, schemeTheme, withSharedTheme } from "../base16.js";
import { BUILT_INS, inVariant, kindIcon, pluginOf, variantOf } from "../catalog.js";
import { bindSettings } from "../settings.js";
import {
  addBuiltIn, addPasted, addPlugin, addShared, boundDocument, emptyDocument, inLayout, layoutOf, modulesOf, toDir, toSingle, updateModule, placeAtEdge, placeModule,
} from "../edit.js";
import { documentFiles, readYaml, themeFiles, variantsYaml } from "../files.js";
import { themeVariants } from "../shared.js";
import { american, canadian } from "../spelling.js";
import { decodeLink, decodeModuleLink, decodeThemeLink, encodeLink, encodeModuleLink, encodeThemeLink, packModule, readFragment } from "../share.js";
import { configSchema, deref } from "../schema.js";
import { newTheme, paletteFor, palettesOf, previewRef, themeKind, themeProblems, toKind } from "../theme.js";
import {
  NODE_INFO, NODE_KINDS, STARTERS, VIEW_KINDS, describeNode, insertNode, moveNode, moveView, starterScript, newNode, nodeAt, nudgeNode, removeNode, replaceNode, shows,
  wrapNode,
} from "../view.js";
import { zip } from "../zip.js";
import { deflateSync } from "fflate";
import { DICTIONARY } from "../dictionary.js";

// The fragment that holds `packed` after `version`, as a link's sender
// could write it by hand.
function rawFragment(version, packed) {
  const deflated = deflateSync(new TextEncoder().encode(JSON.stringify(packed)), { dictionary: new TextEncoder().encode(DICTIONARY) });
  return `${version}.${Buffer.from(deflated).toString("base64url")}`;
}

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

test("a module is shown by its bundled plugin's icon, else its type's", () => {
  const icon = name => kindIcon(modulesOf(everything()).find(module => module.name === name), catalog);
  assert.equal(icon("power"), BUILT_INS.power.icon);
  assert.equal(icon("command"), BUILT_INS.command.icon);
  assert.equal(icon("caffeine"), "mug");
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

test("a document is drawn with its plugins' states bound to their modules' settings", () => {
  const settings = { type: "object", properties: { icons: { type: "object", properties: { on: { $ref: "#/$defs/Icon", default: "mug-filled" } } } }, $defs: { Icon: { type: "string" } } };
  const following = {
    themes: {},
    plugins: { caffeine: { ...catalog.plugins.caffeine, settings, states: [{ name: "On", output: { icon: "{setting(icons.on)}", style: { fg: "{setting(colour)}" } } }] } },
  };
  let document = addPlugin(emptyDocument(), "caffeine", following);
  assert.deepEqual(boundDocument(document, following).states.caffeine[0].output, { icon: "mug-filled" });
  assert.equal(document.states.caffeine[0].output.icon, "{setting(icons.on)}");

  document = updateModule(document, 0, { ...modulesOf(document)[0], config: { ...modulesOf(document)[0].config, settings: { icons: { on: "coffee" }, colour: "#ff0000" } } });
  const bound = boundDocument(document, following);
  assert.deepEqual(bound.states.caffeine[0].output, { icon: "coffee", style: { fg: "#ff0000" } });
  assert.equal(resolveBar(bound).placements.right[0].icon.name, "coffee");

  // A document naming no settings is drawn as it is.
  const plain = everything();
  assert.equal(boundDocument(plain, catalog), plain);

  // A name falls back to what follows it while its setting is unset, and
  // to the last of them when set to inherit.
  const falling = "{setting(colors.calendars.Work)}|{setting(colors.event)}|#1e66f5";
  assert.equal(bindSettings(falling, {}), "#1e66f5");
  assert.equal(bindSettings(falling, { colors: { event: "#ff0000" } }), "#ff0000");
  assert.equal(bindSettings(falling, { colors: { calendars: { Work: "inherit" }, event: "#ff0000" } }), "#1e66f5");
  assert.equal(bindSettings(falling, { colors: { calendars: { Work: "#00ff00" }, event: "#ff0000" } }), "#00ff00");
});

test("a module takes the states of the variant its settings match, until its states are its own", () => {
  const full = [{ name: "Month", output: { value: "full" } }];
  const varied = { themes: {}, plugins: { caffeine: { ...catalog.plugins.caffeine, variants: [{ settings: { mode: "full" }, states: full }] } } };
  const withSettings = (document, settings) => updateModule(document, 0, { ...modulesOf(document)[0], config: { ...modulesOf(document)[0].config, settings } }, varied);
  let document = addPlugin(emptyDocument(), "caffeine", varied);
  assert.deepEqual(document.states.caffeine, varied.plugins.caffeine.states);

  document = withSettings(document, { mode: "full", other: 1 });
  assert.deepEqual(document.states.caffeine, full);
  // A setting left out is the schema's default.
  const defaulting = { themes: {}, plugins: { caffeine: { ...varied.plugins.caffeine, settings: { properties: { mode: { default: "full" } } } } } };
  assert.equal(variantOf({ config: { command: "kantan-plugin-caffeine" } }, defaulting), defaulting.plugins.caffeine.variants[0]);
  assert.deepEqual(withSettings(document, { mode: "compact" }).states.caffeine, varied.plugins.caffeine.states);

  // A variant's interaction comes with the change that enters it, and not after.
  varied.plugins.caffeine.variants[0].interaction = { click: { type: "popup" } };
  const menu = { ...modulesOf(document)[0], config: { command: "kantan-plugin-caffeine" }, interaction: { click: { type: "menu", view: { type: "divider" } } } };
  const entered = inVariant(menu, { ...menu, config: { ...menu.config, settings: { mode: "full" } } }, varied);
  assert.deepEqual(entered.interaction.click, { type: "popup", view: { type: "divider" } });
  const back = { ...entered, interaction: { click: { type: "menu" } } };
  assert.equal(inVariant(entered, back, varied), back);

  // States someone has edited stay as they are.
  const own = [{ name: "Mine", output: {} }];
  const edited = { ...document, states: { caffeine: own } };
  assert.deepEqual(withSettings(edited, {}).states.caffeine, own);
});

const sampleView = () => ({
  type: "vstack",
  children: [
    { type: "header", content: "A" },
    { type: "hstack", children: [{ type: "icon", name: "cpu" }, { type: "text", content: "{cpu}" }] },
    { type: "if", condition: "busy", then: { type: "group", children: [{ type: "text", content: "Busy" }] }, else: { type: "text", content: "Idle" } },
    { type: "foreach", items: "rows", child: { type: "text", content: "{name}" } },
    { type: "divider" },
  ],
});

test("nodes are added, changed, wrapped and removed where their paths say", () => {
  const view = sampleView();
  const added = insertNode(view, ["children", 1], newNode("spacer"), 1);
  assert.deepEqual(added.children[1].children.map(node => node.type), ["icon", "spacer", "text"]);
  assert.equal(insertNode(view, [], newNode("badge")).children.at(-1).type, "badge");
  assert.equal(view.children.length, 5);

  assert.equal(replaceNode(view, ["children", 2, "else"], { type: "text", content: "Free" }).children[2].else.content, "Free");
  assert.deepEqual(replaceNode(view, [], { type: "text", content: "x" }), { type: "text", content: "x" });

  assert.deepEqual(removeNode(view, ["children", 0]).children.map(node => node.type), ["hstack", "if", "foreach", "divider"]);
  assert.equal(removeNode(view, ["children", 2, "else"]).children[2].else, undefined);
  assert.equal(removeNode(view, []), undefined);

  const wrapped = wrapNode(view, ["children", 0], "hstack");
  assert.deepEqual(wrapped.children[0], { type: "hstack", children: [{ type: "header", content: "A" }] });
});

test("a node moves within its list, into another, and never into itself", () => {
  const view = sampleView();
  const types = at => nodeAt(at, ["children"]).map(node => node.type);

  // Later in its own list: it sits where the node at that place was.
  let moved = moveNode(view, ["children", 0], [], 3);
  assert.deepEqual(types(moved.view), ["hstack", "if", "header", "foreach", "divider"]);
  assert.deepEqual(moved.path, ["children", 2]);
  // Earlier in its own list, and to its end.
  moved = moveNode(view, ["children", 4], [], 1);
  assert.deepEqual(types(moved.view), ["vstack", "header", "divider", "hstack", "if", "foreach"].slice(1));
  assert.deepEqual(moved.path, ["children", 1]);
  moved = moveNode(view, ["children", 0], []);
  assert.deepEqual(types(moved.view), ["hstack", "if", "foreach", "divider", "header"]);
  assert.deepEqual(moved.path, ["children", 4]);

  // Into a list further on, whose own path changes as the node leaves.
  moved = moveNode(view, ["children", 0], ["children", 1], 1);
  assert.deepEqual(types(moved.view), ["hstack", "if", "foreach", "divider"]);
  assert.deepEqual(moved.path, ["children", 0, "children", 1]);
  assert.equal(nodeAt(moved.view, moved.path).type, "header");
  // Out of a single place and into a list.
  moved = moveNode(view, ["children", 2, "else"], ["children", 2, "then"], 0);
  assert.equal(moved.view.children[2].else, undefined);
  assert.deepEqual(moved.view.children[2].then.children.map(node => node.content), ["Idle", "Busy"]);

  assert.equal(moveNode(view, [], [], 0), undefined);
  assert.equal(moveNode(view, ["children", 1], ["children", 1], 0), undefined);
  assert.equal(moveNode(view, ["children", 2], ["children", 2, "then"], 0), undefined);
  assert.equal(moveNode(view, ["children", 0], ["children", 4], 0), undefined);

  assert.deepEqual(nudgeNode(view, ["children", 0], 1).path, ["children", 1]);
  assert.deepEqual(types(nudgeNode(view, ["children", 0], 1).view).slice(0, 2), ["hstack", "header"]);
  assert.equal(nudgeNode(view, ["children", 0], -1), undefined);
  assert.equal(nudgeNode(view, ["children", 2, "then"], 1), undefined);
});

test("every node type starts as a node kantan accepts", () => {
  assert.deepEqual(NODE_KINDS.flatMap(([, types]) => types).sort(), [...NODE_TYPES].sort());
  for (const type of NODE_TYPES) {
    const { node, problem } = decodeJsonView(newNode(type, "rows"));
    assert.equal(problem, undefined, type);
    assert.equal(node.type, type);
  }
  assert.equal(newNode("foreach", "rows").items, "rows");
  for (const starter of STARTERS) assert.equal(decodeJsonView(starter.view()).problem, undefined, starter.name);
  // Each kind of view has starting points of its own.
  for (const kind of Object.keys(VIEW_KINDS)) assert.ok(STARTERS.filter(starter => starter.kinds.includes(kind)).length >= 3, kind);
});

test("the plugin output schema describes the nodes and fields the engine reads", () => {
  const schema = JSON.parse(readFileSync(new URL("../../schemas/plugin-output.schema.json", import.meta.url), "utf8"));
  const defs = Object.values(schema.$defs).filter(def => def.properties?.type?.const !== undefined);
  assert.deepEqual(defs.map(def => def.properties.type.const).sort(), [...NODE_TYPES].sort());
  for (const def of defs) {
    const type = def.properties.type.const;
    assert.deepEqual(Object.keys(def.properties).filter(key => key !== "type").sort(), [...NODE_FIELDS[type]].sort(), type);
  }
  assert.deepEqual(Object.keys(schema.$defs.CommonNodeProperties.properties).sort(), ["background", "cornerRadius", "frame", "opacity", "padding", "visible"]);
});

test("a module is shared on its own, with the states it shows", async () => {
  // A bundled plugin's module leaves its starting states to the site.
  const plugin = catalog.plugins.caffeine;
  const packed = packModule(plugin.module, plugin.states, "Off", catalog);
  assert.equal(packed.s, undefined);
  assert.equal(packed.b, 1);
  const fragment = await encodeModuleLink(plugin.module, plugin.states, "Off", catalog);
  assert.match(fragment, /^m1\./);
  assert.deepEqual(readFragment(`#${fragment}`), { module: fragment });
  assert.deepEqual(await decodeModuleLink(fragment, catalog), { module: plugin.module, states: plugin.states, shown: "Off" });

  // A module of someone's own carries its states, a view among them.
  const module = {
    name: "mail", type: "command", placement: "right", config: { command: "~/bin/mail", output: "json" },
    interaction: { click: { type: "popup", view: sampleView() } },
  };
  const states = [{ name: "Unread", output: { value: "3", view: { type: "text", content: "{value}" } } }];
  const shared = await decodeModuleLink(await encodeModuleLink(module, states, "Unread", catalog), catalog);
  assert.deepEqual(shared, { module, states });

  // Added to a bar that has a module of its name, it takes another.
  let document = addShared(emptyDocument(), shared);
  assert.equal(document.name, "mail");
  document = addShared(document.document, shared);
  assert.equal(document.name, "mail-2");
  assert.deepEqual(names(document.document), ["mail", "mail-2"]);
  assert.deepEqual(document.document.states["mail-2"], states);
  assert.deepEqual(validateDocument(document.document), []);

  await assert.rejects(decodeModuleLink("1.abc", catalog), /format/);
  await assert.rejects(decodeModuleLink("m1.!!!", catalog), /damaged/);
  await assert.rejects(decodeModuleLink(await encodeLink(emptyDocument(), catalog).then(link => `m${link}`), catalog), /module/);
});

test("a shared theme with flavours is drawn as each of them", () => {
  const paper = { fg: "#000000", bg: "#ffffff", colors: {} }, ink = { fg: "#ffffff", bg: "#000000", colors: {} }, dusk = { fg: "#eeeeee", bg: "#222244", colors: {} };
  const themes = { mine: { defaults: { light: "paper", dark: "ink" }, flavours: { paper, ink, dusk } } };
  const variants = themeVariants({ selection: { light: "mine[paper]", dark: "mine[dusk]" }, themes });
  assert.deepEqual(variants.map(each => [each.label, each.selection, each.dark, each.uses]), [
    ["paper", "mine[paper]", false, ["light"]], ["ink", "mine[ink]", true, []], ["dusk", "mine[dusk]", true, ["dark"]],
  ]);
  // One file holds them all, with the two the bar uses as its defaults.
  const whole = readYaml(variantsYaml(variants, "all")).value;
  assert.deepEqual(whole.defaults, { light: "paper", dark: "dusk" });
  assert.deepEqual(Object.keys(whole.flavours), ["paper", "ink", "dusk"]);
  assert.equal(readYaml(variantsYaml(variants, variants[1].key)).value.bg, ink.bg);

  // A theme without flavours is its light and its dark.
  const plain = themeVariants({ selection: "day", themes: { day: { light: paper, dark: ink } } });
  assert.deepEqual(plain.map(each => [each.key, each.dark]), [["light", false], ["dark", true]]);
  assert.deepEqual(Object.keys(readYaml(variantsYaml(plain, "all")).value), ["light", "dark"]);
});

test("a bar's theme is shared on its own, and another bar takes it", async () => {
  const day = { fg: "#000000", bg: "#ffffff", colors: { red: "#ff0000" } };
  const selection = { light: "day", dark: "catppuccin[mocha]" };
  const document = { ...emptyDocument(), config: { modules: [], theme: selection }, themes: { day, spare: { fg: "#111111", bg: "#eeeeee" } } };
  const fragment = await encodeThemeLink(document, "Day and night");
  assert.deepEqual(readFragment(`#${fragment}`), { theme: fragment });
  assert.deepEqual(readFragment(`#m1.abc~${fragment}`), { module: "m1.abc", theme: fragment });
  const shared = await decodeThemeLink(fragment);
  assert.deepEqual(shared, { selection, themes: { day }, name: "Day and night" });

  // A bar with another theme of that name keeps it.
  const other = { ...emptyDocument(), themes: { day: { fg: "#222222", bg: "#dddddd" } } };
  const taken = withSharedTheme(other, shared);
  assert.deepEqual(taken.config.theme, { light: "day-2", dark: "catppuccin[mocha]" });
  assert.deepEqual(taken.themes, { ...other.themes, "day-2": day });
  await assert.rejects(decodeThemeLink(await encodeLink(emptyDocument(), catalog).then(link => `t${link}`)), /theme/);
});

test("a click's view moves between the config and what the command prints", () => {
  const view = sampleView();
  const module = { name: "m", type: "command", placement: "right", config: { command: "x" }, interaction: { click: { type: "popup", view } } };
  const states = [{ name: "A", output: "plain" }, { name: "B", output: { value: "2" } }];

  // Printed, it is in every state's output, and the command prints JSON.
  const printed = moveView(module, states, view, "output");
  assert.deepEqual(printed.module.interaction.click, { type: "popup" });
  assert.equal(printed.module.config.output, "json");
  assert.deepEqual(printed.states.map(state => state.output), [{ value: "plain", view }, { value: "2", view }]);

  const kept = moveView(printed.module, printed.states, view, "config");
  assert.deepEqual(kept.module.interaction.click, { type: "popup", view });
  assert.deepEqual(kept.states.map(state => state.output), [{ value: "plain" }, { value: "2" }]);

  const script = starterScript(printed.states[1].output);
  assert.match(script, /^#!\/bin\/sh\n/);
  assert.deepEqual(JSON.parse(script.slice(script.indexOf("'JSON'\n") + 7, script.lastIndexOf("\nJSON"))), printed.states[1].output);
  assert.deepEqual(Object.keys(NODE_INFO).sort(), [...NODE_TYPES].sort());
});

test("American and Canadian spelling keep a word's capital and the words around it", () => {
  assert.equal(american("Customise a copy"), "Customize a copy");
  assert.equal(american("Colours of mocha, each flavour centred"), "Colors of mocha, each flavor centered");
  assert.equal(canadian("Customise the colours"), "Customize the colours");
});

test("a masked module moves among the right placement's modules and nowhere else", () => {
  const module = (name, placement, mask) => ({ name, type: "text", placement, ...(mask ? { mask: { name: mask } } : {}) });
  const document = { version: 1, config: { modules: [module("spaces", "left"), module("caffeine", "right"), module("wifi", "right", "WiFi")] } };
  const names = next => next.config.modules.map(each => `${each.name}:${each.placement}`);
  assert.deepEqual(names(placeModule(document, 2, 1)), ["spaces:left", "wifi:right", "caffeine:right"]);
  assert.equal(placeModule(document, 2, 0), document);
  assert.equal(placeAtEdge(document, 2, "left", true), document);
});

test("a link is refused when a name in it would be a file outside the config's directory", async () => {
  const palette = { fg: "#000000", bg: "#ffffff" };
  const config = { modules: [{ name: "x", type: "command", config: { command: "id" } }] };
  for (const name of ["../config", "..", ".", "a/b", "a\\b", "a\u0000b", " a"]) {
    // A theme's link is refused too, or comes without the file.
    const themes = await decodeThemeLink(rawFragment("t1", { k: name, t: { [name]: config } })).then(shared => shared.themes, error => error);
    assert.ok(themes instanceof Error ? /name/.test(themes.message) : Object.keys(themes).length === 0, name);
    await assert.rejects(decodeLink(rawFragment("1", { c: { theme: "day" }, t: { day: palette, [name]: config } }), catalog), /name/, name);
    await assert.rejects(decodeLink(rawFragment("1", { c: {}, t: { day: { flavours: { [name]: palette } } } }), catalog), /name/, name);
    await assert.rejects(decodeLink(rawFragment("1", { c: {}, m: { [`${name}/x.yaml`]: config.modules[0] } }), catalog), /name/, name);
  }
});

test("a theme's link holds only the themes it selects", async () => {
  const day = { fg: "#000000", bg: "#ffffff" };
  const shared = await decodeThemeLink(rawFragment("t1", { k: "day", t: { day, config: { modules: [] }, "not a mapping": 1 } }));
  assert.deepEqual(shared, { selection: "day", themes: { day } });
});

test("files are only written within the config's directory", () => {
  const palette = { fg: "#000000", bg: "#ffffff" };
  const module = { name: "x", type: "text" };
  assert.deepEqual(themeFiles("../config", palette), []);
  assert.deepEqual(themeFiles("..", { flavours: { a: palette } }, "dir"), []);
  assert.deepEqual(themeFiles("mine", { flavours: { "../../config": palette, day: palette } }, "dir").map(file => file.path), ["themes/mine/day.yaml"]);
  const document = {
    ...emptyDocument(),
    config: { theme: { light: "../config", dark: "day" } },
    themes: { "../config": palette, day: palette },
    modulesDir: { "00-x.yaml": module, "../config.yaml": module, "a/b.yaml": module, "notes.txt": module },
  };
  assert.deepEqual(documentFiles(document).map(file => file.path), ["config.yaml", "modules.d/00-x.yaml", "themes/day.yaml"]);
  for (const path of ["themes/../config.yaml", "../config.yaml", "/config.yaml", "themes//day.yaml", "themes/./day.yaml", "themes\\day.yaml", ""]) {
    assert.throws(() => zip([{ path, text: "" }]), /path/, path);
  }
});

test("what kantan's YAML reads as a merge, a number or a value is written quoted", () => {
  const hidden = { interaction: { click: { type: "command", command: "id" } } };
  const document = { ...emptyDocument(), config: { modules: [{ name: "0o17", type: "text", "<<": hidden, config: { text: "=" } }] } };
  const [{ text }] = documentFiles(document);
  assert.match(text, /^ {4}"<<":$/m);
  assert.match(text, /name: "0o17"/);
  assert.match(text, /text: "="/);
  assert.deepEqual(readYaml(text).value, document.config);
  assert.match(themeFiles("mine", { fg: "#000000", bg: "#ffffff", "<<": { colors: {} } })[0].text, /^"<<":$/m);
});

test("a link that inflates to more than a bar could hold is refused", async () => {
  const fragment = rawFragment("1", { c: { style: { fg: "#".repeat(5_000_000) } } });
  assert.ok(fragment.length < 10_000);
  await assert.rejects(decodeLink(fragment, catalog), /more than/);
  await assert.rejects(decodeThemeLink(`t${fragment}`), /more than/);
});

test("a state naming a setting that isn't written as one is drawn as it is", () => {
  const document = {
    ...emptyDocument(),
    config: { modules: [{ name: "x", type: "command", config: { command: "x", output: "json" } }] },
    states: { x: [{ name: "a", output: { value: "{setting(%)} {setting(%E0%A4%A)}" } }] },
  };
  assert.equal(boundDocument(document, catalog).states.x[0].name, "a");
  assert.equal(describeNode({ type: "text", content: "{setting(%)}" }), "settings.%");
});
