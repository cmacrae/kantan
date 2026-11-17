// Builds one of a module's views in a dialog over the page: the menu or
// popup a click opens, or the tooltip a hover shows. On the left the
// module sits alone on a tall desktop with the view held open. On the
// right the view's parts are listed, the one picked is edited in a form
// made from the plugin output schema, and the Code tab hands over what to
// save: the module's YAML, and the JSON its command has to print.
import { useEffect, useLayoutEffect, useRef, useState } from "react";
import { BarView, PanelView, panelSurface } from "../../components/BarView.jsx";
import { Menu } from "../../components/Menu.jsx";
import { nodeMark } from "../../components/ViewTree.jsx";
import { pluginOf } from "../../builder/catalog.js";
import { writeYaml } from "../../builder/files.js";
import { deref, prune } from "../../builder/schema.js";
import {
  addField, addRow, exampleRows, freeValueName, jsonOutput, listFields, listsOf, printedBy, printingJson, removeField, removeRow, renameField,
  renameList, setCell, withList, withValue,
} from "../../builder/values.js";
import {
  NODE_INFO, NODE_KINDS, STARTERS, describeNode, drawnPaths, holderOf, holdsNodes, insertNode, markedPath, moveNode, newNode, nodeAt,
  nudgeNode, outline, removeNode, renameFieldIn, renameListIn, replaceNode, shows, starterScript, viewVaries, withStateView, withView, wrapNode, VIEW_KINDS,
} from "../../builder/view.js";
import { NODE_SLOTS } from "../../engine/index.js";
import { dict } from "../../engine/values.js";
import { Group, Properties, Row } from "./Fields.jsx";
import { ValueChips } from "./ModuleEditor.jsx";
import { StateEditor } from "./StateEditor.jsx";
import { BuilderContext, Button, CopyButton, Ic, remember, remembered, useBuilder } from "./ui.jsx";

// The icon that stands for each node type.
const NODE_ICONS = {
  vstack: "layout-rows", hstack: "layout-columns", zstack: "stack-2", grid: "layout-grid", scroll: "arrows-vertical", group: "box-multiple",
  spacer: "arrows-horizontal", divider: "minus", text: "letter-case", header: "heading", icon: "star", badge: "tag", image: "photo",
  action: "click", check: "circle-check", toggle: "toggle-right", button: "square-rounded", rect: "rectangle", circle: "circle",
  capsule: "pill", progress: "progress", gauge: "gauge", foreach: "repeat", if: "git-branch",
};

// What a node held on its own is to the node holding it.
const HELD_AS = { then: "when set", else: "otherwise", child: "for each" };

const SPLIT_KEY = "kantan-builder-view-split";
const DEFAULT_SPLIT = 30;
const clampSplit = value => Math.min(70, Math.max(18, value));

const same = (a, b) => a.length === b.length && a.every((key, i) => key === b[i]);
const nameOf = type => NODE_INFO[type]?.[0] ?? String(type ?? "Unknown");

// The schema of a node of `type`: its own fields, and the fields every
// node takes.
function nodeSchema(schema, type) {
  const own = Object.values(schema.$defs ?? {}).find(def => def.properties?.type?.const === type);
  return { own, common: schema.$defs?.CommonNodeProperties };
}

// A choice among a few things, each a button, the one chosen pressed.
// `titles` say more about each under the pointer.
function Choice({ label, options, value, onChange, titles }) {
  return (
    <div className="kb-seg" role="group" aria-label={label}>
      {options.map(([key, text, icon]) => (
        <button key={key} type="button" aria-pressed={value === key} title={titles?.[key]} onClick={() => onChange(key)}>
          {icon && <Ic name={icon} size={14} />}{text}
        </button>
      ))}
    </div>
  );
}

// The node types to add, by kind, each with what it does.
function NodePicker({ into, onPick, onClose }) {
  return (
    <div className="kb-nodepicker" role="dialog" aria-label="Add a node">
      <div className="head"><b>{into}</b><Button kind="plain" icon="x" aria-label="Cancel" onClick={onClose} /></div>
      {NODE_KINDS.map(([kind, types]) => (
        <div key={kind}>
          <div className="kb-h">{kind}</div>
          <div className="kb-nodegrid">
            {types.map(type => (
              <button key={type} type="button" onClick={() => onPick(type)}>
                <Ic name={NODE_ICONS[type]} size={16} />
                <span><b>{nameOf(type)}</b><span>{NODE_INFO[type][1]}</span></span>
              </button>
            ))}
          </div>
        </div>
      ))}
    </div>
  );
}

// A name someone types for something new, and the button that adds it.
function NameAdder({ placeholder, label, onAdd }) {
  const [name, setName] = useState("");
  const add = () => {
    const wanted = name.trim().replace(/^\{|\}$/g, "");
    if (wanted === "") return;
    onAdd(wanted);
    setName("");
  };
  return (
    <div className="kb-row" style={{ padding: "4px 0 6px" }}>
      <input type="text" aria-label={placeholder} placeholder={placeholder} value={name} spellCheck={false}
        onChange={event => setName(event.target.value)} onKeyDown={event => event.key === "Enter" && add()} />
      <Button icon="plus" disabled={name.trim() === ""} onClick={add}>{label}</Button>
    </div>
  );
}

