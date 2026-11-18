// The engine: kantan's config, theme, style, template and view semantics in
// plain JavaScript, turning a document into a bar ready to draw.
export { resolveBar } from "./bar.js";
export { checkCommand, moduleCommands } from "./commands.js";
export { barColor, parseHex, viewColor, withOpacity } from "./color.js";
export { loadConfig, parseFont } from "./config.js";
export { DOCUMENT_VERSION, nextState, validateDocument } from "./document.js";
export { iconTable, noIcons, resolveIcon, scaledSize } from "./icons.js";
export { menuRows } from "./menu.js";
export { MENU_BAR, NOTCH } from "./menubar.js";
export { MODULE_TYPES } from "./modules/index.js";
export { formatDate, ordinalSuffix } from "./dates.js";
export { shuffledRainbow } from "./modules/workspace.js";
export { OVERLAP_MARGIN, resolveOverlap } from "./overlap.js";
export { parseOutput } from "./output.js";
export { createStyler, parseStyle } from "./style.js";
export { createResolver, fillTooltip, isURLCommand } from "./template.js";
export { loadTheme, resolveAllThemeTemplates, resolveThemeTemplate } from "./theme.js";
export { decodeJsonView, decodeYamlView, NODE_FIELDS, NODE_SLOTS, NODE_TYPES, resolveView } from "./view.js";
