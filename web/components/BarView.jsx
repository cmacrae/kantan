// Draws a bar the engine resolved, as kantan draws it: each module's icon,
// value and shape, the tooltip it shows under the pointer, and the menu or
// popup a click opens.
import { useEffect, useLayoutEffect, useRef, useState } from "react";
import { Glyph } from "./Glyph.jsx";
import { Menu } from "./Menu.jsx";
import { Unsupported } from "./Unsupported.jsx";
import { ViewTree } from "./ViewTree.jsx";
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
// width, as kantan keeps a panel within the screen the bar spans.
function useWithinBar(ref, deps) {
  const [shift, setShift] = useState(0);
  useLayoutEffect(() => {
    const screen = ref.current?.closest("[data-kantan-bar]")?.getBoundingClientRect();
    if (!screen) return;
    const rect = ref.current.getBoundingClientRect();
    const left = rect.left - shift, right = rect.right - shift;
    setShift(right > screen.right ? Math.max(screen.right - right, screen.left - left) : left < screen.left ? screen.left - left : 0);
  }, deps);
  return shift;
}

// A panel hanging below the module it sits in: centred under it, or with
// its left edge at the module's, `gap` below the module's content.
function Panel({ bar, dark, align, gap, background, radius, style, deps, children }) {
  const ref = useRef(null);
  const shift = useWithinBar(ref, deps);
  return (
    <div
      ref={ref}
      style={{
        position: "absolute", top: `calc(100% + ${gap}px)`, zIndex: 300,
        left: align === "center" ? "50%" : 0,
        transform: `translateX(calc(${align === "center" ? "-50%" : "0px"} + ${shift}px))`,
        width: "max-content", boxSizing: "border-box",
        borderRadius: radius, background: background ?? panelBackground(bar, dark),
        boxShadow: PANEL_SHADOW(dark), fontFamily: SYSTEM_FONT, fontWeight: 400,
        letterSpacing: 0, textAlign: "left", cursor: "default",
        "--kantan-panel": background ?? panelBackground(bar, dark),
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

function ModuleView({ module, bar, dark, run, toggleDrawer, switchWorkspace, interactive, moduleProps, pinned }) {
  const [hover, setHover] = useState(false);
  const [open, setOpen] = useState(false);
  const ref = useRef(null);

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
  const folded = module.folded === true;
  // A pinned panel stays open and runs nothing, for whoever pinned it to
  // answer clicks within it.
  const held = pinned?.module === module.name ? pinned.slot : undefined;
  const showing = opens && (open || held === "click");
  const runFrom = held === undefined ? command => run(module.name, command) : () => {};
  const close = held === undefined ? () => setOpen(false) : () => {};
  const mark = held !== undefined;
  const fg = bar.native ? "primary" : bar.fg;

  const content = (
    <>
      {module.workspace && (
        <WorkspaceView workspace={module.workspace} bar={bar} dark={dark}
          activate={interactive && switchWorkspace && (target => switchWorkspace(module.name, target))} />
      )}
      {module.icon && <ModuleIcon icon={module.icon} dark={dark} />}
      {module.text && (
        <span style={{ whiteSpace: "pre", fontFamily: fontFamily(module.textFont.name), fontSize: module.textFont.size, fontWeight: module.textFont.weight }}>
          {module.text.map((segment, i) => <span key={i} style={{ color: cssColor(segment.color, dark) }}>{segment.text}</span>)}
        </span>
      )}
    </>
  );

  return (
    <div
      {...moduleProps?.(module)}
      data-kantan-module={module.name}
      aria-hidden={folded || undefined}
      style={{
        paddingLeft: folded ? 0 : padding, paddingRight: folded ? 0 : padding,
        display: "flex", alignItems: "center", height: bar.height, boxSizing: "border-box",
        // A masked module is centred in the place of its menu bar item.
        ...(module.slot ? { width: module.slot.width, justifyContent: "center" } : {}),
        ...(module.inDrawer ? {
          maxWidth: folded ? 0 : 600, opacity: folded ? 0 : 1,
          overflow: folded ? "hidden" : "visible", pointerEvents: folded ? "none" : undefined,
          transition: `max-width ${DRAWER_TIMING}, padding ${DRAWER_TIMING}, opacity ${DRAWER_TIMING}`,
        } : {}),
      }}
    >
      <div
        ref={ref}
        onMouseEnter={() => setHover(interactive)}
        onMouseLeave={() => setHover(false)}
        style={{ position: "relative", display: "flex", alignItems: "center", gap: bar.iconTextSpacing, cursor: onClick ? "pointer" : "default" }}
      >
        <div data-kantan-content onClick={onClick} style={{ display: "flex", alignItems: "center", gap: "inherit" }}>
          {module.shape
            ? <Shaped shape={module.shape} color={cssColor(module.bg, dark)} height={bar.height}>{content}</Shaped>
            : content}
        </div>

        {tooltip && (held === "hover" || (hover && interactive && !showing)) && (
          <Panel bar={bar} dark={dark} align="center" gap={4} radius={6} deps={[tooltip]}
            style={{ pointerEvents: held === "hover" ? undefined : "none", color: cssColor(fg, dark), zIndex: 200 }}>
            {tooltip.text !== undefined
              ? <div style={{ padding: 8, fontSize: 11, lineHeight: "14px", whiteSpace: "pre" }}>{tooltip.text}</div>
              : (
                <div style={{ padding: 8, minWidth: 40, minHeight: 20, boxSizing: "border-box", display: "flex", flexDirection: "column", alignItems: "center", fontSize: 13, lineHeight: "16px" }}>
                  <ViewTree nodes={tooltip.view} context={{ dark, native: bar.native, fg, run: () => {}, dismiss: () => {}, mark }} />
                </div>
              )}
          </Panel>
        )}

        {showing && click.type === "menu" && (
          <Panel bar={bar} dark={dark} align="left" gap={0} radius={8} deps={[click]}
            background={PANEL_MATERIAL[dark ? 1 : 0]} style={{ padding: "5px 0", lineHeight: "16px" }}>
            <Menu rows={click.rows} fg={click.fg} dark={dark} run={runFrom} close={close} mark={mark} />
          </Panel>
        )}

        {showing && click.type === "popup" && (
          <Panel bar={bar} dark={dark} align="center" gap={4} radius={6} deps={[click]} style={{ color: cssColor(fg, dark) }}>
            <div style={{ padding: "8px 0", minWidth: 160, minHeight: 20, boxSizing: "border-box", display: "flex", flexDirection: "column", alignItems: "center", fontSize: 13, lineHeight: "16px" }}>
              <ViewTree nodes={click.view} context={{ dark, native: bar.native, fg, run: runFrom, dismiss: close, mark }} />
            </div>
          </Panel>
        )}
      </div>
    </div>
  );
}

// The camera housing of a screen with a notch: black, hanging from the
// top of the screen over whatever the bar draws there, its lower corners
// rounded and its upper ones flaring into the screen's edge.
function Notch({ notch, gaps }) {
  const flare = 6;
  const corner = side => ({
    position: "absolute", top: 0, [side]: -flare, width: flare, height: flare,
    background: `radial-gradient(circle at ${side === "left" ? "0 100%" : "100% 100%"}, transparent ${flare}px, #000 ${flare + 0.5}px)`,
  });
  return (
    <div data-kantan-notch style={{
      alignSelf: "flex-start", flexShrink: 0, position: "relative", zIndex: 2, width: notch.width, height: notch.height,
      background: "#000", borderRadius: "0 0 10px 10px",
      // The notch stays at the top centre of the screen wherever gaps put the bar.
      marginTop: -gaps.top, transform: `translateX(${(gaps.right - gaps.left) / 2}px)`,
    }}>
      <span style={corner("left")} />
      <span style={corner("right")} />
    </div>
  );
}

// The bar: its modules at the left, on either side of the notch, and at
// the right. `run(module, command)` runs a command a module's click, menu
// or popup asks for.
// `toggleDrawer(module)` opens or closes a drawer when its module is
// clicked, and `switchWorkspace(module, target)` switches to the workspace
// or window of a clicked segment. Without them those clicks do nothing.
// With `interactive` false the modules answer neither clicks nor the
// pointer. `moduleProps(module)` gives a module's element props of the
// caller's own. `pinned`, `{ module, slot }`, keeps a module's menu or
// popup open for the slot `click`, or its tooltip for `hover`: it runs
// nothing, and each node it draws carries `data-kantan-node`, the path of
// the node it came from in the view as written.
export function BarView({ bar, dark, run, toggleDrawer, switchWorkspace, style, interactive = true, moduleProps, pinned }) {
  const view = module => (
    <ModuleView key={module.name} module={module} bar={bar} dark={dark} run={run} pinned={pinned}
      toggleDrawer={toggleDrawer} switchWorkspace={switchWorkspace} interactive={interactive} moduleProps={moduleProps} />
  );
  // Masked modules sit together over the system's menu bar items.
  const modules = placement => bar.placements[placement].filter(module => !module.slot).map(view);
  const all = Object.values(bar.placements).flat();
  const masked = bar.menuBar.modules.map(name => all.find(module => module.name === name));
  const group = { display: "flex", alignItems: "center" };
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
      <div data-kantan-bar style={{
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
          <div data-kantan-placement="notchleft" style={{ ...group, marginLeft: "auto" }}>{modules("notchleft")}</div>
        </div>
        {bar.notch && <Notch notch={bar.notch} gaps={gaps} />}
        <div data-kantan-half style={{ ...half, justifyContent: "flex-end" }}>
          <div data-kantan-placement="notchright" style={group}>{modules("notchright")}</div>
          <div data-kantan-placement="right" style={{ ...group, marginLeft: "auto" }}>{modules("right")}</div>
          <div style={{ ...group, paddingRight: Math.max(0, bar.menuBar.trailing - gaps.right) }}>{masked.map(view)}</div>
        </div>
      </div>
    </div>
  );
}
