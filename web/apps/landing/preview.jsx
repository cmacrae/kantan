import { createRoot } from "react-dom/client";
import { DeskWordmark } from "../../components/Desk.jsx";
import KantanBarMock from "./components/MockBar.jsx";

// The mock desktop with the wordmark where the terminals sit, for the README
// and link preview images. The query string sets its look:
//   dark     1 for the dark appearance
//   fill     1 to fill the page with the landing page's background
//   width    the desktop's width
//   desktop  the desktop's height below the bar
//   scale    the wordmark's size, relative to the landing page's
//   zoom     the whole image's zoom
const q = new URLSearchParams(location.search);
const dark = q.get("dark") === "1";
const fill = q.get("fill") === "1";
const num = (key, fallback) => Number(q.get(key) ?? fallback);

// The landing page's background.
const background = dark ? "#141413" : "#faf9f5";

function Preview() {
  return (
    <div style={{
      width: "100vw", height: "100vh",
      display: "flex", alignItems: "center", justifyContent: "center",
      background: fill ? background : "transparent",
    }}>
      <div style={{ width: num("width", 880), zoom: num("zoom", 1) }}>
        <KantanBarMock themed dark={dark} time="2026-11-16T09:41:00Z"
          desktopHeight={num("desktop", 260)} maxWidth="none">
          <DeskWordmark dark={dark} scale={num("scale", 1.5)} />
        </KantanBarMock>
      </div>
    </div>
  );
}

createRoot(document.getElementById("root")).render(<Preview />);
