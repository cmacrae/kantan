// The dialog that adds a module to the bar: a module of each type and
// each bundled plugin, drawn as it would look, a plugin someone is about
// to write or has output from, and a module someone shared by link.
import { useMemo, useState } from "react";
import { BarView } from "../../components/BarView.jsx";
import { BUILT_INS, PLUGIN_ABOUT } from "../../builder/catalog.js";
import { decodeModuleLink, decodeThemeLink, readFragment } from "../../builder/share.js";
import { selectedThemes } from "../../builder/theme.js";
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
// `onShared(shared, theme)` adds a module from a link, with the theme
// that came with it when the bar is to take that too.
export function AddModule({ onClose, onBuiltIn, onPlugin, onPasted, onShared, onOwn, taken, draw, dark }) {
  const { catalog } = useBuilder();
  const [link, setLink] = useState("");
  const [problem, setProblem] = useState();
  // A module someone shared, from its link or the part of it after the #.
  // One that came with its theme waits to hear whether the bar takes the
  // theme too.
  const [themed, setThemed] = useState();
  const open = async () => {
    const asked = readFragment(link.trim().slice(link.indexOf("#") + 1));
    if (asked?.module === undefined) return setProblem("Not a module link.");
    try {
      const shared = await decodeModuleLink(asked.module, catalog);
      if (asked.theme === undefined) return onShared(shared);
      return setThemed({ shared, theme: await decodeThemeLink(asked.theme) });
    } catch (error) {
      return setProblem(error.message);
    }
  };
  const [name, setName] = useState("my-plugin");
  const [pasted, setPasted] = useState("");
  const clash = name === "" || taken.includes(name);

  // Each thing to add as the bar would draw it, in the states it starts
  // with.
  const bars = useMemo(() => ({
    types: Object.fromEntries(Object.entries(BUILT_INS).map(([type, { module, states }]) => [type, draw({ name: type, type, ...module }, states ?? [])])),
    plugins: Object.fromEntries(Object.entries(catalog.plugins).map(([plugin, { module, states }]) => [plugin, draw(module, states ?? [])])),
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
          onChange={event => { setLink(event.target.value); setProblem(undefined); setThemed(undefined); }} onKeyDown={event => event.key === "Enter" && link.trim() !== "" && open()} />
        <Button icon="plus" disabled={link.trim() === ""} onClick={open}>Add it</Button>
      </div>
      {problem !== undefined && <div className="kb-problem">{problem}</div>}
      {themed && (
        <>
          <div className="kb-note">
            {themed.shared.module.name} came with the theme it was drawn in, {selectedThemes(themed.theme.selection).join(" and ")}. Taking the theme
            changes the whole bar to it.
          </div>
          <div className="kb-row" style={{ flexWrap: "wrap" }}>
            <Button kind="primary" onClick={() => onShared(themed.shared)}>Add the module only</Button>
            <Button onClick={() => onShared(themed.shared, themed.theme)}>Add it and take its theme</Button>
          </div>
        </>
      )}
    </Modal>
  );
}
