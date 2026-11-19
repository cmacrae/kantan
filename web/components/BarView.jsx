// Draws a bar the engine resolved, as kantan draws it: each module's icon,
// value and shape, the tooltip it shows under the pointer, and the menu or
// popup a click opens.
import { useEffect, useLayoutEffect, useRef, useState } from "react";
import { OVERLAP_MARGIN, matchWaveform, resolveOverlap, resolveTuck, tuckHides } from "../engine/index.js";
import { Glyph } from "./Glyph.jsx";
import { Menu } from "./Menu.jsx";
import { Unsupported } from "./Unsupported.jsx";
import { ViewTree } from "./ViewTree.jsx";
import { Waveform } from "./Waveform.jsx";
import { cssColor, faded, fontFamily, SYSTEM_FONT } from "./system.js";

// The translucent materials macOS draws behind the native bar and behind
// menus, popups and tooltips.
const BAR_MATERIAL = ["rgba(253,253,255,0.68)", "rgba(28,28,32,0.68)"];
const PANEL_MATERIAL = ["rgb(246,246,246)", "rgb(40,40,42)"];
const PANEL_SHADOW = dark =>
  `0 8px 28px rgba(0,0,0,${dark ? 0.45 : 0.2}), 0 0 0 0.5px ${dark ? "rgba(255,255,255,0.14)" : "rgba(0,0,0,0.12)"}`;

// A panel's background: the menu material, tinted with the bar's own
// background when a theme or style gives it one.
function panelBackground(bar, dark) {
  const material = PANEL_MATERIAL[dark ? 1 : 0];
  return bar.native ? material : `color-mix(in srgb, ${cssColor(bar.bg, dark)} 85%, ${material})`;
}

// How far to move `ref`'s element sideways to keep it within the bar's
// How far to move `ref`'s element from where it hangs, as `{ x, y }`: to
// keep it within the screen its bar is on, and to keep it where it opened
// along each axis `holds` names, as kantan keeps a popup in place while its
// module changes size under it. The place is kept within the bar, so it holds as
// the page scrolls. Measured again whenever `deps` change, and whenever the
// element, its module or its bar changes size, as each does when a font
// loads.
function usePanelOffset(ref, holds, deps) {
  const opened = useRef(null);
  const [offset, setOffset] = useState({ x: 0, y: 0 });
  const [resized, setResized] = useState(0);
  useEffect(() => {
    const panel = ref.current;
    if (!panel || typeof ResizeObserver === "undefined") return undefined;
    const observer = new ResizeObserver(() => setResized(count => count + 1));
    for (const each of [panel, panel.offsetParent, panel.closest("[data-kantan-bar]")]) {
      if (each) observer.observe(each);
    }
    return () => observer.disconnect();
  }, []);
  useLayoutEffect(() => {
    const bar = ref.current?.closest("[data-kantan-bar]");
    if (!bar) return;
    const screen = bar.getBoundingClientRect();
    // The page may draw the bar scaled, which the move is made within.
    const scale = (bar.offsetWidth ? screen.width / bar.offsetWidth : 1) || 1;
    const rect = ref.current.getBoundingClientRect();
    const top = (rect.top - screen.top) / scale - offset.y;
    let hold = { x: 0, y: 0 };
    const module = ref.current.offsetParent;
    if (module) {
      const under = module.getBoundingClientRect();
      const centre = (under.left + under.width / 2 - screen.left) / scale;
      opened.current ??= { centre, top };
      hold = { x: holds.x ? opened.current.centre - centre : 0, y: holds.y ? opened.current.top - top : 0 };
    }
    // Where the element's sides would be, held in place but not yet kept
    // within the screen.
    const left = rect.left + (hold.x - offset.x) * scale, right = rect.right + (hold.x - offset.x) * scale;
    const shift = right > screen.right ? Math.max(screen.right - right, screen.left - left) : left < screen.left ? screen.left - left : 0;
    const next = { x: hold.x + shift / scale, y: hold.y };
    if (next.x !== offset.x || next.y !== offset.y) setOffset(next);
  }, [...deps, resized]);
  return offset;
}

// What a menu, popup or tooltip is drawn on: its corners, material,
// shadow and text. `kind` is `menu`, `popup` or `tooltip`.
export function panelSurface(kind, bar, dark) {
  const menu = kind === "menu";
  const background = menu ? PANEL_MATERIAL[dark ? 1 : 0] : panelBackground(bar, dark);
  return {
    width: "max-content", boxSizing: "border-box",
    borderRadius: menu ? 8 : 6, background, "--kantan-panel": background,
    boxShadow: PANEL_SHADOW(dark), fontFamily: SYSTEM_FONT, fontWeight: 400,
    letterSpacing: 0, textAlign: "left", cursor: "default",
    ...(menu ? { padding: "5px 0", lineHeight: "16px" } : { color: cssColor(bar.native ? "primary" : bar.fg, dark) }),
  };
}

