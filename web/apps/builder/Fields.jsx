// Form fields made from the module config schema: one for each kind of
// value a config holds, with colours, icons and styles given fields of
// their own. A field left empty leaves its key out of the config.
import { useEffect, useRef, useState } from "react";
import { labelOf, sameAsKey } from "../../builder/labels.js";
import { deref, prune } from "../../builder/schema.js";
import { resolveThemeTemplate } from "../../engine/index.js";
import { dict } from "../../engine/values.js";
import { IconPicker } from "./IconPicker.jsx";
import { Button, Ic, YamlArea, useBuilder } from "./ui.jsx";
import { spell } from "../../builder/spelling.js";

const first = text => (typeof text === "string" ? text.split(/(?<=\.)\s/)[0] : undefined);

// A config key beside the label that stands for it, unless the label says
// no more than the key does.
export function Key({ label, name }) {
  return name === undefined || sameAsKey(String(label), name) ? null : <code className="kb-key">{name}</code>;
}

// A labelled row. `description` explains the field when hovered over, and
// `name` is the config key the label stands for.
export function Row({ label, name, description, wide, children }) {
  return (
    <div className={`kb-f ${wide ? "wide" : ""}`}>
      <span className="label" title={description}>{label}<Key label={label} name={name} /></span>
      {children}
    </div>
  );
}

export function TextField({ value, onChange, placeholder, examples, label }) {
  const id = examples ? `kb-list-${label}` : undefined;
  return (
    <>
      <input type="text" aria-label={label} value={typeof value === "string" ? value : ""} placeholder={placeholder} list={id} spellCheck={false}
        onChange={event => onChange(event.target.value === "" ? undefined : event.target.value)} />
      {examples && <datalist id={id}>{examples.map(example => <option key={example} value={example} />)}</datalist>}
    </>
  );
}

function NumberField({ value, onChange, node, label }) {
  return (
    <input type="number" aria-label={label} value={typeof value === "number" ? value : ""} min={node.minimum} max={node.maximum}
      step={node.type === "integer" ? 1 : "any"} placeholder={node.default === undefined ? undefined : String(node.default)}
      onChange={event => onChange(event.target.value === "" || Number.isNaN(event.target.valueAsNumber) ? undefined : event.target.valueAsNumber)} />
  );
}

// Whether `node` takes a string, a number or a truth value, any of them.
function isLooseScalar(node) {
  const scalar = type => ["string", "number", "integer", "boolean"].includes(type);
  if (Array.isArray(node.type)) return node.type.every(scalar);
  const branches = node.oneOf ?? node.anyOf;
  return Array.isArray(branches) && branches.every(branch => scalar(branch.type) && !branch.enum);
}

// A value written as text that may be a number or a truth value: `true`,
// `false` and numbers are kept as such, anything else as text.
function LooseField({ value, onChange, label, placeholder }) {
  const read = text => (text === "" ? undefined : text === "true" ? true : text === "false" ? false
    : text.trim() !== "" && Number.isFinite(Number(text)) ? Number(text) : text);
  return (
    <input type="text" aria-label={label} value={value === undefined || value === null ? "" : String(value)} placeholder={placeholder} spellCheck={false}
      onChange={event => onChange(read(event.target.value))} />
  );
}

// A choice among `options`, the first standing for the key left out.
function Choice({ value, onChange, options, unset, label }) {
  const index = options.findIndex(option => option === value);
  return (
    <select aria-label={label} value={index < 0 ? "" : String(index)}
      onChange={event => onChange(event.target.value === "" ? undefined : options[Number(event.target.value)])}>
      <option value="">{unset}</option>
      {options.map((option, i) => <option key={i} value={String(i)}>{String(option)}</option>)}
    </select>
  );
}

// A truth value kantan has a default for, as a tick. One left as kantan
// has it is left out of the config.
function Switch({ value, onChange, fallback, label }) {
  const on = typeof value === "boolean" ? value : fallback;
  return (
    <div className="kb-row">
      <input type="checkbox" aria-label={label} checked={on} onChange={event => onChange(event.target.checked === fallback ? undefined : event.target.checked)} />
    </div>
  );
}

