// Draws a view the engine resolved, as kantan's popups and rich tooltips
// draw one with SwiftUI.
import { useState } from "react";
import { Glyph } from "./Glyph.jsx";
import { Unsupported } from "./Unsupported.jsx";
import { cssColor, faded } from "./system.js";

const WEIGHTS = { ultraLight: 100, thin: 200, light: 300, regular: 400, medium: 500, semibold: 600, bold: 700, heavy: 800, black: 900 };
const FLEX = { leading: "flex-start", top: "flex-start", center: "center", trailing: "flex-end", bottom: "flex-end" };
// SwiftUI's own spacing between a stack's children when a view names none.
const DEFAULT_SPACING = 8;

// The highlight behind a row the pointer is over.
const hoverFill = native => (native ? "#0a84ff" : faded("#0a84ff", 0.3));

// Whether a node takes all the width it is offered, as SwiftUI lays it
// out: a row holding a spacer does, and so does a stack holding such a row.
function fills(node) {
  switch (node.type) {
    case "spacer":
    case "action":
    case "check":
    case "divider":
    case "scroll":
    case "grid":
      return true;
    case "progress":
      return node.style !== "ring";
    case "rect":
      return node.width === undefined;
    case "vstack":
    case "hstack":
    case "zstack":
      return node.children.some(child => fills(child) && !(child.boxes ?? []).some(fixed));
    default:
      return false;
  }
}

// Whether a box's frame sets its width.
const fixed = box => box.frame?.w !== undefined || box.frame?.maxW !== undefined;

// A node's padding, frame, background, corner radius and opacity, applied
// from the inside out, as SwiftUI applies a view's modifiers. The frame
// goes around the padding, so its sizes take the padding in. With `fill`,
// each box up to one with a width of its own is as wide as it is offered.
function Boxed({ boxes, fill, dark, children }) {
  const list = boxes ?? [];
  const until = list.findIndex(fixed);
  return list.reduce((inner, box, i) => (
    <div key={i} style={{
      display: "flex", flexDirection: "column", alignItems: "stretch", flexShrink: 0,
      alignSelf: fill && (until === -1 || i < until) ? "stretch" : undefined,
      boxSizing: "border-box",
      padding: box.padding && `${box.padding.top}px ${box.padding.trailing}px ${box.padding.bottom}px ${box.padding.leading}px`,
      width: box.frame?.w, height: box.frame?.h,
      minWidth: box.frame?.minW, maxWidth: box.frame?.maxW,
      minHeight: box.frame?.minH, maxHeight: box.frame?.maxH,
      background: cssColor(box.background, dark),
      borderRadius: box.cornerRadius,
      opacity: box.opacity,
    }}>{inner}</div>
  ), children);
}

// A row that highlights under the pointer and runs a command when clicked.
function Row({ height, native, onClick, children, style }) {
  const [hover, setHover] = useState(false);
  return (
    <div
      onClick={onClick}
      onMouseEnter={() => setHover(true)}
      onMouseLeave={() => setHover(false)}
      style={{
        display: "flex", alignItems: "center", height, boxSizing: "border-box",
        borderRadius: 4, cursor: onClick ? "pointer" : "default",
        background: hover && onClick ? hoverFill(native) : undefined,
        color: hover && onClick && native ? "#fff" : undefined,
        ...style,
      }}
    >{children}</div>
  );
}

// A check's mark: an open circle, or a filled one holding a tick.
export function CheckMark({ checked }) {
  return (
    <svg viewBox="0 0 16 16" width={15} height={15} style={{ flexShrink: 0 }}>
      {checked
        ? <>
            <circle cx="8" cy="8" r="7" fill="currentColor" />
            <path d="M4.9 8.3l2.1 2.1l4.1 -4.5" fill="none" stroke="var(--kantan-panel, #fff)" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" />
          </>
        : <circle cx="8" cy="8" r="6.4" fill="none" stroke="currentColor" strokeWidth="1.2" />}
    </svg>
  );
}

// A switch, on or off.
export function Switch({ on }) {
  return (
    <span style={{
      width: 26, height: 15, borderRadius: 8, position: "relative", flexShrink: 0,
      background: on ? "#34c759" : "color-mix(in srgb, currentColor 25%, transparent)",
    }}>
      <span style={{ position: "absolute", top: 1.5, left: on ? 12.5 : 1.5, width: 12, height: 12, borderRadius: 6, background: "#fff", boxShadow: "0 0 1px rgba(0,0,0,0.3)" }} />
    </span>
  );
}

