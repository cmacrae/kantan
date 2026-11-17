// Draws a bar the engine resolved, as kantan draws it: each module's icon,
// value and shape, the tooltip it shows under the pointer, and the menu or
// popup a click opens.
import { useEffect, useLayoutEffect, useRef, useState } from "react";
import { Glyph } from "./Glyph.jsx";
import { Menu } from "./Menu.jsx";
import { Unsupported } from "./Unsupported.jsx";
import { ViewTree } from "./ViewTree.jsx";
import { cssColor, fontFamily, SYSTEM_FONT } from "./system.js";

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

function ModuleView({ module, bar, dark, run }) {
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
  const onClick = click?.type === "toggle" ? () => run(module.name, click.command)
    : opens ? () => setOpen(o => !o)
    : undefined;
  const runFrom = command => run(module.name, command);
  const fg = bar.native ? "primary" : bar.fg;

  const content = (
    <>
      {module.icon && (
        <Glyph icon={module.icon} color={module.icon.color} dark={dark} opacity={module.icon.opacity}
          fallbackFont={fontFamily(module.icon.font)} />
      )}
      {module.text && (
        <span style={{ whiteSpace: "pre", fontFamily: fontFamily(module.textFont.name), fontSize: module.textFont.size, fontWeight: module.textFont.weight }}>
          {module.text.map((segment, i) => <span key={i} style={{ color: cssColor(segment.color, dark) }}>{segment.text}</span>)}
        </span>
      )}
    </>
  );

  return (
    <div style={{ padding: `0 ${bar.padding}px`, display: "flex", alignItems: "center", height: bar.height, boxSizing: "border-box" }}>
      <div
        ref={ref}
        onMouseEnter={() => setHover(true)}
        onMouseLeave={() => setHover(false)}
        style={{ position: "relative", display: "flex", alignItems: "center", gap: bar.iconTextSpacing, cursor: onClick ? "pointer" : "default" }}
      >
        <div onClick={onClick} style={{ display: "flex", alignItems: "center", gap: "inherit" }}>
          {module.shape
            ? <Shaped shape={module.shape} color={cssColor(module.bg, dark)} height={bar.height}>{content}</Shaped>
            : content}
        </div>

        {tooltip && hover && !open && (
          <Panel bar={bar} dark={dark} align="center" gap={4} radius={6} deps={[tooltip]}
            style={{ pointerEvents: "none", color: cssColor(fg, dark), zIndex: 200 }}>
            {tooltip.text !== undefined
              ? <div style={{ padding: 8, fontSize: 11, lineHeight: "14px", whiteSpace: "pre" }}>{tooltip.text}</div>
              : (
                <div style={{ padding: 8, minWidth: 40, minHeight: 20, boxSizing: "border-box", display: "flex", flexDirection: "column", alignItems: "center", fontSize: 13, lineHeight: "16px" }}>
                  <ViewTree nodes={tooltip.view} context={{ dark, native: bar.native, fg, run: () => {}, dismiss: () => {} }} />
                </div>
              )}
          </Panel>
        )}

        {open && click.type === "menu" && (
          <Panel bar={bar} dark={dark} align="left" gap={0} radius={8} deps={[click]}
            background={PANEL_MATERIAL[dark ? 1 : 0]} style={{ padding: "5px 0", lineHeight: "16px" }}>
            <Menu rows={click.rows} fg={click.fg} dark={dark} run={runFrom} close={() => setOpen(false)} />
          </Panel>
        )}

        {open && click.type === "popup" && (
          <Panel bar={bar} dark={dark} align="center" gap={4} radius={6} deps={[click]} style={{ color: cssColor(fg, dark) }}>
            <div style={{ padding: "8px 0", minWidth: 160, minHeight: 20, boxSizing: "border-box", display: "flex", flexDirection: "column", alignItems: "center", fontSize: 13, lineHeight: "16px" }}>
              <ViewTree nodes={click.view} context={{ dark, native: bar.native, fg, run: runFrom, dismiss: () => setOpen(false) }} />
            </div>
          </Panel>
        )}
      </div>
    </div>
  );
}

// The bar: its modules at the left, on either side of the notch, and at
// the right. `run(module, command)` runs a command a module's click, menu
// or popup asks for.
export function BarView({ bar, dark, run, style }) {
  const modules = placement => bar.placements[placement].map(module => (
    <ModuleView key={module.name} module={module} bar={bar} dark={dark} run={run} />
  ));
  const group = { display: "flex", alignItems: "center" };
  return (
    <div data-kantan-bar style={{
      display: "flex", alignItems: "center", height: bar.height, position: "relative", zIndex: 1,
      color: cssColor(bar.fg, dark),
      background: bar.native ? BAR_MATERIAL[dark ? 1 : 0] : cssColor(bar.bg, dark),
      backdropFilter: bar.native ? "blur(24px) saturate(1.5)" : undefined,
      WebkitBackdropFilter: bar.native ? "blur(24px) saturate(1.5)" : undefined,
      fontSize: 13, lineHeight: 1, whiteSpace: "nowrap",
      ...style,
    }}>
      <div style={group}>{modules("left")}</div>
      <div style={{ ...group, flex: 1, justifyContent: "flex-end" }}>{modules("notchleft")}</div>
      <div style={{ ...group, flex: 1 }}>{modules("notchright")}</div>
      <div style={group}>{modules("right")}</div>
    </div>
  );
}
