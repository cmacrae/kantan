import { useState, useLayoutEffect, useRef } from "react";

export const BAR_HEIGHT = 33;

// The bar's colours: the palette `p`'s when `themed`, or the native
// translucent look, in the dark or light appearance.
export function barColors({ themed, dark, p }) {
  return {
    p,
    fg: themed ? p.fg : dark ? "rgba(255,255,255,0.92)" : "rgba(0,0,0,0.85)",
    bg: themed ? p.bg : dark ? "rgba(28,28,32,0.68)" : "rgba(253,253,255,0.68)",
    tipBg: themed
      ? dark ? "rgba(30,30,46,0.9)" : "rgba(239,241,245,0.9)"
      : dark ? "rgba(42,42,48,0.9)" : "rgba(255,255,255,0.9)",
    blur: themed ? "none" : "blur(24px) saturate(1.5)",
  };
}

// The bar itself, in `colors` from `barColors`, holding its modules.
export function Bar({ colors, style, children }) {
  const { fg, bg, tipBg, blur } = colors;
  return (
    <div style={{
      height: BAR_HEIGHT, display: "flex", alignItems: "center",
      position: "relative", zIndex: 1,
      fontSize: 13, fontWeight: 400, color: fg,
      background: bg, backdropFilter: blur, WebkitBackdropFilter: blur,
      overflow: "visible",
      "--fg": fg, "--tip-bg": tipBg,
      ...style,
    }}>
      {children}
    </div>
  );
}

// A hover tooltip below the module it sits in. With `clamp`, it moves
// sideways to stay within the window.
export function Tooltip({ children, clamp = false }) {
  const ref = useRef(null);
  const [shift, setShift] = useState(0);
  useLayoutEffect(() => {
    if (!clamp) return;
    const rect = ref.current.getBoundingClientRect();
    const margin = 16;
    const left = rect.left - shift;
    const right = rect.right - shift;
    const room = document.documentElement.clientWidth - margin;
    setShift(left < margin ? margin - left : right > room ? room - right : 0);
  }, [clamp, children]);
  return (
    <div ref={ref} style={{
      position: "absolute", top: 35, left: "50%",
      transform: shift ? `translateX(calc(-50% + ${shift}px))` : "translateX(-50%)",
      padding: "5px 10px", borderRadius: 6, fontSize: 11, fontWeight: 400,
      whiteSpace: "nowrap", zIndex: 200, pointerEvents: "none",
      backdropFilter: "blur(20px)", WebkitBackdropFilter: "blur(20px)",
      background: "var(--tip-bg)", color: "var(--fg)",
      boxShadow: "0 2px 12px rgba(0,0,0,0.2)", letterSpacing: 0,
    }}>{children}</div>
  );
}

// A module in the bar, showing `tip` in a tooltip while hovered.
export function Module({ children, style, onClick, tip, padOuter = true, clampTip = false }) {
  const [hov, setHov] = useState(false);
  return (
    <div
      style={{
        display: "flex", alignItems: "center",
        padding: padOuter ? "0 10px" : 0,
        gap: 5, whiteSpace: "nowrap", height: BAR_HEIGHT, boxSizing: "border-box",
        cursor: onClick ? "pointer" : "default", position: "relative",
        ...style,
      }}
      onClick={onClick}
      onMouseEnter={() => setHov(true)}
      onMouseLeave={() => setHov(false)}
    >
      {children}
      {tip && hov && <Tooltip clamp={clampTip}>{tip}</Tooltip>}
    </div>
  );
}

// A module's background shape, as kantan draws a `box`: a rounded
// rectangle padded around the icon and value.
export function Shape({ background, radius = 4, style, onClick, children }) {
  return (
    <div
      onClick={onClick}
      style={{
        display: "flex", alignItems: "center", gap: 5,
        background, borderRadius: radius, padding: "3px 6px",
        ...style,
      }}
    >
      {children}
    </div>
  );
}

// A menu or popup panel dropping from the module it sits in, `width` wide.
export function MenuPanel({ themed, dark, fg, width, style, children }) {
  return (
    <div style={{
      position: "absolute", top: 37, left: 0, zIndex: 300,
      width, borderRadius: 10, padding: "5px 0",
      backdropFilter: "blur(50px) saturate(1.6)",
      WebkitBackdropFilter: "blur(50px) saturate(1.6)",
      background: themed
        ? dark ? "rgba(40,40,55,0.97)" : "rgba(244,245,249,0.97)"
        : dark ? "rgba(50,50,56,0.97)" : "rgba(255,255,255,0.97)",
      boxShadow: "0 8px 32px rgba(0,0,0,0.22), 0 0 0 0.5px " + (dark ? "rgba(255,255,255,0.08)" : "rgba(0,0,0,0.08)"),
      color: fg, fontSize: 13,
      fontFamily: "'Helvetica Neue', Helvetica, sans-serif",
      ...style,
    }}>
      {children}
    </div>
  );
}

// A separator between a menu's items.
export function MenuDivider({ dark }) {
  return (
    <div style={{
      height: 1, margin: "4px 12px",
      background: dark ? "rgba(255,255,255,0.1)" : "rgba(0,0,0,0.08)",
    }} />
  );
}
