// kantan's module types. Each loads its `config` block, returning undefined
// when kantan would reject the module, and makes the state it shows. A type
// listed without an implementation is one kantan has and the preview can't
// draw yet.
import command from "./command.js";
import icon from "./icon.js";
import text from "./text.js";

const implemented = { command, icon, text };

export const MODULE_TYPES = [
  "text", "clock", "power", "command", "workspace", "volume", "wifi",
  "bluetooth", "icon", "drawer", "focus",
];

export const moduleType = type => (Object.hasOwn(implemented, type) ? implemented[type] : undefined);
