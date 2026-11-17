// The quick settings that drop from a module clicked in the bar: the
// first parts of its design, what it shows and how it looks, the example
// it is previewed with, and the way to the rest.
import { useEffect } from "react";
import { Looks, Shows, kindOf } from "./ModuleEditor.jsx";
import { PreviewWith } from "./StateEditor.jsx";
import { Button, useBuilder } from "./ui.jsx";

// `module` is the module's config, `drawn` the module as the bar draws it,
// `states` its examples and `shown` the name of the one showing. `at` is
// where the module sits: `x`, its centre, and `y`, its foot, within a
// parent `width` wide. `onEdit` opens the rest of its design.
export function QuickEdit({ module, drawn, states = [], shown, at, width, onChange, onShow, onEdit, onRemove, onClose }) {
  const { catalog } = useBuilder();
  useEffect(() => {
    const key = event => event.key === "Escape" && onClose();
    window.addEventListener("keydown", key);
    return () => window.removeEventListener("keydown", key);
  }, [onClose]);

  const example = states.find(state => state.name === shown) ?? states[0];
  const size = Math.min(400, width - 16);
  const left = Math.max(8, Math.min(at.x - size / 2, width - size - 8));
  return (
    <div className="kb-quick" role="dialog" aria-label={`Quick settings for ${module.name}`} style={{ left, top: at.y + 10, width: size }}>
      <span className="arrow" style={{ left: Math.max(14, Math.min(at.x - left, size - 14)) }} />
      <div className="head">
        <b>{module.name}</b>
        <span>{kindOf(module, catalog)}</span>
        <Button kind="plain" icon="x" aria-label="Close" onClick={onClose} />
      </div>

      <Shows module={module} onChange={onChange} compact />
      <Looks module={module} drawn={drawn} example={example} onChange={onChange} compact />
      <PreviewWith module={module} drawn={drawn} states={states} shown={shown} onShow={onShow} compact />

      <div className="foot">
        <Button kind="plain" icon="trash" onClick={onRemove}>Remove</Button>
        <Button kind="primary" icon="pencil" onClick={onEdit}>Edit</Button>
      </div>
    </div>
  );
}