// Text that is kept once the field is left, such as a name other things
// go by.
function Held({ value, label, onCommit }) {
  const [draft, setDraft] = useState(value);
  useEffect(() => setDraft(value), [value]);
  return (
    <input type="text" aria-label={label} value={draft} spellCheck={false} onChange={event => setDraft(event.target.value)}
      onBlur={() => (draft === value || draft.trim() === "" ? setDraft(value) : onCommit(draft.trim()))}
      onKeyDown={event => event.key === "Enter" && event.target.blur()} />
  );
}

// One list of a command's example data as a table: a column for each
// field its items have and a row for each item, all of it to change.
function ListTable({ name, rows, onRows, onRename, onRenameField, onRemove }) {
  // A field's new name is kept when no other field has it.
  const renamed = (field, to) => renameField(rows, field, to) !== rows && onRenameField(field, to);
  const fields = listFields(rows);
  return (
    <div className="kb-listed">
      <div className="kb-row">
        <span className="kb-note">List</span>
        <Held value={name} label={`The name of the list ${name}`} onCommit={onRename} />
        <Button kind="plain" icon="trash" aria-label={`Remove the list ${name}`} onClick={onRemove} />
      </div>
      <div className="table" style={{ gridTemplateColumns: `repeat(${Math.max(fields.length, 1)}, minmax(84px, 1fr)) 26px` }}>
        {fields.map(field => (
          <span key={field} className="field kb-row">
            <Held value={field} label={`The name of the field ${field}`} onCommit={to => renamed(field, to)} />
            <Button kind="plain" icon="x" aria-label={`Remove the field ${field}`} onClick={() => onRows(removeField(rows, field))} />
          </span>
        ))}
        {fields.length === 0 && <span className="kb-note">No fields yet</span>}
        <span />
        {rows.map((row, i) => (
          // The cells of one item, then the button that removes it.
          [...fields.map(field => (
            <input key={`${i}-${field}`} type="text" aria-label={`${field} of item ${i + 1}`} spellCheck={false}
              value={row[field] === undefined || row[field] === null ? "" : String(row[field])} onChange={event => onRows(setCell(rows, i, field, event.target.value))} />
          )), <Button key={`${i}-remove`} kind="plain" icon="x" aria-label={`Remove item ${i + 1}`} onClick={() => onRows(removeRow(rows, i))} />]
        ))}
      </div>
      <Button kind="plain" icon="plus" onClick={() => onRows(addRow(rows))}>Add an item</Button>
      <NameAdder placeholder="New field" label="Add a field" onAdd={field => onRows(addField(rows, field))} />
    </div>
  );
}

// A command's example values and lists, each to change, with the fields
// that add more. `output` is what the example shows the command printing
// and `onOutput` changes it. `onRenamed(list, to)` gives a list a new
// name, and `onRenamed(list, to, field)` one of its fields.
function ValueFields({ output, onOutput, onRenamed }) {
  const json = jsonOutput(output);
  const variables = dict(json.variables) ?? {};
  const lists = listsOf(output);
  return (
    <>
      <Row label={<code>{"{value}"}</code>} description="The module's text in the bar.">
        <input type="text" aria-label="value" value={typeof json.value === "string" ? json.value : ""} spellCheck={false}
          onChange={event => onOutput(typeof output === "string" ? event.target.value : withValue(output, "value", event.target.value))} />
      </Row>
      {Object.entries(variables).map(([name, value]) => (
        <Row key={name} label={<code>{`{${name}}`}</code>}>
          <div className="kb-row">
            <input type="text" aria-label={name} value={typeof value === "string" ? value : ""} spellCheck={false} onChange={event => onOutput(withValue(output, name, event.target.value))} />
            <Button kind="plain" icon="x" aria-label={`Remove ${name}`} onClick={() => onOutput(withValue(output, name, undefined))} />
          </div>
        </Row>
      ))}
      <NameAdder placeholder="New value" label="Add a value"
        onAdd={name => name !== "value" && !Object.hasOwn(variables, name) && onOutput(withValue(output, name, ""))} />
      {Object.entries(lists).map(([name, rows]) => (
        <ListTable key={name} name={name} rows={rows} onRows={next => onOutput(withList(output, name, next))}
          onRename={to => onRenamed(name, to)} onRenameField={(field, to) => onRenamed(name, to, field)}
          onRemove={() => onOutput(withList(output, name, undefined))} />
      ))}
      <Button icon="list-details" onClick={() => onOutput(withList(output, freeValueName(output, Object.keys(lists).length ? "list" : "items"), exampleRows()))}>
        Add a list
      </Button>
    </>
  );
}

