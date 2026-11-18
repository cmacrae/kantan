import { useState, useEffect } from "react";
import { I } from "./Icons.jsx";
import KantanBarMock, { MOCK_WIDTH } from "./MockBar.jsx";
import { ConfigToggle, ConfigCode } from "./ConfigPreview.jsx";
import InstallTabs from "./InstallTabs.jsx";
import Wordmark from "../../../components/Wordmark.jsx";
import features from "../content/features.json";

function Toggle({ icon, label, onClick, siteDark }) {
  const color = siteDark ? "rgba(232,230,220,0.5)" : "rgba(25,25,24,0.45)";
  return (
    <button
      onClick={onClick}
      style={{
        display: "flex", alignItems: "center", gap: 5,
        background: "none", border: "none", cursor: "pointer",
        color, fontSize: 13, fontWeight: 500, padding: 0,
        fontFamily: "inherit",
      }}
    >
      <I name={icon} size={14} color={color} />
      <span>{label}</span>
    </button>
  );
}

function NavIcon({ name, label, href, color }) {
  const external = href.startsWith("http");
  return (
    <a href={href} target={external ? "_blank" : undefined} rel={external ? "noopener noreferrer" : undefined} title={label}
      style={{ color, display: "flex", alignItems: "center", gap: 6, textDecoration: "none", fontSize: 13, fontWeight: 450 }}
    >
      <I name={name} size={18} color={color} />
      <span>{label}</span>
    </a>
  );
}

export default function KantanLanding() {
  const [siteDark, setSiteDark] = useState(() => {
    if (typeof window !== "undefined" && window.matchMedia) {
      return window.matchMedia("(prefers-color-scheme: dark)").matches;
    }
    return false;
  });
  const [themed, setThemed] = useState(true);
  const [barDark, setBarDark] = useState(siteDark);
  const [configOpen, setConfigOpen] = useState(false);

  useEffect(() => {
    if (typeof window === "undefined" || !window.matchMedia) return;
    const mq = window.matchMedia("(prefers-color-scheme: dark)");
    const handler = (e) => { setSiteDark(e.matches); setBarDark(e.matches); };
    mq.addEventListener("change", handler);
    return () => mq.removeEventListener("change", handler);
  }, []);

  const bg = siteDark ? "#141413" : "#faf9f5";
  const fg = siteDark ? "#e8e6dc" : "#191918";
  const fgMuted = siteDark ? "rgba(232,230,220,0.45)" : "rgba(25,25,24,0.4)";
  const fgSub = siteDark ? "rgba(232,230,220,0.65)" : "rgba(25,25,24,0.55)";
  const ff = "-apple-system, BlinkMacSystemFont, 'Helvetica Neue', Helvetica, sans-serif";

  return (
    <div style={{
      minHeight: "100vh", background: bg, color: fg,
      fontFamily: ff, transition: "background 0.3s ease, color 0.3s ease",
    }}>
      {/* Nav */}
      <nav style={{
        display: "flex", justifyContent: "flex-end", alignItems: "center",
        padding: "20px 32px", gap: 24, maxWidth: 1400, margin: "0 auto",
      }}>
        <NavIcon name="brush" label="Builder" href="/builder/" color={fgSub} />
        <NavIcon name="book" label="Docs" href="/docs/" color={fgSub} />
        <NavIcon name="brand-github" label="GitHub" href="https://github.com/cmacrae/kantan" color={fgSub} />
      </nav>

      {/* Hero */}
      <div style={{
        textAlign: "center", padding: "60px 24px 0",
        maxWidth: 800, margin: "0 auto",
      }}>
        <Wordmark color={fg} subColor={fgMuted} />
        <p style={{
          fontSize: 19, color: fgSub, margin: "28px 0 0",
          fontWeight: 400, lineHeight: 1.5, letterSpacing: "-0.01em",
        }}>
          A beautifully simple status bar for macOS
        </p>
      </div>

      {/* Mock Bar */}
      <div style={{
        display: "flex", flexDirection: "column", alignItems: "center",
        padding: "48px 24px 0",
        maxWidth: 1400, margin: "0 auto",
      }}>
        <KantanBarMock themed={themed} dark={barDark} />

        {/* Controls */}
        <div style={{
          marginTop: 24, display: "flex", flexWrap: "wrap", gap: "12px 24px",
          justifyContent: "space-between", alignItems: "center",
          width: "100%", maxWidth: MOCK_WIDTH,
        }}>
          <ConfigToggle siteDark={siteDark} open={configOpen} onToggle={() => setConfigOpen(o => !o)} />
          <div style={{ display: "flex", gap: 16, alignItems: "center" }}>
            <span style={{ fontSize: 13, fontWeight: 500, color: siteDark ? "rgba(232,230,220,0.5)" : "rgba(25,25,24,0.45)" }}>Change appearance:</span>
            <Toggle icon={themed ? "palette-filled" : "palette"} label={themed ? "themed" : "native"} onClick={() => setThemed(t => !t)} siteDark={siteDark} />
            <Toggle icon={barDark ? "moon-filled" : "sun-filled"} label={barDark ? "dark" : "light"} onClick={() => setBarDark(d => !d)} siteDark={siteDark} />
          </div>
        </div>

        {configOpen && <ConfigCode siteDark={siteDark} />}

        <a href="/builder/" style={{
          marginTop: 28, display: "inline-flex", alignItems: "center", gap: 8,
          padding: "9px 18px", borderRadius: 8, textDecoration: "none",
          fontSize: 14, fontWeight: 600,
          background: "#fab387", color: "#141413",
        }}>
          <I name="brush" size={16} color="#141413" />
          Build your own bar
        </a>
      </div>

      {/* Features */}
      <div style={{
        maxWidth: 960, margin: "0 auto",
        padding: "72px 32px 96px",
      }}>
        <div style={{
          display: "grid",
          gridTemplateColumns: "repeat(auto-fit, minmax(260px, 1fr))",
          gap: "32px 48px",
        }}>
          {features.map(({ icon, title, description }) => (
            <div key={title}>
              <h3 style={{
                display: "flex", alignItems: "center", gap: 7,
                fontSize: 15, fontWeight: 600, margin: "0 0 6px",
                color: fg, letterSpacing: "-0.01em",
              }}>
                <I name={icon} size={16} color={fg} />
                {title}
              </h3>
              <p style={{
                fontSize: 14, color: fgSub, margin: 0,
                lineHeight: 1.55,
              }}>{description}</p>
            </div>
          ))}
        </div>
      </div>

      {/* Install */}
      <div id="install" style={{
        maxWidth: 520, margin: "0 auto",
        padding: "0 32px 96px",
      }}>
        <h2 style={{
          display: "flex", alignItems: "center", gap: 10,
          fontSize: 20, fontWeight: 600, margin: "0 0 20px",
          color: fg, letterSpacing: "-0.02em",
        }}>
          <I name="app-window-filled" size={22} color={fg} />
          Install
        </h2>
        <InstallTabs siteDark={siteDark} />
      </div>

      <footer style={{
        textAlign: "center", padding: "0 24px 48px",
        fontSize: 12, color: fgMuted,
      }}>
        © 2023–2026 Calum MacRae · Released under the{" "}
        <a href="https://github.com/cmacrae/kantan/blob/main/LICENSE"
          style={{ color: "inherit" }}>MIT License</a>
      </footer>
    </div>
  );
}
