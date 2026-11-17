// The mock desktop a bar is shown on: the bar across the top of a
// wallpaper, with room below it for whatever the desktop holds.
import { BarView } from "./BarView.jsx";
import Wordmark from "./Wordmark.jsx";

// The desktop's wallpaper in either appearance.
export const wallpaper = dark => (dark
  ? "radial-gradient(ellipse at 25% 25%, #1e3a5f 0%, #132740 35%, #162447 60%, #1a1a2e 100%)"
  : "linear-gradient(150deg, #91bdd6 0%, #6fa3c2 25%, #5d90ac 50%, #7fafc8 70%, #b0d4e6 100%)");

// The desktop with `bar` across its top and `children` on the `height` of
// desktop below it. `frameRef` and `style` are its outermost element's,
// and any other props are `BarView`'s.
export function Desk({ bar, dark, height, frameRef, style, children, ...barProps }) {
  const paper = wallpaper(dark);
  return (
    <div ref={frameRef} style={{
      borderRadius: 10, position: "relative",
      boxShadow: dark
        ? "0 16px 64px rgba(0,0,0,0.55), 0 2px 6px rgba(0,0,0,0.3)"
        : "0 8px 40px rgba(0,0,0,0.12), 0 2px 6px rgba(0,0,0,0.06)",
      ...style,
    }}>
      <div style={{ position: "absolute", inset: 0, background: paper, zIndex: 0, borderRadius: 10, overflow: "hidden" }} />
      <BarView bar={bar} dark={dark} {...barProps} style={{ borderRadius: "10px 10px 0 0" }} />
      <div style={{ height, position: "relative", zIndex: 0, borderRadius: "0 0 10px 10px", overflow: "hidden", background: paper }}>
        {children}
      </div>
    </div>
  );
}

// The wordmark set in the middle of a desktop, in Catppuccin Mocha
// colours that stand out from each wallpaper, `scale` times the landing
// page's size.
export function DeskWordmark({ dark, scale = 1.5 }) {
  return (
    <div style={{
      height: "100%", display: "flex", flexDirection: "column",
      alignItems: "center", justifyContent: "center", textAlign: "center",
    }}>
      <Wordmark color={dark ? "#cdd6f4" : "#11111b"} subColor={dark ? "#a6adc8" : "#313244"} scale={scale} />
    </div>
  );
}