// The values a view can show. They are the ones the example being
// previewed has. A command's are fields to change and add to: they stand
// for what the command prints. Any other module's are what it reads, each
// a button that copies its name. `onEdit` opens the rest of the example
// data.
function Values({ values, output, textual, onOutput, onRenamed, onEdit }) {
  const [copied, setCopied] = useState();
  const copy = name => {
    navigator.clipboard?.writeText(name);
    setCopied(name);
  };
  return (
    <div className="kb-preview kb-vars">
      <div className="head">
        <b>Values</b>
        <span style={{ flex: 1 }} />
        <Button kind="plain" icon="database" onClick={onEdit}>States</Button>
      </div>
      <div className="body">
        {onOutput
          ? (
            <>
              <div className="kb-note">
                Reference as <code>{"{name}"}</code>. The command has to print each one.
                {textual && " Adding a value or a list sets output: json."}
              </div>
              <ValueFields output={output} onOutput={onOutput} onRenamed={onRenamed} />
            </>
          )
          : (
            <>
              <div className="kb-note">Reference as <code>{"{name}"}</code>. Click one to copy it.</div>
              <ValueChips values={values?.variables} onPick={copy} />
              {copied !== undefined && <div className="kb-note">Copied <code>{copied}</code>.</div>}
            </>
          )}
      </div>
    </div>
  );
}

// The states the preview is drawn with, to change: a command's
// values and lists as fields, then everything it prints, and any other
// module's sample of what it reads.
function States({ module, drawn, states, shown, onShow, onStates, onOutput, onRenamed }) {
  const current = states.find(state => state.name === shown) ?? states[0];
  return (
    <div className="kb-handoff">
      <div className="kb-preview">
        <div className="head"><b>States</b></div>
        <div className="body">
          <div className="kb-note">Preview data. It is never written to the config.</div>
          {onOutput && current && (
            <>
              <div className="kb-h">Values and lists</div>
              <ValueFields output={current.output} onOutput={onOutput} onRenamed={onRenamed} />
              <div className="kb-h">Everything it prints</div>
            </>
          )}
          <StateEditor module={module} drawn={drawn} states={states} shown={shown} onShow={onShow} onStates={onStates} />
        </div>
      </div>
    </div>
  );
}

// A starting point as it would look, small: the panel the bar draws for it.
function Thumb({ model, kind, bar, dark }) {
  const context = { dark, native: bar.native, fg: bar.native ? "primary" : bar.fg, run: () => {}, dismiss: () => {} };
  const nodes = kind === "tooltip" ? model?.tooltip?.view : model?.click?.view;
  return (
    <div className="kb-thumb" aria-hidden="true">
      <div style={panelSurface(kind, bar, dark)}>
        {kind === "menu"
          ? <Menu rows={model?.click?.rows ?? []} fg={model?.click?.fg} dark={dark} run={() => {}} close={() => {}} />
          : <PanelView kind={kind} nodes={nodes ?? []} context={context} />}
      </div>
    </div>
  );
}

// The form for one node: its own fields, then those every node takes.
function NodeForm({ node, output, onChange, onList }) {
  const context = useBuilder();
  const { own, common } = nodeSchema(context.outputSchema, node.type);
  if (!own) return <div className="kb-problem">kantan has no node of the type {String(node.type)}.</div>;
  const { one, many } = NODE_SLOTS[node.type];
  // A field kantan needs stays, empty, when its text is cleared.
  const keep = next => {
    const kept = { ...next };
    for (const key of own.required ?? []) if (kept[key] === undefined && own.properties[key]?.type === "string") kept[key] = "";
    for (const key of many) if (!Array.isArray(kept[key])) kept[key] = node[key] ?? [];
    onChange({ ...kept, type: node.type });
  };
  const collections = Object.keys(dict(dict(output)?.data) ?? {});
  const fields = Object.keys(own.properties).filter(key => key !== "type" && !one.includes(key) && !many.includes(key));
  return (
    <BuilderContext.Provider value={{ ...context, schema: context.outputSchema }}>
      {node.type === "foreach" && collections.length === 0 && (
        <div className="kb-row" style={{ flexWrap: "wrap" }}>
          <span className="kb-note" style={{ flex: 1 }}>This state has no list to repeat over.</span>
          {onList && <Button icon="list-details" onClick={onList}>Add a list</Button>}
        </div>
      )}
      {node.type === "foreach" && collections.length > 0 && (
        <>
          <div className="kb-note">The lists this state has.</div>
          <div className="kb-chips" role="group" aria-label="The state's lists">
            {collections.map(name => (
              <button key={name} type="button" className="kb-chip" aria-pressed={node.items === name} onClick={() => onChange({ ...node, items: name })}>{name}</button>
            ))}
          </div>
        </>
      )}
      {fields.length === 0 && <div className="kb-note">It has no settings of its own.</div>}
      <Properties node={own} value={node} onChange={next => keep(dict(next) ?? {})} skip={["type", ...one, ...many]} />
      <Group title="Size, padding and background" node={{ ...deref(context.outputSchema, common), description: "Padding, size, background and visibility, which any node takes." }}
        value={prune(Object.fromEntries(Object.keys(common.properties).map(key => [key, node[key]])))}
        onChange={next => {
          const rest = Object.fromEntries(Object.entries(node).filter(([key]) => !Object.hasOwn(common.properties, key)));
          keep({ ...rest, ...dict(next) });
        }} />
    </BuilderContext.Provider>
  );
}