// A view in a popup or a tooltip, with the room kantan leaves around it
// and the least size kantan gives the panel.
export function PanelView({ kind, nodes, context }) {
  const tooltip = kind === "tooltip";
  return (
    <div style={{
      padding: tooltip ? 8 : "8px 0", minWidth: tooltip ? 40 : 160, minHeight: 20, boxSizing: "border-box",
      display: "flex", flexDirection: "column", alignItems: "center", fontSize: 13, lineHeight: "16px",
    }}>
      <ViewTree nodes={nodes} context={context} />
    </div>
  );
}

// A panel hanging below the module it sits in: centred under it, or with
// its left edge at the module's, `gap` below the module's content.
function Panel({ kind, bar, dark, align, gap, style, deps, children }) {
  const ref = useRef(null);
  // A menu hangs from its module's left edge, so only its height is held.
  const offset = usePanelOffset(ref, { x: kind === "popup", y: kind !== "tooltip" }, deps);
  return (
    <div
      ref={ref}
      data-kantan-panel={kind}
      style={{
        position: "absolute", top: `calc(100% + ${gap}px)`, zIndex: 300,
        left: align === "center" ? "50%" : 0,
        transform: `translate(calc(${align === "center" ? "-50%" : "0px"} + ${offset.x}px), ${offset.y}px)`,
        ...panelSurface(kind, bar, dark),
        ...style,
      }}
    >{children}</div>
  );
}

// A module's shape behind its content: a capsule, a rounded box, or a line
// under or over a module as tall as the bar.
function Shaped({ shape, color, height, children }) {
  if (shape === "pill" || shape === "box") {
    return (
      <div style={{ display: "flex", alignItems: "center", gap: "inherit", padding: "3px 6px", background: color, borderRadius: shape === "pill" ? 9999 : 4 }}>
        {children}
      </div>
    );
  }
  return (
    <div style={{ display: "flex", alignItems: "center", gap: "inherit", padding: "0 6px", height, boxSizing: "border-box", position: "relative" }}>
      {children}
      <span style={{ position: "absolute", left: 0, right: 0, height: 2, background: color, [shape === "underline" ? "bottom" : "top"]: 0 }} />
    </div>
  );
}

// How long a drawer takes to open or close, and a workspace to change.
const DRAWER_TIMING = "0.25s ease-in-out";
const WORKSPACE_TIMING = "0.3s cubic-bezier(0.4, 0, 0.2, 1)";
// A module making way for one from behind the notch clears in the first
// half of the change, and fades back in from a third of the way through.
const TUCK_EXIT = "0.15s cubic-bezier(0.4, 0, 1, 1)";
const TUCK_ENTRANCE = "0.2s cubic-bezier(0, 0, 0.2, 1) 0.1s";

// A module's icon, over the icon kantan draws faintly behind it when it
// has one: the full-strength signal behind a weaker one, say.
function ModuleIcon({ icon, dark }) {
  const glyph = <Glyph icon={icon} color={icon.color} dark={dark} opacity={icon.opacity} fallbackFont={fontFamily(icon.font)} />;
  if (!icon.background) return glyph;
  return (
    <span style={{ display: "inline-grid", placeItems: "center", flexShrink: 0 }}>
      <span style={{ gridArea: "1 / 1" }}>
        <Glyph icon={{ ...icon, ...icon.background }} color={icon.color} dark={dark} opacity={icon.opacity * 0.15}
          fallbackFont={fontFamily(icon.font)} />
      </span>
      <span style={{ gridArea: "1 / 1" }}>{glyph}</span>
    </span>
  );
}

// A waveform module: a bar for each level, or the levels joined as a wave.
// The width of the module a waveform follows, without its padding, as it
// is drawn in the waveform's bar: 0 when it follows none, or one out of the
// bar. `element` is the waveform's own.
function useMatchedWidth(name, bar) {
  const element = useRef(null);
  const [width, setWidth] = useState(0);
  useLayoutEffect(() => {
    const followed = name === undefined ? undefined
      : [...element.current?.closest("[data-kantan-bar]")?.querySelectorAll("[data-kantan-module]") ?? []]
        .find(each => each.dataset.kantanModule === name);
    if (!followed) {
      setWidth(0);
      return undefined;
    }
    const measure = () => {
      const style = getComputedStyle(followed);
      setWidth(Math.max(0, followed.offsetWidth - parseFloat(style.paddingLeft) - parseFloat(style.paddingRight)));
    };
    measure();
    if (typeof ResizeObserver === "undefined") return undefined;
    const observer = new ResizeObserver(measure);
    observer.observe(followed);
    return () => observer.disconnect();
  }, [name, bar]);
  return { element, width };
}

function WaveformView({ waveform: own, bar, dark }) {
  const matched = useMatchedWidth(own.matchWidth, bar);
  return <Waveform waveform={matchWaveform(own, matched.width)} dark={dark} element={matched.element} />;
}

