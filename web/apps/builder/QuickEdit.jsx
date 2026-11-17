// The quick settings that drop from a module clicked in the bar: its
// icon, its colours and shape, the state it shows, and the way to the
// rest of its settings.
import { useEffect } from "react";
import { BUILT_INS } from "../../builder/catalog.js";
import { getIn, prune, setIn } from "../../builder/schema.js";
import { cssColor } from "../../components/system.js";
import { dict } from "../../engine/values.js";
import { ColorField, IconField, Row, TextField } from "./Fields.jsx";
import { Button } from "./ui.jsx";

const SHAPES = ["pill", "box", "underline", "overline"];

// The one setting of its own a type is most often changed by.
const MAIN_FIELD = {
  text: { path: ["config", "value"], label: "Text" },
  clock: { path: ["config", "format"], label: "Format" },
  command: { path: ["config", "command"], label: "Command" },
};

// `module` is the module's config, `drawn` the module as the bar draws it,
// `states` its states and `shown` the name of the one showing. `at` is where the module sits: `x`, its centre,
// and `y`, its foot, within a parent `width` wide. `dark` is the
// appearance the bar is drawn in, whose colours a style split by
// appearance has changed.
export function QuickEdit({ module, drawn, states = [], shown, at, width, dark, onChange, onShow, onEdit, onRemove, onClose }) {
  useEffect(() => {
    const key = event => event.key === "Escape" && onClose();
    window.addEventListener("keydown", key);
    return () => window.removeEventListener("keydown", key);
  }, [onClose]);

  const split = dict(module.style) !== undefined && (module.style.light !== undefined || module.style.dark !== undefined);
  const style = split ? ["style", dark ? "dark" : "light"] : ["style"];
  const get = path => getIn(module, path);
  const set = (path, value) => onChange(prune(setIn(module, path, value)));
  const main = MAIN_FIELD[module.type];
  const current = states.find(state => state.name === shown) ?? states[0];

  // The colours the bar draws the module in, shown where none is set here.
  const iconColor = cssColor(drawn?.icon?.color, dark), textColor = cssColor(drawn?.text?.[0]?.color, dark);
  // A plugin's output can carry colours of its own, which win.
  const ownStyle = dict(dict(current?.output)?.style) !== undefined;

  const size = Math.min(400, width - 16);
  const left = Math.max(8, Math.min(at.x - size / 2, width - size - 8));
  return (
    <div className="kb-quick" role="dialog" aria-label={`Quick settings for ${module.name}`} style={{ left, top: at.y + 10, width: size }}>
      <span className="arrow" style={{ left: Math.max(14, Math.min(at.x - left, size - 14)) }} />
      <div className="head">
        <b>{module.name}</b>
        <span>{BUILT_INS[module.type]?.label ?? module.type}</span>
        <Button kind="plain" icon="x" aria-label="Close" onClick={onClose} />
      </div>

      {main && <Row label={main.label}><TextField value={get(main.path)} onChange={value => set(main.path, value)} label={main.label} /></Row>}
      {module.type !== "drawer" && (
        <Row label="Icon"><IconField value={module.icon} onChange={value => set(["icon"], value)} label="Icon" /></Row>
      )}
      <Row label="Colour"><ColorField value={get([...style, "fg"])} onChange={value => set([...style, "fg"], value)} label="Colour" fallback={iconColor ?? textColor} /></Row>
      <Row label="Icon colour"><ColorField value={get([...style, "icon", "fg"])} onChange={value => set([...style, "icon", "fg"], value)} label="Icon colour" fallback={iconColor} /></Row>
      <Row label="Text colour"><ColorField value={get([...style, "text", "fg"])} onChange={value => set([...style, "text", "fg"], value)} label="Text colour" fallback={textColor} /></Row>
      <Row label="Shape">
        <div className="kb-chips" style={{ padding: 0 }} role="group" aria-label="Shape">
          {[undefined, ...SHAPES].map(shape => (
            <button key={shape ?? "none"} type="button" className="kb-chip" aria-pressed={get([...style, "shape"]) === shape}
              onClick={() => set([...style, "shape"], shape)}>{shape ?? "none"}</button>
          ))}
        </div>
      </Row>
      {get([...style, "shape"]) !== undefined && (
        <Row label="Shape colour"><ColorField value={get([...style, "bg"])} onChange={value => set([...style, "bg"], value)} label="Shape colour" /></Row>
      )}
      {ownStyle && (
        <div className="kb-note">
          In this state the module's command sets colours of its own, which win over these. Change them in its settings, under Edit.
        </div>
      )}
      {split && <div className="kb-note">These colours are the ones for the {dark ? "dark" : "light"} appearance.</div>}

      {states.length > 1 && (
        <Row label="Showing">
          <div className="kb-chips" style={{ padding: 0 }} role="group" aria-label="The state shown">
            {states.map(state => (
              <button key={state.name} type="button" className="kb-chip" aria-pressed={state === current} onClick={() => onShow(state.name)}>{state.name}</button>
            ))}
          </div>
        </Row>
      )}

      <div className="foot">
        <Button kind="plain" icon="trash" onClick={onRemove}>Remove</Button>
        <Button kind="primary" icon="pencil" onClick={onEdit}>Edit</Button>
      </div>
    </div>
  );
}
