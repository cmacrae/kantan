// Edits one module: its settings as a form made from the config schema,
// the states the bar shows it in, and its YAML as written.
import { useState } from "react";
import { BUILT_INS, pluginOf } from "../../builder/catalog.js";
import { configSchema, deref, getIn, prune, setIn } from "../../builder/schema.js";
import { dict } from "../../engine/values.js";
import { ColorField, Group, IconField, Properties, Row } from "./Fields.jsx";
import { StateEditor } from "./StateEditor.jsx";
import { Button, Ic, YamlArea, useBuilder } from "./ui.jsx";

const PLACEMENTS = [
  ["left", "Left"],
  ["right", "Right"],
  ["notchleft", "Left of the notch"],
  ["notchright", "Right of the notch"],
  ["notchleft|left", "Left of the notch, or left without one"],
  ["notchright|right", "Right of the notch, or right without one"],
];

// The module's name, changed once it is one no other module has.
function NameField({ name, taken, onRename }) {
  const [draft, setDraft] = useState(name ?? "");
  const clash = draft !== name && (draft === "" || taken.includes(draft));
  const commit = () => (clash || draft === name ? setDraft(name ?? "") : onRename(draft));
  return (
    <Row label="name" description="What the module is called. Each module needs a name of its own.">
      <div>
        <input type="text" aria-label="name" value={draft} spellCheck={false} onChange={event => setDraft(event.target.value)}
          onBlur={commit} onKeyDown={event => event.key === "Enter" && event.target.blur()} />
        {clash && <div className="kb-problem">{draft === "" ? "A module needs a name" : "Another module has that name"}</div>}
      </div>
    </Row>
  );
}

// Where the colours within `value` are, each a list of keys: the strings
// that are a hex colour or a colour of the theme.
function colourPaths(value, path = []) {
  if (typeof value === "string") return /^(#?[0-9a-fA-F]{6}([0-9a-fA-F]{2})?|\{theme\([^)]+\)\})$/.test(value) ? [path] : [];
  if (value === null || typeof value !== "object") return [];
  return Object.entries(value).flatMap(([key, item]) => colourPaths(item, [...path, Array.isArray(value) ? Number(key) : key]));
}

function Settings({ module, taken, onChange }) {
  const { schema } = useBuilder();
  const set = (key, value) => {
    const { [key]: _, ...rest } = module;
    const pruned = prune(value);
    onChange(pruned === undefined ? rest : { ...module, [key]: pruned });
  };
  const config = configSchema(schema, module.type);
  const placements = PLACEMENTS.some(([value]) => value === module.placement) ? PLACEMENTS : [...PLACEMENTS, [module.placement, module.placement]];
  const hasConfig = config && Object.keys(config.properties ?? {}).length > 0;
  const colours = module.type === "command" ? colourPaths(dict(module.config)?.settings) : [];
  return (
    <div>
      <NameField key={module.name} name={module.name} taken={taken} onRename={name => onChange({ ...module, name })} />
      <Row label="placement" description={schema.properties.placement.description}>
        <select aria-label="placement" value={module.placement ?? ""} onChange={event => set("placement", event.target.value)}>
          {placements.map(([value, label]) => <option key={value} value={value}>{label}</option>)}
        </select>
      </Row>
      {module.type !== "drawer" && (
        <Row label="icon" description={schema.properties.icon.description}>
          <IconField value={module.icon} onChange={value => set("icon", value)} label="icon" />
        </Row>
      )}

      {hasConfig && (
        <>
          <div className="kb-h">{BUILT_INS[module.type]?.label ?? module.type} settings</div>
          <Properties node={config} value={dict(module.config)} onChange={value => set("config", value)} />
        </>
      )}

      {colours.length > 0 && (
        <>
          <div className="kb-h">Colours in its settings</div>
          <div className="kb-note">
            The colours its command is given, such as the ones for each level of a reading. The preview's states were printed with the example's
            colours, so changing these changes the YAML and not the preview.
          </div>
          {colours.map(path => (
            <Row key={path.join(".")} label={path.join(".")}>
              <ColorField value={getIn(module.config.settings, path)} label={path.join(".")}
                onChange={value => value !== undefined && set("config", setIn(module.config, ["settings", ...path], value))} />
            </Row>
          ))}
        </>
      )}

      <div className="kb-h">Look and behaviour</div>
      {["style", "interaction", "mask", "fonts"].map(key => (
        <Group key={key} title={key} node={deref(schema, schema.properties[key])} value={module[key]} onChange={value => set(key, value)} />
      ))}
    </div>
  );
}

// `module` is the module's config and `drawn` the module as the bar draws
// it, undefined when it has no place on the screen. `accepted` says whether
// kantan would load it, `masked` whether it sits over a menu bar item, and
// `taken` lists the other modules' names.
export function ModuleEditor({ module, drawn, accepted, masked, taken, states, shown, onChange, onShow, onStates, onRemove }) {
  const { catalog } = useBuilder();
  const [tab, setTab] = useState("settings");
  const plugin = pluginOf(module, catalog);
  const tabs = [["settings", "Settings"], ["states", "Preview data"], ["yaml", "YAML"]];
  return (
    <>
      <h2>
        <Ic name={BUILT_INS[module.type]?.icon ?? "puzzle"} />
        <span>{module.name} · {plugin === undefined ? BUILT_INS[module.type]?.label ?? module.type : `${plugin} plugin`}</span>
        <Button kind="plain" icon="trash" onClick={onRemove}>Remove</Button>
      </h2>
      <div className="kb-subtabs" role="tablist">
        {tabs.map(([key, label]) => <button key={key} type="button" role="tab" aria-selected={tab === key} onClick={() => setTab(key)}>{label}</button>)}
      </div>
      <div className="kb-body">
        {!accepted && (
          <div className="kb-problem" style={{ paddingBottom: 8 }}>
            kantan would leave this module out: its settings are missing something its type needs, or another module has its name.
          </div>
        )}
        {accepted && !drawn && <div className="kb-note">This module has no place on the screen as it is. Switch the notch to see it.</div>}
        {masked && tab === "settings" && (
          <div className="kb-note">This module sits over its menu bar item, wherever its placement puts it and wherever macOS has that item.</div>
        )}
        {tab === "settings" && <Settings module={module} taken={taken} onChange={onChange} />}
        {tab === "states" && <StateEditor module={module} drawn={drawn} states={states} shown={shown} onShow={onShow} onStates={onStates} />}
        {tab === "yaml" && (
          <>
            <div className="kb-note">The module as it's written to the config. Anything the settings have no field for can be written here.</div>
            <YamlArea value={module} rows={18} label="The module's YAML" onChange={value => dict(value) && onChange(value)} />
          </>
        )}
      </div>
    </>
  );
}
