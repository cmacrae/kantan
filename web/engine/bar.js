// Resolves a document into the bar kantan draws for it: every module's
// icon, text, colours and shape, its tooltip, and what a click opens.
import { loadConfig, DEFAULT_ICON_FONT, DEFAULT_TEXT_FONT } from "./config.js";
import { menuRows } from "./menu.js";
import { moduleType } from "./modules/index.js";
import { noIcons } from "./icons.js";
import { createStyler } from "./style.js";
import { createResolver, fillTooltip } from "./template.js";
import { resolveView } from "./view.js";

const PLACEMENTS = ["left", "notchleft", "notchright", "right"];

// Where a module sits on a screen with or without a notch, or undefined
// when it has no place there: `left|notchleft` names one of each.
function resolvePlacement(raw, notch) {
  const parts = raw.split("|").filter(part => part !== "");
  if (parts.length === 2) {
    const notchPart = parts.find(p => p === "notchleft" || p === "notchright");
    const normalPart = parts.find(p => p === "left" || p === "right");
    return notch ? notchPart ?? normalPart : normalPart;
  }
  if (raw === "notchleft" || raw === "notchright") return notch ? raw : undefined;
  return raw;
}

// The state `module` shows: the one of its document states `chosen` names,
// or its first.
function moduleState(module, document, chosen) {
  const states = document.states?.[module.name] ?? [];
  const picked = states.find(state => state.name === chosen) ?? states[0];
  return moduleType(module.type).state(module.loaded, picked?.output);
}

function resolveModule(module, state, config, styler, icons) {
  const model = { name: module.name, type: module.type, hidden: state.hidden };
  if (module.masked) model.masked = true;

  const dynamic = state.style;
  const rawIcon = state.icon === "" ? module.icon : state.icon;
  if (rawIcon !== undefined && rawIcon !== "") {
    const base = module.iconFont ?? config.iconFont ?? DEFAULT_ICON_FONT;
    const entry = icons(rawIcon);
    // An icon the fonts have is drawn in its own font, scaled. Anything else
    // is drawn as written, in the font the config names for icons.
    model.icon = {
      ...(entry
        ? { name: rawIcon, glyph: entry.char, font: entry.font, size: Math.round(base.size * entry.scale) }
        : { name: rawIcon, text: rawIcon, font: base.name, size: base.size }),
      color: styler.iconFg(module, dynamic),
      opacity: state.active ? 1 : 0.4,
    };
  }

  if (state.value !== "") {
    const fg = styler.textFg(module, dynamic);
    const segments = state.segments.length ? state.segments : [{ text: state.value }];
    model.text = segments.map(segment => ({ text: segment.text, color: styler.segmentFg(segment.fg) ?? fg }));
    model.textFont = module.textFont ?? config.textFont ?? DEFAULT_TEXT_FONT;
  }

  const shape = styler.shape(module, dynamic);
  if (shape !== undefined) {
    model.shape = shape;
    model.bg = styler.bg(module, dynamic);
  }

  // What a view's placeholders resolve from: the module's variables, its
  // value and icon, and the theme's colours.
  const glyph = model.icon?.glyph ?? model.icon?.text;
  const variables = { ...state.variables, value: state.value, ...(glyph === undefined ? {} : { icon: glyph }) };
  const resolver = createResolver({ variables, data: state.data, theme: key => styler.resolve(`{${key}}`) });
  const context = { resolver, native: styler.native, fg: styler.native ? "primary" : styler.barFg, icons };

  const { hover, click } = module.interaction ?? {};
  if (hover?.type === "tooltip") {
    model.tooltip = hover.view
      ? { view: resolveView(hover.view, context) }
      : { text: fillTooltip(hover.content ?? "{value}", { value: state.value, icon: glyph, variables: state.variables }) };
  }

  const view = click?.view ?? state.view;
  switch (click?.type) {
    case undefined:
      break;
    case "menu":
      if (view) model.click = { type: "menu", rows: menuRows(view, resolver, icons), fg: styler.native ? undefined : styler.barFg };
      break;
    case "popup":
      if (view) model.click = { type: "popup", view: resolveView(view, context) };
      break;
    case "toggle":
    case "complete": {
      const command = moduleType(module.type).toggle?.(module.loaded);
      if (command) model.click = { type: "toggle", command };
      break;
    }
    default:
      model.click = { type: click.type };
  }
  if (state.viewProblem !== undefined) model.viewProblem = state.viewProblem;
  return model;
}

// The bar a document draws. `options` are the appearance (`dark`), the
// state each module shows (`states`, by module name), the `icons` lookup,
// the theme files kantan bundles (`themes`) and whether the screen has a
// `notch`. The modules are listed for each placement, as they sit from
// left to right.
export function resolveBar(document, { dark = false, states = {}, icons = noIcons, themes = {}, notch = false } = {}) {
  const config = loadConfig(document, themes);
  const styler = createStyler(config, dark);

  const placements = Object.fromEntries(PLACEMENTS.map(placement => [placement, []]));
  for (const module of config.modules) {
    const placement = resolvePlacement(module.placement, notch);
    if (!Object.hasOwn(placements, placement ?? "")) continue;
    const model = moduleType(module.type)
      ? resolveModule(module, moduleState(module, document, states[module.name]), config, styler, icons)
      : { name: module.name, type: module.type, hidden: false, unsupported: `${module.type} module` };
    placements[placement].push(model);
  }

  // Within a placement, the modules on the far side of its drawer from the
  // screen's centre fold away with it.
  for (const placement of PLACEMENTS) {
    const modules = placements[placement];
    const drawer = modules.findIndex(module => module.type === "drawer");
    if (drawer < 0) continue;
    const rightToLeft = placement === "right" || placement === "notchleft";
    modules.forEach((module, i) => {
      if (rightToLeft ? i < drawer : i > drawer) module.inDrawer = true;
    });
  }

  const bar = {
    native: styler.native,
    fg: styler.barFg,
    bg: styler.barBg,
    height: config.height,
    padding: config.padding,
    iconTextSpacing: config.iconTextSpacing,
    cornerRadius: config.cornerRadius,
    blur: config.blur,
    placements,
  };
  if (config.problem !== undefined) bar.problem = config.problem;
  return bar;
}
