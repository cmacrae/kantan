// A view as a native menu shows it. A menu is a flat list of rows, so
// stacks flatten into their children, an hstack becomes one row, and the
// nodes a menu has no row for are left out.
// Each row has its `source`, the path of the node it came from in the view
// as written. A row an hstack makes also lists the `sources` of the nodes
// within the hstack that went into it.
import { parseHex } from "./color.js";
import { resolveIcon } from "./icons.js";

const MENU_FONT_SIZE = 13;
const INTERACTIVE = ["action", "check", "toggle", "button"];
const BOLD = ["bold", "semibold", "heavy", "black"];

// An icon in a menu row: the icon font's glyph, or the name as text.
function iconPart(name, size, icons) {
  const icon = resolveIcon(name, size ?? MENU_FONT_SIZE, icons);
  return icon.glyph === undefined ? { text: name, secondary: false, strike: false } : { icon };
}

// The text and icon parts nested within `node`, leaving out empty ones.
function nestedParts(node, r, icons) {
  switch (node.type) {
    case "text": {
      const text = r.resolve(node.content);
      return text === "" ? [] : [{ text, secondary: node.style === "secondary", strike: node.strikethrough === true }];
    }
    case "icon": {
      const name = r.resolve(node.name);
      return name === "" ? [] : [iconPart(name, node.size, icons)];
    }
    case "vstack":
    case "hstack":
    case "group":
      return node.children.flatMap(child => nestedParts(child, r, icons));
    default:
      return [];
  }
}

// An hstack as one row: the parts before its first spacer are the label,
// those after it the detail, and its first coloured rect the indicator.
function hstackRow(node, r, icons) {
  const label = [], detail = [], sources = [];
  let side = label;
  let indicator;
  for (const child of node.children) {
    const before = label.length + detail.length;
    switch (child.type) {
      case "spacer":
        side = detail;
        sources.push(child.path);
        break;
      case "text":
        side.push({ text: r.resolve(child.content), secondary: child.style === "secondary", strike: child.strikethrough === true });
        break;
      case "icon": {
        const name = r.resolve(child.name);
        if (name !== "") side.push(iconPart(name, child.size, icons));
        break;
      }
      case "rect":
        if (child.color !== undefined && indicator === undefined) {
          indicator = r.resolve(child.color) || undefined;
          sources.push(child.path);
        }
        break;
      case "progress":
        break;
      default:
        side.push(...nestedParts(child, r, icons));
    }
    if (label.length + detail.length > before) sources.push(child.path);
  }
  if (!label.length && !detail.length) return [];
  const row = { type: "row", label, detail, source: node.path, sources };
  if (indicator !== undefined && parseHex(indicator)) row.indicator = parseHex(indicator);
  if (node.command !== undefined) row.command = r.resolveCommand(node.command);
  return [row];
}

// The rows of the menu the decoded view `node` makes, with `r` resolving
// its placeholders and `icons` its icons.
export function menuRows(node, r, icons) {
  if (!node) return [];
  const each = nodes => nodes.flatMap(child => menuRows(child, r, icons));
  const command = value => (value === undefined ? undefined : r.resolveCommand(value));
  const source = node.path;
  switch (node.type) {
    case "vstack":
    case "zstack":
    case "scroll":
    case "group":
    case "grid":
      return each(node.children);
    case "hstack":
      return node.children.some(child => INTERACTIVE.includes(child.type)) ? each(node.children) : hstackRow(node, r, icons);
    case "action": {
      const name = node.icon === undefined ? "" : r.resolve(node.icon);
      const row = { type: "action", label: r.resolve(node.label ?? ""), command: command(node.command), source };
      if (name !== "") {
        const icon = resolveIcon(name, MENU_FONT_SIZE, icons);
        if (icon.glyph === undefined) row.iconText = name;
        else row.icon = icon;
      }
      return [row];
    }
    case "check":
      return [{
        type: "check", label: r.resolve(node.label ?? ""),
        checked: node.checked === undefined ? false : r.resolveBool(node.checked),
        command: command(node.command), uncheckedCommand: command(node.uncheckedCommand), source,
      }];
    case "toggle":
      return [{
        type: "toggle", label: r.resolve(node.label ?? ""),
        on: node.on === undefined ? false : r.resolveBool(node.on), command: command(node.command), source,
      }];
    case "header":
      return [{ type: "header", text: r.resolve(node.content), source }];
    case "divider":
      return [{ type: "divider", source }];
    case "text":
      return [{
        type: "text", text: r.resolve(node.content), bold: BOLD.includes(node.weight),
        secondary: node.style === "secondary", strike: node.strikethrough === true, source,
      }];
    case "foreach":
      return (r.data[node.items] ?? []).flatMap(element => menuRows(node.child, r.scoped(element), icons));
    case "if":
      return menuRows(r.truthy(node.condition) ? node.then : node.else, r, icons);
    default:
      return [];
  }
}
