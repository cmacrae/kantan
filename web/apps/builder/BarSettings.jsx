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
    padding: { type: "integer", default: 10, minimum: 0, description: "The space on either side of each module, in points. Two modules side by side sit twice this far apart." },
    iconTextSpacing: { type: "integer", default: 5, minimum: 0, description: "The space between a module's icon and its text, in points." },
    cornerRadius: { type: "number", default: 0, minimum: 0, description: "How round the corners of the bar's background are, in points." },
    blur: { type: "integer", default: 0, minimum: 0, maximum: 6, description: "Lets what is behind the bar show through, blurred: 1 the most, 6 the least, 0 not at all." },
    gaps: {
      type: "object",
      description: "The room left between the bar and the screen's edges, in points.",
      properties: {
        top: { type: "integer", default: 0, minimum: 0, description: "How far the bar sits below the top of the screen." },
        left: { type: "integer", default: 0, minimum: 0, description: "How far the bar's left end sits from the screen's left edge." },
        right: { type: "integer", default: 0, minimum: 0, description: "How far the bar's right end sits from the screen's right edge." },
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
        <Properties node={BAR_SCHEMA} value={rest} onChange={value => onChange({ ...(theme === undefined ? {} : { theme }), ...value })} />
      </div>
    </>
  );
}