// A workspace module: a segment for each workspace or window, the active
// one at full strength, with the pips of a scrolling layout's workspaces
// before them and an overflow's indicators either side. `activate` switches
// to a segment's target when it is clicked.
function WorkspaceView({ workspace, bar, dark, activate }) {
  const glyph = (segment, style) => (
    <span style={{
      display: "inline-block", lineHeight: 1, whiteSpace: "pre",
      fontFamily: segment.glyph === undefined ? fontFamily(segment.font) : `'${segment.font}'`,
      fontSize: segment.size, fontWeight: segment.weight ?? 400,
      color: cssColor(segment.color, dark), opacity: segment.opacity,
      transition: `opacity ${WORKSPACE_TIMING}, color ${WORKSPACE_TIMING}`,
      ...style,
    }}>{segment.glyph ?? segment.text}</span>
  );
  const clickable = segment => activate && segment.target !== undefined;
  // Pips shrink to fit within the bar when there are many.
  const natural = workspace.pips.length * 4 + (workspace.pips.length - 1) * 2;
  const scale = Math.min(1, bar.height * 0.6 / natural);

  return (
    <div style={{ display: "flex", alignItems: "center", gap: 6 }}>
      {workspace.pips.length > 0 && (
        <div style={{ display: "flex", flexDirection: "column", gap: 2 * scale }}>
          {workspace.pips.map(pip => (
            <span key={pip.id} onClick={clickable(pip) ? () => activate(pip.target) : undefined}
              style={{
                width: 4 * scale, height: 4 * scale, borderRadius: "50%",
                background: cssColor(pip.color, dark), opacity: pip.opacity,
                cursor: clickable(pip) ? "pointer" : undefined,
              }} />
          ))}
        </div>
      )}
      {workspace.before && glyph(workspace.before)}
      {workspace.segments.map(segment => (
        // A click reaches halfway to the segments beside this one.
        <span key={segment.id} onClick={clickable(segment) ? () => activate(segment.target) : undefined}
          style={{
            display: "inline-grid", placeItems: "center", padding: "0 3px", margin: "0 -3px",
            cursor: clickable(segment) ? "pointer" : undefined,
          }}>
          {workspace.slot && glyph(workspace.slot, { gridArea: "1 / 1", visibility: "hidden" })}
          {glyph(segment, { gridArea: "1 / 1" })}
        </span>
      ))}
      {workspace.after && glyph(workspace.after)}
    </div>
  );
}

