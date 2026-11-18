// Edits one theme file: the kind of file it is, its palettes, and the
// colours each names, with the bar drawn in the palette being edited.
import { useState } from "react";
import { getIn, prune, setIn } from "../../builder/schema.js";
import {
  addColor, addFlavour, colorNames, nameProblem, palettesOf, removeColor, removeFlavour, themeKind, themeProblems, toKind,
} from "../../builder/theme.js";
import { dict } from "../../engine/values.js";
import { ColorField, Row } from "./Fields.jsx";
import { Button, Ic } from "./ui.jsx";
import { spell } from "../../builder/spelling.js";

const KINDS = [
  ["single", "One palette", spell("The same colours in light and dark.")],
  ["modes", "Light and dark", "A palette for each appearance."],
  ["flavours", spell("Flavours"), "Named palettes, with a light and a dark default."],
];

// A name changed in place, once it is one that can be used and none of
// `taken` has. `what` says what is being named.
function NameInput({ value, taken, what, onRename }) {
  const [draft, setDraft] = useState(value);
  const [held, setHeld] = useState(value);
  if (held !== value) {
    setHeld(value);
    setDraft(value);
  }
  const problem = draft === value ? undefined : nameProblem(draft) ?? (taken.includes(draft) ? `Another ${what} has that name` : undefined);
  const commit = () => (problem !== undefined || draft === value ? setDraft(value) : onRename(draft));
  return (
    <div style={{ minWidth: 0 }}>
      <input type="text" aria-label={`The ${what}'s name`} value={draft} spellCheck={false} onChange={event => setDraft(event.target.value)}
        onBlur={commit} onKeyDown={event => event.key === "Enter" && event.target.blur()} />
      {problem !== undefined && <div className="kb-problem">{problem}</div>}
    </div>
  );
}

