// Resolves a document into the bar kantan draws for it: every module's
// icon, text, colours and shape, its tooltip, and what a click opens. Each
// module also has its `placeholders`: the `variables` and `data` a view's
// placeholders read.
import { loadConfig, DEFAULT_ICON_FONT, DEFAULT_TEXT_FONT } from "./config.js";
import { menuRows } from "./menu.js";
import { MENU_BAR, NOTCH, menuBarModules } from "./menubar.js";
import { moduleType } from "./modules/index.js";
import { barGeometry, barLevels, matchedBars } from "./modules/waveform.js";
import { barColor } from "./color.js";
import { noIcons } from "./icons.js";
import { createStyler } from "./style.js";
import { createResolver, fillTooltip } from "./template.js";
import { resolveView } from "./view.js";

const PLACEMENTS = ["left", "notchleft", "center", "notchright", "right"];

// Where a module sits on a screen with or without a notch, or undefined
// when it has no place there: `left|notchleft` names one of each. A screen
// without a notch has the placements beside one too: they meet at the
// bar's centre, around the modules at `center`, and hold the modules whose
// pair names `center` for such a screen.
export function resolvePlacement(raw, notch) {
  const parts = raw.split("|").filter(part => part !== "");
  if (parts.length === 2) {
    const notchPart = parts.find(p => p === "notchleft" || p === "notchright");
    const normalPart = parts.find(p => p === "left" || p === "right" || p === "center");
    if (notch) return notchPart ?? (normalPart === "center" ? undefined : normalPart);
    return normalPart === "center" ? notchPart ?? normalPart : normalPart;
  }
  if (raw === "notchleft" || raw === "notchright") return notch ? raw : undefined;
  if (raw === "center") return notch ? undefined : raw;
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

// The colour between the hex colours `low` and `high`, `fraction` of the
// way from the first.
function blend(low, high, fraction) {
  const channels = hex => [0, 2, 4].map(at => parseInt(hex.replace(/^#/, "").slice(at, at + 2), 16) / 255);
  const [from, to] = [channels(low), channels(high)];
  return from.map((channel, i) => Math.round(Math.min(Math.max(channel + (to[i] - channel) * fraction, 0), 1) * 255)
    .toString(16).padStart(2, "0").toUpperCase()).join("").replace(/^/, "#");
}

// The colour of each of a waveform's `count` bars, or undefined for the
// module's: its palette in order, going round again, or its gradient
// through each of its stops from the first bar to the last. `resolve` turns
// a colour as written into one to draw, or undefined for one it can't,
// which leaves the bars the module's.
function waveformColors(colors, count, resolve) {
  if (!colors) return undefined;
  const drawn = (colors.palette ?? colors.stops).map(resolve);
  if (drawn.some(color => color === undefined || !color.startsWith("#"))) return undefined;
  if (colors.palette) return Array.from({ length: count }, (_, i) => drawn[i % drawn.length]);
  return Array.from({ length: count }, (_, i) => {
    const along = (count > 1 ? i / (count - 1) : 0) * (drawn.length - 1);
    const lower = Math.min(Math.floor(along), drawn.length - 2);
    return blend(drawn[lower], drawn[lower + 1], along - lower);
  });
}

// How many colours a waveform is given: a wave following the sound's tone
// takes a palette's own, each once, and any other as many as it has bars.
function waveformColorCount(waveform, bars) {
  const toned = waveform.style === "wave" && waveform.options?.tone;
  return toned && waveform.colors?.palette ? waveform.colors.palette.length : bars;
}

// A resolved waveform as it is drawn beside the module it follows, once
// that module is `matched` points wide: as many bars as fit that width, or
// as wide itself in a style without bars, and never less than its own. A module out of the bar is
// 0 wide, and leaves the waveform as it is.
export function matchWaveform(waveform, matched) {
  if (waveform.matchWidth === undefined || !(matched > 0)) return waveform;
  if (!barGeometry(waveform.style)) return { ...waveform, width: Math.max(waveform.width, matched) };
  const bars = matchedBars(waveform.bars, matched, waveform.style);
  return {
    ...waveform, bars, levels: barLevels(waveform.bands, bars),
    colors: waveformColors(waveform.shades, bars, color => color),
  };
}

function resolveModule(module, state, config, styler, icons, dark) {
  const model = { name: module.name, type: module.type, hidden: state.hidden };
  if (module.masked) model.masked = true;
  if (state.unsupported !== undefined) return { ...model, unsupported: state.unsupported };
  if (state.open !== undefined) model.open = state.open;
  if (state.workspace) model.workspace = resolveWorkspace(module, state.workspace, config, styler, icons, dark);

  const dynamic = state.style;
  // A waveform is drawn in the colour of the module's icon, in its place.
  if (state.waveform) {
    model.waveform = {
      ...state.waveform, color: styler.iconFg(module, dynamic),
      colors: waveformColors(state.waveform.colors, waveformColorCount(state.waveform, state.waveform.bars), styler.segmentFg),
    };
    // The colours as resolved, for the bars a followed module's width adds.
    if (state.waveform.matchWidth !== undefined && model.waveform.colors) {
      const { palette, stops } = state.waveform.colors;
      model.waveform.shades = palette ? { palette: palette.map(styler.segmentFg) } : { stops: stops.map(styler.segmentFg) };
    }
  }

  const rawIcon = state.icon === "" ? module.icon : state.icon;
  if (rawIcon !== undefined && rawIcon !== "" && !state.workspace && !state.waveform) {
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
      // The icon's outline starts where the one behind it does.
      if (state.backgroundIconLeading && behind && entry) {
        model.icon.shift = ((behind.left ?? 0) - (entry.left ?? 0)) * model.icon.size;
      }
    }
  }

  if (state.value !== "" && !state.workspace) {
    const fg = styler.textFg(module, dynamic);
    const segments = state.segments.length ? state.segments : [{ text: state.value }];
    model.text = segments.map(segment => ({
      text: segment.text, color: styler.segmentFg(segment.fg) ?? fg,
      ...(segment.reveal && module.interaction?.hover?.type === "reveal" ? { reveal: true } : {}),
    }));
    model.textFont = module.textFont ?? config.textFont ?? DEFAULT_TEXT_FONT;
  }

  const shape = state.workspace || state.waveform ? undefined : styler.shape(module, dynamic);
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
  model.placeholders = { variables, data: state.data };

  const { hover, click } = module.interaction ?? {};
  // A module that keeps some of itself hidden until the pointer is over
  // it: the parts its hover lists, or without a list, those its output
  // marks, and its text when the output says nothing of them.
  if (hover?.type === "reveal") {
    // An output that says nothing of what a hover reveals marks nothing.
    const marked = state.revealsIcon !== undefined || state.segments.some(segment => segment.reveal);
    const hides = part => (hover.reveal ? hover.reveal.includes(part) : part === "icon" ? state.revealsIcon === true : !marked);
    model.reveal = true;
    if (hover.persist) model.persist = true;
    if (model.icon && hides("icon")) model.icon.reveal = true;
    if (model.text && hides("text")) model.text = model.text.map(segment => ({ ...segment, reveal: true }));
  }
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
    const model = resolveModule(module, moduleState(module, document, states[module.name], samples[module.name]), config, styler, icons, dark);
    // A module slides in and out as it shows and hides when its transition
    // says so, or without one, when it sits beside the notch.
    if ((module.transition ?? (placement.startsWith("notch") ? "slide" : "none")) === "slide") model.transition = "slide";
    // The icon is at the module's left unless its `iconPosition` says
    // otherwise, or it reveals on hover left of the notch, where the icon
    // stays beside the notch as the rest slides out.
    if ((module.iconPosition ?? (model.reveal && placement === "notchleft" ? "right" : "left")) === "right") model.iconPosition = "right";
    // A module beside a notch gives way to the others on its side when it
    // has a `tuck`, but for a drawer and a module over a menu bar item.
    if (module.tuck && notch && placement.startsWith("notch") && !module.masked && module.type !== "drawer") model.tuck = module.tuck;
    placements[placement].push(model);
  }

  // Without a notch, the first module around the bar's centre to name an
  // anchor has its icon on the centre, at the side `anchor` tells, and the
  // module on that side is `joined` to it at the side facing it: the
  // padding between the two gives way to the room between icon and text.
  if (!notch) {
    const around = ["notchleft", "center", "notchright"].flatMap(placement => placements[placement]);
    const anchors = new Set(config.modules.filter(module => module.anchor === "icon").map(module => module.name));
    const index = around.findIndex(module => anchors.has(module.name));
    if (index >= 0) {
      const trails = around[index].iconPosition === "right";
      around[index].anchor = trails ? "right" : "left";
      const neighbour = around[index + (trails ? 1 : -1)];
      if (neighbour) neighbour.joined = trails ? "left" : "right";
    }
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
  // The centre has no direction to fold in.
  for (const placement of PLACEMENTS.filter(each => each !== "center")) {
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
  // right of the screen, wherever the config places it, and the unmasked
  // modules kantan holds room for in the menu bar sit among them.
  const all = PLACEMENTS.flatMap(placement => placements[placement]);
  const masks = Object.fromEntries(config.modules.filter(module => module.masked).map(module => [module.name, module.mask]));
  const showing = module => !module.masked || !module.hidden;
  const withMask = module => ({ name: module.name, mask: module.masked ? masks[module.name] : undefined });
  const over = menuBarModules({
    right: placements.right.filter(showing).map(withMask),
    strays: all.filter(module => module.masked && !module.hidden && !placements.right.includes(module)).map(withMask),
    slots: config.menuBarSlots !== false,
  }, menuBar);
  for (const each of over) {
    const module = all.find(module => module.name === each.name);
    if (each.width !== undefined) module.slot = { width: each.width };
    if (each.fixed) module.fixed = true;
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
    gaps: config.gaps,
    placements,
    menuBar: { trailing: over.some(each => each.width !== undefined) ? menuBar.trailing : 0, modules: over.map(each => each.name) },
  };
  if (notch) bar.notch = NOTCH;
  if (config.problem !== undefined) bar.problem = config.problem;
  return bar;
}