// A block of text to copy, under what it is and where it goes.
function Snippet({ step, title, note, text, lang }) {
  return (
    <section className="kb-snippet">
      <header>
        <span className="step">{step}</span>
        <span><b>{title}</b><span>{note}</span></span>
        <CopyButton text={text}>Copy</CopyButton>
      </header>
      <pre data-lang={lang}>{text}</pre>
    </section>
  );
}

// What to save for the view to show in kantan: the module's YAML, and
// what its command has to print. `printed` says the command prints the
// view too, and `own` that the command is someone's own, not a bundled
// plugin.
function Code({ module, output, printed, own, kind }) {
  const [whole, setWhole] = useState(true);
  const yaml = writeYaml(module);
  const json = dict(module.config)?.output === "json";
  if (!printed) {
    const reads = module.type === "command" && own && json;
    return (
      <div className="kb-handoff">
        <div className="kb-note">
          This {kind} is in the config, and kantan builds it.
          {module.type !== "command" ? " Nothing else is needed."
            : reads ? " Your command prints the values it shows, as JSON."
            : own ? " Its command prints text, which the view shows as {value}."
            : " The plugin prints the values it shows."}
        </div>
        <Snippet step="1" title="The module" lang="yaml" text={yaml}
          note={<>Put it under <code>modules:</code> in <code>~/.config/kantan/config.yaml</code>, or in a file of its own in <code>modules.d/</code>.</>} />
        {reads && (
          <>
            <Snippet step="2" title="What your command prints" lang="json" text={JSON.stringify(printedBy(output, true), null, 2)}
              note={(
                <>
                  <code>value</code>: the module's text. <code>variables</code>: values the view references. <code>data</code>: lists for <code>foreach</code>.
                </>
              )} />
            <Snippet step="3" title="A script to start from" lang="sh" text={starterScript(printedBy(output, true))}
              note={<>A script that prints it. Replace the fixed values.</>} />
          </>
        )}
      </div>
    );
  }
  const text = JSON.stringify(whole ? output ?? {} : { view: dict(output)?.view }, null, 2);
  return (
    <div className="kb-handoff">
      <div className="kb-note">
        The plugin prints this {kind} as JSON on stdout. See <a href="/docs/plugins/building-a-plugin.html">Building a plugin</a> and the <a href="/docs/view-dsl/nodes.html">node reference</a>.
      </div>
      <Snippet step="1" title="What your plugin prints" lang="json" text={text}
        note={(
          <>
            <code>view</code>: the view built here. <code>value</code>, <code>variables</code> and <code>data</code>: the values it shows.{" "}
            <label><input type="checkbox" checked={!whole} onChange={event => setWhole(!event.target.checked)} /> Just the view</label>
          </>
        )} />
      <Snippet step="2" title="The module that runs it" lang="yaml" text={yaml}
        note={<>In the config. <code>command</code> is the plugin.</>} />
      <Snippet step="3" title="A plugin to start from" lang="sh" text={starterScript(output ?? {})}
        note={<>A script that prints it. Replace the fixed values.</>} />
    </div>
  );
}

// The starting points for a view of `kind`, each drawn as it would look.
// `drawStart(starter, kind)` gives the module as drawn once one is picked.
function Starters({ kind, module, bar, dark, drawStart, onStart }) {
  return (
    <div className="kb-startgrid">
      {STARTERS.filter(starter => starter.kinds.includes(kind) && (!starter.repeats || module.type === "command")).map(starter => (
        <button key={starter.name} type="button" onClick={() => onStart(starter, kind)}>
          <Thumb model={drawStart(starter, kind)} kind={kind} bar={bar} dark={dark} />
          <span><b>{starter.name}</b>{starter.about !== undefined && <span>{starter.about}</span>}</span>
        </button>
      ))}
    </div>
  );
}

