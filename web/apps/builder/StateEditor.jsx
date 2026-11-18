// A module's states: what the bar shows it reading. A built-in module's
// state is a sample of the system, set with controls for its type. A
// command module's is the output its command printed, edited as written,
// with the state each command it runs leads to. None of it is part of a
// config.
import { useState } from "react";
import { BUILT_INS, pluginOf } from "../../builder/catalog.js";
import { removeState, renameState, setTransition } from "../../builder/edit.js";
import { getIn, prune, setIn } from "../../builder/schema.js";
import { moduleCommands } from "../../engine/index.js";
import { dict } from "../../engine/values.js";
import { Row } from "./Fields.jsx";
import { Button, OutputArea, useBuilder } from "./ui.jsx";
import { spell } from "../../builder/spelling.js";

// The controls that set each built-in type's sample. A `list` holds items
// with controls of their own.
const SAMPLE_FIELDS = {
  power: [
    { key: ["level"], label: "Level", kind: "range", min: 0, max: 100, step: 1, show: value => `${value}%` },
    { key: ["charging"], label: "Charging", kind: "bool" },
    { key: ["plugged"], label: "Plugged in", kind: "bool" },
    { key: ["lowPowerMode"], label: "Low Power Mode", kind: "bool" },
  ],
  volume: [
    { key: ["volume"], label: "Volume", kind: "range", min: 0, max: 1, step: 0.01, show: value => `${Math.round(value * 100)}%` },
    { key: ["muted"], label: "Muted", kind: "bool" },
    { key: ["device"], label: "Output device", kind: "text" },
  ],
  wifi: [
    { key: ["connected"], label: "Connected", kind: "bool" },
    { key: ["rssi"], label: "Signal", kind: "range", min: -90, max: -30, step: 1, show: value => `${value} dBm` },
    { key: ["hotspot"], label: "Personal hotspot", kind: "bool" },
  ],
  bluetooth: [
    { key: ["on"], label: "Bluetooth on", kind: "bool" },
    {
      key: ["devices"], label: "Devices", kind: "list", item: { name: "Device", connected: true },
      fields: [{ key: ["name"], label: "Name", kind: "text" }, { key: ["connected"], label: "Connected", kind: "bool" }],
    },
  ],
  focus: [
    { key: ["active"], label: "A Focus is on", kind: "bool" },
    { key: ["mode", "name"], label: "Its name", kind: "text" },
    { key: ["mode", "identifier"], label: "Its identifier", kind: "text" },
  ],
  drawer: [{ key: ["open"], label: "Open", kind: "bool" }],
  clock: [
    { key: ["time"], label: "Time", kind: "text", placeholder: "Now, or 2026-01-01T09:41:00" },
    { key: ["timezone"], label: "Time zone", kind: "text", placeholder: "The config's, or this browser's" },
    { key: ["locale"], label: "Locale", kind: "text", placeholder: "This browser's, or en_GB" },
  ],
  workspace: [
    {
      key: ["workspaces"], label: "Workspaces", kind: "list", item: {},
      fields: [
        { key: ["label"], label: "Label", kind: "text" },
        { key: ["active"], label: "Active", kind: "bool" },
        { key: ["hasWindows"], label: "Has windows", kind: "bool" },
      ],
    },
  ],
};

// The state a module with none starts with when one is added.
const FIRST_STATE = {
  clock: { name: "Fixed time", output: { time: "2026-01-01T09:41:00" } },
  drawer: { name: "Open", output: { open: true } },
};

