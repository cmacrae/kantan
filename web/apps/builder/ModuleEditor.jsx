// Edits one module, in the order someone designs it: what it shows, how
// it looks, what a hover and a click do, and where it sits. The settings
// few people change are folded under Advanced, and the module's YAML is a
// tab over.
import { useEffect, useState } from "react";
import { BUILT_INS, kindIcon, pluginOf } from "../../builder/catalog.js";
import { placementParts, withPlacement } from "../../builder/edit.js";
import { ADVANCED, CLICKS, CLOCK_FORMATS, QUICK, labelOf } from "../../builder/labels.js";
import { configSchema, deref, getIn, prune, setIn } from "../../builder/schema.js";
import { cssColor } from "../../components/system.js";
import { TUCK_PEEK, formatDate, parseTuck } from "../../engine/index.js";
import { dict } from "../../engine/values.js";
import { ColorField, Group, IconField, Properties, Row, TextField } from "./Fields.jsx";
import { SECONDARY } from "./ModuleList.jsx";
import { PreviewWith } from "./StateEditor.jsx";
import { BuilderContext, Button, Ic, YamlArea, useBuilder } from "./ui.jsx";
import { spell } from "../../builder/spelling.js";

const PLACEMENTS = [
  ["left", "Left"],
  ["right", "Right"],
  ["notchleft", "Left of the notch"],
  ["notchright", "Right of the notch"],
  ["center", "Centre, without a notch"],
];

const SHAPES = [[undefined, "None"], ["pill", "Pill"], ["box", "Box"], ["underline", "Underline"], ["overline", "Overline"]];

// What a module is, in a word or two: its plugin, or its type.
export function kindOf(module, catalog) {
  const plugin = pluginOf(module, catalog);
  return plugin === undefined ? BUILT_INS[module.type]?.label ?? module.type : `${plugin} plugin`;
}

// One section of a module's design, under its title.
function Section({ icon, title, children }) {
  return (
    <section className="kb-sec">
      <h3><Ic name={icon} size={16} /><b>{title}</b></h3>
      {children}
    </section>
  );
}

