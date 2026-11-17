import { createRoot } from "react-dom/client";
import KantanBarMock from "./components/MockBar.jsx";
import Wordmark from "./components/Wordmark.jsx";

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

// The landing page's background, and Catppuccin Mocha colours for the
// wordmark that stand out from each wallpaper.
const page = dark
  ? { bg: "#141413", fg: "#cdd6f4" /* text */, sub: "#a6adc8" /* subtext0 */ }
  : { bg: "#faf9f5", fg: "#11111b" /* crust */, sub: "#313244" /* surface0 */ };

function Preview() {
  return (
    <div style={{
      width: "100vw", height: "100vh",
      display: "flex", alignItems: "center", justifyContent: "center",
      background: fill ? page.bg : "transparent",
    }}>
      <div style={{ width: num("width", 880), zoom: num("zoom", 1) }}>
        <KantanBarMock themed dark={dark} clock="09:41"
          desktopHeight={num("desktop", 260)} maxWidth="none">
          <div style={{
            height: "100%", display: "flex", flexDirection: "column",
            alignItems: "center", justifyContent: "center", textAlign: "center",
          }}>
            <Wordmark color={page.fg} subColor={page.sub} scale={num("scale", 1.5)} />
          </div>
        </KantanBarMock>
      </div>
    </div>
  );
}

createRoot(document.getElementById("root")).render(<Preview />);