function ModuleView({ module, bar, dark, run, toggleDrawer, switchWorkspace, interactive, moduleProps, pinned, onEngaged, tuck }) {
  const [hover, setHover] = useState(false);
  const [open, setOpen] = useState(false);
  // Whether a click has left the popup open until the pointer leaves it.
  const [lingering, setLingering] = useState(false);
  const ref = useRef(null);
  // The module's width, for it to make way by, and whether it has been
  // drawn at it: a module that starts out of the bar doesn't slide there.
  const outer = useRef(null);
  const [width, setWidth] = useState(0);
  const [settled, setSettled] = useState(false);
  useLayoutEffect(() => {
    if (tuck && outer.current && outer.current.offsetWidth !== width) setWidth(outer.current.offsetWidth);
  });
  useEffect(() => setSettled(width > 0), [width > 0]);

  // A module that reveals on hover is in use while it shows what it
  // reveals, which the bar makes room for.
  const engaged = module.reveal === true && !module.hidden && (hover || (module.persist === true && open));
  useEffect(() => {
    onEngaged?.(module.name, engaged);
    return () => onEngaged?.(module.name, false);
  }, [engaged, module.name]);

  useEffect(() => {
    if (!open) return undefined;
    const outside = event => ref.current && !ref.current.contains(event.target) && setOpen(false);
    const escape = event => event.key === "Escape" && setOpen(false);
    document.addEventListener("mousedown", outside);
    document.addEventListener("keydown", escape);
    return () => {
      document.removeEventListener("mousedown", outside);
      document.removeEventListener("keydown", escape);
    };
  }, [open]);

  if (module.hidden) return null;
  if (module.unsupported !== undefined) {
    return <div style={{ padding: `0 ${bar.padding}px`, display: "flex", alignItems: "center" }}><Unsupported what={module.unsupported} /></div>;
  }

  const { click, tooltip } = module;
  const opens = click?.type === "menu" || click?.type === "popup";
  const onClick = !interactive ? undefined
    : click?.type === "toggle" ? () => run(module.name, click.command)
    : click?.type === "drawer" && toggleDrawer ? () => toggleDrawer(module.name)
    : opens ? () => setOpen(o => !o)
    : undefined;
  // A drawer's toggle sits without the padding other modules have, and a
  // module in a closed drawer takes no room.
  const padding = module.type === "drawer" || module.slot ? 0 : bar.padding;
  // The anchor of the bar's centre and the module joined to it sit as far
  // apart as an icon and its text.
  const edge = side => (module.slot ? 0 : module.anchor === side ? bar.iconTextSpacing : module.joined === side ? 0 : padding);
  const folded = module.folded === true;
  // Whether the module is out of the bar for the others on its side of
  // the notch.
  const away = tuck?.away === true;
  // A pinned panel stays open and runs nothing, for whoever pinned it to
  // answer clicks within it.
  const held = pinned?.module === module.name ? pinned.slot : undefined;
  const showing = opens && (open || held === "click");
  const runFrom = held === undefined ? command => run(module.name, command) : () => {};
  const close = held === undefined ? () => setOpen(false) : () => {};
  const mark = held !== undefined;
  const fg = bar.native ? "primary" : bar.fg;

  // What a hover reveals is showing: under the pointer, or while the
  // module's menu or popup is open when its hover persists.
  const revealed = hover || held === "hover" || (module.persist === true && showing);
  // A part that waits for a hover takes no room until then, and slides out.
  const waiting = (part, key) => (
    <span key={key} style={{
      display: "inline-flex", overflow: "hidden", maxWidth: revealed ? 600 : 0, opacity: revealed ? 1 : 0,
      transition: `max-width ${WORKSPACE_TIMING}, opacity ${WORKSPACE_TIMING}`,
    }}>{part}</span>
  );
  const text = module.text && (
    <span style={{ display: "inline-flex", whiteSpace: "pre", fontFamily: fontFamily(module.textFont.name), fontSize: module.textFont.size, fontWeight: module.textFont.weight }}>
      {module.text.map((segment, i) => {
        const words = <span key={i} style={{ color: cssColor(segment.color, dark) }}>{segment.text}</span>;
        return segment.reveal ? waiting(words, i) : words;
      })}
    </span>
  );
  const glyph = module.icon && (module.icon.reveal
    ? waiting(<ModuleIcon icon={module.icon} dark={dark} />)
    : <ModuleIcon icon={module.icon} dark={dark} />);
  // The icon anchoring the bar's centre is marked for the bar to find.
  const icon = glyph && module.anchor ? <span data-kantan-anchor style={{ display: "inline-flex" }}>{glyph}</span> : glyph;
  // The text comes before an icon at the module's right. The room between
  // them, in a revealing module, is there while both are.
  const textLeads = module.iconPosition === "right";
  const showsIcon = module.icon && (!module.icon.reveal || revealed);
  const showsText = module.text?.some(segment => !segment.reveal || revealed);
  const room = module.reveal && (
    <span style={{ width: showsIcon && showsText ? bar.iconTextSpacing : 0, transition: `width ${WORKSPACE_TIMING}` }} />
  );

  const content = (
    <>
      {module.workspace && (
        <WorkspaceView workspace={module.workspace} bar={bar} dark={dark}
          activate={interactive && switchWorkspace && (target => switchWorkspace(module.name, target))} />
      )}
      {module.waveform && <WaveformView waveform={module.waveform} bar={bar} dark={dark} />}
      {textLeads && text}
      {textLeads && room}
      {icon}
      {!textLeads && room}
      {!textLeads && text}
    </>
  );

  return (
    <div
      {...moduleProps?.(module)}
      ref={outer}
      data-kantan-module={module.name}
      data-kantan-away={away || undefined}
      aria-hidden={folded || away || undefined}
      style={{
        paddingLeft: folded ? 0 : edge("left"), paddingRight: folded ? 0 : edge("right"),
        display: "flex", alignItems: "center", height: bar.height, boxSizing: "border-box",
        // A masked module is centred in the place of its menu bar item.
        ...(module.slot ? { width: module.slot.width, justifyContent: "center" } : {}),
        ...(module.inDrawer ? {
          maxWidth: folded ? 0 : 600, opacity: folded ? 0 : 1,
          overflow: folded ? "hidden" : "visible", pointerEvents: folded ? "none" : undefined,
          transition: `max-width ${DRAWER_TIMING}, padding ${DRAWER_TIMING}, opacity ${DRAWER_TIMING}`,
        } : {}),
        // A module out of the bar leaves its room to the others, which
        // close over it. One that gives way slides its own width towards
        // the notch, and behind it, as it fades. Any other fades where it
        // is, leaving quickly.
        ...(tuck ? {
          [tuck.notch === "right" ? "marginLeft" : "marginRight"]: away ? -width : 0,
          transform: away && tuck.givesWay ? `translateX(${tuck.notch === "right" ? width : -width}px)` : undefined,
          opacity: away ? 0 : 1, pointerEvents: away ? "none" : undefined,
          transition: settled
            ? `margin ${WORKSPACE_TIMING}, transform ${WORKSPACE_TIMING}, opacity ${tuck.givesWay ? WORKSPACE_TIMING : away ? TUCK_EXIT : TUCK_ENTRANCE}`
            : "none",
        } : {}),
      }}
    >
      <div
        ref={ref}
        onMouseEnter={() => setHover(interactive)}
        onMouseLeave={() => { setHover(false); if (lingering) { setLingering(false); setOpen(false); } }}
        style={{ position: "relative", display: "flex", alignItems: "center", gap: bar.iconTextSpacing, cursor: onClick ? "pointer" : "default" }}
      >
        <div data-kantan-content onClick={onClick} style={{ display: "flex", alignItems: "center", gap: module.reveal ? 0 : "inherit" }}>
          {module.shape
            ? <Shaped shape={module.shape} color={cssColor(module.bg, dark)} height={bar.height}>{content}</Shaped>
            : content}
        </div>

        {tooltip && (held === "hover" || (hover && interactive && !showing)) && (
          <Panel kind="tooltip" bar={bar} dark={dark} align="center" gap={4} deps={[tooltip]}
            style={{ pointerEvents: held === "hover" ? undefined : "none", zIndex: 200 }}>
            {tooltip.text !== undefined
              ? <div style={{ padding: 8, fontSize: 11, lineHeight: "14px", whiteSpace: "pre" }}>{tooltip.text}</div>
              : <PanelView kind="tooltip" nodes={tooltip.view} context={{ dark, native: bar.native, fg, run: () => {}, dismiss: () => {}, mark }} />}
          </Panel>
        )}

        {showing && click.type === "menu" && (
          <Panel kind="menu" bar={bar} dark={dark} align="left" gap={0} deps={[click]}>
            <Menu rows={click.rows} fg={click.fg} dark={dark} run={runFrom} close={close} mark={mark} />
          </Panel>
        )}

        {showing && click.type === "popup" && (
          <Panel kind="popup" bar={bar} dark={dark} align="center" gap={4} deps={[click]}>
            <PanelView kind="popup" nodes={click.view}
              context={{ dark, native: bar.native, fg, run: runFrom, dismiss: close, linger: () => setLingering(true), mark }} />
          </Panel>
        )}
      </div>
    </div>
  );
}