// The theme's colours to pick from, each beside a dot of itself.
function ThemeColors({ value, onChange, palette, label }) {
  const [open, setOpen] = useState(false);
  const ref = useRef(null);
  useEffect(() => {
    if (!open) return undefined;
    const outside = event => !ref.current?.contains(event.target) && setOpen(false);
    const escape = event => event.key === "Escape" && setOpen(false);
    window.document.addEventListener("mousedown", outside);
    window.document.addEventListener("keydown", escape, true);
    return () => {
      window.document.removeEventListener("mousedown", outside);
      window.document.removeEventListener("keydown", escape, true);
    };
  }, [open]);
  const names = ["fg", "bg", ...(palette.shape === undefined ? [] : ["shape"]), ...Object.keys(palette.colors)];
  const picked = names.find(name => value === `{theme(${name})}`);
  const dot = name => <i className="dot" style={{ background: resolveThemeTemplate(`{theme(${name})}`, palette) }} />;
  return (
    <span className="kb-colors" ref={ref}>
      <button type="button" aria-haspopup="listbox" aria-expanded={open} aria-label={spell(`${label}: a colour of the theme`)} onClick={() => setOpen(!open)}>
        {picked ? <>{dot(picked)}<span>{picked}</span></> : <span className="unset">Theme</span>}
        <Ic name="chevron-down" size={12} />
      </button>
      {open && (
        <ul role="listbox">
          {names.map(name => (
            <li key={name} role="option" aria-selected={name === picked}>
              <button type="button" onClick={() => { onChange(`{theme(${name})}`); setOpen(false); }}>{dot(name)}<span>{name}</span></button>
            </li>
          ))}
        </ul>
      )}
    </span>
  );
}

// A colour: a hex colour or one of the theme's, by name. `fallback` is
// the colour drawn while none is set here. A `plain` one is a hex colour
// alone.
export function ColorField({ value, onChange, label, fallback, plain }) {
  const context = useBuilder();
  const palette = plain ? undefined : context.palette;
  const text = typeof value === "string" ? value : "";
  const resolved = palette && text.startsWith("{theme(") ? resolveThemeTemplate(text, palette) : text;
  const hex = /^#?[0-9a-fA-F]{6}/.test(resolved) ? `#${resolved.replace(/^#/, "").slice(0, 6)}` : undefined;
  const shown = hex ?? (text === "" ? fallback : undefined);
  return (
    <div className="kb-row">
      <span className={`kb-swatch ${hex === undefined && shown !== undefined ? "inherited" : ""}`}
        style={{ background: shown ?? "repeating-linear-gradient(45deg, transparent 0 4px, var(--line) 4px 8px)" }}>
        <input type="color" aria-label={spell(`${label}: pick a colour`)} value={hex ?? "#888888"} onChange={event => onChange(event.target.value)} />
      </span>
      <input type="text" aria-label={label} value={text} placeholder={fallback !== undefined ? "Not set here" : palette ? "#rrggbb or {theme(name)}" : "#rrggbb"} spellCheck={false}
        onChange={event => onChange(event.target.value === "" ? undefined : event.target.value)} />
      {palette && <ThemeColors value={text} onChange={onChange} palette={palette} label={label} />}
    </div>
  );
}

// The style of one of a module's conditions, such as a battery charging:
// a colour, or separate colours for its parts.
function StateStyleField({ value, onChange, label }) {
  const { schema } = useBuilder();
  const [parts, setParts] = useState(dict(value) !== undefined);
  const node = deref(schema, { $ref: "#/$defs/StateStyle" }).oneOf.map(each => deref(schema, each)).find(each => each.type === "object");
  const toggle = () => {
    onChange(parts ? value?.fg : typeof value === "string" ? { fg: value } : value);
    setParts(!parts);
  };
  return (
    <div>
      {parts
        ? <Properties node={node} value={dict(value)} onChange={onChange} />
        : <ColorField value={typeof value === "string" ? value : undefined} onChange={onChange} label={label} />}
      <label className="kb-row" style={{ padding: "4px 0" }}>
        <input type="checkbox" checked={parts} onChange={toggle} />
        <span>{spell("Separate colours for its icon, text and shape")}</span>
      </label>
    </div>
  );
}

