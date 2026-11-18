// What the images of a shared theme and a shared module show, drawn with
// no styles but their own, as an image needs.
import { useLayoutEffect, useRef, useState } from "react";
import { Desk } from "../../components/Desk.jsx";

const FONT = "-apple-system, BlinkMacSystemFont, 'Helvetica Neue', Helvetica, sans-serif";
const MONO = "'SF Mono', Menlo, Monaco, monospace";

// A theme in one appearance: `bar`, the example bar in it, over the
// colours of `palette`, each with its name.
export function ThemeCard({ bar, palette, dark, width }) {
  const colors = [["fg", palette.fg], ["bg", palette.bg], ...(palette.shape === undefined ? [] : [["shape", palette.shape]]), ...Object.entries(palette.colors)];
  return (
    <div style={{ width, minWidth: "max-content" }}>
      <Desk bar={bar} dark={dark} height={84} interactive={false} style={{ width: "100%", minWidth: "max-content" }} />
      <div style={{
        marginTop: 22, padding: "16px 18px", borderRadius: 10, display: "grid", gridTemplateColumns: "repeat(5, 1fr)", gap: "12px 14px",
        background: dark ? "#1c1c1b" : "#ffffff", color: dark ? "#e8e6dc" : "#191918", fontFamily: FONT,
        boxShadow: dark ? "0 16px 64px rgba(0,0,0,0.55), 0 2px 6px rgba(0,0,0,0.3)" : "0 8px 40px rgba(0,0,0,0.12), 0 2px 6px rgba(0,0,0,0.06)",
      }}>
        {colors.map(([name, color]) => (
          <div key={name} style={{ display: "flex", alignItems: "center", gap: 8, minWidth: 0 }}>
            <div style={{ flex: "none", width: 28, height: 28, borderRadius: 7, background: color, border: `1px solid ${dark ? "rgba(232,230,220,0.14)" : "rgba(25,25,24,0.12)"}` }} />
            <div style={{ display: "flex", flexDirection: "column", lineHeight: 1.3, minWidth: 0 }}>
              <span style={{ fontSize: 13, fontWeight: 600, whiteSpace: "nowrap" }}>{name}</span>
              <span style={{ fontSize: 11.5, fontFamily: MONO, opacity: 0.62 }}>{color}</span>
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}

// A module in one appearance: `bar`, a bar holding it alone, with the
// panel `pinned` names held open on a desktop as large as that needs.
export function ModuleCard({ bar, dark, width, pinned }) {
  const frame = useRef(null);
  const [room, setRoom] = useState({ height: 84 });
  useLayoutEffect(() => {
    const panel = frame.current.querySelector("[data-kantan-panel]");
    if (!panel) return setRoom({ height: 84 });
    const within = frame.current.getBoundingClientRect(), rect = panel.getBoundingClientRect();
    const foot = frame.current.querySelector("[data-kantan-bar]").getBoundingClientRect().bottom;
    return setRoom({ height: Math.max(84, Math.ceil(rect.bottom - foot) + 28), minWidth: Math.ceil(rect.right - within.left) + 24 });
  }, [bar, pinned?.slot]);
  return (
    <Desk frameRef={frame} bar={bar} dark={dark} height={room.height} interactive={false} run={() => {}} pinned={pinned}
      style={{ width, minWidth: room.minWidth ?? "max-content" }} />
  );
}