// The camera housing of a screen with a notch: black, hanging from the
// top of the screen over whatever the bar draws there, its lower corners
// rounded and its upper ones flaring into the screen's edge.
function Notch({ notch, gaps, glows = {}, onHover }) {
  const flare = 6;
  const radius = 10, reach = 26, tail = 26;
  // The glow of one side with modules waiting behind the notch: a soft
  // light around the notch's edge, in `color`, down its side and round its
  // bottom corner, fading out beneath it.
  const glow = side => (
    <span key={side} data-kantan-glow={side} aria-hidden style={{
      position: "absolute", top: 0, left: -reach, width: notch.width + reach * 2, height: notch.height + reach,
      pointerEvents: "none", opacity: glows[side] ? 1 : 0, transition: `opacity ${WORKSPACE_TIMING}`,
      maskImage: `linear-gradient(to ${side === "left" ? "right" : "left"}, #000 ${reach + radius}px, transparent ${reach + radius + tail}px)`,
      WebkitMaskImage: `linear-gradient(to ${side === "left" ? "right" : "left"}, #000 ${reach + radius}px, transparent ${reach + radius + tail}px)`,
    }}>
      <span style={{
        position: "absolute", top: 0, left: reach, width: notch.width, height: notch.height,
        borderRadius: `0 0 ${radius}px ${radius}px`, boxShadow: glows[side] ? `0 0 14px 1px ${glows[side]}` : undefined,
      }} />
    </span>
  );
  const corner = side => ({
    position: "absolute", top: 0, [side]: -flare, width: flare, height: flare,
    background: `radial-gradient(circle at ${side === "left" ? "0 100%" : "100% 100%"}, transparent ${flare}px, #000 ${flare + 0.5}px)`,
  });
  return (
    <div data-kantan-notch onMouseEnter={onHover && (() => onHover(true))} onMouseLeave={onHover && (() => onHover(false))} style={{
      alignSelf: "flex-start", flexShrink: 0, position: "relative", zIndex: 2, width: notch.width, height: notch.height,
      background: "#000", borderRadius: "0 0 10px 10px",
      // The notch stays at the top centre of the screen wherever gaps put the bar.
      marginTop: -gaps.top, transform: `translateX(${(gaps.right - gaps.left) / 2}px)`,
    }}>
      <span style={corner("left")} />
      <span style={corner("right")} />
      {glow("left")}
      {glow("right")}
    </div>
  );
}

// The bar: its modules at the left, on either side of the notch or of the
// bar's centre on a screen without one, and at the right. `run(module, command)` runs a command a module's click, menu
// or popup asks for.
// `toggleDrawer(module)` opens or closes a drawer when its module is
// clicked, and `switchWorkspace(module, target)` switches to the workspace
// or window of a clicked segment. Without them those clicks do nothing.
// With `interactive` false the modules answer neither clicks nor the
// pointer. `moduleProps(module)` gives a module's element props of the
// caller's own. `pinned`, `{ module, slot }`, keeps a module's menu or
// popup open for the slot `click`, or its tooltip for `hover`: it runs
// nothing, and each node it draws carries `data-kantan-node`, the path of
// the node it came from in the view as written. `kept` names a module to
// keep in view, as one being edited: what would take its place makes way
// as it would for a module in use. The modules it waits behind the notch
// for go there, and a drawer that has its room closes for now.
const group = { display: "flex", alignItems: "center" };

