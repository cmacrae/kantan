// The dialog that brings in a theme from elsewhere: a kantan theme file,
// or a Base16 or Base24 scheme for each appearance, pasted in or picked
// from the schemes the tinted-theming project lists.
import { useEffect, useRef, useState } from "react";
import { GALLERY, readListing, readScheme, schemeFileName, schemeTheme } from "../../builder/base16.js";
import { readYaml } from "../../builder/files.js";
import { nameProblem } from "../../builder/theme.js";
import { loadTheme } from "../../engine/index.js";
import { dict } from "../../engine/values.js";
import { Button, Modal, remember, remembered } from "./ui.jsx";

const SYSTEMS = [["base16", "Base16"], ["base24", "Base24"]];
const MODES = [["light", "Light"], ["dark", "Dark"]];
const DOTS = ["base08", "base09", "base0A", "base0B", "base0C", "base0D", "base0E"];

// A scheme's face: its foreground on its background, over a row of its
// colours.
function Face({ palette, mark = "Aa" }) {
  return (
    <span className="face" style={palette ? { background: palette.base00, color: palette.base05 } : undefined}>
      <b>{mark}</b>
      <span className="dots">{palette && DOTS.map(slot => <i key={slot} style={{ background: palette[slot] }} />)}</span>
    </span>
  );
}

// How long this browser keeps what it fetched of the schemes before
// fetching it again: a day.
const KEPT_FOR = 24 * 60 * 60 * 1000;

// What this browser kept under `key` within the last day, or undefined.
function kept(key) {
  try {
    const { at, value } = JSON.parse(remembered(key));
    return Date.now() - at < KEPT_FOR ? value : undefined;
  } catch {
    return undefined;
  }
}
const keep = (key, value) => remember(key, JSON.stringify({ at: Date.now(), value }));

// The scheme at an address, or undefined when it holds none: as this
// browser kept it, or fetched, once.
const schemes = new Map();
function schemeAt(url) {
  if (!schemes.has(url)) {
    const had = readScheme(kept(`kantan-scheme:${url}`));
    schemes.set(url, had ? Promise.resolve(had) : fetch(url).then(response => (response.ok ? response.text() : undefined))
      .then(text => {
        const scheme = text === undefined ? undefined : readScheme(readYaml(text).value);
        if (scheme) keep(`kantan-scheme:${url}`, scheme);
        return scheme;
      })
      .catch(() => undefined));
  }
  return schemes.get(url);
}

// The schemes listed for a system, each `{ name, url }`, as this browser
// kept the listing or fetched, once: undefined when the listing can't be
// had, isn't laid out as expected, or its first file isn't a scheme. A
// listing that passes is kept, with only what is read of it.
const listings = new Map();
function listed(system) {
  if (!listings.has(system)) {
    const key = `kantan-schemes:${system}`;
    const had = readListing(kept(key));
    listings.set(system, had ? Promise.resolve(had) : fetch(GALLERY[system]).then(response => (response.ok ? response.json() : undefined))
      .then(async listing => {
        const entries = readListing(listing);
        if (!entries || !await schemeAt(entries[0].url)) return undefined;
        keep(key, listing.map(({ name, type, download_url }) => ({ name, type, download_url })));
        return entries;
      })
      .catch(() => undefined));
  }
  return listings.get(system);
}

// A scheme in the gallery, drawn in its own colours once it scrolls into
// view. One whose file isn't a scheme can't be picked. `picked` are the
// appearances it has been picked for.
function Card({ entry, picked, onPick }) {
  const ref = useRef(null);
  const [scheme, setScheme] = useState();
  const [failed, setFailed] = useState(false);
  useEffect(() => {
    let current = true;
    const observer = new IntersectionObserver(([seen]) => {
      if (!seen.isIntersecting) return;
      observer.disconnect();
      schemeAt(entry.url).then(read => current && (read ? setScheme(read) : setFailed(true)));
    }, { rootMargin: "200px" });
    observer.observe(ref.current);
    return () => { current = false; observer.disconnect(); };
  }, [entry.url]);
  return (
    <button ref={ref} type="button" className="kb-theme" disabled={!scheme} aria-pressed={picked.length > 0}
      title={scheme?.name ?? entry.name} onClick={() => onPick(entry.name, scheme)}>
      <Face palette={scheme?.palette} mark={failed ? "?" : "Aa"} />
      <span className="name">{entry.name}</span>
      {picked.length > 0 && <span className="pills">{picked.map(mode => <i key={mode}>{mode}</i>)}</span>}
    </button>
  );
}