// An icon: a Tabler icon by name, picked from them all, or any text.
export function IconField({ value, onChange, placeholder, label }) {
  const [picking, setPicking] = useState(false);
  const text = typeof value === "string" ? value : "";
  return (
    <div className="kb-row">
      <button type="button" className="kb-iconbtn" aria-label={`${label}: pick an icon`} onClick={() => setPicking(true)}>
        <Ic name={text || placeholder || "search"} size={16} style={{ opacity: text ? 1 : 0.4 }} />
      </button>
      <input type="text" aria-label={label} value={text} placeholder={placeholder ?? "An icon's name, or text"} spellCheck={false}
        onChange={event => onChange(event.target.value === "" ? undefined : event.target.value)} />
      {picking && <IconPicker value={text} onPick={name => { onChange(name); setPicking(false); }} onClose={() => setPicking(false)} />}
    </div>
  );
}

// The settings an icon can come with, when `node` is written either as an
// icon alone or as a mapping holding one, such as an icon with a colour of
// its own. Undefined for any other node.
function iconParts(schema, node) {
  const branches = (node.oneOf ?? []).map(branch => deref(schema, branch));
  const parts = branches.find(branch => branch.type === "object" && branch.properties?.icon);
  return branches.length === 2 && parts && branches.some(branch => branch.ref === "Icon") ? parts : undefined;
}

// An icon alone, or with the settings of its own that `parts` describes.
function IconPartsField({ value, onChange, parts, label }) {
  const [own, setOwn] = useState(dict(value) !== undefined);
  const toggle = () => {
    onChange(own ? value?.icon : typeof value === "string" ? { icon: value } : value);
    setOwn(!own);
  };
  return (
    <div>
      {own
        // Each of its settings on a line of its own, the icon's first.
        ? Object.entries(parts.properties).map(([key, child]) => (
          <div key={key} style={{ padding: "2px 0" }}>
            <Control node={child} value={dict(value)?.[key]} label={`${label} ${labelOf(key)}`} name={key}
              onChange={next => onChange(prune({ ...dict(value), [key]: next }))} />
          </div>
        ))
        : <IconField value={typeof value === "string" ? value : undefined} onChange={onChange} label={label} />}
      <label className="kb-row" style={{ padding: "4px 0" }}>
        <input type="checkbox" checked={own} onChange={toggle} />
        <span>{spell("A colour of its own")}</span>
      </label>
    </div>
  );
}

// What a new item of a list starts as: text, or a mapping holding the
// keys it needs.
const blankItem = node => (node.type === "object" ? Object.fromEntries((node.required ?? []).map(key => [key, ""])) : "");

// A list, each item a field of its own. One with no items is left to its
// default, `fallback`, or set to hold none.
function ListField({ value, onChange, items: raw, iconish, label, fallback }) {
  const { schema } = useBuilder();
  const items = deref(schema, raw);
  const list = Array.isArray(value) ? value : [];
  const set = next => onChange(next.length ? next : undefined);
  return (
    <div>
      {list.length === 0 && (
        <div className="kb-row" style={{ padding: "2px 0" }}>
          <select aria-label={`${label}: with no items`} value={Array.isArray(value) ? "none" : ""}
            onChange={event => onChange(event.target.value === "none" ? [] : undefined)}>
            <option value="">{Array.isArray(fallback) ? `Default (${fallback.length ? fallback.join(", ") : "none"})` : "Not set"}</option>
            <option value="none">None</option>
          </select>
        </div>
      )}
      {list.map((item, i) => (
        <div className="kb-row" key={i} style={{ padding: "2px 0" }}>
          <div style={{ flex: 1, minWidth: 0 }}>
            <Control node={items} value={item} iconish={iconish} label={`${label} ${i + 1}`}
              onChange={next => set(list.map((other, j) => (j === i ? next ?? "" : other)))} />
          </div>
          <Button kind="plain" icon="x" aria-label={`Remove ${label} ${i + 1}`} onClick={() => set(list.filter((_, j) => j !== i))} />
        </div>
      ))}
      <Button kind="plain" icon="plus" onClick={() => onChange([...list, blankItem(items)])}>Add</Button>
    </div>
  );
}

