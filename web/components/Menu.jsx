// Draws the rows of a native menu the engine made from a view, as macOS
// draws the menu kantan builds.
import { useState } from "react";
import { Glyph } from "./Glyph.jsx";
import { CheckMark, Switch, nodeMark } from "./ViewTree.jsx";
import { checkCommand } from "../engine/index.js";
import { cssColor, faded } from "./system.js";

const ROW = { display: "flex", alignItems: "center", minHeight: 22, padding: "0 14px", boxSizing: "border-box" };

// A menu item with the highlight macOS and kantan draw behind an item a
// click acts on, while the pointer is over it.
function Selectable({ onClick, dark, style, tag, children }) {
  const [hover, setHover] = useState(false);
  const highlight = hover && onClick ? cssColor("accent", dark) : undefined;
  return (
    <div
      {...tag}
      onClick={onClick}
      onMouseEnter={() => setHover(true)}
      onMouseLeave={() => setHover(false)}
      style={{
        ...ROW, ...style, margin: "0 5px", padding: "0 9px", borderRadius: 4,
        cursor: onClick ? "default" : undefined,
        background: highlight,
        color: highlight ? "#fff" : style?.color,
        ...(highlight ? { "--kantan-panel": highlight } : {}),
      }}
    >{children}</div>
  );
}

// A row's text and icon parts, each in its own font, the secondary ones dimmed.
function Parts({ parts, secondary, dark }) {
  return parts.map((part, i) => part.icon
    ? <Glyph key={i} icon={part.icon} dark={dark} fallbackFont="inherit" />
    : <span key={i} style={{ opacity: secondary || part.secondary ? 0.5 : undefined, textDecoration: part.strike ? "line-through" : undefined, whiteSpace: "pre" }}>{part.text}</span>);
}

// The `rows` of a menu. `fg` is the theme's text colour, when there is one,
// `run` runs a row's command, and `close` closes the menu, as choosing an
// item does. Ticking a check leaves the menu open. With `mark`, each row
// says which node of the view as written it came from.
export function Menu({ rows, fg, dark, run, close, mark }) {
  const tag = row => (mark && row.source ? { "data-kantan-node": nodeMark(row.source) } : undefined);
  const text = fg === undefined ? cssColor("primary", dark) : cssColor(fg, dark);
  const choose = command => () => {
    close();
    run(command);
  };
  return (
    <div style={{ color: text, fontSize: 13, minWidth: 280 }}>
      {rows.map((row, i) => {
        switch (row.type) {
          case "header":
            return <div key={i} {...tag(row)} style={{ ...ROW, height: 22, fontSize: 12, fontWeight: 700 }}>{row.text}</div>;
          case "divider":
            return <div key={i} {...tag(row)} style={{ height: 1, margin: "5px 14px", background: dark ? "rgba(255,255,255,0.14)" : "rgba(0,0,0,0.1)" }} />;
          case "text":
            return (
              <div key={i} {...tag(row)} style={{ ...ROW, fontWeight: row.bold ? 700 : 400, opacity: row.secondary ? 0.5 : undefined, textDecoration: row.strike ? "line-through" : undefined }}>
                {row.text}
              </div>
            );
          case "row": {
            const content = (
              <>
                {row.indicator && <span style={{ width: 3, height: 16, borderRadius: 1.5, background: row.indicator, marginRight: 8, flexShrink: 0 }} />}
                <span style={{ display: "flex", alignItems: "center", gap: 4 }}><Parts parts={row.label} dark={dark} /></span>
                <span style={{ flex: 1, minWidth: 16 }} />
                <span style={{ display: "flex", alignItems: "center", gap: 4 }}><Parts parts={row.detail} secondary dark={dark} /></span>
              </>
            );
            return row.command !== undefined
              ? <Selectable key={i} tag={tag(row)} dark={dark} onClick={choose(row.command)}>{content}</Selectable>
              : <div key={i} {...tag(row)} style={ROW}>{content}</div>;
          }
          case "action":
            return (
              <Selectable key={i} tag={tag(row)} dark={dark} onClick={row.command === undefined ? undefined : choose(row.command)}
                style={{ gap: 4, color: row.command === undefined ? faded(text, 0.35) : undefined }}>
                {row.icon && <Glyph icon={row.icon} dark={dark} fallbackFont="inherit" />}
                {row.iconText !== undefined && <span>{row.iconText}</span>}
                <span>{row.label}</span>
              </Selectable>
            );
          case "check":
            return (
              <Selectable key={i} tag={tag(row)} dark={dark} onClick={() => checkCommand(row) && run(checkCommand(row))}
                style={{ minHeight: 26, gap: 8, color: faded(text, row.checked ? 0.4 : 1) }}>
                <CheckMark checked={row.checked} />
                <span style={{ textDecoration: row.checked ? "line-through" : undefined }}>{row.label}</span>
              </Selectable>
            );
          case "progress":
            return (
              <div key={i} {...tag(row)} style={{ ...ROW, minHeight: 14 }}>
                <div style={{ flex: 1, height: 6, borderRadius: 2, background: cssColor(row.track, dark) }}>
                  <div style={{ width: `${row.value * 100}%`, height: 6, borderRadius: 2, background: cssColor(row.color, dark) }} />
                </div>
              </div>
            );
          case "toggle":
            return (
              <div key={i} {...tag(row)} onClick={() => row.command && run(row.command)} style={{ ...ROW, minHeight: 28, gap: 8 }}>
                <span>{row.label}</span>
                <Switch on={row.on} />
              </div>
            );
          default:
            return null;
        }
      })}
    </div>
  );
}