// The module's name, changed once it is one no other module has.
function NameField({ name, taken, onRename }) {
  const [draft, setDraft] = useState(name ?? "");
  const clash = draft !== name && (draft === "" || taken.includes(draft));
  const commit = () => (clash || draft === name ? setDraft(name ?? "") : onRename(draft));
  return (
    <Row label="Name" description="Unique name.">
      <div>
        <input type="text" aria-label="Name" value={draft} spellCheck={false} onChange={event => setDraft(event.target.value)}
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

// A clock's format: the pattern as written, and a few to pick from, each
// drawn as the time it writes now.
function ClockFormat({ module, onChange }) {
  const [now, setNow] = useState(() => Date.now());
  useEffect(() => {
    const timer = setInterval(() => setNow(Date.now()), 30000);
    return () => clearInterval(timer);
  }, []);
  const config = dict(module.config) ?? {};
  const set = format => onChange(prune({ ...module, config: { ...config, format } }));
  return (
    <>
      <Row label="Format" description="Unicode date pattern.">
        <TextField value={config.format} onChange={set} label="Format" placeholder="HH:mm" />
      </Row>
      <div className="kb-f">
        <span />
        <div className="kb-chips" role="group" aria-label="Formats to pick from">
          {CLOCK_FORMATS.map(format => (
            <button key={format} type="button" className="kb-chip" aria-pressed={config.format === format} title={format} onClick={() => set(format)}>
              {formatDate(now, format, { timezone: config.timezone }).text ?? format}
            </button>
          ))}
        </div>
      </div>
    </>
  );
}

// A form made from a bundled plugin's own schema, whose keys it holds.
function PluginForm({ plugin, children }) {
  const context = useBuilder();
  return <BuilderContext.Provider value={{ ...context, schema: context.catalog.plugins[plugin].settings }}>{children}</BuilderContext.Provider>;
}

// What the module shows: its icon and the settings of its type. A
// `compact` one has only the settings changed most often.
export function Shows({ module, onChange, compact }) {
  const { schema, catalog } = useBuilder();
  const plugin = pluginOf(module, catalog);
  const type = module.type;
  const config = configSchema(schema, type);
  const set = (key, value) => onChange(prune({ ...module, [key]: prune(value) }) ?? {});
  const settings = plugin === undefined ? undefined : catalog.plugins[plugin].settings;
  const hasSettings = settings && Object.keys(settings.properties ?? {}).some(key => key !== "style");
  // A bundled plugin's command is the plugin. Its own settings shape it.
  const folded = plugin === undefined ? [...(ADVANCED[type] ?? []), "style"] : Object.keys(config?.properties ?? {});
  return (
    <>
      {type === "clock" && <ClockFormat module={module} onChange={onChange} />}
      {config && (
        <Properties node={config} value={dict(module.config)} name={type} onChange={value => set("config", value)}
          skip={[...folded, ...(type === "clock" ? ["format"] : [])]} only={compact ? QUICK[type] ?? [] : undefined} />
      )}
      {type !== "drawer" && (
        <Row label="Icon" description={schema.properties.icon.description}>
          <IconField value={module.icon} onChange={value => set("icon", value)} label="Icon" />
        </Row>
      )}
      {hasSettings && !compact && (
        <PluginForm plugin={plugin}>
          <Properties node={settings} value={dict(dict(module.config)?.settings)} name={plugin} skip={["style"]}
            onChange={value => set("config", { ...dict(module.config), settings: value })} />
        </PluginForm>
      )}
    </>
  );
}

// How the module looks: its colour and its shape, then the colours of
// its icon and text apart. `drawn` is the module as the bar draws it and
// `example` the state it shows. A `compact` one leaves out the colours a
// type or a plugin has for its own conditions.
export function Looks({ module, drawn, example, onChange, compact }) {
  const { schema, catalog, dark } = useBuilder();
  const plugin = pluginOf(module, catalog);
  const split = dict(module.style) !== undefined && (module.style.light !== undefined || module.style.dark !== undefined);
  const style = split ? ["style", dark ? "dark" : "light"] : ["style"];
  const get = path => getIn(module, path);
  const set = (path, value) => onChange(prune(setIn(module, path, value)) ?? {});

  // The colours the bar draws the module in, shown where none is set here.
  const iconColor = cssColor(drawn?.icon?.color, dark), textColor = cssColor(drawn?.text?.[0]?.color, dark);
  // A plugin's output can carry colours of its own. Those win.
  const ownStyle = dict(dict(example?.output)?.style) !== undefined;
  const apart = get([...style, "icon", "fg"]) !== undefined || get([...style, "text", "fg"]) !== undefined;

  const conditions = configSchema(schema, module.type)?.properties?.style;
  const pluginStyle = plugin === undefined ? undefined : catalog.plugins[plugin].settings?.properties?.style;
  const given = module.type === "command" && plugin === undefined ? colourPaths(dict(module.config)?.settings) : [];
  const setConfig = value => onChange(prune({ ...module, config: prune(value) }) ?? {});

  return (
    <>
      <Row label={spell("Colour")} name="fg"><ColorField value={get([...style, "fg"])} onChange={value => set([...style, "fg"], value)} label={spell("Colour")} fallback={iconColor ?? textColor} /></Row>
      <Row label="Shape" name="shape">
        <div className="kb-chips" style={{ padding: 0 }} role="group" aria-label="Shape">
          {SHAPES.map(([shape, label]) => (
            <button key={label} type="button" className="kb-chip" aria-pressed={get([...style, "shape"]) === shape}
              onClick={() => set([...style, "shape"], shape)}>{label}</button>
          ))}
        </div>
      </Row>
      {get([...style, "shape"]) !== undefined && (
        <Row label={spell("Shape colour")} name="bg"><ColorField value={get([...style, "bg"])} onChange={value => set([...style, "bg"], value)} label={spell("Shape colour")} /></Row>
      )}
      <details className="kb-group" open={apart}>
        <summary>{spell("Icon and text colours")}{apart && <span className="set">set</span>}</summary>
        <div>
          <Row label={spell("Icon colour")} name="icon.fg"><ColorField value={get([...style, "icon", "fg"])} onChange={value => set([...style, "icon", "fg"], value)} label={spell("Icon colour")} fallback={iconColor} /></Row>
          <Row label={spell("Text colour")} name="text.fg"><ColorField value={get([...style, "text", "fg"])} onChange={value => set([...style, "text", "fg"], value)} label={spell("Text colour")} fallback={textColor} /></Row>
        </div>
      </details>
      {split && <div className="kb-note">The {dark ? "dark" : "light"} {spell("colours")}. Switch the preview for the others.</div>}
      {ownStyle && (
        <div className="kb-note">
          {pluginStyle
            ? `The ${plugin} plugin's output sets style, which overrides these.${compact ? spell(" Its colours are under Edit.") : spell(" Its colours are below.")}`
            : "The command's output sets style, which overrides these."}
        </div>
      )}

      {!compact && conditions && (
        <Group title={labelOf("style", module.type)} name="style" node={deref(schema, conditions)} value={dict(module.config)?.style}
          onChange={value => setConfig({ ...dict(module.config), style: value })} />
      )}
      {!compact && pluginStyle && (
        <PluginForm plugin={plugin}>
          <Group title={`${plugin} style`} name="style" open node={pluginStyle} value={dict(dict(module.config)?.settings)?.style}
            onChange={value => setConfig({ ...dict(module.config), settings: { ...dict(dict(module.config)?.settings), style: value } })} />
        </PluginForm>
      )}
      {!compact && given.length > 0 && (
        <details className="kb-group" open>
          <summary>{spell("Colours in settings")}</summary>
          <div>
            <div className="kb-note">{spell("Colours")} in <code>config.settings</code>. The states stay as they were printed.</div>
            {given.map(path => (
              <Row key={path.join(".")} label={path.join(".")}>
                <ColorField value={getIn(module.config.settings, path)} label={path.join(".")}
                  onChange={value => value !== undefined && setConfig(setIn(module.config, ["settings", ...path], value))} />
              </Row>
            ))}
          </div>
        </details>
      )}
    </>
  );
}

// The values a module's text can name in braces, each a button that
// writes it. `values` are a drawn module's variables.
export function ValueChips({ values = {}, onPick }) {
  const names = Object.keys(values).filter(name => name !== "icon");
  if (names.length === 0) return null;
  return (
    <div className="kb-valchips" role="group" aria-label="Values to show">
      {names.map(name => (
        <button key={name} type="button" title={`Write {${name}}`} onClick={() => onPick(`{${name}}`)}>
          <code>{`{${name}}`}</code><span>{values[name] === "" ? "empty" : String(values[name])}</span>
        </button>
      ))}
    </div>
  );
}

// What shows while the pointer is over the module: a line of text, or a
// layout built in the view builder.
function OnHover({ module, drawn, onChange, onView }) {
  const interaction = dict(module.interaction) ?? {};
  const hover = dict(interaction.hover);
  const laidOut = dict(hover?.view) !== undefined;
  const text = hover === undefined ? "" : typeof hover.content === "string" ? hover.content : "{value}";
  // A tooltip with nothing to say is no tooltip.
  const write = content => {
    const { content: _, ...rest } = hover ?? {};
    const next = content === "" ? undefined : { ...rest, type: "tooltip", content };
    onChange(prune({ ...module, interaction: { ...interaction, hover: next } }) ?? {});
  };
  if (laidOut) {
    return (
      <div className="kb-row" style={{ flexWrap: "wrap" }}>
        <span className="kb-note" style={{ flex: 1 }}>The tooltip is a view.</span>
        <Button icon="pencil" onClick={() => onView({ slot: "hover" })}>Edit the view</Button>
      </div>
    );
  }
  return (
    <>
      <Row label="Tooltip" name="content">
        <input type="text" aria-label="Tooltip" value={text} placeholder="None" spellCheck={false} onChange={event => write(event.target.value)} />
      </Row>
      <div className="kb-f">
        <span />
        <div>
          <ValueChips values={drawn?.placeholders?.variables} onPick={name => write(`${text}${name}`)} />
          <div className="kb-row" style={{ flexWrap: "wrap" }}>
            <span style={{ flex: 1 }} />
            <Button kind="plain" icon="layout-list" onClick={() => onView({ slot: "hover" })}>Build a view</Button>
          </div>
        </div>
      </div>
    </>
  );
}

// What a click on the module does, picked from the things kantan can do,
// and the way into the view builder for a menu or a popup.
function OnClick({ module, states = [], onChange, onView }) {
  const { catalog } = useBuilder();
  const plugin = pluginOf(module, catalog);
  const interaction = dict(module.interaction) ?? {};
  const click = dict(interaction.click);
  const kind = click === undefined ? undefined : click.type ?? "menu";
  const options = CLICKS.filter(each => each.only === undefined || each.only === module.type);
  const listed = options.some(each => each.type === kind);
  const own = dict(click?.view) !== undefined;
  const printed = states.filter(state => dict(dict(state.output)?.view));
  const shows = kind === "menu" || kind === "popup";
  const word = kind === "popup" ? "popup" : "menu";

  const open = () => onView(own || printed.length === 0 ? { slot: "click" } : { slot: "state", state: printed[0].name });
  const choose = type => {
    if (type === kind) return;
    const next = type === undefined ? undefined : { ...click, type };
    onChange(prune({ ...module, interaction: { ...interaction, click: next } }) ?? {});
    // A menu or popup with nothing in it yet is built straight away.
    if ((type === "menu" || type === "popup") && !own && printed.length === 0) onView({ slot: "click" });
  };
  // A drawer's click opens and closes it, whatever its config says.
  if (module.type === "drawer") {
    return (
      <div className="kb-opts">
        <div>
          <Ic name="box-align-right" size={18} />
          <span><b>Drawer</b><span>Opens and closes the drawer.</span></span>
        </div>
      </div>
    );
  }
  return (
    <>
      <div className="kb-opts" role="group" aria-label="What a click does">
        {options.map(each => (
          <button key={each.label} type="button" aria-pressed={each.type === kind} onClick={() => choose(each.type)}>
            <Ic name={each.icon} size={18} />
            <span><b>{each.label}</b><span>{each.about}</span></span>
          </button>
        ))}
      </div>
      {!listed && (
        <div className="kb-note">The click's type is <code>{String(kind)}</code>. It is under Advanced, in Interaction.</div>
      )}
      {shows && (
        <div className="kb-row" style={{ flexWrap: "wrap", marginTop: 6 }}>
          <span className="kb-note" style={{ flex: 1 }}>
            {own || printed.length === 0 ? ""
              : plugin !== undefined ? `The ${plugin} plugin prints this ${word}.`
              : `Your command prints this ${word}.`}
          </span>
          <Button kind={own || printed.length > 0 ? "" : "primary"} icon="layout-list" onClick={open}>
            {printed.length === 0 && !own ? `Build a ${word}` : `Edit the ${word}`}
          </Button>
        </div>
      )}
      {(kind === "toggle" || kind === "complete") && module.type === "command" && (
        <Row label="Toggle" name="toggle" description="Run on click, then the module refreshes.">
          <TextField value={dict(module.config)?.toggle} label="Toggle" placeholder="A command"
            onChange={value => onChange(prune({ ...module, config: { ...dict(module.config), toggle: value } }) ?? {})} />
        </Row>
      )}
    </>
  );
}

function Design({ module, drawn, example, taken, states, masked, onChange, onView }) {
  const { schema, catalog } = useBuilder();
  const plugin = pluginOf(module, catalog);
  const set = (key, value) => onChange(prune({ ...module, [key]: prune(value) }) ?? {});
  const config = configSchema(schema, module.type);
  // A placement is where the module sits, and for one beside the notch,
  // where it sits on a screen without one.
  const { primary, secondary } = placementParts(module.placement);
  const placements = PLACEMENTS.some(([value]) => value === primary) ? PLACEMENTS : [...PLACEMENTS, [primary, primary]];
  const besideNotch = primary === "notchleft" || primary === "notchright";
  // A module beside the notch can give way to the others on its side.
  const tuck = parseTuck(module.tuck);
  const place = (first, second) => onChange(withPlacement(module, first.startsWith("notch") && second ? `${first}|${second}` : first));
  // A drawer has no click to set.
  const interaction = deref(schema, schema.properties.interaction);
  const { click: _, ...unclicked } = interaction.properties;
  const interactions = module.type === "drawer" ? { ...interaction, properties: unclicked } : interaction;
  const folded = (plugin === undefined ? ADVANCED[module.type] ?? [] : Object.keys(config?.properties ?? {})).filter(key => key !== "settings" || plugin === undefined);
  return (
    <div>
      <Section icon="eye" title="Content">
        <Shows module={module} onChange={onChange} />
      </Section>
      <Section icon="palette" title="Style">
        <Looks module={module} drawn={drawn} example={example} onChange={onChange} />
      </Section>
      {onView && (
        <>
          <Section icon="message" title="On hover">
            <OnHover module={module} drawn={drawn} onChange={onChange} onView={onView} />
          </Section>
          <Section icon="click" title="On click">
            <OnClick module={module} states={states} onChange={onChange} onView={onView} />
          </Section>
        </>
      )}
      <Section icon="layout-navbar" title="Name and placement">
        <NameField key={module.name} name={module.name} taken={taken} onRename={name => onChange({ ...module, name })} />
        <Row label="Placement" name="placement" description={schema.properties.placement.description}>
          <select aria-label="Placement" value={primary ?? ""} disabled={masked && primary === "right"} onChange={event => place(event.target.value, secondary)}>
            {placements.map(([value, label]) => <option key={value} value={value}>{label}</option>)}
          </select>
        </Row>
        {besideNotch && (
          <Row label="Secondary placement" name="placement" description="Where the module sits on a display without a notch. Centre is its own side of the bar's centre.">
            <select aria-label="Secondary placement" value={secondary ?? ""} onChange={event => place(primary, event.target.value)}>
              <option value="">None: hidden without a notch</option>
              {Object.entries(SECONDARY).map(([value, label]) => <option key={value} value={value}>{label}</option>)}
            </select>
          </Row>
        )}
        {besideNotch && module.type !== "drawer" && !masked && (
          <Row label="Tuck" name="tuck" description={schema.properties.tuck.description}>
            <select aria-label="Tuck" value={tuck ? "on" : ""} onChange={event => set("tuck", event.target.value ? true : undefined)}>
              <option value="">Off: keeps its place</option>
              <option value="on">On: waits behind the notch while another module shows</option>
            </select>
          </Row>
        )}
        {besideNotch && module.type !== "drawer" && !masked && tuck && (
          <Row label="Peek" name="tuck" description={schema.properties.tuck.oneOf[1].properties.peek.description}>
            <input type="number" aria-label="Peek" min={0} step={1} value={tuck.peek}
              onChange={event => {
                const peek = event.target.value === "" ? TUCK_PEEK : Math.max(0, Number(event.target.value));
                set("tuck", peek === TUCK_PEEK ? true : { peek });
              }} />
          </Row>
        )}
        {(module.placement ?? "").includes("center") && (
          <Row label="Anchor" name="anchor" description={schema.properties.anchor.description}>
            <select aria-label="Anchor" value={module.anchor ?? ""} onChange={event => set("anchor", event.target.value || undefined)}>
              <option value="">None</option>
              <option value="icon">Icon</option>
            </select>
          </Row>
        )}
        {masked && (
          <div className="kb-note">
            {primary === "right"
              ? "It sits over its menu bar item, at the right. Its place among the other modules there is where its item belongs in the menu bar."
              : "It sits over its menu bar item, at the right, whatever its placement. Place it at the right to give it a place among the modules there."}
          </div>
        )}
        <Group title={labelOf("mask")} name="mask" node={deref(schema, schema.properties.mask)} value={module.mask} onChange={value => set("mask", value)} />
      </Section>

      <details className="kb-more">
        <summary><Ic name="adjustments" size={16} /><b>Advanced</b></summary>
        <div>
          {config && folded.length > 0 && (
            <Properties node={config} value={dict(module.config)} name={module.type} only={folded} onChange={value => set("config", value)} />
          )}
          <Group title={labelOf("fonts")} name="fonts" node={deref(schema, schema.properties.fonts)} value={module.fonts} onChange={value => set("fonts", value)} />
          <Group title="Style" name="style" node={deref(schema, schema.properties.style)} value={module.style} onChange={value => set("style", value)} />
          <Group title="Interaction" name="interaction" node={interactions} value={module.interaction}
            onChange={value => set("interaction", value)} />
        </div>
      </details>
    </div>
  );
}

// `module` is the module's config and `drawn` the module as the bar draws
// it, undefined when it has no place on the screen. `accepted` says whether
// kantan would load it, `masked` whether it sits over a menu bar item, and
// `taken` lists the other modules' names. `states` are the examples it is
// previewed with and `shown` the name of the one showing. `onView` opens
// one of its views in the view builder, and `onShare` shares the module on
// its own.
export function ModuleEditor({ module, drawn, accepted, masked, taken, states, shown, onChange, onShow, onStates, onView, onShare, onRemove }) {
  const { catalog } = useBuilder();
  const [tab, setTab] = useState("design");
  const example = (states ?? []).find(state => state.name === shown) ?? states?.[0];
  return (
    <>
      <h2>
        <Ic name={kindIcon(module, catalog)} />
        <span>{module.name} · {kindOf(module, catalog)}</span>
        {onShare && <Button kind="plain" icon="share" onClick={onShare}>Share</Button>}
        <Button kind="plain" icon="trash" onClick={onRemove}>Remove</Button>
      </h2>
      <div className="kb-subtabs" role="tablist">
        {[["design", "Design"], ["yaml", "YAML"]].map(([key, label]) => (
          <button key={key} type="button" role="tab" aria-selected={tab === key} onClick={() => setTab(key)}>{label}</button>
        ))}
      </div>
      <div className="kb-body">
        {!accepted && (
          <div className="kb-problem" style={{ paddingBottom: 8 }}>
            kantan would leave this module out: its settings are missing something its type needs, or another module has its name.
          </div>
        )}
        {accepted && !drawn && <div className="kb-note">This module has no place on the screen as it is. Switch the notch to see it.</div>}
        {tab === "design" && (
          <>
            <PreviewWith module={module} drawn={drawn} states={states} shown={shown} onShow={onShow} onStates={onStates} />
            <Design module={module} drawn={drawn} example={example} taken={taken} states={states} masked={masked} onChange={onChange} onView={onView} />
          </>
        )}
        {tab === "yaml" && (
          <>
            <div className="kb-note">The module's YAML.</div>
            <YamlArea value={module} rows={18} label="The module's YAML" onChange={value => dict(value) && onChange(value)} />
          </>
        )}
      </div>
    </>
  );
}