// A mapping from names someone chooses to values, each a field.
function MapField({ value, onChange, items, iconish, label }) {
  const [adding, setAdding] = useState("");
  const map = dict(value) ?? {};
  const set = next => onChange(Object.keys(next).length ? next : undefined);
  const add = () => {
    if (adding === "" || Object.hasOwn(map, adding)) return;
    set({ ...map, [adding]: "" });
    setAdding("");
  };
  return (
    <div>
      {Object.entries(map).map(([key, item]) => (
        <div className="kb-row" key={key} style={{ padding: "2px 0" }}>
          <span style={{ flex: "0 1 40%", overflowWrap: "anywhere" }}>{key}</span>
          <div style={{ flex: 1, minWidth: 0 }}>
            <Control node={items} value={item} iconish={iconish} label={`${label} ${key}`} onChange={next => set({ ...map, [key]: next ?? "" })} />
          </div>
          <Button kind="plain" icon="x" aria-label={`Remove ${key}`} onClick={() => { const { [key]: _, ...rest } = map; set(rest); }} />
        </div>
      ))}
      <div className="kb-row" style={{ padding: "2px 0" }}>
        <input type="text" aria-label={`${label}: a new name`} placeholder="Name" value={adding} spellCheck={false}
          onChange={event => setAdding(event.target.value)} onKeyDown={event => event.key === "Enter" && add()} />
        <Button kind="plain" icon="plus" onClick={add}>Add</Button>
      </div>
    </div>
  );
}

// What each appearance takes, when `node` is written either once for both
// appearances or under `light` and `dark`. Undefined for any other node.
function appearanceMode(schema, node) {
  const branches = (node.oneOf ?? []).map(branch => deref(schema, branch));
  const split = branches.find(branch => Object.keys(branch.properties ?? {}).sort().join() === "dark,light");
  const flat = branches.find(branch => branch !== split);
  return branches.length === 2 && split && flat?.properties ? flat : undefined;
}

// A style, or anything else written per appearance: the same in both, or
// one for each. `mode` describes what an appearance takes.
function StyleField({ value, onChange, mode }) {
  const [split, setSplit] = useState(dict(value) !== undefined && (value.light !== undefined || value.dark !== undefined));
  const toggle = () => {
    onChange(split ? prune(value?.light ?? value?.dark) : prune({ light: value, dark: value }));
    setSplit(!split);
  };
  return (
    <div>
      <label className="kb-row" style={{ padding: "4px 0" }}>
        <input type="checkbox" checked={split} onChange={toggle} />
        <span>Different in light and dark</span>
      </label>
      {split
        ? ["light", "dark"].map(key => (
          <Group key={key} title={labelOf(key)} name={key} node={mode} value={value?.[key]} open
            onChange={next => onChange(prune({ ...value, [key]: next }))} />
        ))
        : <Properties node={mode} value={value} onChange={onChange} />}
    </div>
  );
}

// Whether a key holds icons: any with "icon" in its name, but one that
// names the font icons are drawn in.
const isIconKey = key => /icon/i.test(key) && !/font$/i.test(key);

