// kantan's styles: the bar's and each module's `style`, and the order a
// module's colours and shape resolve in.
import { barColor } from "./color.js";
import { resolveThemeTemplate } from "./theme.js";
import { dict, str } from "./values.js";

export const SHAPES = ["pill", "box", "underline", "overline"];

// One appearance's style, or undefined when it sets nothing.
function parseStyleMode(value) {
  const style = dict(value);
  if (!style) return undefined;
  const mode = {
    fg: str(style.fg),
    bg: str(style.bg),
    text: dict(style.text) && { fg: str(style.text.fg) },
    icon: dict(style.icon) && { fg: str(style.icon.fg) },
    shape: SHAPES.includes(style.shape) ? style.shape : undefined,
  };
  return Object.values(mode).some(v => v !== undefined) ? mode : undefined;
}

// A `style` block: `light` and `dark` styles, or one flat style for both.
export function parseStyle(value) {
  if (!dict(value)) return undefined;
  const light = parseStyleMode(value.light), dark = parseStyleMode(value.dark);
  if (light || dark) return { light, dark };
  const flat = parseStyleMode(value);
  return flat && { light: flat, dark: flat };
}

// The style a plugin's output or a module's state overrides the module's
// with. A shape it doesn't know is ignored, and `none` removes the shape.
export function parseDynamicStyle(style) {
  if (!dict(style)) return undefined;
  const dynamic = {
    fg: str(style.fg),
    bg: str(style.bg),
    iconFg: stringMap(style.icon)?.fg,
    textFg: stringMap(style.text)?.fg,
    shape: style.shape === "none" || SHAPES.includes(style.shape) ? style.shape : undefined,
  };
  return Object.values(dynamic).some(v => v !== undefined) ? dynamic : undefined;
}

// `value` when it is a mapping of strings alone.
function stringMap(value) {
  return dict(value) && Object.values(value).every(v => typeof v === "string") ? value : undefined;
}

// Resolves a module's colours and shape for one appearance of `config`, a
// loaded config: `theme` its palettes, `style` its parsed style.
export function createStyler(config, dark) {
  const palette = config.theme && (dark ? config.theme.dark : config.theme.light);
  const native = config.native;
  const globalMode = (dark ? config.style?.dark ?? config.style?.light : config.style?.light ?? config.style?.dark)
    ?? { fg: "FFFFFF", bg: "000000" };

  const resolve = value => (palette ? resolveThemeTemplate(value, palette) : value);
  const color = value => barColor(resolve(value));
  // A theme template with no palette to resolve it.
  const unresolvable = value => !palette && value.startsWith("{theme(") && value.endsWith(")}");
  const first = values => values.find(v => v !== undefined);

  const moduleMode = style => (dark ? style?.dark : style?.light);

  // An element's colour: the plugin's for the element, the plugin's `fg`,
  // then the module's for the element, the module's `fg`, and the bar's.
  const elementFg = (module, dynamic, element, dynamicKey) => {
    const override = [dynamic?.[dynamicKey], dynamic?.fg].find(v => v !== undefined && !unresolvable(v));
    if (override !== undefined) return color(override);
    if (native) return "label";
    const mode = moduleMode(module.style);
    return color(first([mode?.[element]?.fg, mode?.fg, globalMode[element]?.fg, globalMode.fg]) ?? "FFFFFF");
  };

  const shape = (module, dynamic) => {
    if (dynamic?.shape === "none") return undefined;
    return dynamic?.shape ?? moduleMode(module.style)?.shape;
  };

  return {
    native,
    palette,
    resolve,

    // The bar's own colours: the system's when native.
    barFg: native ? "label" : color(globalMode.fg ?? "FFFFFF"),
    barBg: native ? "clear" : color(globalMode.bg ?? "000000"),

    iconFg: (module, dynamic) => elementFg(module, dynamic, "icon", "iconFg"),
    textFg: (module, dynamic) => elementFg(module, dynamic, "text", "textFg"),

    // A value segment's own colour, or undefined to take the text's. The
    // native appearance colours every segment alike.
    segmentFg: fg => (fg !== undefined && !native && !unresolvable(fg) ? color(fg) : undefined),

    shape,

    // The colour of the module's shape: the plugin's, the module's, the
    // palette's shape colour, then the bar's background.
    bg(module, dynamic) {
      if (dynamic?.bg !== undefined && dynamic.bg !== "" && !unresolvable(dynamic.bg)) return color(dynamic.bg);
      if (native) return "clear";
      const mode = moduleMode(module.style);
      if (mode?.bg !== undefined) return color(mode.bg);
      if (shape(module, dynamic) !== undefined && palette?.shape !== undefined) return barColor(palette.shape);
      return color(globalMode.bg ?? "000000");
    },
  };
}
