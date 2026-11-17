// Picks the theme the bar is drawn in, for each appearance, from swatches
// of every theme's colours.
import { loadTheme } from "../../engine/index.js";
import { dict } from "../../engine/values.js";

const titled = text => text.replace(/(^|[-_ ])(\p{L})/gu, (_, gap, letter) => (gap ? " " : "") + letter.toUpperCase());

// A theme reference's parts: `name`, or `name[flavour]`.
function parts(ref) {
  const match = /^([^[]+)(?:\[(.+)\])?$/.exec(ref);
  return match ? { name: match[1].trim(), flavour: match[2]?.trim() } : { name: ref };
}

// Every theme a config can name for the appearance `mode`: each theme
// file, or each flavour of one that has them, with the palette it gives.
function choices(themes, mode) {
  return Object.entries(themes).flatMap(([name, file]) => {
    const flavours = Object.keys(dict(file?.flavours) ?? {});
    const refs = flavours.length ? flavours.map(flavour => ({ ref: `${name}[${flavour}]`, name, flavour })) : [{ ref: name, name }];
    return refs.map(choice => ({ ...choice, palette: loadTheme(choice.ref, themes)?.[mode] })).filter(choice => choice.palette);
  });
}

// The theme `selection`, a config's `theme`, names for `mode`, with the
// flavour its theme defaults to written out. Empty when it names none.
function chosen(selection, mode, themes) {
  const raw = typeof selection === "string" ? selection : dict(selection)?.[mode];
  if (typeof raw !== "string") return "";
  const { name, flavour } = parts(raw);
  const fallback = dict(themes[name]?.flavours) ? themes[name].defaults?.[mode] : undefined;
  return flavour ?? fallback ? `${name}[${flavour ?? fallback}]` : name;
}

// A config's `theme` for a choice in each appearance, written the
// shortest way that names them: a theme alone when the two are its
// defaults.
function selection(light, dark, themes) {
  if (light === "" || dark === "") return undefined;
  const l = parts(light), d = parts(dark);
  const defaults = themes[l.name]?.defaults;
  if (l.name === d.name && l.flavour !== undefined && defaults?.light === l.flavour && defaults?.dark === d.flavour) return l.name;
  return light === dark ? light : { light, dark };
}

// A few of a palette's colours, spread across those it names.
function sample(palette, count = 7) {
  const colors = Object.values(palette.colors);
  if (colors.length <= count) return colors;
  return Array.from({ length: count }, (_, i) => colors[Math.round((i * (colors.length - 1)) / (count - 1))]);
}

function Swatch({ choice, picked, onPick }) {
  const { palette } = choice;
  return (
    <button type="button" className="kb-theme" aria-pressed={picked} onClick={onPick}
      title={`${titled(choice.name)}${choice.flavour ? ` ${titled(choice.flavour)}` : ""}`}>
      <span className="face" style={{ background: palette.bg, color: palette.fg }}>
        <b>Aa</b>
        <span className="dots">{sample(palette).map((color, i) => <i key={i} style={{ background: color }} />)}</span>
      </span>
      <span className="name">{titled(choice.flavour ?? choice.name)}</span>
    </button>
  );
}

// `theme` is the config's `theme`, `themes` every theme file it can name,
// and `onChange` is given the `theme` to write, undefined for none.
export function ThemePicker({ theme, themes, onChange }) {
  const current = { light: chosen(theme, "light", themes), dark: chosen(theme, "dark", themes) };
  // A theme names both appearances or neither.
  const pick = (mode, ref) => {
    const next = { ...current, [mode]: ref };
    const other = mode === "light" ? "dark" : "light";
    if (next[other] === "") next[other] = ref;
    onChange(selection(next.light, next.dark, themes));
  };
  const row = (mode, label) => {
    const all = choices(themes, mode);
    const names = [...new Set(all.map(choice => choice.name))];
    return (
      <div className="kb-theme-row">
        <div className="kb-theme-mode">{label}</div>
        {names.map(name => (
          <div key={name}>
            {(names.length > 1 || all.some(choice => choice.flavour)) && <div className="kb-note" style={{ paddingTop: 0 }}>{titled(name)}</div>}
            <div className="kb-theme-set">
              {all.filter(choice => choice.name === name).map(choice => (
                <Swatch key={choice.ref} choice={choice} picked={current[mode] === choice.ref} onPick={() => pick(mode, choice.ref)} />
              ))}
            </div>
          </div>
        ))}
      </div>
    );
  };
  // The theme picked when one is first asked for: the first theme, in
  // the flavours it defaults to.
  const first = () => {
    const light = choices(themes, "light")[0], dark = choices(themes, "dark")[0];
    if (!light || !dark) return undefined;
    return selection(chosen(light.name, "light", themes) || light.ref, chosen(dark.name, "dark", themes) || dark.ref, themes);
  };
  const themed = theme !== undefined;
  return (
    <div>
      <div className="kb-chips" role="group" aria-label="How the bar is coloured">
        <button type="button" className="kb-chip" aria-pressed={!themed} onClick={() => onChange(undefined)}>Native</button>
        <button type="button" className="kb-chip" aria-pressed={themed} onClick={() => themed || onChange(first())}>Theme</button>
      </div>
      {themed
        ? <>{row("light", "While the Mac is light")}{row("dark", "While the Mac is dark")}</>
        : (
          <div className="kb-note">
            The bar takes the menu bar's own material and colours, in light and dark alike. Pick a theme instead to give it colours of its own.
          </div>
        )}
    </div>
  );
}
