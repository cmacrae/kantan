// The workspace module: a segment for each workspace, or for each window
// of the active workspace's scrolling layout. Its sample is
// `{ workspaces: [{ index, label, active, hasWindows, scroll }] }` as a
// window manager reports them, in display order. `index` defaults to the
// workspace's position and `label` to its number; `scroll` lists the
// windows of a scrolling layout as `{ id, app, bundleIdentifier, selected }`.
import { plainState } from "../output.js";
import { parseStyle } from "../style.js";
import { bool, dict, int, list, str } from "../values.js";
import { iconList, stringEntries } from "./levels.js";

const U64 = (1n << 64n) - 1n;

// `colors` in an order that depends only on the number of workspaces, one
// for each workspace, with no two neighbours alike when cycling through
// them: a Fisher-Yates shuffle seeded by the count.
export function shuffledRainbow(colors, spaceCount) {
  if (colors.length <= 1) return colors.slice();
  const shuffled = colors.slice();
  let rng = BigInt.asUintN(64, BigInt(spaceCount));
  for (let i = shuffled.length - 1; i >= 1; i--) {
    rng = (rng * 6364136223846793005n + 1442695040888963407n) & U64;
    const j = Number((rng >> 33n) % BigInt(i + 1));
    [shuffled[i], shuffled[j]] = [shuffled[j], shuffled[i]];
  }
  if (spaceCount <= shuffled.length) return shuffled;
  const result = shuffled.slice();
  while (result.length < spaceCount) {
    const last = result.at(-1);
    const start = result.length % shuffled.length;
    let next = shuffled[start];
    for (let offset = 1; next === last && offset < shuffled.length; offset++) {
      next = shuffled[(start + offset) % shuffled.length];
    }
    result.push(next);
  }
  return result;
}

// The FNV-1a hash of `text`'s UTF-8 bytes, which picks an app's colour.
function fnv1a(text) {
  let hash = 14695981039346656037n;
  for (const byte of new TextEncoder().encode(text)) {
    hash = ((hash ^ BigInt(byte)) * 1099511628211n) & U64;
  }
  return hash;
}

function parseOverflow(value) {
  const overflow = dict(value);
  if (!overflow) return { enabled: false, max: 5, showIcon: true, left: "‹", right: "›" };
  const icon = overflow.icon;
  const sides = icon === false ? { showIcon: false, left: "", right: "" }
    : typeof icon === "string" ? { showIcon: true, left: icon, right: icon }
    : { showIcon: true, left: str(dict(icon)?.left) ?? "‹", right: str(dict(icon)?.right) ?? "›" };
  return { enabled: bool(overflow.enabled) ?? false, max: int(overflow.max) ?? 5, style: parseStyle(overflow.style), ...sides };
}

function parseScrolling(value, palette) {
  const scrolling = dict(value);
  if (!scrolling) return { enabled: false, icon: "rectangle-vertical-filled", icons: {}, workspaces: true, rainbow: [] };
  const rainbow = dict(scrolling.rainbow);
  const icons = {};
  // Of keys alike but for their case, the first in order stands.
  for (const [app, icon] of Object.entries(stringEntries(scrolling.icons)).sort(([a], [b]) => (a < b ? -1 : 1))) {
    if (!Object.hasOwn(icons, app.toLowerCase())) icons[app.toLowerCase()] = icon;
  }
  return {
    enabled: bool(scrolling.enabled) ?? false,
    icon: str(scrolling.icon) ?? "rectangle-vertical-filled",
    icons,
    workspaces: bool(scrolling.workspaces) ?? true,
    rainbow: rainbow?.enabled === true ? iconList(rainbow.colors, palette) : [],
  };
}

export default {
  load(config) {
    const rainbow = dict(config?.rainbow);
    const colors = iconList(rainbow?.colors, []);
    const type = str(config?.type);
    return {
      // Only AeroSpace and Rift can switch workspace when asked.
      activates: type === "aerospace" || type === "rift",
      icons: iconList(config?.icons, []),
      rainbow: { enabled: bool(rainbow?.enabled) ?? false, random: bool(rainbow?.random) ?? true, colors },
      overflow: parseOverflow(config?.overflow),
      scrolling: parseScrolling(config?.scrolling, colors),
    };
  },

  // The state holds the module's `workspace` display: its `segments`, each
  // with the `icon` to resolve, whether it is `active`, the rainbow's
  // `color` for it and the `target` a click switches to; whether they are
  // a `scroll`'s windows; the `pips` and `slot` shown beside a scroll; and
  // whether segments lie `before` and `after` the page of an overflow.
  state(loaded, sample, module) {
    const spaces = (list(sample?.workspaces) ?? []).filter(dict).map((space, position) => ({
      index: int(space.index) ?? position,
      label: str(space.label) ?? String((int(space.index) ?? position) + 1),
      active: space.active === true,
      hasWindows: space.hasWindows === true,
      scroll: list(space.scroll)?.filter(dict).map(window => ({
        id: str(window.id) ?? "", app: str(window.app) ?? "",
        bundleIdentifier: str(window.bundleIdentifier), selected: window.selected === true,
      })),
    }));

    const { rainbow, scrolling, overflow } = loaded;
    const palette = rainbow.enabled && rainbow.colors.length
      ? (rainbow.random ? shuffledRainbow(rainbow.colors, spaces.length) : rainbow.colors)
      : undefined;
    const color = space => palette?.[((space.index % palette.length) + palette.length) % palette.length];

    const segments = spaces.map(space => ({
      id: `workspace-${space.index}`,
      icon: space.index >= 0 && space.index < loaded.icons.length ? loaded.icons[space.index]
        : module?.icon ? module.icon : space.label,
      active: space.active,
      color: color(space),
      target: space.active ? undefined : { workspace: space.index, label: space.label },
    }));

    const display = { segments, scroll: false, pips: [], slot: undefined };
    const active = spaces.find(space => space.active);
    if (scrolling.enabled && active?.scroll?.length) {
      display.scroll = true;
      display.segments = active.scroll.map(window => {
        const app = window.bundleIdentifier ?? window.app;
        const own = scrolling.rainbow.length
          ? scrolling.rainbow[Number(fnv1a(app.toLowerCase()) % BigInt(scrolling.rainbow.length))]
          : undefined;
        const lookup = key => (key !== undefined && Object.hasOwn(scrolling.icons, key.toLowerCase())
          ? scrolling.icons[key.toLowerCase()] : undefined);
        return {
          id: `window-${window.id}`,
          icon: lookup(window.bundleIdentifier) ?? lookup(window.app) ?? scrolling.icon,
          active: window.selected,
          color: own ?? color(active),
          target: { window: window.id },
        };
      });
      const pips = segments.filter((_, i) => spaces[i].hasWindows || spaces[i].active);
      display.pips = scrolling.workspaces && pips.length > 1 ? pips : [];
      display.slot = segments[spaces.indexOf(active)];
    }

    // An overflow shows one page of segments: the one holding the active.
    display.before = false;
    display.after = false;
    if (overflow.enabled && overflow.max > 0 && display.segments.length > overflow.max) {
      const at = Math.max(0, display.segments.findIndex(segment => segment.active));
      const start = Math.trunc(at / overflow.max) * overflow.max;
      const end = Math.min(start + overflow.max, display.segments.length);
      display.before = start > 0;
      display.after = end < display.segments.length;
      display.segments = display.segments.slice(start, end);
    }

    return { ...plainState(""), workspace: display };
  },
};
