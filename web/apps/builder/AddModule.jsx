// The dialog that adds a module to the bar: a module of each type and
// each bundled plugin, drawn as it would look, a plugin someone is about
// to write or has output from, and a module someone shared by link.
import { useMemo, useState } from "react";
import { BarView } from "../../components/BarView.jsx";
import { BUILT_INS, PLUGIN_ABOUT } from "../../builder/catalog.js";
import { bindStates, settingDefaults } from "../../builder/settings.js";
import { decodeModuleLink, readFragment } from "../../builder/share.js";
import { dict } from "../../engine/values.js";
import { Button, Modal, useBuilder } from "./ui.jsx";

// Something to add, under the module it would be: a strip of bar holding
// it, then what it's called and is for.
function Card({ bar, dark, label, about, onClick }) {
  return (
    <button type="button" className="kb-addcard" onClick={onClick}>
      <span className="strip" aria-hidden="true"><BarView bar={bar} dark={dark} run={() => {}} interactive={false} /></span>
      <span><b>{label}</b>{about !== undefined && <span>{about}</span>}</span>
    </button>
  );
}

// `draw(module, states)` gives a bar holding one module alone, in `dark`
// or light. `taken` are the names the bar's modules have.
export function AddModule({ onClose, onBuiltIn, onPlugin, onPasted, onShared, onOwn, taken, draw, dark }) {
  const { catalog } = useBuilder();
  const [link, setLink] = useState("");
  const [problem, setProblem] = useState();
  // A module someone shared, from its link or the part of it after the #.
  const open = async () => {
    const asked = readFragment(link.trim().slice(link.indexOf("#") + 1));
    if (asked?.module === undefined) return setProblem("Not a module link.");
    try {
      return onShared(await decodeModuleLink(asked.module, catalog));
    } catch (error) {
      return setProblem(error.message);
    }
  };
  const [name, setName] = useState("my-plugin");
  const [pasted, setPasted] = useState("");
  const clash = name === "" || taken.includes(name);

  // Each thing to add as the bar would draw it, in the states it starts
  // with. A plugin's are drawn with its settings' defaults.
  const bars = useMemo(() => ({
    types: Object.fromEntries(Object.entries(BUILT_INS).map(([type, { module, states }]) => [type, draw({ name: type, type, ...module }, states ?? [])])),
    plugins: Object.fromEntries(Object.entries(catalog.plugins).map(([plugin, { module, states, settings }]) => [
      plugin,
      draw(module, bindStates(states ?? [], dict(module.config)?.settings ?? {}, settings === undefined ? {} : settingDefaults(settings))),
    ])),
  }), [catalog, dark]);

  return (
    <Modal title="Add a module" onClose={onClose} wide>
      <div className="kb-h">Built in</div>
      <div className="kb-addgrid">
        {Object.entries(BUILT_INS).map(([type, { label }]) => (
          <Card key={type} bar={bars.types[type]} dark={dark} label={label} onClick={() => onBuiltIn(type)} />
        ))}
      </div>
      <div className="kb-h">Bundled plugins</div>
      <div className="kb-addgrid">
        {Object.keys(catalog.plugins).map(plugin => (
          <Card key={plugin} bar={bars.plugins[plugin]} dark={dark} label={plugin} about={PLUGIN_ABOUT[plugin]} onClick={() => onPlugin(plugin)} />
        ))}
      </div>

      <div className="kb-h">Your own plugin</div>
      <div className="kb-note">Build its view here, then take the JSON it has to print.</div>
      <div className="kb-row" style={{ padding: "4px 0" }}>
        <input type="text" aria-label="The plugin's name" value={name} spellCheck={false} onChange={event => setName(event.target.value)} />
        <Button kind="primary" icon="pencil" disabled={clash} onClick={() => onOwn(name)}>Build it</Button>
      </div>
      {clash && <div className="kb-problem">{name === "" ? "The module needs a name" : "Another module has that name"}</div>}
      <details className="kb-group">
        <summary>Paste its output</summary>
        <div>
          <div className="kb-note">JSON or text. The bar draws it under the name above.</div>
          <textarea aria-label="The plugin's output" rows={5} spellCheck={false} value={pasted} placeholder={'{ "value": "3 unread", "icon": "mail" }'}
            onChange={event => setPasted(event.target.value)} />
          <div style={{ marginTop: 8 }}>
            <Button icon="plus" disabled={clash || pasted.trim() === ""} onClick={() => onPasted(name, pasted)}>Add it</Button>
          </div>
        </div>
      </details>

      <div className="kb-h">A module someone shared</div>
      <div className="kb-row" style={{ padding: "4px 0" }}>
        <input type="text" aria-label="A link to a module" value={link} spellCheck={false} placeholder="Paste a link to a module"
          onChange={event => { setLink(event.target.value); setProblem(undefined); }} onKeyDown={event => event.key === "Enter" && link.trim() !== "" && open()} />
        <Button icon="plus" disabled={link.trim() === ""} onClick={open}>Add it</Button>
      </div>
      {problem !== undefined && <div className="kb-problem">{problem}</div>}
    </Modal>
  );
}
