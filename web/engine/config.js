// Loads a document's config as kantan loads its files: config.yaml, the
// modules in modules.d and the theme they select.
import { moduleType } from "./modules/index.js";
import { parseStyle } from "./style.js";
import { loadTheme } from "./theme.js";
import { parseTuck } from "./tuck.js";
import { bool, dict, int, list, num, str } from "./values.js";
import { decodeYamlView } from "./view.js";

// A font descriptor, `Name:Size` or `Name:Weight:Size`, with `system:` in
// front for a font the system has installed.
const WEIGHTS = {
  ultralight: 100, thin: 200, light: 300, regular: 400, medium: 500,
  semibold: 600, "demi-bold": 600, bold: 700, heavy: 800, extrabold: 800, black: 900,
};

export function parseFont(raw) {
  const system = raw.startsWith("system:");
  const parts = (system ? raw.slice("system:".length) : raw).split(":");
  const number = text => (text.trim() !== "" && Number.isFinite(Number(text)) ? Number(text) : undefined);
  const sizeOnly = parts.length === 2 ? number(parts[1]) : undefined;
  return {
    name: parts[0],
    system,
    weight: parts.length > 1 && sizeOnly === undefined ? WEIGHTS[parts[1].toLowerCase()] ?? 400 : 400,
    size: parts.length === 2 ? sizeOnly ?? 14 : parts.length > 2 ? number(parts[2]) ?? 14 : 14,
  };
}

const DEFAULT_TEXT_FONT = parseFont("system:Helvetica Neue:13");
const DEFAULT_ICON_FONT = parseFont("tabler-icons:regular:15");

// The icon a module type shows when its config names none.
const DEFAULT_ICONS = { focus: "brain" };

function parseHover(value) {
  if (!dict(value)) return undefined;
  return {
    type: str(value.type) ?? "tooltip",
    content: str(value.content),
    // The parts a `reveal` hover hides until then: a list of them, or one.
    reveal: (list(value.reveal)?.filter(part => typeof part === "string") ?? (str(value.reveal) === undefined ? undefined : [value.reveal]))
      ?.filter(part => part === "icon" || part === "text"),
    persist: bool(value.persist) ?? false,
    view: value.view == null ? undefined : decodeYamlView(value.view),
  };
}

// One module's config, or undefined when kantan would leave the module out:
// without a name, placement and type, of a type it doesn't have, or with a
// `config` block its type rejects.
function parseModule(yaml) {
  const name = str(yaml?.name), placement = str(yaml?.placement), type = str(yaml?.type);
  if (name === undefined || placement === undefined || type === undefined) return undefined;
  const implementation = moduleType(type);
  if (!implementation) return undefined;

  const module = {
    name, placement, type,
    icon: str(yaml.icon) ?? DEFAULT_ICONS[type],
    textFont: str(yaml.fonts?.text) === undefined ? undefined : parseFont(yaml.fonts.text),
    iconFont: str(yaml.fonts?.icon) === undefined ? undefined : parseFont(yaml.fonts.icon),
    style: parseStyle(yaml.style),
    transition: ["slide", "none"].includes(yaml.transition) ? yaml.transition : undefined,
    iconPosition: ["left", "right"].includes(yaml.iconPosition) ? yaml.iconPosition : undefined,
    anchor: yaml.anchor === "icon" ? "icon" : undefined,
    tuck: parseTuck(yaml.tuck),
  };

  const clickType = str(yaml.interaction?.click?.type);
  if (dict(yaml.interaction)) {
    const click = dict(yaml.interaction.click);
    module.interaction = {
      hover: parseHover(yaml.interaction.hover),
      click: click && {
        type: clickType ?? "menu",
        view: click.view == null ? undefined : decodeYamlView(click.view),
      },
    };
  }

  // A masked module passes its clicks to the menu bar item it covers,
  // unless the config says otherwise. A drawer's click opens and closes it,
  // whatever the config says.
  if (dict(yaml.mask) && (int(yaml.mask.index) !== undefined || str(yaml.mask.name) !== undefined)) {
    module.masked = true;
    module.mask = { name: str(yaml.mask.name), index: int(yaml.mask.index) };
  }
  if (dict(yaml.mask) && clickType === undefined) {
    module.interaction = { hover: parseHover(yaml.interaction?.hover), click: { type: "passthrough" } };
  }
  if (type === "drawer") {
    module.interaction = { hover: parseHover(yaml.interaction?.hover), click: { type: "drawer" } };
  }

  module.loaded = implementation.load(yaml.config ?? null);
  return module.loaded === undefined ? undefined : module;
}

