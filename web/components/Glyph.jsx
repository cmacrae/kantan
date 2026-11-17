import { cssColor } from "./system.js";

// An icon the engine resolved: a glyph of the icon font at its scaled
// size, or the text it was given, drawn in `fallbackFont`.
export function Glyph({ icon, color, dark, opacity, fallbackFont, width }) {
  return (
    <span style={{
      display: "inline-block", flexShrink: 0, lineHeight: 1, whiteSpace: "pre",
      fontFamily: icon.glyph === undefined ? fallbackFont : `'${icon.font}'`,
      fontSize: icon.size, fontWeight: 400,
      color: cssColor(color, dark), opacity,
      width, textAlign: width === undefined ? undefined : "center",
    }}>{icon.glyph ?? icon.text}</span>
  );
}
