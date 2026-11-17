import { I } from "./Icons.jsx";
import { MOCK_WIDTH } from "./MockBar.jsx";
import { highlightYaml } from "../../../components/yaml-highlight.jsx";
import CONFIG_YAML from "../content/config-example.yaml";

export function ConfigToggle({ siteDark, open, onToggle }) {
  const fgMuted = siteDark ? "rgba(232,230,220,0.5)" : "rgba(25,25,24,0.45)";
  return (
    <button
      onClick={onToggle}
      style={{
        display: "flex", alignItems: "center", gap: 6,
        background: "none", border: "none", cursor: "pointer",
        color: fgMuted, fontSize: 13, fontWeight: 500,
        padding: "4px 0", fontFamily: "inherit", textAlign: "left",
      }}
    >
      <I name="chevron-down" size={12} color={fgMuted}
        style={{ transform: open ? "rotate(0deg)" : "rotate(-90deg)", transition: "transform 0.2s ease" }} />
      <I name="file-smile-filled" size={14} color={fgMuted} />
      Click here to see the config used to build this bar
    </button>
  );
}

export function ConfigCode({ siteDark }) {
  const colors = siteDark
    ? { comment: "#6c6c60", key: "#d97757", string: "#a6e3a1", bool: "#fab387", number: "#fab387", value: "#bab8ae", punct: "#6c6c60" }
    : { comment: "#9c9c90", key: "#c4593a", string: "#40a02b", bool: "#d76a00", number: "#d76a00", value: "#4a4a44", punct: "#9c9c90" };
  const codeBg = siteDark ? "#1c1c1b" : "#eeeee8";
  const fg = siteDark ? "#e8e6dc" : "#191918";
  return (
    <pre style={{
      margin: "12px 0 0", padding: "16px 20px",
      background: codeBg, borderRadius: 8,
      fontSize: 12.5, lineHeight: 1.6,
      fontFamily: "'SF Mono', Menlo, Monaco, monospace",
      overflowX: "auto", overflowY: "auto",
      maxHeight: 420, color: fg, width: "100%", maxWidth: MOCK_WIDTH,
    }}>
      <code>{highlightYaml(CONFIG_YAML, colors)}</code>
    </pre>
  );
}