function SampleFields({ fields, value, onChange, label = "" }) {
  const set = (key, next) => onChange(prune(setIn(value ?? {}, key, next)) ?? {});
  // A list keeps an item that says nothing: a workspace with no windows.
  const setList = (key, next) => onChange(setIn(value ?? {}, key, next));
  return fields.map(field => {
    const current = getIn(value, field.key);
    const name = `${label}${field.label}`;
    if (field.kind === "bool") {
      return (
        <Row key={name} label={field.label}>
          <div className="kb-row"><input type="checkbox" aria-label={name} checked={current === true} onChange={event => set(field.key, event.target.checked)} /></div>
        </Row>
      );
    }
    if (field.kind === "range") {
      const number = typeof current === "number" ? current : undefined;
      return (
        <Row key={name} label={field.label}>
          <div className="kb-row">
            <input type="range" aria-label={name} min={field.min} max={field.max} step={field.step} value={number ?? field.min}
              onChange={event => set(field.key, event.target.valueAsNumber)} />
            <span style={{ width: 64, textAlign: "right", color: "var(--muted)" }}>{number === undefined ? "Not set" : field.show(number)}</span>
          </div>
        </Row>
      );
    }
    if (field.kind === "list") {
      const items = Array.isArray(current) ? current : [];
      return (
        <div key={name}>
          <div className="kb-h">{field.label}</div>
          {items.map((item, i) => (
            <div key={i} className="kb-group">
              <div style={{ paddingTop: 6 }}>
                <SampleFields fields={field.fields} value={item} label={`${field.label} ${i + 1}: `}
                  onChange={next => setList(field.key, items.map((other, j) => (j === i ? next : other)))} />
                <Button kind="plain" icon="trash" onClick={() => setList(field.key, items.filter((_, j) => j !== i))}>Remove</Button>
              </div>
            </div>
          ))}
          <Button kind="plain" icon="plus" onClick={() => setList(field.key, [...items, field.item])}>Add</Button>
        </div>
      );
    }
    return (
      <Row key={name} label={field.label}>
        <input type="text" aria-label={name} value={typeof current === "string" ? current : ""} placeholder={field.placeholder} spellCheck={false}
          onChange={event => set(field.key, event.target.value === "" ? undefined : event.target.value)} />
      </Row>
    );
  });
}

// The name of a state, changed once it is one no other state has.
function StateName({ name, taken, onRename }) {
  const [draft, setDraft] = useState(name);
  const clash = draft !== name && (draft === "" || taken.includes(draft));
  const commit = () => (clash || draft === name ? setDraft(name) : onRename(draft));
  return (
    <Row label="State's name">
      <div>
        <input type="text" aria-label="State's name" value={draft} spellCheck={false} onChange={event => setDraft(event.target.value)}
          onBlur={commit} onKeyDown={event => event.key === "Enter" && event.target.blur()} />
        {clash && <div className="kb-problem">{draft === "" ? "A state needs a name" : "Another state has that name"}</div>}
      </div>
    </Row>
  );
}