// `name` is the theme's name and `theme` its file. `taken` are the other
// themes' names, `used` whether the config selects it, `palette` the key
// of the palette being edited and `dark` the appearance the bar is drawn
// in. `missing` are the colours the config names that the theme lacks,
// and `problem` why kantan can't load the config with it, when it can't.
export function ThemeEditor({
  name, theme, taken, used, palette, dark, missing, problem,
  onChange, onRename, onRenameFlavour, onRenameColor, onPalette, onUse, onRemove, onClose,
}) {
  const [adding, setAdding] = useState("");
  const kind = themeKind(theme);
  const palettes = palettesOf(theme);
  const current = palettes.find(each => each.key === palette) ?? palettes[0];
  const values = dict(getIn(theme, current.path)) ?? {};
  const colors = colorNames(theme);
  const problems = themeProblems(theme);
  const set = (key, value) => onChange(prune(setIn(theme, [...current.path, ...key], value)) ?? {});

  const addProblem = adding === "" ? undefined
    : nameProblem(adding) ?? (["fg", "bg", "shape", ...colors].includes(adding) ? spell("The theme has a colour of that name") : undefined);
  const add = () => {
    if (adding === "" || addProblem !== undefined) return;
    onChange(addColor(theme, adding, "#888888"));
    setAdding("");
  };

  // The colours the config names that the theme could hold by name:
  // `shape` is a palette's own.
  const named = missing.filter(each => each !== "shape");

  const flavours = Object.keys(dict(theme.flavours) ?? {});
  const copy = () => {
    let fresh = `${current.key}-copy`;
    for (let n = 2; flavours.includes(fresh); n++) fresh = `${current.key}-copy-${n}`;
    onChange(addFlavour(theme, fresh, current.key));
    onPalette(fresh);
  };

  return (
    <>
      <h2>
        <Ic name="palette" />
        <span>Theme: {name}</span>
        <Button kind="plain" icon="arrow-left" onClick={onClose}>Bar Settings</Button>
      </h2>
      <div className="kb-body">
        <Row label="name" description="The theme key's value, and the file's name.">
          <NameInput value={name} taken={taken} what="theme" onRename={onRename} />
        </Row>
        {!used && (
          <div className="kb-row" style={{ padding: "6px 0" }}>
            <span className="kb-note" style={{ flex: 1 }}>Previewed above. The config doesn't select it.</span>
            <Button kind="primary" onClick={onUse}>Use it</Button>
          </div>
        )}

        <div className="kb-h">Palettes</div>
        <div className="kb-chips" role="group" aria-label="The kind of theme file">
          {KINDS.map(([key, label, tip]) => (
            <button key={key} type="button" className="kb-chip" title={tip} aria-pressed={kind === key}
              onClick={() => kind === key || onChange(toKind(theme, key, dark))}>{label}</button>
          ))}
        </div>
        {kind !== "single" && (
          <div className="kb-subtabs" role="tablist" aria-label="The palette being edited" style={{ padding: 0, marginBottom: 8 }}>
            {palettes.map(each => (
              <button key={each.key} type="button" role="tab" aria-selected={each.key === current.key} onClick={() => onPalette(each.key)}>{each.key}</button>
            ))}
          </div>
        )}
        {kind === "flavours" && (
          <>
            <Row label={spell("flavour")} description={spell("This flavour's name, as a config selects it: theme[flavour].")}>
              <div className="kb-row">
                <NameInput value={current.key} taken={flavours.filter(each => each !== current.key)} what={spell("flavour")}
                  onRename={to => onRenameFlavour(current.key, to)} />
                <Button kind="plain" icon="copy" onClick={copy}>Duplicate</Button>
                <Button kind="plain" icon="trash" disabled={flavours.length < 2} aria-label={spell(`Remove the flavour ${current.key}`)}
                  onClick={() => onChange(removeFlavour(theme, current.key))} />
              </div>
            </Row>
            {["light", "dark"].map(mode => (
              <Row key={mode} label={`${mode} default`} description={spell(`The ${mode} flavour of a config that names the theme alone.`)}>
                <select aria-label={spell(`The default flavour for ${mode}`)} value={flavours.includes(theme.defaults?.[mode]) ? theme.defaults[mode] : ""}
                  onChange={event => onChange({ ...theme, defaults: { ...theme.defaults, [mode]: event.target.value } })}>
                  {!flavours.includes(theme.defaults?.[mode]) && <option value="">None</option>}
                  {flavours.map(each => <option key={each} value={each}>{each}</option>)}
                </select>
              </Row>
            ))}
          </>
        )}

        <div className="kb-h">{spell(kind === "single" ? "Colours" : `Colours of ${current.key}`)}</div>
        <Row label="fg" description="The bar's text and icons.">
          <ColorField plain label="fg" value={values.fg} onChange={value => set(["fg"], value)} />
        </Row>
        <Row label="bg" description="The bar's background.">
          <ColorField plain label="bg" value={values.bg} onChange={value => set(["bg"], value)} />
        </Row>
        <Row label="shape" description="Default shape background. Optional.">
          <ColorField plain label="shape" value={values.shape} onChange={value => set(["shape"], value)} />
        </Row>

        <div className="kb-h">{spell("Named colours")}</div>
        <div className="kb-note" style={{ paddingTop: 0 }}>
          A config uses one as <code>{"{theme(name)}"}</code>.
        </div>
        {colors.map(color => (
          <div className="kb-tc" key={color}>
            <NameInput value={color} taken={["fg", "bg", "shape", ...colors.filter(each => each !== color)]} what={spell("colour")}
              onRename={to => onRenameColor(color, to)} />
            <ColorField plain label={color} value={values.colors?.[color]} onChange={value => set(["colors", color], value)} />
            <Button kind="plain" icon="x" aria-label={spell(`Remove the colour ${color}`)} onClick={() => onChange(removeColor(theme, color))} />
          </div>
        ))}
        <div className="kb-row" style={{ padding: "4px 0" }}>
          <input type="text" aria-label={spell("A new colour's name")} placeholder={spell("A new colour's name")} value={adding} spellCheck={false}
            onChange={event => setAdding(event.target.value)} onKeyDown={event => event.key === "Enter" && add()} />
          <Button icon="plus" disabled={adding === "" || addProblem !== undefined} onClick={add}>Add</Button>
        </div>
        {addProblem !== undefined && <div className="kb-problem">{addProblem}</div>}

        {(problems.length > 0 || missing.length > 0 || problem !== undefined) && <div className="kb-h">To fix</div>}
        {problem !== undefined && <div className="kb-problem">kantan can't load the config with this theme: {problem}</div>}
        {problems.map(each => <div key={each} className="kb-problem">{each}</div>)}
        {missing.length > 0 && (
          <div className="kb-problem">
            The config names {spell(missing.length === 1 ? "a colour" : "colours")} this theme lacks in light or dark: {missing.join(", ")}. kantan draws {missing.length === 1 ? "it" : "them"} transparent.
            {named.length > 0 && (
              <div style={{ marginTop: 6 }}>
                <Button icon="plus" onClick={() => onChange(named.reduce((next, each) => addColor(next, each), theme))}>
                  Add {named.length === 1 ? "it" : "them"} to the theme
                </Button>
              </div>
            )}
          </div>
        )}

        <div style={{ marginTop: 14 }}>
          <Button icon="trash" onClick={onRemove}>Remove this theme</Button>
        </div>
      </div>
    </>
  );
}
