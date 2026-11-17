// The landing page's desktop: kantan's bar as the engine draws it for the
// example config, over a wallpaper with a terminal for each workspace.
import { useLayoutEffect, useMemo, useRef, useState } from "react";
import { BarView } from "../../../components/BarView.jsx";
import { useBar } from "../../../components/useBar.js";
import { iconTable } from "../../../engine/index.js";
import barDocument from "../../../generated/landing-document.json";
import iconGlyphs from "../../../generated/landing-icons.json";
import { WorkspaceTerminals } from "./Terminal.jsx";

const icons = iconTable(iconGlyphs);

// The example config without its theme, which kantan draws in the
// system's own look.
const nativeDocument = { ...barDocument, config: { ...barDocument.config, theme: undefined } };

// The state each plugin's module starts in, where it isn't its first.
const INITIAL_STATES = { caffeine: "Off" };

// The mock's width on the landing page: 60% of the window, or the whole
// column on narrow screens.
export const MOCK_WIDTH = "max(60vw, min(100%, 640px))";

// Shrinks `ref`'s element to fit its parent when its content is wider, as
// the bar is on a phone.
function useFitZoom(ref) {
  const [zoom, setZoom] = useState(1);
  const current = useRef(1);
  useLayoutEffect(() => {
    const frame = ref.current;
    const parent = frame.parentElement;
    function fit() {
      // Both widths as drawn, so a zoom further out cancels out.
      const style = getComputedStyle(parent);
      const drawn = parent.getBoundingClientRect().width / parent.clientWidth;
      const room = (parent.clientWidth - parseFloat(style.paddingLeft) - parseFloat(style.paddingRight)) * drawn;
      const natural = frame.getBoundingClientRect().width / current.current;
      const next = Math.min(1, room / natural);
      if (Math.abs(next - current.current) > 0.001) {
        current.current = next;
        setZoom(next);
      }
    }
    const observer = new ResizeObserver(fit);
    observer.observe(parent);
    observer.observe(frame);
    return () => observer.disconnect();
  }, [ref]);
  return zoom;
}

// The desktop, in the example config's theme when `themed` and the system's
// look otherwise. `children` replace the terminals on the desktop below
// the bar, and `time`, an ISO 8601 date, stops the clock at that moment.
export default function KantanBarMock({ themed, dark, children, time, desktopHeight = 200, maxWidth = MOCK_WIDTH }) {
  const samples = useMemo(
    () => (time === undefined ? undefined : { clock: { time, timezone: "UTC", locale: "en_GB" } }),
    [time]);
  const { bar, run, toggleDrawer, switchWorkspace } = useBar(themed ? barDocument : nativeDocument, { dark, icons, samples, states: INITIAL_STATES });

  // The workspace the bar shows as active, for the terminals to follow.
  const spaces = Object.values(bar.placements).flat().find(module => module.workspace)?.workspace.segments ?? [];
  const activeSpace = Math.max(0, spaces.findIndex(segment => segment.active));

  const wallpaper = dark
    ? "radial-gradient(ellipse at 25% 25%, #1e3a5f 0%, #132740 35%, #162447 60%, #1a1a2e 100%)"
    : "linear-gradient(150deg, #91bdd6 0%, #6fa3c2 25%, #5d90ac 50%, #7fafc8 70%, #b0d4e6 100%)";

  const frameRef = useRef(null);
  const zoom = useFitZoom(frameRef);

  return (
    <div ref={frameRef} style={{
      // Grows to fit the bar, then shrinks as a whole when that's wider
      // than the page.
      width: "100%", maxWidth, minWidth: "max-content", borderRadius: 10, zoom,
      boxShadow: dark
        ? "0 16px 64px rgba(0,0,0,0.55), 0 2px 6px rgba(0,0,0,0.3)"
        : "0 8px 40px rgba(0,0,0,0.12), 0 2px 6px rgba(0,0,0,0.06)",
      position: "relative",
    }}>
      <div style={{ position: "absolute", inset: 0, background: wallpaper, zIndex: 0, borderRadius: 10, overflow: "hidden" }} />

      {/* On the page a click on a workspace switches to it, standing in for
          the window manager that does on a Mac. */}
      <BarView bar={bar} dark={dark} run={run} toggleDrawer={toggleDrawer} switchWorkspace={switchWorkspace}
        style={{ borderRadius: "10px 10px 0 0" }} />

      <div style={{ height: desktopHeight, position: "relative", zIndex: 0, borderRadius: "0 0 10px 10px", overflow: "hidden", background: wallpaper }}>
        {children ?? <WorkspaceTerminals dark={dark} themed={themed} activeSpace={activeSpace} />}
      </div>
    </div>
  );
}