// The schemes to pick from, shown only while their listing reads as it
// did when this was written.
function Gallery({ slots, onPick }) {
  const [lists, setLists] = useState({});
  const [system, setSystem] = useState("base16");
  const [query, setQuery] = useState("");
  useEffect(() => {
    let current = true;
    for (const [key] of SYSTEMS) listed(key).then(entries => current && entries && setLists(had => ({ ...had, [key]: entries })));
    return () => { current = false; };
  }, []);
  const available = SYSTEMS.filter(([key]) => lists[key]);
  if (available.length === 0) return null;
  const shown = lists[system] ? system : available[0][0];
  const entries = lists[shown];
  const words = query.toLowerCase().split(/\s+/).filter(Boolean);
  const matches = entries.filter(entry => words.every(word => entry.name.includes(word)));
  return (
    <>
      <div className="kb-h">Pick a scheme</div>
      <div className="kb-row" style={{ flexWrap: "wrap", marginBottom: 8 }}>
        {available.length > 1 && (
          <div className="kb-chips" role="group" aria-label="The kind of scheme" style={{ padding: 0 }}>
            {available.map(([key, label]) => (
              <button key={key} type="button" className="kb-chip" aria-pressed={shown === key} onClick={() => setSystem(key)}>{label}</button>
            ))}
          </div>
        )}
        <input type="text" aria-label="Search the schemes" placeholder={`Search ${entries.length} schemes`} value={query} spellCheck={false}
          style={{ flex: "1 1 160px" }} onChange={event => setQuery(event.target.value)} />
      </div>
      <div className="kb-gallery">
        {matches.map(entry => (
          <Card key={entry.url} entry={entry} onPick={onPick}
            picked={MODES.map(([mode]) => mode).filter(mode => slots[mode]?.name === entry.name && slots[mode].scheme.system === shown)} />
        ))}
      </div>
      <div className="kb-note">
        {matches.length === 0 ? "No scheme has that name. " : ""}
        Your browser fetches these from the <a href="https://github.com/tinted-theming/schemes" target="_blank" rel="noreferrer">tinted-theming schemes</a> on GitHub.
      </div>
    </>
  );
}

