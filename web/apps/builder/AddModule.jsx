// The dialog that adds a module to the bar: a module of each type, each
// bundled plugin, or a plugin of someone's own from the output it prints.
import { useState } from "react";
import { BUILT_INS } from "../../builder/catalog.js";
import { Button, Ic, Modal, useBuilder } from "./ui.jsx";

export function AddModule({ onClose, onBuiltIn, onPlugin, onPasted, taken }) {
  const { catalog } = useBuilder();
  const [name, setName] = useState("my-plugin");
  const [pasted, setPasted] = useState("");
  const clash = name === "" || taken.includes(name);
  return (
    <Modal title="Add a module" onClose={onClose}>
      <div className="kb-h">Built in</div>
      <div className="kb-grid">
        {Object.entries(BUILT_INS).map(([type, { label, icon }]) => (
          <button key={type} type="button" className="kb-card" onClick={() => onBuiltIn(type)}><Ic name={icon} size={18} />{label}</button>
        ))}
      </div>
      <div className="kb-h">Bundled plugins</div>
      <div className="kb-grid">
        {Object.entries(catalog.plugins).map(([plugin, { module }]) => (
          <button key={plugin} type="button" className="kb-card" onClick={() => onPlugin(plugin)}><Ic name={module.icon ?? "puzzle"} size={18} />{plugin}</button>
        ))}
      </div>
      <div className="kb-h">Your own plugin</div>
      <div className="kb-note">Paste what your plugin prints, JSON or text, and the bar draws it.</div>
      <div className="kb-row" style={{ padding: "4px 0" }}>
        <input type="text" aria-label="The module's name" value={name} spellCheck={false} onChange={event => setName(event.target.value)} />
      </div>
      <textarea aria-label="The plugin's output" rows={6} spellCheck={false} value={pasted} placeholder={'{ "value": "3 unread", "icon": "mail" }'}
        onChange={event => setPasted(event.target.value)} />
      {clash && <div className="kb-problem">{name === "" ? "The module needs a name" : "Another module has that name"}</div>}
      <div style={{ marginTop: 8 }}>
        <Button kind="primary" icon="plus" disabled={clash || pasted.trim() === ""} onClick={() => onPasted(name, pasted)}>Add it</Button>
      </div>
    </Modal>
  );
}
