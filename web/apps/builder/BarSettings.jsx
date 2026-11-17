// Edits the bar itself: the theme it's drawn in, its size and its fonts.
import { prune } from "../../builder/schema.js";
import { Properties } from "./Fields.jsx";
import { ThemePicker } from "./ThemePicker.jsx";
import { Ic } from "./ui.jsx";

// The bar's own settings, described as the module config schema describes
// a module's.
const BAR_SCHEMA = {
  type: "object",
  properties: {
    height: { type: "integer", default: 33, minimum: 1, description: "The bar's height in points." },
    padding: { type: "integer", default: 10, minimum: 0, description: "Horizontal padding per module, in points." },
    iconTextSpacing: { type: "integer", default: 5, minimum: 0, description: "Icon to text spacing, in points." },
    cornerRadius: { type: "number", default: 0, minimum: 0, description: "Corner radius, in points." },
    blur: { type: "integer", default: 0, minimum: 0, maximum: 6, description: "Background blur: 1 strongest, 6 weakest, 0 off." },
    gaps: {
      type: "object",
      description: "Gaps to the screen's edges, in points.",
      properties: {
        top: { type: "integer", default: 0, minimum: 0, description: "Top gap." },
        left: { type: "integer", default: 0, minimum: 0, description: "Left gap." },
        right: { type: "integer", default: 0, minimum: 0, description: "Right gap." },
      },
    },
    fonts: {
      type: "object",
      description: "The fonts of every module's text and icon, as Name:Size or Name:Weight:Size.",
      properties: { text: { type: "string", default: "system:Helvetica Neue:13" }, icon: { type: "string", default: "tabler-icons:regular:15" } },
    },
    style: { $ref: "#/$defs/StyleConfig", description: "The bar's colours. Without a theme, light and dark each need fg and bg." },
  },
};

// `config` is the config without its modules, `themes` every theme file it
// can name, `own` the names of those the document holds, and `problem` why
// kantan can't load it, when it can't. `theming` holds what the theme
// picker starts: `onNew`, `onEdit`, `onCopy`, `onImport` and
// `onImportSchemes`. Keys the form has no field for stay as they are.
export function BarSettings({ config, themes, own, problem, onChange, theming }) {
  const theme = config.theme;
  const { theme: _, modules: __, ...rest } = config;
  return (
    <>
      <h2><Ic name="adjustments-horizontal" /><span>Bar Settings</span></h2>
      <div className="kb-body">
        {problem !== undefined && <div className="kb-problem" style={{ paddingBottom: 8 }}>kantan can't load this config: {problem}</div>}
        <div className="kb-h">Appearance</div>
        <ThemePicker theme={theme} themes={themes} own={own} {...theming}
          onChange={next => onChange(prune({ ...config, theme: next }) ?? {})} />
        <div className="kb-h">Size, fonts and colours</div>
        <Properties node={BAR_SCHEMA} value={rest} name="bar" onChange={value => onChange({ ...(theme === undefined ? {} : { theme }), ...value })} />
      </div>
    </>
  );
}