// The control for a value of the kind `node` describes. `label` names it
// to someone reading the page, and `name` is the key it is held under.
function Control({ node: raw, value, onChange, iconish, label, name }) {
  const { schema } = useBuilder();
  const node = deref(schema, raw);
  if (node.ref === "Color") return <ColorField value={value} onChange={onChange} label={label} />;
  if (node.ref === "Icon") return <IconField value={value} onChange={onChange} placeholder={node.default} label={label} />;
  if (node.ref === "StateStyle") return <StateStyleField value={value} onChange={onChange} label={label} />;
  const parts = iconParts(schema, node);
  if (parts) return <IconPartsField value={value} onChange={onChange} parts={parts} label={label} />;
  const mode = appearanceMode(schema, node);
  if (mode) return <StyleField value={value} onChange={onChange} mode={mode} />;
  if (isLooseScalar(node)) return <LooseField value={value} onChange={onChange} label={label} placeholder={node.default === undefined ? undefined : String(node.default)} />;
  if (node.oneOf || node.anyOf) return <YamlArea value={value} onChange={onChange} rows={3} label={label} />;
  if (node.enum) return <Choice value={value} onChange={onChange} options={node.enum} label={label} unset={node.default === undefined ? "Not set" : `Default (${node.default})`} />;
  switch (node.type) {
    case "string":
      return iconish
        ? <IconField value={value} onChange={onChange} placeholder={node.default} label={label} />
        : <TextField value={value} onChange={onChange} placeholder={node.default} examples={node.examples} label={label} />;
    case "boolean":
      return typeof node.default === "boolean"
        ? <Switch value={value} onChange={onChange} fallback={node.default} label={label} />
        : <Choice value={value} onChange={onChange} options={[true, false]} label={label} unset="Not set" />;
    case "number":
    case "integer":
      return <NumberField value={value} onChange={onChange} node={node} label={label} />;
    case "array":
      return <ListField value={value} onChange={onChange} items={node.items ?? { type: "string" }} iconish={iconish} label={label} fallback={node.default} />;
    case "object":
      if (node.properties && Object.keys(node.properties).length) return <Properties node={node} value={value} onChange={onChange} iconish={iconish} name={name ?? label} />;
      if (dict(node.additionalProperties)) return <MapField value={value} onChange={onChange} items={node.additionalProperties} iconish={iconish} label={label} />;
      return <YamlArea value={value} onChange={onChange} rows={5} label={label} />;
    default:
      return <YamlArea value={value} onChange={onChange} rows={3} label={label} />;
  }
}

// Whether a value of the kind `node` describes takes more room than a row.
function isBlock(schema, raw) {
  const node = deref(schema, raw);
  if (node.ref === "Color" || isLooseScalar(node)) return false;
  return node.oneOf !== undefined || node.type === "object" || node.type === "array";
}

// A field for each of an object's properties, or only those in `only`.
// Those in `skip` are left to the caller. `name` is the key the object is
// held under. Its properties' labels can depend on it: the properties of
// `fonts` name fonts, whatever they're called.
export function Properties({ node, value, onChange, iconish, name, skip = [], only }) {
  const { schema } = useBuilder();
  const object = dict(value) ?? {};
  const set = (key, next) => {
    const { [key]: _, ...rest } = object;
    const pruned = prune(next);
    onChange(prune(pruned === undefined ? rest : { ...object, [key]: pruned }));
  };
  return Object.entries(node.properties ?? {}).filter(([key]) => !skip.includes(key) && (only === undefined || only.includes(key))).map(([key, child]) => {
    const iconKey = name !== "fonts" && (iconish || isIconKey(key));
    const label = labelOf(key, name);
    return isBlock(schema, child)
      ? <Group key={key} title={label} name={key} node={child} value={object[key]} onChange={next => set(key, next)} iconish={iconKey} />
      : (
        <Row key={key} label={label} name={key} description={first(child.description)}>
          <Control node={child} value={object[key]} onChange={next => set(key, next)} iconish={iconKey} label={label} name={key} />
        </Row>
      );
  });
}

// A value that takes more room than a row, folded away under its title
// until opened. One that is set says so. `name` is the config key it is
// held under.
export function Group({ title, name, node, value, onChange, iconish, open }) {
  return (
    <details className="kb-group" open={open}>
      <summary title={first(node.description)}>
        {title}<Key label={title} name={name} />
        {value !== undefined && <span className="set">set</span>}
      </summary>
      <div><Control node={node} value={value} onChange={onChange} iconish={iconish} label={title} name={name ?? title} /></div>
    </details>
  );
}
