// Resolves a document into the bar kantan draws for it: every module's
// icon, text, colours and shape, its tooltip, and what a click opens.
import { loadConfig, DEFAULT_ICON_FONT, DEFAULT_TEXT_FONT } from "./config.js";
import { menuRows } from "./menu.js";
import { MENU_BAR, NOTCH, menuBarSlots } from "./menubar.js";
import { moduleType } from "./modules/index.js";
import { barColor } from "./color.js";
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
// or its first, made from that state's output, or from `sample` when the
// caller has a reading of its own.
function moduleState(module, document, chosen, sample) {
  const states = document.states?.[module.name] ?? [];
  const picked = states.find(state => state.name === chosen) ?? states[0];
  return moduleType(module.type).state(module.loaded, sample ?? picked?.output, module);
}

// The workspace module's segments as drawn: each an icon the fonts have at
// the text's size, scaled, or its label in the text's font. A segment that
// isn't the active one is faded.
function resolveWorkspace(module, display, config, styler, icons, dark) {
  const textFont = module.textFont ?? config.textFont;
  const fg = styler.textFg(module, undefined);
  const glyph = name => {
    const entry = icons(name);
    return entry
      ? { name, glyph: entry.char, font: entry.font, size: Math.round((textFont?.size ?? 14) * entry.scale) }
      : { name, text: name, font: (textFont ?? DEFAULT_TEXT_FONT).name, size: (textFont ?? DEFAULT_TEXT_FONT).size, weight: (textFont ?? DEFAULT_TEXT_FONT).weight };
  };
  const segment = ({ id, icon, active, color, target }) => {
    const drawn = { id, ...glyph(icon), active, color: color !== undefined && !styler.native ? barColor(styler.resolve(color)) : fg, opacity: active ? 1 : 0.4 };
    if (target !== undefined) drawn.target = target;
    return drawn;
  };

  // An overflow's indicator: in its own style's colour, or faded like an
  // inactive segment.
  const { overflow } = module.loaded;
  const own = (dark ? overflow.style?.dark : overflow.style?.light)?.fg;
  const resolved = own === undefined ? undefined : styler.resolve(own);
  const ownColor = resolved === undefined || resolved.startsWith("{theme(") ? undefined : barColor(resolved);
  const indicator = name => ({ ...glyph(name), ...(ownColor === undefined ? { color: fg, opacity: 0.4 } : { color: ownColor, opacity: 1 }) });

  const workspace = {
    scroll: display.scroll,
    activates: module.loaded.activates && module.interaction?.click === undefined,
    segments: display.segments.map(segment),
    pips: display.pips.map(segment),
  };
  if (display.slot) workspace.slot = segment(display.slot);
  if (overflow.showIcon && display.before) workspace.before = indicator(overflow.left);
  if (overflow.showIcon && display.after) workspace.after = indicator(overflow.right);
  return workspace;
}

function resolveModule(module, state, config, styler, icons, dark) {
  const model = { name: module.name, type: module.type, hidden: state.hidden };
  if (module.masked) model.masked = true;
  if (state.unsupported !== undefined) return { ...model, unsupported: state.unsupported };
  if (state.open !== undefined) model.open = state.open;
  if (state.workspace) model.workspace = resolveWorkspace(module, state.workspace, config, styler, icons, dark);

  const dynamic = state.style;
  const rawIcon = state.icon === "" ? module.icon : state.icon;
  if (rawIcon !== undefined && rawIcon !== "" && !state.workspace) {
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
    // An icon drawn faintly behind the module's own, in its font and size.
    if (state.backgroundIcon !== undefined) {
      const behind = icons(state.backgroundIcon);
      model.icon.background = behind
        ? { name: state.backgroundIcon, glyph: behind.char }
        : { name: state.backgroundIcon, text: state.backgroundIcon };
    }
  }

  if (state.value !== "" && !state.workspace) {
    const fg = styler.textFg(module, dynamic);
    const segments = state.segments.length ? state.segments : [{ text: state.value }];
    model.text = segments.map(segment => ({ text: segment.text, color: styler.segmentFg(segment.fg) ?? fg }));
    model.textFont = module.textFont ?? config.textFont ?? DEFAULT_TEXT_FONT;
  }

  const shape = state.workspace ? undefined : styler.shape(module, dynamic);
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
// state each module shows (`states`, by module name), readings that stand
// in for a module's state (`samples`, by module name: the time, say, or
// which workspace is active), the `icons` lookup, the theme files kantan
// bundles (`themes`), whether the screen has a `notch`, and the system's
// menu bar items that masked modules sit over (`menuBar`). The modules are
// listed for each placement, as they sit from left to right. A screen with
// a notch gives the bar its `notch`, the size of the camera housing. The
// bar's `gaps` are the room left between it and the screen's top, left
// and right edges, and its `blur` how far its background lets what is
// behind it through: 0 for not at all, then 1, the most, to 6.
export function resolveBar(document, { dark = false, states = {}, samples = {}, icons = noIcons, themes = {}, notch = false, menuBar = MENU_BAR } = {}) {
  const config = loadConfig(document, themes);
  const styler = createStyler(config, dark);

  const placements = Object.fromEntries(PLACEMENTS.map(placement => [placement, []]));
  for (const module of config.modules) {
    const placement = resolvePlacement(module.placement, notch);
    if (!Object.hasOwn(placements, placement ?? "")) continue;
    placements[placement].push(
      resolveModule(module, moduleState(module, document, states[module.name], samples[module.name]), config, styler, icons, dark));
  }

  // Each side of the screen has one drawer, the first drawer module placed
  // there, and is open when that module is.
  const side = placement => (placement.includes("right") ? "right" : "left");
  const open = {};
  for (const placement of PLACEMENTS) {
    const drawer = placements[placement].find(module => module.type === "drawer");
    if (drawer && open[side(placement)] === undefined) open[side(placement)] = drawer.open === true;
  }

  // Within a placement, the modules on the far side of its drawer from the
  // screen's centre fold away with it while their side's drawer is closed.
  for (const placement of PLACEMENTS) {
    const modules = placements[placement];
    const drawer = modules.findIndex(module => module.type === "drawer");
    if (drawer < 0) continue;
    const rightToLeft = placement === "right" || placement === "notchleft";
    modules.forEach((module, i) => {
      if (rightToLeft ? i < drawer : i > drawer) {
        module.inDrawer = true;
        module.folded = !open[side(placement)];
      }
    });
  }

  // A masked module that is showing takes its menu bar item's place at the
  // right of the screen, wherever the config places it.
  const all = PLACEMENTS.flatMap(placement => placements[placement]);
  const masks = Object.fromEntries(config.modules.filter(module => module.masked).map(module => [module.name, module.mask]));
  const slots = menuBarSlots(
    all.filter(module => module.masked && !module.hidden).map(module => ({ name: module.name, mask: masks[module.name] })),
    menuBar);
  for (const slot of slots) all.find(module => module.name === slot.name).slot = { width: slot.width };

  const bar = {
    native: styler.native,
    fg: styler.barFg,
    bg: styler.barBg,
    height: config.height,
    padding: config.padding,
    iconTextSpacing: config.iconTextSpacing,
    cornerRadius: config.cornerRadius,
    blur: config.blur,
    gaps: config.gaps,
    placements,
    menuBar: { trailing: slots.length ? menuBar.trailing : 0, modules: slots.map(slot => slot.name) },
  };
  if (notch) bar.notch = NOTCH;
  if (config.problem !== undefined) bar.problem = config.problem;
  return bar;
}