// The placement beside the notch on each side of the screen.
const BESIDE_NOTCH = { left: "notchleft", right: "notchright" };

// Settles what shares each side of the notch, as kantan does: the modules
// beside it and an open drawer's contents further out. Gives the placements
// slid behind the notch, the bar's element to measure, what a module tells
// of being in use, and the drawer's toggle for a click to call.
function useOverlaps(bar, toggleDrawer, kept) {
  const element = useRef(null);
  const [displaced, setDisplaced] = useState({});
  const [engaged, setEngaged] = useState({});
  // The width a displaced placement's modules had, and the sides whose
  // drawer is closed for now.
  const widths = useRef({});
  const yielded = useRef({});
  // Measured again once a drawer has finished opening or closing.
  const [settled, setSettled] = useState(0);
  useEffect(() => {
    const timer = setTimeout(() => setSettled(count => count + 1), 320);
    return () => clearTimeout(timer);
  }, [bar]);

  useLayoutEffect(() => {
    const root = element.current;
    if (!root) return;
    const next = { ...displaced };
    for (const side of ["left", "right"]) {
      const inner = BESIDE_NOTCH[side];
      // The modules over the menu bar are outside the room being shared.
      const outerModules = bar.placements[side].filter(module => !bar.menuBar.modules.includes(module.name));
      const drawer = bar.placements[side].find(module => module.type === "drawer");
      if (!drawer || !outerModules.some(module => module.inDrawer) || !bar.placements[inner].length) continue;

      const modules = placement => [...root.querySelectorAll(`[data-kantan-placement="${placement}"] > [data-kantan-module]:not([data-kantan-away])`)];
      const total = elements => elements.reduce((sum, each) => sum + each, 0);
      // A drawer's contents are measured at the width they open to.
      const drawerOpen = drawer.open === true;
      const outerWidth = total(modules(side).map(each => {
        const module = outerModules.find(candidate => candidate.name === each.dataset.kantanModule);
        return module?.inDrawer ? (drawerOpen ? each.scrollWidth : 0) : each.offsetWidth;
      }));
      const innerWidth = displaced[inner] ? widths.current[inner] ?? 0 : total(modules(inner).map(each => each.offsetWidth));
      const half = root.querySelectorAll("[data-kantan-half]")[side === "left" ? 0 : 1];
      const span = (half?.offsetWidth ?? 0) - (side === "right" ? root.querySelector("[data-kantan-masked]")?.offsetWidth ?? 0 : 0);
      // A module kept in view is in use for as long as it is kept.
      const keeps = bar.placements[inner].some(module => module.name === kept);
      const using = keeps || bar.placements[inner].some(module => engaged[module.name]);

      const action = resolveOverlap({
        collides: span - innerWidth - outerWidth < OVERLAP_MARGIN, drawerOpen, engaged: using,
        displaced: displaced[inner] === true, yielded: yielded.current[side] === true,
      });
      if (keeps && displaced[inner] && drawerOpen && toggleDrawer) {
        // Kept in view where a drawer already has its room, it comes back
        // out and the drawer closes for now.
        next[inner] = false;
        yielded.current[side] = true;
        toggleDrawer(drawer.name);
      } else if (action === "displace") {
        widths.current[inner] = innerWidth;
        next[inner] = true;
      } else if (action === "restore") {
        next[inner] = false;
      } else if ((action === "closeDrawer" || action === "reopenDrawer") && toggleDrawer) {
        yielded.current[side] = action === "closeDrawer";
        toggleDrawer(drawer.name);
      }
    }
    if (Object.keys(next).some(placement => next[placement] !== (displaced[placement] ?? false))) setDisplaced(next);
  }, [bar, engaged, displaced, settled, kept]);

  return {
    element, displaced,
    onEngaged: (name, using) => setEngaged(current => (Boolean(current[name]) === using ? current : { ...current, [name]: using })),
    // A drawer the user sets is no longer one waiting to open again.
    toggle: toggleDrawer && (name => {
      for (const side of ["left", "right"]) {
        if (bar.placements[side].some(module => module.name === name)) yielded.current[side] = false;
      }
      toggleDrawer(name);
    }),
  };
}

// How long the pointer rests at the notch before the modules behind it come
// out, and how long they stay once it has left, in milliseconds.
const TUCK_DWELL = 120;
const TUCK_LINGER = 600;

