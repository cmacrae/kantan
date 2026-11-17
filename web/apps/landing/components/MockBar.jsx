// The landing page's desktop: kantan's bar as the engine draws it for the
// example config, over a wallpaper with a terminal for each workspace.
import { useMemo, useRef } from "react";
import { Desk } from "../../../components/Desk.jsx";
import { useBar } from "../../../components/useBar.js";
import { useFitZoom } from "../../../components/useFitZoom.js";
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

  const frameRef = useRef(null);
  const zoom = useFitZoom(frameRef);

  // The desktop grows to fit the bar, then shrinks as a whole when that's
  // wider than the page. On the page a click on a workspace switches to
  // it, standing in for the window manager that does on a Mac.
  return (
    <Desk bar={bar} dark={dark} height={desktopHeight} frameRef={frameRef} style={{ width: "100%", maxWidth, minWidth: "max-content", zoom }}
      run={run} toggleDrawer={toggleDrawer} switchWorkspace={switchWorkspace}>
      {children ?? <WorkspaceTerminals dark={dark} themed={themed} activeSpace={activeSpace} />}
    </Desk>
  );
}
