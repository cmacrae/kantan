import { useState } from "react";
import { I } from "./Icons.jsx";
import INSTALL_TABS from "../content/install.js";

export default function InstallTabs({ siteDark }) {
  const [tab, setTab] = useState(0);
  const fg = siteDark ? "#e8e6dc" : "#191918";
  const fgMuted = siteDark ? "rgba(232,230,220,0.5)" : "rgba(25,25,24,0.45)";
  const fgSub = siteDark ? "rgba(232,230,220,0.65)" : "rgba(25,25,24,0.55)";
  const codeBg = siteDark ? "#1c1c1b" : "#eeeee8";
  const commentColor = siteDark ? "#6c6c60" : "#9c9c90";
  const accent = "#d97757";

  const current = INSTALL_TABS[tab];

  function highlightShell(code) {
    return code.split('\n').map((line, i, arr) => {
      const nl = i < arr.length - 1 ? '\n' : '';
      if (line.startsWith('#')) {
        return <span key={i} style={{ color: commentColor }}>{line}{nl}</span>;
      }
      return <span key={i} style={{ color: fg }}>{line}{nl}</span>;
    });
  }

  return (
    <div>
      <div style={{ display: "flex", gap: 0 }}>
        {INSTALL_TABS.map((t, i) => (
          <button
            key={t.label}
            onClick={() => setTab(i)}
            style={{
              background: "none", border: "none", cursor: "pointer",
              padding: "8px 16px", fontSize: 13, fontWeight: 500,
              fontFamily: "inherit",
              color: i === tab ? fg : fgMuted,
              borderBottom: i === tab ? `2px solid ${accent}` : "2px solid transparent",
              transition: "color 0.15s, border-color 0.15s",
            }}
          >
            {t.label}
          </button>
        ))}
      </div>
      <pre style={{
        margin: 0, padding: "16px 20px",
        background: codeBg, borderRadius: "0 8px 8px 8px",
        fontSize: 12.5, lineHeight: 1.6,
        fontFamily: "'SF Mono', Menlo, Monaco, monospace",
        overflowX: "auto",
      }}>
        <code>{highlightShell(current.content)}</code>
      </pre>
      {current.note && (
        <p style={{ margin: "8px 0 0", fontSize: 12, color: fgMuted }}>
          {current.note.href ? (
            <a href={current.note.href} style={{ color: fgSub, textDecoration: "none", borderBottom: `1px solid ${fgMuted}` }}>
              {current.note.text} &rarr;
            </a>
          ) : (
            current.note.text
          )}
        </p>
      )}
    </div>
  );
}