// Settles how each side of the notch is shared, as kantan does: a module
// with a `tuck` waits behind the notch while another on its side shows. It
// stays out for its `peek` when it arrives, and comes out while the pointer
// is at the notch. Gives each side's phase by placement, what the pointer
// tells of being at the notch or over the modules it brought out, how a
// module is drawn, and the colour each side of the notch glows in. A side
// with the module `kept` in view is as that module needs: out from behind
// the notch when it gives way, and behind it otherwise.
function useTucks(bar, dark, interactive, kept) {
  const [hovered, setHovered] = useState(false);
  const [peeks, setPeeks] = useState({});
  // Whether each module that gives way was showing when last drawn.
  const shown = useRef({});
  const timers = useRef({});

  const sides = Object.values(BESIDE_NOTCH).map(placement => {
    const modules = bar.notch
      ? bar.placements[placement].filter(module => !bar.menuBar.modules.includes(module.name) && module.type !== "drawer" && !module.folded)
      : [];
    const tucking = modules.filter(module => module.tuck && !module.hidden);
    return { placement, modules, tucking, holding: modules.some(module => !module.tuck && !module.hidden) };
  });

  // A module arriving while another holds its side stays out for its peek.
  useEffect(() => {
    for (const { placement, modules, holding } of sides) {
      for (const module of modules.filter(each => each.tuck)) {
        const arrived = !module.hidden && shown.current[module.name] === false;
        shown.current[module.name] = !module.hidden;
        if (!arrived || !holding || !(module.tuck.peek > 0)) continue;
        clearTimeout(timers.current[placement]);
        setPeeks(current => ({ ...current, [placement]: true }));
        timers.current[placement] = setTimeout(() => setPeeks(current => ({ ...current, [placement]: false })), module.tuck.peek * 1000);
      }
    }
  }, [bar]);
  useEffect(() => () => Object.values(timers.current).forEach(clearTimeout), []);

  const phases = Object.fromEntries(sides.map(({ placement, modules, tucking, holding }) => {
    const held = modules.find(module => module.name === kept);
    const revealing = held ? Boolean(held.tuck) : hovered || peeks[placement] === true;
    return [placement, resolveTuck({ tucking: tucking.length > 0, holding, revealing })];
  }));
  const waiting = Object.values(phases).includes("tucked");

  const hover = inside => {
    clearTimeout(timers.current.hover);
    if (!interactive || inside === hovered) return;
    timers.current.hover = setTimeout(() => setHovered(inside), inside ? TUCK_DWELL : TUCK_LINGER);
  };
  const glow = side => {
    const { tucking } = sides.find(each => each.placement === BESIDE_NOTCH[side]);
    if (phases[BESIDE_NOTCH[side]] !== "tucked") return undefined;
    return cssColor(tucking[0].icon?.color ?? bar.fg, dark);
  };
  return {
    phases,
    // The pointer brings the modules out at the notch, and keeps them out
    // over them.
    atNotch: inside => (inside ? (waiting || hovered) && hover(true) : hover(false)),
    overModules: inside => hovered && hover(inside),
    // How a module that shares its side of the notch is drawn.
    of: (module, placement) => {
      const side = sides.find(each => each.placement === placement);
      if (!side?.modules.includes(module) || phases[placement] === undefined) return undefined;
      if (!side.modules.some(each => each.tuck)) return undefined;
      return {
        givesWay: Boolean(module.tuck), away: tuckHides(phases[placement], Boolean(module.tuck)),
        // The side of the module the notch is on.
        notch: placement === "notchleft" ? "right" : "left",
      };
    },
    glows: { left: glow("left"), right: glow("right") },
  };
}

// How far the modules around the bar's centre move, measured in `element`,
// the bar's: for the icon anchoring the centre to sit on it, or without
// one and without a notch, for modules showing on one side of the centre
// alone to be centred together.
function useCenterShift(element, notch) {
  const [shift, setShift] = useState(0);
  const current = useRef(0);
  useLayoutEffect(() => {
    const root = element.current;
    if (!root) return undefined;
    const measure = () => {
      const icon = root.querySelector("[data-kantan-anchor]");
      let next = 0;
      if (icon) {
        const outer = root.getBoundingClientRect(), inner = icon.getBoundingClientRect();
        const scale = outer.width / root.offsetWidth || 1;
        next = current.current + (outer.left + outer.width / 2 - (inner.left + inner.width / 2)) / scale;
      } else if (!notch) {
        const width = placement => root.querySelector(`[data-kantan-placement="${placement}"]`)?.offsetWidth ?? 0;
        const left = width("notchleft"), right = width("notchright");
        if (width("center") === 0 && (left > 0) !== (right > 0)) next = (left - right) / 2;
      }
      if (Math.abs(next - current.current) < 0.5) return;
      current.current = next;
      setShift(next);
    };
    measure();
    if (typeof ResizeObserver === "undefined") return undefined;
    // Measured again as the modules around the centre change width.
    const observer = new ResizeObserver(measure);
    for (const each of root.querySelectorAll("[data-kantan-around-center]")) observer.observe(each);
    return () => observer.disconnect();
  });
  return shift;
}