// `module` is the module's config, `drawn` the module as the bar draws it,
// `states` its states, `shown` the name of the one showing, `onShow` shows
// another and `onStates` changes them. A `bare` one leaves picking among
// them to whatever holds it.
export function StateEditor({ module, drawn, states = [], shown, onShow, onStates, bare }) {
  const { catalog } = useBuilder();
  const type = module.type;
  const fields = SAMPLE_FIELDS[type];
  const current = states.find(state => state.name === shown) ?? states[0];

  if (type === "text" || type === "icon") {
    return <div className="kb-note">This module shows what its settings say. It reads nothing, so it has no states.</div>;
  }

  const fresh = wanted => {
    let name = wanted;
    for (let n = 2; states.some(state => state.name === name); n++) name = `${wanted} ${n}`;
    return name;
  };
  const add = () => {
    const base = current ?? FIRST_STATE[type] ?? BUILT_INS[type]?.states?.[0] ?? { name: "State", output: {} };
    const name = fresh(base.name);
    onStates([...states, { name, output: base.output }]);
    onShow(name);
  };
  const setCurrent = change => onStates(states.map(state => (state === current ? { ...state, ...change } : state)));

  if (!current) {
    return (
      <div>
        <div className="kb-note">
          {type === "clock" ? "The clock shows the time now. Add a state to stop it at a set time."
            : type === "drawer" ? "The drawer starts closed, and opens when clicked. Add a state to start it open."
            : "This module has no states, so the bar draws it with nothing to read."}
        </div>
        <Button icon="plus" onClick={add}>Add a state</Button>
      </div>
    );
  }

  const json = type !== "command" || dict(current.output) !== undefined || module.config?.output === "json";
  const commands = type === "command" && drawn ? [...new Set(moduleCommands(drawn))] : [];
  const plugin = pluginOf(module, catalog);

  return (
    <div>
      {plugin !== undefined && (
        <div className="kb-note">
          These states are what the {plugin} plugin prints. A <code>{"{setting(…)}"}</code> stands for a {spell("colour")} or an icon of the module's
          settings, which the preview follows. Its other settings change the config, not these states.
        </div>
      )}
      <div className="kb-chips" role="group" aria-label="States">
        {!bare && states.map(state => (
          <button key={state.name} type="button" className="kb-chip" aria-pressed={state === current} onClick={() => onShow(state.name)}>{state.name}</button>
        ))}
        <Button kind="plain" icon="plus" onClick={add}>Add a state</Button>
      </div>

      <StateName key={current.name} name={current.name} taken={states.map(state => state.name)}
        onRename={name => { onStates(renameState(states, current.name, name)); onShow(name); }} />

      {fields && <SampleFields fields={fields} value={dict(current.output)} onChange={output => setCurrent({ output })} />}

      {fields
        ? (
          <details className="kb-group">
            <summary>As JSON</summary>
            <div><OutputArea key={current.name} json value={current.output ?? {}} onChange={output => setCurrent({ output })} rows={8} /></div>
          </details>
        )
        : (
          <>
            <div className="kb-h">{json ? "Output (JSON)" : "Output"}</div>
            <OutputArea key={`${current.name}-${json}`} json={json} value={current.output ?? (json ? {} : "")} onChange={output => setCurrent({ output })} rows={14} />
          </>
        )}

      {drawn?.viewProblem !== undefined && <div className="kb-problem">kantan would reject this view: {drawn.viewProblem}</div>}

      {commands.length > 0 && states.length > 1 && (
        <>
          <div className="kb-h">Transitions</div>
          {commands.map(command => (
            <Row key={command} wide label={<code>{command}</code>}>
              <select aria-label={`${command} leads to`} value={current.transitions?.[command] ?? ""}
                onChange={event => onStates(setTransition(states, current.name, command, event.target.value || undefined))}>
                <option value="">Stays in this state</option>
                {states.filter(state => state !== current).map(state => <option key={state.name} value={state.name}>{state.name}</option>)}
              </select>
            </Row>
          ))}
        </>
      )}

      <div style={{ marginTop: 10 }}>
        <Button kind="plain" icon="trash" onClick={() => { onStates(removeState(states, current.name)); onShow(states.find(state => state !== current)?.name); }}>
          Remove this state
        </Button>
      </div>
    </div>
  );
}

// The state a module is previewed in, set apart from its config: which
// state is showing, and behind a fold, what each one holds. A
// `compact` one only picks among them. A module that reads nothing has
// none.
export function PreviewWith({ module, drawn, states = [], shown, onShow, onStates, compact }) {
  const [open, setOpen] = useState(false);
  if (module.type === "text" || module.type === "icon") return null;
  if (compact && states.length < 2) return null;
  const current = states.find(state => state.name === shown) ?? states[0];
  return (
    <div className="kb-preview">
      <div className="head">
        <b>Preview state</b>
        <div className="kb-chips" role="group" aria-label="The state shown">
          {states.map(state => (
            <button key={state.name} type="button" className="kb-chip" aria-pressed={state === current} onClick={() => onShow(state.name)}>{state.name}</button>
          ))}
          {states.length === 0 && <span className="kb-note">{module.type === "clock" ? "now" : "none"}</span>}
        </div>
        {!compact && (
          <Button kind="plain" icon={open ? "chevron-up" : "chevron-down"} aria-expanded={open} onClick={() => setOpen(!open)}>
            {open ? "Done" : "Edit states"}
          </Button>
        )}
      </div>
      {open && !compact && (
        <div className="body">
          <div className="kb-note">States are preview data. They are never written to the config.</div>
          <StateEditor module={module} drawn={drawn} states={states} shown={shown} onShow={onShow} onStates={onStates} bare />
        </div>
      )}
    </div>
  );
}