// `taken` are the names themes already have. `onImport(name, theme)`
// takes in a kantan theme file. `onImportSchemes(picks)` takes in the
// themes of the schemes picked: `picks` holds `{ name, theme }` for
// `light`, for `dark` or for both, and an appearance it leaves out keeps
// the theme the config has for it.
export function ThemeImport({ taken, onImport, onImportSchemes, onClose }) {
  // The scheme picked for each appearance, each `{ name, scheme }`, and
  // the appearance the next pick is for. A scheme that says which
  // appearance it suits goes there first, until a slot is asked for.
  const [slots, setSlots] = useState({});
  const [filling, setFilling] = useState("light");
  const [asked, setAsked] = useState(false);
  const [name, setName] = useState("");
  const [text, setText] = useState("");

  const other = mode => (mode === "light" ? "dark" : "light");
  const pick = (picked, scheme) => {
    const mode = !asked && scheme.variant !== undefined && slots[scheme.variant] === undefined ? scheme.variant : filling;
    const next = { ...slots, [mode]: { name: picked, scheme } };
    setSlots(next);
    setFilling(next[other(mode)] === undefined ? other(mode) : mode);
    setAsked(false);
  };
  const clear = mode => {
    const { [mode]: _, ...rest } = slots;
    setSlots(rest);
    setFilling(mode);
    setAsked(true);
  };

  const read = text.trim() === "" ? {} : readYaml(text);
  const scheme = readScheme(read.value);
  const loads = dict(read.value) !== undefined && loadTheme("it", { it: read.value }) !== undefined;
  const wanted = name !== "" ? name : scheme ? schemeFileName(scheme.name) : "";
  const problem = wanted === "" ? undefined : nameProblem(wanted) ?? (loads && taken.includes(wanted) ? "Another theme has that name" : undefined);
  const unread = text.trim() === "" || loads || scheme ? undefined
    : read.problem !== undefined ? `It isn't YAML kantan can read: ${read.problem}`
    : "It's neither a theme kantan can load, whose palettes each need fg and bg, nor a Base16 or Base24 scheme";

  const theme = slot => ({ name: slot.name, theme: schemeTheme(slot.scheme) });
  const filled = MODES.map(([mode]) => mode).filter(mode => slots[mode] !== undefined);
  const only = filled.length === 1 ? filled[0] : undefined;

  return (
    <Modal title="Import a theme" onClose={onClose} wide>
      <div className="kb-note" style={{ paddingTop: 0 }}>
        A <a href="https://github.com/tinted-theming/home" target="_blank" rel="noreferrer">Base16 or Base24</a> scheme becomes a theme with a colour for each of its slots,
        {" "}<code>base00</code> to <code>base0F</code> or <code>base17</code>. A config that names Catppuccin's colours is rewritten to name the slots that hold them.
      </div>
      <div className="kb-h">Schemes to import</div>
      <div className="kb-slots">
        {MODES.map(([mode, label]) => (
          <div key={mode} className={`kb-slotcard ${filling === mode ? "on" : ""}`}>
            <button type="button" aria-pressed={filling === mode} aria-label={`Pick the scheme for ${mode}`}
              onClick={() => { setFilling(mode); setAsked(true); }}>
              <Face palette={slots[mode]?.scheme.palette} mark={slots[mode] ? "Aa" : ""} />
              <span>
                <b>{label}</b>
                <span>{slots[mode]?.name ?? (filling === mode ? "Pick a scheme below" : "Nothing picked")}</span>
              </span>
            </button>
            {slots[mode] && <Button kind="plain" icon="x" aria-label={`Clear the scheme for ${mode}`} onClick={() => clear(mode)} />}
          </div>
        ))}
      </div>
      <div className="kb-row" style={{ flexWrap: "wrap", margin: "8px 0 4px" }}>
        {filled.length === 2 && <Button kind="primary" onClick={() => onImportSchemes({ light: theme(slots.light), dark: theme(slots.dark) })}>Import</Button>}
        {only && (
          <>
            <Button kind="primary" onClick={() => onImportSchemes({ light: theme(slots[only]), dark: theme(slots[only]) })}>Import it for light and dark</Button>
            <Button onClick={() => onImportSchemes({ [only]: theme(slots[only]) })}>Import it for {only} only</Button>
          </>
        )}
        {filled.length === 0 && <span className="kb-note">Pick one scheme for both appearances, or one for each.</span>}
      </div>
      <Gallery slots={slots} onPick={pick} />

      <div className="kb-h">Or paste a file</div>
      <textarea aria-label="The theme file" rows={7} spellCheck={false} value={text} placeholder="Paste a scheme's YAML, or a kantan theme file"
        onChange={event => setText(event.target.value)} />
      {unread !== undefined && <div className="kb-problem">{unread}</div>}
      {scheme && !loads && <div className="kb-note">A {scheme.system === "base24" ? "Base24" : "Base16"} scheme{scheme.name === "" ? "" : `: ${scheme.name}`}.</div>}
      {loads && <div className="kb-note">A kantan theme file. It opens in the theme editor, and the config keeps the theme it has until you choose to use this one.</div>}
      <div className="kb-row" style={{ marginTop: 6 }}>
        <input type="text" aria-label="The theme's name" value={name} placeholder={wanted === "" ? "The theme's name" : wanted} spellCheck={false}
          onChange={event => setName(event.target.value)} />
        {loads
          ? <Button kind="primary" disabled={wanted === "" || problem !== undefined} onClick={() => onImport(wanted, read.value)}>Import it</Button>
          : <Button disabled={!scheme || wanted === "" || problem !== undefined} onClick={() => { pick(wanted, scheme); setText(""); setName(""); }}>Pick it for {filling}</Button>}
      </div>
      {problem !== undefined && <div className="kb-problem">{problem}</div>}
      <div className="kb-note">A kantan theme kept as a directory goes in as one file: its flavours under <code>flavours</code>, beside its <code>defaults</code>.</div>
    </Modal>
  );
}