export function BarView({ bar, dark, run, toggleDrawer, switchWorkspace, style, interactive = true, moduleProps, pinned, kept }) {
  const overlaps = useOverlaps(bar, toggleDrawer, kept);
  const tucks = useTucks(bar, dark, interactive, kept);
  const shift = useCenterShift(overlaps.element, Boolean(bar.notch));
  const aroundCenter = { "data-kantan-around-center": true };
  const shifted = shift ? { transform: `translateX(${shift}px)` } : {};
  const view = (module, placement) => (
    <ModuleView key={module.name} module={module} bar={bar} dark={dark} run={run} pinned={pinned} onEngaged={overlaps.onEngaged}
      toggleDrawer={overlaps.toggle} switchWorkspace={switchWorkspace} interactive={interactive} moduleProps={moduleProps}
      tuck={tucks.of(module, placement)} />
  );
  // The pointer over the modules beside the notch keeps out those it
  // brought out from behind it.
  const keepsOut = { onMouseEnter: () => tucks.overModules(true), onMouseLeave: () => tucks.overModules(false) };
  // The modules beside the notch slide behind it while a drawer has their room.
  const besideNotch = placement => ({
    ...group, overflow: overlaps.displaced[placement] ? "hidden" : undefined,
    maxWidth: overlaps.displaced[placement] ? 0 : 2000, opacity: overlaps.displaced[placement] ? 0 : 1,
    pointerEvents: overlaps.displaced[placement] ? "none" : undefined,
    transition: `max-width ${WORKSPACE_TIMING}, opacity ${WORKSPACE_TIMING}`,
  });
  // Masked modules sit together over the system's menu bar items, with
  // the unmasked ones kantan holds room for among them.
  const modules = placement => bar.placements[placement].filter(module => !bar.menuBar.modules.includes(module.name)).map(module => view(module, placement));
  const all = Object.values(bar.placements).flat();
  const masked = bar.menuBar.modules.map(name => all.find(module => module.name === name));
  const gaps = bar.gaps ?? { top: 0, left: 0, right: 0 };
  // With a blur the bar is a tint of its background colour, or of black in
  // the native appearance, over a blur of what is behind it: the lower the
  // blur, the thinner the tint.
  const frosted = bar.native || bar.blur > 0;
  const background = bar.blur > 0 ? faded(bar.native ? "#000000" : cssColor(bar.bg, dark), bar.blur / 7)
    : bar.native ? BAR_MATERIAL[dark ? 1 : 0] : cssColor(bar.bg, dark);
  // A bar with corners of its own, or set in from the screen's edges, is
  // drawn with them and not with the corners its caller gives the screen.
  const detached = bar.cornerRadius > 0 || gaps.top > 0 || gaps.left > 0 || gaps.right > 0;
  // Each half of the screen is as wide as the other whatever it holds, so
  // a notch sits at the screen's centre. Modules a half has no room for
  // run on beneath the notch, those of the right half from the right.
  const half = { ...group, flex: "1 1 0", minWidth: 0 };
  return (
    // The gaps are room within the screen, between its edges and the bar.
    <div style={{ padding: `${gaps.top}px ${gaps.right}px 0 ${gaps.left}px` }}>
      <div data-kantan-bar ref={overlaps.element} style={{
        display: "flex", alignItems: "center", height: bar.height, position: "relative", zIndex: 1,
        color: cssColor(bar.fg, dark),
        background,
        backdropFilter: frosted ? "blur(24px) saturate(1.5)" : undefined,
        WebkitBackdropFilter: frosted ? "blur(24px) saturate(1.5)" : undefined,
        fontSize: 13, lineHeight: 1, whiteSpace: "nowrap",
        ...style,
        ...(detached ? { borderRadius: bar.cornerRadius } : {}),
      }}>
        <div data-kantan-half style={half}>
          <div data-kantan-placement="left" style={group}>{modules("left")}</div>
          <div data-kantan-placement="notchleft" {...aroundCenter} {...keepsOut} style={{ ...besideNotch("notchleft"), ...shifted, marginLeft: "auto", justifyContent: "flex-end" }}>{modules("notchleft")}</div>
        </div>
        {bar.notch && <Notch notch={bar.notch} gaps={gaps} glows={tucks.glows} onHover={tucks.atNotch} />}
        <div data-kantan-placement="center" {...aroundCenter} style={{ ...group, ...shifted, flexShrink: 0 }}>{modules("center")}</div>
        <div data-kantan-half style={{ ...half, justifyContent: "flex-end" }}>
          <div data-kantan-placement="notchright" {...aroundCenter} {...keepsOut} style={{ ...besideNotch("notchright"), ...shifted }}>{modules("notchright")}</div>
          <div data-kantan-placement="right" style={{ ...group, marginLeft: "auto" }}>{modules("right")}</div>
          <div data-kantan-masked style={{ ...group, paddingRight: Math.max(0, bar.menuBar.trailing - gaps.right) }}>{masked.map(module => view(module))}</div>
        </div>
      </div>
    </div>
  );
}