const unique = modules => {
  const names = new Set();
  return modules.filter(module => !names.has(module.name) && names.add(module.name));
};

const isRightSide = module => module.placement.includes("right");

const WELCOME_MODULES = [
  { name: "welcome", placement: "notchleft|left", type: "text", icon: "mood-smile-beam", loaded: { value: "Welcome to kantan!" } },
  {
    name: "setup-hint", placement: "notchright|right", type: "text", icon: "file-smile",
    loaded: { value: "Populate and customise your bar by writing a config file" },
  },
];

// The bar kantan shows until a config that fails to load is fixed.
function errorConfig(problem) {
  return {
    problem,
    native: true, style: undefined, theme: undefined,
    height: 33, padding: 10, iconTextSpacing: 4, cornerRadius: 0, blur: 0,
    gaps: { top: 0, left: 0, right: 0 },
    textFont: undefined, iconFont: undefined,
    modules: [
      {
        name: "config-error", placement: "notchleft|left", type: "text", icon: "alert-triangle",
        loaded: { value: "config.yaml isn't a valid configuration" },
      },
      {
        name: "config-error-hint", placement: "notchright|right", type: "text", icon: "file-alert",
        loaded: { value: "Fix it and save to reload" },
      },
    ],
  };
}

// The config a document's files load to. `bundledThemes` are the theme
// files kantan ships, which the document's own themes come before. A config
// kantan would refuse loads as the bar it shows instead, with `problem`
// saying why.
export function loadConfig(document, bundledThemes = {}) {
  const yaml = dict(document.config) ?? {};

  let theme;
  if (typeof yaml.theme === "string" || dict(yaml.theme)) {
    theme = loadTheme(yaml.theme, { ...bundledThemes, ...document.themes });
    if (!theme) return errorConfig("The theme can't be loaded");
  }

  // Without a style, a theme's palettes give the bar its colours. Without
  // either, the bar takes the system's.
  let style = parseStyle(yaml.style);
  if (!style && theme) {
    style = { light: { fg: theme.light.fg, bg: theme.light.bg }, dark: { fg: theme.dark.fg, bg: theme.dark.bg } };
  } else if (!style && dict(yaml.style)) {
    return errorConfig("style.light and style.dark must have fg and bg");
  }
  if (!theme && style) {
    const complete = mode => mode?.fg !== undefined && mode?.bg !== undefined;
    if (!complete(style.light) || !complete(style.dark)) {
      return errorConfig("A style without a theme needs light and dark, each with fg and bg");
    }
  }

  const clamp = (value, min, max, fallback) => (value === undefined ? fallback : Math.max(min, Math.min(max, value)));
  const base = unique((list(yaml.modules) ?? []).map(parseModule).filter(Boolean));
  const files = Object.keys(dict(document.modulesDir) ?? {})
    .filter(name => name.endsWith(".yaml") || name.endsWith(".yml"))
    .sort();
  const extra = unique([...base, ...files.map(name => parseModule(document.modulesDir[name])).filter(Boolean)])
    .slice(base.length);

  // The modules of config.yaml sit at the screen's edges, with those of
  // modules.d inside them.
  const modules = [
    ...base.filter(m => !isRightSide(m)), ...extra.filter(m => !isRightSide(m)),
    ...extra.filter(isRightSide), ...base.filter(isRightSide),
  ];

  return {
    theme,
    style,
    native: !theme && style?.light?.fg === undefined && style?.dark?.fg === undefined,
    height: int(yaml.height) ?? 33,
    padding: int(yaml.padding) ?? 10,
    iconTextSpacing: int(yaml.iconTextSpacing) ?? 5,
    cornerRadius: clamp(num(yaml.cornerRadius), 0, Infinity, 0),
    blur: clamp(int(yaml.blur), 0, 6, 0),
    gaps: {
      top: Math.max(0, int(yaml.gaps?.top) ?? 0),
      left: Math.max(0, int(yaml.gaps?.left) ?? 0),
      right: Math.max(0, int(yaml.gaps?.right) ?? 0),
    },
    textFont: str(yaml.fonts?.text) === undefined ? undefined : parseFont(yaml.fonts.text),
    iconFont: str(yaml.fonts?.icon) === undefined ? undefined : parseFont(yaml.fonts.icon),
    menuBarSlots: typeof yaml.menuBarSlots === "boolean" ? yaml.menuBarSlots : true,
    modules: modules.length ? modules : WELCOME_MODULES,
  };
}

export { DEFAULT_ICON_FONT, DEFAULT_TEXT_FONT };