// `module` is the module's config, `bar` a bar holding it alone and
// `drawn` the module as that bar draws it. `states` are its states,
// `shown` the name of the one showing and `printedOutput` that state's
// output as a plugin prints it, with its settings in place of their
// names. `where` says which view is being built, `view` is that view as
// written, and `path` the part of it picked. `onWhere`, `onView` and
// `onPath` change them, `onKind` makes the click a menu or a popup,
// `onMove` moves the view to the config or to what the command prints,
// `onShow` shows another state, `onStates` changes the states, `onModule`
// changes the module's config and `onCommit(module, states)` both at once.
// `onStart(starter, kind)` starts the view from a starting point, and
// `drawStart(starter, kind)` gives the module as drawn once it has.
// `onDark` switches the appearance, `onUndo` undoes the last change when
// there is one, and `onClose` closes the dialog. `paper` is the desktop's
// wallpaper.
export function ViewBuilder({
  module, bar, drawn, states = [], printedOutput, shown, where, view, path, dark, paper,
  onWhere, onView, onPath, onKind, onMove, onShow, onStates, onModule, onCommit, onStart, drawStart, onDark, onUndo, onClose,
}) {
  const { catalog } = useBuilder();
  const [tab, setTab] = useState("design");
  const [adding, setAdding] = useState();
  const [dragged, setDragged] = useState();
  const [over, setOver] = useState();
  const [split, setSplitState] = useState(() => clampSplit(Number(remembered(SPLIT_KEY)) || DEFAULT_SPLIT));
  const setSplit = value => { setSplitState(clampSplit(value)); remember(SPLIT_KEY, String(Math.round(clampSplit(value)))); };
  const box = useRef(null);
  const desk = useRef(null);

  // Escape puts down whatever is being added, then closes the dialog.
  useEffect(() => {
    const key = event => {
      if (event.key !== "Escape") return;
      if (adding) setAdding(undefined);
      else onClose();
    };
    window.addEventListener("keydown", key);
    return () => window.removeEventListener("keydown", key);
  }, [adding, onClose]);

  const plugin = pluginOf(module, catalog);
  const current = states.find(state => state.name === shown) ?? states[0];
  const output = current?.output;
  const click = dict(dict(module.interaction)?.click);
  const tooltip = where.slot === "hover";
  const kind = tooltip ? "tooltip" : click?.type === "popup" ? "popup" : "menu";
  const printed = where.slot === "state";
  const canPrint = module.type === "command" && states.length > 0;
  // A view in the config is drawn in place of the one a state prints.
  const overridden = printed && dict(click?.view) !== undefined;
  // The first state whose output holds a view.
  const printing = states.find(state => dict(dict(state.output)?.view));
  const varies = viewVaries(states);

  const rows = outline(view);
  const picked = rows.find(row => same(row.path, path)) ?? rows[0];
  const slot = tooltip ? "hover" : "click";
  const drawnNow = drawnPaths(drawn, slot);
  const markAt = picked && markedPath(drawn, slot, picked.path);
  const mark = markAt && `[data-kantan-node="${CSS.escape(nodeMark(markAt))}"]`;
  const collections = Object.keys(listsOf(output));

  // The desktop is as wide and as tall as the panel held open needs.
  const [room, setRoom] = useState({});
  useLayoutEffect(() => {
    const within = desk.current.getBoundingClientRect();
    const marks = [...desk.current.querySelectorAll("[data-kantan-node]")].flatMap(each => [each, ...each.children]);
    if (marks.length === 0) return setRoom({});
    const rects = marks.map(each => each.getBoundingClientRect());
    return setRoom({
      minHeight: Math.ceil(Math.max(...rects.map(rect => rect.bottom)) - within.top) + 28,
      minWidth: Math.ceil(Math.max(...rects.map(rect => rect.right)) - within.left) + 16,
    });
  }, [bar, split]);

  const apply = result => {
    if (!result) return;
    onView(result.view);
    onPath(result.path);
  };
  // Where a new part goes: into the part picked when it holds others, and
  // after it otherwise.
  const addTarget = () => {
    if (!picked || holdsNodes(picked.node)) return { parent: picked?.path ?? [] };
    const held = holderOf(picked.path);
    return held?.index === undefined ? undefined : { parent: held.parent, index: held.index + 1 };
  };
  const add = type => {
    const node = newNode(type, collections[0]);
    const { parent, index, key } = adding;
    setAdding(undefined);
    if (key !== undefined) {
      onView(replaceNode(view, parent, { ...nodeAt(view, parent), [key]: node }));
      return onPath([...parent, key]);
    }
    const next = insertNode(view, parent, node, index);
    onView(next);
    return onPath([...parent, "children", index ?? nodeAt(next, parent).children.length - 1]);
  };
  const remove = at => {
    onView(removeNode(view, at));
    onPath(holderOf(at)?.parent ?? []);
  };
  // Where a part dropped on `row` goes: into a part that holds others when
  // dropped on its lower half, and before any other part of a list.
  const landing = (event, row) => {
    const rect = event.currentTarget.getBoundingClientRect();
    const lower = event.clientY > rect.top + rect.height / 2;
    if (holdsNodes(row.node) && lower) return { parent: row.path, into: true };
    const held = holderOf(row.path);
    return held?.index === undefined ? undefined : { parent: held.parent, key: held.key, index: held.index };
  };

  // The divider between the two sides follows the pointer, and the arrow
  // keys move it.
  const grip = {
    onPointerDown: event => {
      event.preventDefault();
      const within = box.current.getBoundingClientRect();
      const move = moved => setSplit(((moved.clientX - within.left) / within.width) * 100);
      const stop = () => { window.removeEventListener("pointermove", move); window.removeEventListener("pointerup", stop); };
      window.addEventListener("pointermove", move);
      window.addEventListener("pointerup", stop);
    },
    onKeyDown: event => {
      if (event.key === "ArrowLeft") setSplit(split - 2);
      if (event.key === "ArrowRight") setSplit(split + 2);
    },
    onDoubleClick: () => setSplit(DEFAULT_SPLIT),
  };

  const hover = dict(dict(module.interaction)?.hover);
  const hoverText = typeof hover?.content === "string" ? hover.content : "";
  const setHoverText = content => onModule({ ...module, interaction: { ...dict(module.interaction), hover: prune({ ...hover, type: "tooltip", content: content || undefined }) ?? { type: "tooltip" } } });

  // A command's example values are changed where they are listed. One that
  // gains a value or a list of its own prints JSON from then on.
  const textual = typeof output === "string";
  const setOutput = module.type === "command" && current !== undefined
    ? next => {
      const changed = states.map(state => (state === current ? { ...state, output: next } : state));
      if (typeof next === "string") return onStates(changed);
      const json = printingJson(module, changed);
      return json.module === module ? onStates(json.states) : onCommit(json.module, json.states);
    }
    : undefined;
  // Changes the example's output and the view that shows it at once.
  const setBoth = (nextOutput, nextView) => {
    let changed = states.map(state => (state === current ? { ...state, output: nextOutput } : state));
    let held = module;
    if (nextView !== undefined && printed) changed = withStateView(changed, where.state, nextView);
    else if (nextView !== undefined) held = withView(module, slot, nextView);
    const json = printingJson(held, changed);
    onCommit(json.module, json.states);
  };
  // A list called something new is the one its Repeats go on repeating
  // over, and a field called something new the one they go on showing.
  const followNames = (list, to, field) => {
    if (field === undefined) {
      const next = renameList(output, list, to);
      return Object.hasOwn(listsOf(next), to) && setBoth(next, view && renameListIn(view, list, to));
    }
    return setBoth(withList(output, list, renameField(listsOf(output)[list], field, to)), view && renameFieldIn(view, list, field, to));
  };
  // A new list is the one a Repeat picked with none repeats over.
  const addList = setOutput && (() => {
    const name = freeValueName(output, "items");
    const repeat = picked?.node?.type === "foreach" && !picked.node.items;
    setBoth(withList(output, name, exampleRows()), repeat ? replaceNode(view, picked.path, { ...picked.node, items: name }) : undefined);
  });

  const addInto = adding && (adding.key !== undefined ? `Add what shows otherwise` : adding.index === undefined
    ? `Add to ${nameOf(dict(nodeAt(view, adding.parent))?.type)}`
    : `Add after ${nameOf(dict(nodeAt(view, [...adding.parent, "children", adding.index - 1]))?.type)}`);
  const what = tooltip ? "tooltip" : view === undefined ? "click" : kind;

  return (
    <div className="kb-shade kb-viewshade" onMouseDown={event => event.target === event.currentTarget && onClose()}>
      <div className="kb-view" role="dialog" aria-label={`Design ${module.name}'s ${what}`}>
        <header className="kb-view-top">
          <span className="title"><Ic name="layout-list" size={16} /><b>{module.name}</b></span>
          <label className="kb-view-from">
            <span>Trigger</span>
            <Choice label="Trigger" value={tooltip ? "hover" : "click"} onChange={to => (to === "hover") !== tooltip && onWhere({ slot: to })}
              titles={{ click: "What opens when the module is clicked.", hover: VIEW_KINDS.tooltip }}
              options={[["click", "On click", "click"], ["hover", "On hover", "message"]]} />
          </label>
          {!tooltip && (
            <label className="kb-view-from">
              <span>Style</span>
              <Choice label="Style" value={kind} onChange={onKind} titles={VIEW_KINDS}
                options={[["menu", "Native", "list"], ["popup", "Themed", "app-window"]]} />
            </label>
          )}
          <span className="grow" />
          <Button kind="plain" icon="arrow-back-up" disabled={!onUndo} onClick={onUndo}>Undo</Button>
          <Button kind="primary" icon="check" onClick={onClose}>Done</Button>
        </header>

        <div className="kb-view-split" ref={box} style={{ "--split": `${split}%` }}>
          <section className="kb-view-stage" aria-label="Preview">
            <div className="kb-view-desk" ref={desk} style={{ background: paper, ...room }}
              onClick={event => {
                const node = event.target.closest?.("[data-kantan-node]");
                if (node) onPath(JSON.parse(node.dataset.kantanNode));
              }}>
              <BarView bar={bar} dark={dark} run={() => {}} interactive={false} pinned={{ module: module.name, slot }} style={{ borderRadius: "10px 10px 0 0" }} />
              {drawn?.hidden
                ? <div className="empty">The module is hidden in this state.</div>
                : view === undefined && !tooltip && <div className="empty">The view shows here.</div>}
            </div>
            <div className="kb-view-under">
              {states.length > 1 && (
                <div className="kb-preview">
                  <div className="head">
                    <b>Preview state</b>
                    <div className="kb-chips" role="group" aria-label="The state shown">
                      {states.map(state => (
                        <button key={state.name} type="button" className="kb-chip" aria-pressed={state === current} onClick={() => onShow(state.name)}>{state.name}</button>
                      ))}
                    </div>
                  </div>
                </div>
              )}
              <Button kind="plain" icon={dark ? "moon" : "sun"} onClick={onDark}>{dark ? "Dark" : "Light"}</Button>
            </div>
            {view !== undefined && <div className="kb-note">Click anything in the {kind} to pick it.</div>}
            {mark && <style>{`.kb-view-desk [data-kantan-node] { cursor: pointer; } .kb-view-desk div${mark}:not([style*="contents"]), .kb-view-desk ${mark}[style*="contents"] > * { outline: 1.5px solid #0a84ff; outline-offset: 1px; border-radius: 3px; }`}</style>}
          </section>

          <div className="kb-view-grip" role="separator" aria-orientation="vertical" aria-label="Resize the preview" tabIndex={0}
            aria-valuenow={Math.round(split)} aria-valuemin={18} aria-valuemax={70} {...grip} />

          <section className="kb-view-work">
            <div className="kb-view-bar">
              <div className="kb-subtabs" role="tablist">
                <button type="button" role="tab" aria-selected={tab === "design"} onClick={() => setTab("design")}>Design</button>
                <button type="button" role="tab" aria-selected={tab === "data"} onClick={() => setTab("data")}>States</button>
                <button type="button" role="tab" aria-selected={tab === "code"} onClick={() => setTab("code")}>
                  Code
                </button>
              </div>
              {!tooltip && canPrint && plugin === undefined && (
                <label className="kb-view-from">
                  <span>Data source</span>
                  <Choice label="Data source" value={printed ? "output" : "config"}
                    onChange={to => (to === "output") !== printed && (view === undefined ? onWhere(to === "output" ? { slot: "state", state: current.name } : { slot: "click" }) : onMove(to))}
                    titles={{
                      config: "interaction.click.view in the config.",
                      output: "view in the plugin's JSON output.",
                    }}
                    options={[["config", "The config"], ["output", "My plugin"]]} />
                </label>
              )}
            </div>

            <div className="kb-view-notes">
              {printed && plugin !== undefined && !overridden && (
                <div className="kb-own">
                  <Ic name="lock" size={18} />
                  <span>
                    <b>The {plugin} plugin prints this {kind}.</b>
                    Changes here are preview only. Copy it to the config to keep them: kantan shows the config's in place of the plugin's.
                    {varies && ` The plugin prints a different ${kind} in other states. The copy is of this one, and stays as it is in all of them.`}
                  </span>
                  <Button kind="primary" icon="copy" onClick={() => onMove("config")}>Copy to config</Button>
                </div>
              )}
              {printed && plugin === undefined && view !== undefined && tab === "design" && (
                <div className="kb-note">
                  The plugin prints this {kind}.{" "}
                  <button type="button" className="kb-link" onClick={() => setTab("code")}>Code</button>
                </div>
              )}
              {!printed && !tooltip && plugin !== undefined && view !== undefined && printing && (
                <div className="kb-note">
                  This {kind} is in the config. kantan shows it in place of the one the {plugin} plugin prints
                  {varies ? ", in every state." : "."}{" "}
                  <button type="button" className="kb-link" onClick={() => { onView(undefined); onWhere({ slot: "state", state: printing.name }); }}>
                    Use the plugin's
                  </button>
                </div>
              )}
              {kind === "menu" && view !== undefined && tab === "design" && (
                <div className="kb-note">
                  Native menus show rows only. Unsupported nodes are marked <span className="kb-tagdemo">no row</span>.{" "}
                  <button type="button" className="kb-link" onClick={() => onKind("popup")}>Themed</button> shows everything.
                </div>
              )}
              {overridden && <div className="kb-problem">The config has a {kind} of its own for this click, which kantan shows in place of this one.</div>}
              {drawn?.viewProblem !== undefined && printed && <div className="kb-problem">kantan would reject this view: {drawn.viewProblem}</div>}
            </div>

            {tab === "data"
              ? <States module={module} drawn={drawn} states={states} shown={current?.name} onShow={onShow} onStates={onStates} onOutput={setOutput} onRenamed={followNames} />
              : tab === "code"
              ? <Code module={module} output={printedOutput ?? output} printed={printed} own={plugin === undefined} kind={kind} />
              : view === undefined
              ? (
                <div className="kb-view-start">
                  {tooltip
                    ? (
                      <>
                        <h3>Content</h3>
                        <div className="kb-row" style={{ margin: "8px 0 4px" }}>
                          <input type="text" aria-label="The tooltip's text" value={hoverText} placeholder="{value}" spellCheck={false} onChange={event => setHoverText(event.target.value)} />
                        </div>
                        <ValueChips values={drawn?.placeholders?.variables} onPick={name => setHoverText(`${hoverText}${name}`)} />
                        <h3 style={{ marginTop: 22 }}>View</h3>
                        <div className="kb-note">A view takes the place of the content.</div>
                        <Starters kind="tooltip" module={module} bar={bar} dark={dark} drawStart={drawStart} onStart={onStart} />
                      </>
                    )
                    : (
                      <>
                        <h3>Pick a starting point</h3>
                        <div className="kb-note">
                          {VIEW_KINDS[kind]}
                          {printed && plugin === undefined && " Your plugin prints the view. Code has the JSON."}
                        </div>
                        <Starters kind={kind} module={module} bar={bar} dark={dark} drawStart={drawStart} onStart={onStart} />
                      </>
                    )}
                </div>
              )
              : (
                <div className="kb-view-design">
                  <div className="kb-view-layers">
                    <div className="kb-view-head">
                      <span className="kb-h">Contents</span>
                      <Button icon="plus" disabled={!addTarget()} onClick={() => setAdding(addTarget())}>Add</Button>
                    </div>
                    <ul className="kb-list kb-tree" role="tree" aria-label="The view's nodes">
                      {rows.map(row => {
                        const key = JSON.stringify(row.path);
                        const type = dict(row.node)?.type;
                        const on = picked && same(row.path, picked.path);
                        const held = holderOf(row.path);
                        const isOver = over && same(over.at, row.path);
                        return (
                          <li key={key} role="treeitem" aria-selected={on} draggable={row.path.length > 0} title={NODE_INFO[type]?.[1]}
                            className={`kb-item ${on ? "on" : ""} ${isOver ? (over.into ? "into" : "over") : ""}`}
                            style={{ paddingLeft: 6 + row.deep * 16 }}
                            onClick={() => onPath(row.path)}
                            onDragStart={event => { setDragged(row.path); event.dataTransfer.effectAllowed = "move"; event.dataTransfer.setData("text/plain", key); }}
                            onDragOver={event => {
                              const to = dragged && landing(event, row);
                              if (!to) return;
                              event.preventDefault();
                              setOver({ at: row.path, into: to.into === true });
                            }}
                            onDragLeave={() => setOver(undefined)}
                            onDrop={event => {
                              event.preventDefault();
                              const to = dragged && landing(event, row);
                              if (to) apply(moveNode(view, dragged, to.parent, to.into ? undefined : to.index, to.key));
                              setDragged(undefined);
                              setOver(undefined);
                            }}
                            onDragEnd={() => { setDragged(undefined); setOver(undefined); }}>
                            <span className="kb-glyph"><Ic name={NODE_ICONS[type] ?? "help"} size={15} /></span>
                            <span className="name">
                              {HELD_AS[row.key] && <i>{HELD_AS[row.key]} </i>}
                              <b>{nameOf(type)}</b> {describeNode(row.node)}
                            </span>
                            {!overridden && !shows(drawnNow, row.path) && (
                              <span className="tag out" title={kind === "menu" ? "A menu has no row for this, or it holds nothing in this state. A popup would show it." : "It shows nothing in this state"}>
                                {kind === "menu" && !["if", "foreach"].includes(type) ? "no row" : "not showing"}
                              </span>
                            )}
                            <span className="moves">
                              {held?.index !== undefined && (
                                <>
                                  <Button kind="plain" icon="chevron-up" aria-label="Move up" onClick={event => { event.stopPropagation(); apply(nudgeNode(view, row.path, -1)); }} />
                                  <Button kind="plain" icon="chevron-down" aria-label="Move down" onClick={event => { event.stopPropagation(); apply(nudgeNode(view, row.path, 1)); }} />
                                </>
                              )}
                              <Button kind="plain" icon="trash" aria-label={`Remove ${nameOf(type)}`} onClick={event => { event.stopPropagation(); remove(row.path); }} />
                            </span>
                          </li>
                        );
                      })}
                    </ul>
                    <div className="kb-note">Drag to reorder. Drop on a container's lower half to nest.</div>
                    <Values values={drawn?.placeholders} output={output} textual={textual} onOutput={setOutput} onRenamed={followNames} onEdit={() => setTab("data")} />
                  </div>

                  <div className="kb-view-inspect">
                    {adding
                      ? <NodePicker into={addInto} onPick={add} onClose={() => setAdding(undefined)} />
                      : picked && dict(picked.node)
                      ? (
                        <>
                          <div className="kb-view-head">
                            <span><b>{nameOf(picked.node.type)}</b> <code>{picked.node.type}</code></span>
                          </div>
                          <div className="kb-note">{NODE_INFO[picked.node.type]?.[1]}.</div>
                          <NodeForm key={JSON.stringify(picked.path)} node={picked.node} output={output} onList={addList} onChange={node => onView(replaceNode(view, picked.path, node))} />
                          <div className="kb-row" style={{ flexWrap: "wrap", marginTop: 6 }}>
                            {picked.node.type === "if" && picked.node.else === undefined && (
                              <Button kind="plain" icon="plus" onClick={() => setAdding({ parent: picked.path, key: "else" })}>Add what shows otherwise</Button>
                            )}
                            <Button kind="plain" icon="layout-columns" onClick={() => { onView(wrapNode(view, picked.path, "hstack")); onPath(picked.path); }}>Wrap in a Row</Button>
                            <Button kind="plain" icon="layout-rows" onClick={() => { onView(wrapNode(view, picked.path, "vstack")); onPath(picked.path); }}>Wrap in a Column</Button>
                          </div>
                        </>
                      )
                      : <div className="kb-note">Pick something on the left, or in the preview, to change it.</div>}
                    <div className="kb-view-foot">
                      <Button kind="plain" icon="trash" onClick={() => { onView(undefined); onPath([]); }}>Start over</Button>
                    </div>
                  </div>
                </div>
              )}
          </section>
        </div>
      </div>
    </div>
  );
}