function Node({ node, context }) {
  const { dark, native, fg, run, dismiss, linger } = context;
  const color = value => cssColor(value, dark);
  const children = (node.children ?? []).map((child, i) => <ViewNode key={i} node={child} context={context} />);
  // Runs a command the node holds. Most close the popup as they do.
  // One that doesn't leaves it open until the pointer leaves it.
  const runs = (command, closes = true) => () => {
    if (closes) dismiss();
    else linger?.();
    if (command) run(command);
  };

  switch (node.type) {
    case "unsupported":
      return <Unsupported what={node.what} />;
    case "vstack":
      return <div style={{ display: "flex", flexDirection: "column", alignItems: FLEX[node.align], gap: node.spacing ?? DEFAULT_SPACING, alignSelf: fills(node) ? "stretch" : undefined }}>{children}</div>;
    case "hstack": {
      const style = { display: "flex", alignItems: FLEX[node.align], gap: node.spacing ?? DEFAULT_SPACING, alignSelf: "stretch" };
      return node.command
        ? <Row native={native} onClick={runs(node.command)} style={style}>{children}</Row>
        : <div style={style}>{children}</div>;
    }
    case "zstack": {
      const [vertical, horizontal] = {
        topLeading: ["start", "start"], top: ["start", "center"], topTrailing: ["start", "end"],
        leading: ["center", "start"], center: ["center", "center"], trailing: ["center", "end"],
        bottomLeading: ["end", "start"], bottom: ["end", "center"], bottomTrailing: ["end", "end"],
      }[node.align];
      return (
        <div style={{ display: "grid", alignItems: vertical, justifyItems: horizontal }}>
          {children.map((child, i) => <div key={i} style={{ gridArea: "1 / 1" }}>{child}</div>)}
        </div>
      );
    }
    case "scroll":
      return (
        <div style={{
          display: "flex", flexDirection: node.axis === "horizontal" ? "row" : "column", alignItems: "center",
          overflowX: node.axis === "horizontal" ? "auto" : "hidden", overflowY: node.axis === "horizontal" ? "hidden" : "auto",
          alignSelf: "stretch", flex: "1 1 auto", minHeight: 0,
        }}>{children}</div>
      );
    case "spacer":
      return <span style={{ flex: "1 1 0", minWidth: node.minLength ?? DEFAULT_SPACING, minHeight: node.minLength ?? DEFAULT_SPACING }} />;
    case "text":
      return (
        <span style={{
          fontSize: node.size, fontWeight: WEIGHTS[node.weight], color: color(node.color),
          opacity: node.secondary ? 0.5 : undefined, whiteSpace: "pre-wrap",
          textDecoration: node.strikethrough ? "line-through" : undefined,
          textAlign: { leading: "left", center: "center", trailing: "right" }[node.align],
        }}>{node.text}</span>
      );
    case "icon":
      return node.icon.type === "unsupported"
        ? <Unsupported what={node.icon.what} />
        : <Glyph icon={node.icon} color={node.color} dark={dark} fallbackFont="inherit" />;
    case "divider":
      return <div style={{ alignSelf: "stretch", padding: "4px 8px" }}><div style={{ height: 1, background: dark ? "rgba(255,255,255,0.1)" : "rgba(0,0,0,0.1)" }} /></div>;
    case "header":
      return <span style={{ fontSize: 12, fontWeight: 700, color: color(node.color), height: 22, display: "flex", alignItems: "center" }}>{node.text}</span>;
    case "rect":
    case "circle":
    case "capsule":
      return (
        <span style={{
          display: "block", flexShrink: 0, boxSizing: "border-box",
          width: node.width, height: node.height,
          flex: node.width === undefined ? "1 1 auto" : undefined,
          alignSelf: node.height === undefined ? "stretch" : undefined,
          background: color(node.color),
          borderRadius: node.type === "rect" ? node.cornerRadius : node.type === "circle" ? "50%" : 9999,
          border: node.stroke && `${node.stroke.width}px solid ${color(node.stroke.color)}`,
        }} />
      );
    case "action":
      return (
        <Row height={28} native={native} onClick={runs(node.command)} style={{ gap: 8, padding: "0 14px", alignSelf: "stretch", color: color(fg), fontSize: 13 }}>
          {node.icon && (node.icon.type === "unsupported"
            ? <Unsupported what={node.icon.what} />
            : <Glyph icon={node.icon} dark={dark} fallbackFont="inherit" width={16} />)}
          <span>{node.label}</span>
        </Row>
      );
    case "check":
      return (
        <div
          onClick={runs(node.checked ? node.uncheckedCommand ?? node.command : node.command, false)}
          style={{
            display: "flex", alignItems: "center", gap: 8, height: 26, padding: "0 14px", boxSizing: "border-box",
            alignSelf: "stretch", cursor: "pointer", fontSize: 13, color: faded(color(fg), node.checked ? 0.4 : 1),
          }}
        >
          <CheckMark checked={node.checked} />
          <span style={{ textDecoration: node.checked ? "line-through" : undefined }}>{node.label}</span>
        </div>
      );
    case "toggle":
      return (
        <div onClick={runs(node.command)} style={{
          display: "flex", alignItems: "center", gap: 8, height: 26, padding: "0 14px", boxSizing: "border-box",
          alignSelf: "stretch", cursor: "pointer", fontSize: 13, color: color(fg),
        }}>
          <span>{node.label}</span>
          <Switch on={node.on} />
        </div>
      );
    case "button":
      return (
        <span onClick={runs(node.command, node.dismiss !== false)} style={{ display: "inline-flex", alignItems: "center", gap: 6, cursor: "pointer", fontSize: 13, color: color("accent") }}>
          {node.icon && (node.icon.type === "unsupported"
            ? <Unsupported what={node.icon.what} />
            : <Glyph icon={node.icon} dark={dark} fallbackFont="inherit" />)}
          {node.label !== undefined && <span>{node.label}</span>}
        </span>
      );
    case "progress":
      return node.style === "ring"
        ? (
          // A stroke of the ring's width along the edge of the space it is
          // given, whatever its size, as kantan draws it.
          <svg width="100%" height="100%" style={{ flex: "1 1 auto", minWidth: 12, minHeight: 12, transform: "rotate(-90deg)", overflow: "visible" }}>
            <circle cx="50%" cy="50%" r="50%" fill="none" stroke={color(node.track)} strokeWidth={node.strokeWidth} />
            {node.value > 0 && (
              <circle cx="50%" cy="50%" r="50%" fill="none" stroke={color(node.color)} strokeWidth={node.strokeWidth} strokeLinecap="round" pathLength="1" strokeDasharray={`${node.value} 1`} />
            )}
          </svg>
        )
        : (
          <div style={{ alignSelf: "stretch", flex: "1 1 auto", height: 6, borderRadius: 2, background: color(node.track), minWidth: 8 }}>
            <div style={{ width: `${node.value * 100}%`, height: 6, borderRadius: 2, background: color(node.color) }} />
          </div>
        );
    case "badge":
      return <span style={{ fontSize: 11, fontWeight: 500, padding: "2px 8px", borderRadius: 9999, whiteSpace: "nowrap", background: color(node.color), color: color(node.textColor) }}>{node.text}</span>;
    case "grid":
      return <div style={{ display: "grid", gridTemplateColumns: `repeat(${node.columns}, 1fr)`, gap: node.spacing, alignSelf: "stretch", justifyItems: "center" }}>{children}</div>;
    default:
      return null;
  }
}

// The value of the attribute that says which node of the view as written
// something drawn came from.
export const nodeMark = source => JSON.stringify(source);

function ViewNode({ node, context }) {
  const drawn = <Boxed boxes={node.boxes} fill={fills(node)} dark={context.dark}><Node node={node} context={context} /></Boxed>;
  // The mark takes no room of its own, leaving the layout as it is.
  return context.mark && node.source
    ? <div data-kantan-node={nodeMark(node.source)} style={{ display: "contents" }}>{drawn}</div>
    : drawn;
}

// The view `nodes` the engine resolved. `context` holds the appearance
// (`dark`, `native`), the default text colour `fg`, `run` to run a command
// and `dismiss` to close the panel the view is in. With `mark`, each node
// drawn says which node of the view as written it came from.
export function ViewTree({ nodes, context }) {
  return nodes.map((node, i) => <ViewNode key={i} node={node} context={context} />);
}
