// The config builder: a bar drawn live as kantan would draw it, the
// modules it holds, a form for whichever is picked, and the YAML that
// makes it, to copy, download or share as a link.
import { useCallback, useEffect, useLayoutEffect, useMemo, useRef, useState } from "react";
import { BarView } from "../../components/BarView.jsx";
import { wallpaper } from "../../components/Desk.jsx";
import { cssColor, faded } from "../../components/system.js";
import { useBar } from "../../components/useBar.js";
import { useFitZoom } from "../../components/useFitZoom.js";
import { loadConfig, loadTheme, resolveBar } from "../../engine/index.js";
import { dict } from "../../engine/values.js";
import { pluginOf } from "../../builder/catalog.js";
import {
  addBuiltIn, addOwnPlugin, addPasted, addPlugin, addShared, boundDocument, documentFromConfig, emptyDocument, inLayout, layoutOf, modulesOf, placeAtEdge,
  placeModule, removeModule, setModuleStates, toSingle, updateModule,
} from "../../builder/edit.js";
import { adoptSlots, importSchemes, withSharedTheme } from "../../builder/base16.js";
import { documentFiles, readYaml, themeFiles, writeYaml } from "../../builder/files.js";
import {
  WITH_THEME, configText, decodeLink, decodeModuleLink, decodeThemeLink, encodeLink, encodeModuleLink, encodeThemeLink, readFragment,
} from "../../builder/share.js";
import { moduleDocument, openDrawers, themeDocument, themeVariants } from "../../builder/shared.js";
import {
  freeThemeName, missingColors, newTheme, paletteFor, previewRef, removeTheme, renameColor, renameColorRefs, renameTheme,
  renameThemeFlavour, selectedThemes, setTheme, themeKind,
} from "../../builder/theme.js";
import bundled from "../../generated/catalog.json";
import example from "../../generated/example.json";
import schema from "../../generated/module-config.schema.json";
import outputSchema from "../../generated/plugin-output.schema.json";
import { AddModule } from "./AddModule.jsx";
import { BarSettings } from "./BarSettings.jsx";
import { ModuleEditor } from "./ModuleEditor.jsx";
import { ModuleList } from "./ModuleList.jsx";
import { Output, Share, ShareModule } from "./Output.jsx";
import { QuickEdit } from "./QuickEdit.jsx";
import { SharedModule } from "./SharedModule.jsx";
import { SharedTheme } from "./SharedTheme.jsx";
import { ThemeEditor } from "./ThemeEditor.jsx";
import { STYLES } from "./styles.js";
import { BuilderContext, Button, Ic, Modal, SiteLinks, remember, remembered } from "./ui.jsx";
import { ViewBuilder } from "./ViewEditor.jsx";
import { moveView, startView, viewOf, withStateView, withView } from "../../builder/view.js";
import { spell } from "../../builder/spelling.js";

// Whether the editor was left open, as this browser keeps it.
const EDITOR_KEY = "kantan-builder-editor";

// What the desktop's hint asks its reader to try, and where this browser
// keeps the ones they have.
const HINT_KEY = "kantan-builder-hint";
const HINTED = ["edit", "move", "add"];

// As many changes as can be undone.
const HISTORY = 100;

// What can be added to a bar, with the example bar: the one the landing
// page draws, in the states it shows there.
const catalog = { ...bundled, example: { version: example.version, config: example.config, states: example.states } };

// It opens with caffeine off, as the landing page's does.
const exampleDocument = () => ({ ...catalog.example, view: { shown: { caffeine: "Off" } } });

// The document a config.yaml's text makes, or an error saying why it
// makes none.
function documentFromText(text) {
  const { value, problem } = readYaml(text);
  if (problem !== undefined) throw new Error(`The config isn't YAML kantan can read: ${problem}`);
  if (!dict(value)) throw new Error("The config isn't a mapping of settings");
  return documentFromConfig(value, catalog);
}

// The example bar with a module someone shared added to it and picked,
// in the state it was shared in, and in the theme that came with it.
function onExample(shared) {
  const { document: added, name } = addShared(exampleDocument(), shared);
  const document = shared.theme === undefined ? added : withSharedTheme(added, shared.theme, catalog.themes);
  const shown = { ...document.view?.shown, ...(shared.shown === undefined ? {} : { [name]: shared.shown }) };
  return {
    document: { ...document, view: { ...document.view, shown } },
    pick: name,
    note: `${name} is a module shared by a link, added here to the example bar. To put it on a bar of your own, open that bar and paste the link into Add a module.`,
  };
}

// The example bar drawn in a theme someone shared.
function inTheme(shared) {
  return {
    document: withSharedTheme(exampleDocument(), shared, catalog.themes),
    note: `${shared.name ?? selectedThemes(shared.selection).join(" and ")} is a theme shared by a link, shown here on the example bar. To use it on a bar of your own, open that bar and paste the link into Import a theme.`,
  };
}

// What the page's address asks for: `{ document }` from a shared link,
// `{ shared }` from a link to one module, with the `theme` that came with
// it and `themeLink`, the fragment that holds that theme alone,
// `{ sharedTheme }` from a link to a theme, `{ document, source }` from a
// config file fetched from elsewhere, or undefined when it asks for
// nothing.
async function fromAddress() {
  const asked = readFragment(window.location.hash);
  if (asked === undefined) return undefined;
  if (asked.link !== undefined) return { document: await decodeLink(asked.link, catalog) };
  if (asked.module !== undefined) {
    const shared = await decodeModuleLink(asked.module, catalog);
    return asked.theme === undefined ? { shared } : { shared: { ...shared, theme: await decodeThemeLink(asked.theme), themeLink: asked.theme } };
  }
  if (asked.theme !== undefined) return { sharedTheme: await decodeThemeLink(asked.theme) };
  const response = await fetch(asked.url);
  if (!response.ok) throw new Error(`The config couldn't be fetched: ${asked.url} answered ${response.status}`);
  return { document: documentFromText(configText(await response.text(), asked)), source: window.location.href };
}

// Every Tabler icon, once their table has loaded: `icons`, the lookup the
// engine draws with, and `iconNames`, for searching.
function useIcons() {
  const [table, setTable] = useState();
  useEffect(() => {
    fetch("icons.json").then(response => response.json()).then(fonts => {
      const loaded = new Map();
      for (const [font, glyphs] of Object.entries(fonts)) {
        for (const [name, [code, scale]] of Object.entries(glyphs)) loaded.set(name, { font, char: String.fromCodePoint(code), scale });
      }
      setTable(loaded);
    });
  }, []);
  return useMemo(() => ({
    icons: name => table?.get(name),
    iconNames: table ? [...table.keys()].sort() : [],
  }), [table]);
}

function useSystemDark() {
  const query = "(prefers-color-scheme: dark)";
  const [dark, setDark] = useState(() => window.matchMedia(query).matches);
  useEffect(() => {
    const media = window.matchMedia(query);
    const changed = event => setDark(event.matches);
    media.addEventListener("change", changed);
    return () => media.removeEventListener("change", changed);
  }, []);
  return dark;
}

// The dialog that starts the bar over: from the example, from nothing, or
// from a config someone has, pasted or fetched.
function Start({ onClose, onOpen }) {
  const [text, setText] = useState("");
  const [url, setUrl] = useState("");
  const [problem, setProblem] = useState();
  const paste = () => {
    try {
      onOpen({ document: documentFromText(text) });
    } catch (error) {
      setProblem(error.message);
    }
  };
  // A file on GitHub is fetched as its raw text.
  const fetchUrl = () => {
    const github = url.match(/^https:\/\/github\.com\/([^/]+)\/([^/]+)\/blob\/[^/]+\/(.+)$/);
    const gist = url.match(/^https:\/\/gist\.github\.com\/(?:[^/]+\/)?([0-9a-f]+)\/?$/i);
    window.location.hash = github ? `gh=${github[1]}/${github[2]}/${github[3]}` : gist ? `gist=${gist[1]}` : `from=${encodeURIComponent(url)}`;
    onClose();
  };
  return (
    <Modal title="Start a bar" onClose={onClose}>
      <div className="kb-grid">
        <button type="button" className="kb-card" onClick={() => onOpen({ document: exampleDocument() })}>The example bar</button>
        <button type="button" className="kb-card" onClick={() => onOpen({ document: emptyDocument() })}>An empty bar</button>
      </div>
      <div className="kb-h">From your config.yaml</div>
      <textarea aria-label="Your config.yaml" rows={8} spellCheck={false} value={text} placeholder="Paste your config.yaml here" onChange={event => setText(event.target.value)} />
      <div className="kb-note">Comments are dropped. Files in modules.d aren't read.</div>
      {problem !== undefined && <div className="kb-problem">{problem}</div>}
      <Button kind="primary" disabled={text.trim() === ""} onClick={paste}>Open it</Button>
      <div className="kb-h">From a file on the web</div>
      <div className="kb-row">
        <input type="url" aria-label="The address of a config.yaml" value={url} placeholder="https://github.com/you/dotfiles/blob/main/kantan/config.yaml"
          onChange={event => setUrl(event.target.value)} />
        <Button disabled={!/^https:\/\//.test(url)} onClick={fetchUrl}>Fetch it</Button>
      </div>
      <div className="kb-note">Fetched by the browser. The page's address then links to the live file.</div>
    </Modal>
  );
}

// Whether a module's config sets it over a menu bar item.
const isMasked = module => dict(module?.mask) !== undefined && (typeof module.mask.name === "string" || Number.isInteger(module.mask.index));

// Where the bar draws each module, for listing them: a section for each
// placement the screen has, one for the modules set over the menu bar, and
// one for those with no place. `items` are indexes into `modules`.
function sectionsOf(modules, bar, notch) {
  const index = name => modules.findIndex(module => module?.name === name);
  const listed = new Set();
  const take = names => names.map(index).filter(i => i >= 0 && !listed.has(i) && listed.add(i));

  const masked = take([
    ...bar.menuBar.modules,
    ...Object.values(bar.placements).flat().filter(module => isMasked(modules[index(module.name)])).map(module => module.name),
  ]);
  const placed = key => take(bar.placements[key].map(module => module.name));
  const sections = [
    { title: "Left", placement: "left", items: placed("left") },
    ...(notch ? [
      { title: "Left of the notch", placement: "notchleft|left", items: placed("notchleft") },
      { title: "Right of the notch", placement: "notchright|right", items: placed("notchright") },
    ] : []),
    { title: "Right", placement: "right", items: placed("right") },
  ];
  if (masked.length) {
    sections.push({
      title: "Over the menu bar", fixed: true, items: masked,
      note: "Masked over menu bar items. Position follows macOS.",
    });
  }
  const rest = modules.map((_, i) => i).filter(i => !listed.has(i));
  if (rest.length) {
    sections.push({ title: "Not on this screen", fixed: true, items: rest, note: notch ? undefined : "Notch-only placements. Shown with a notch." });
  }
  return sections;
}

// The builder at work on the document it was opened with.
function Workspace({ opened, iconSet, onStart }) {
  const systemDark = useSystemDark();
  const [history, setHistory] = useState(() => [toSingle(opened.document)]);
  const [layout, setLayout] = useState(() => layoutOf(opened.document));
  // What the editor is on: `{ kind: "bar" }` for the bar's own settings,
  // `{ kind: "module", index }` for a module, `{ kind: "theme", name,
  // palette }` for one of the document's themes and the palette of it
  // being edited, or `{ kind: "view", index, where, path }` for one of a
  // module's views: which of them, and the node of it picked.
  const [focus, setFocus] = useState(() => {
    // A module the address asked for is the one picked.
    const index = opened.pick === undefined ? -1 : modulesOf(opened.document).findIndex(each => each?.name === opened.pick);
    return index < 0 ? { kind: "bar" } : { kind: "module", index };
  });
  const selected = focus.kind === "module" || focus.kind === "view" ? focus.index : -1;
  // Keeps the editor on the module now at `index`, in the view being
  // built if one is.
  const follow = index => setFocus(now => (now.kind === "view" && index >= 0 ? { ...now, index } : index >= 0 ? { kind: "module", index } : { kind: "bar" }));
  const setSelected = index => setFocus(index >= 0 ? { kind: "module", index } : { kind: "bar" });
  const [themeLayout, setThemeLayout] = useState("file");
  const [dark, setDark] = useState(opened.document.view?.dark ?? systemDark);
  const [notch, setNotch] = useState(opened.document.view?.notch ?? false);
  const [pane, setPane] = useState(opened.pick === undefined ? "modules" : "edit");
  const [sharing, setSharing] = useState(false);
  const [sharingModule, setSharingModule] = useState(false);
  const [edited, setEdited] = useState(false);
  // While trying the bar out its modules answer clicks as they do in
  // kantan. Otherwise a click picks a module and a drag moves it.
  const [trying, setTrying] = useState(false);
  const [quick, setQuick] = useState(false);
  // The desktop says what can be done to the bar until each has been
  // done once, in this visit or an earlier one.
  const [learned, setLearned] = useState(() => (remembered(HINT_KEY) ?? "").split(",").filter(Boolean));
  const learn = action => {
    if (learned.includes(action)) return;
    const next = [...learned, action];
    setLearned(next);
    remember(HINT_KEY, next.join(","));
  };
  const [hinting] = useState(() => HINTED.some(action => !learned.includes(action)));
  const hinted = trying || HINTED.every(action => learned.includes(action));
  // Whether the editor below the bar is showing: the settings, the
  // modules and the config. It starts folded away, and stays as it was
  // last left. A module the address asked for opens it.
  const [editing, setEditingState] = useState(() => opened.pick !== undefined || remembered(EDITOR_KEY) === "open");
  const setEditing = open => { setEditingState(open); remember(EDITOR_KEY, open ? "open" : "closed"); };

  // Space folds the editor away or brings it back, unless the keyboard is
  // in something that takes a space itself, or a dialog is open.
  useEffect(() => {
    const key = event => {
      if (event.key !== " " || event.metaKey || event.ctrlKey || event.altKey) return;
      const held = window.document.activeElement;
      if (held?.closest?.("input, textarea, select, button, summary, a, [contenteditable]")) return;
      if (window.document.querySelector(".kb-shade")) return;
      event.preventDefault();
      setEditing(!editing);
    };
    window.addEventListener("keydown", key);
    return () => window.removeEventListener("keydown", key);
  }, [editing]);

  // Tab switches between the two wherever the keyboard is, but in a
  // dialog, where it moves between the dialog's fields.
  useEffect(() => {
    const key = event => {
      if (event.key !== "Tab" || event.shiftKey || event.metaKey || event.ctrlKey || event.altKey) return;
      if (window.document.querySelector(".kb-shade")) return;
      event.preventDefault();
      setTrying(now => !now);
      setQuick(false);
    };
    window.addEventListener("keydown", key);
    return () => window.removeEventListener("keydown", key);
  }, []);
  const [drag, setDrag] = useState();
  // Where a dragged module would land, or a new one be added.
  const [slot, setSlot] = useState();
  // Where the module being added goes: `{ placement, start }`.
  const [adding, setAdding] = useState();
  const [cramped, setCramped] = useState(false);

  const document = history[history.length - 1];
  const change = useCallback(next => {
    setEdited(true);
    setHistory(past => (next === past[past.length - 1] ? past : [...past.slice(-HISTORY), next]));
  }, []);
  // Undoing a change to a theme or a view leaves the editor on it.
  const undo = () => {
    setHistory(past => (past.length > 1 ? past.slice(0, -1) : past));
    if (focus.kind !== "theme" && focus.kind !== "view") setSelected(-1);
    setQuick(false);
  };

  const modules = useMemo(() => modulesOf(document), [document]);
  const themes = useMemo(() => ({ ...catalog.themes, ...document.themes }), [document.themes]);

  // The theme being edited, while the document still has it, and the
  // palette of it being edited.
  const themeName = focus.kind === "theme" && dict(document.themes?.[focus.name]) ? focus.name : undefined;
  const theme = themeName === undefined ? undefined : document.themes[themeName];
  const themePalette = theme && paletteFor(theme, focus.palette, dark);
  // The bar is drawn in the palette being edited, whatever the config
  // selects, with each plugin's states following its module's settings.
  const drawnDocument = useMemo(() => {
    const bound = boundDocument(document, catalog);
    return theme === undefined ? bound : { ...bound, config: { ...bound.config, theme: previewRef(themeName, theme, themePalette) } };
  }, [document, themeName, theme, themePalette]);
  const config = useMemo(() => loadConfig(drawnDocument, catalog.themes), [drawnDocument]);
  const accepted = useMemo(() => new Set(config.problem === undefined ? config.modules.map(module => module.name) : []), [config]);

  // While customising, every drawer is open, so what it holds can be
  // reached.
  const drawersOpen = useMemo(
    () => (trying ? undefined : Object.fromEntries(modules.filter(each => each?.type === "drawer").map(each => [each.name, { open: true }]))),
    [trying, modules]);
  const { bar, run, toggleDrawer, switchWorkspace, states: shown, setState, samples } = useBar(drawnDocument, {
    dark, notch, icons: iconSet.icons, themes: catalog.themes, states: opened.document.view?.shown, samples: drawersOpen,
  });
  const drawn = useMemo(() => Object.values(bar.placements).flat(), [bar]);
  const sections = useMemo(() => sectionsOf(modules, bar, notch), [modules, bar, notch]);

  const module = selected >= 0 ? modules[selected] : undefined;
  const indexOf = name => modules.findIndex(each => each?.name === name);
  // Picking a module from the list opens its settings in full.
  const select = index => { setSelected(index); setQuick(false); setPane("edit"); };

  // A document with the Catppuccin colours its config names written as the
  // slots of the theme it selects, where that theme lacks them: a bundled
  // plugin's module names Catppuccin's.
  const inSlots = made => {
    const palettes = loadTheme(made.config.theme, { ...catalog.themes, ...made.themes });
    return palettes ? adoptSlots(made, palettes) : made;
  };

  // Adds the module `make` makes where `adding` says, or where a module
  // of its kind starts when it names no placement, and picks it. Returns
  // where the module is among the others.
  const add = make => {
    const made = inSlots(make(document));
    const before = new Set(modules.map(each => each?.name));
    const fresh = modulesOf(made).find(each => !before.has(each?.name));
    const next = placeAtEdge(made, modulesOf(made).indexOf(fresh), adding.placement ?? fresh.placement, adding.start);
    change(next);
    setAdding(undefined);
    setEditing(true);
    const index = modulesOf(next).findIndex(each => each?.name === fresh.name);
    select(index);
    return index;
  };
  // A plugin someone is about to write starts in the view builder, on the
  // popup it will print.
  const addOwn = name => {
    const index = add(doc => addOwnPlugin(doc, name));
    setFocus({ kind: "view", index, where: { slot: "state", state: "Example" }, path: [] });
  };
  // A module that moves stays the one picked, if it was.
  const moved = (next, name) => {
    const picked = module?.name;
    change(next);
    const now = modulesOf(next);
    if (picked !== undefined) setSelected(now.findIndex(each => each?.name === picked));
    return now.findIndex(each => each?.name === name);
  };
  const place = (from, to, after) => moved(placeModule(document, from, to, after), modules[from]?.name);
  const placeIn = (from, placement, start) => moved(placeAtEdge(document, from, placement, start), modules[from]?.name);
  const update = next => {
    const clash = next.name !== module.name && modules.some(each => each !== module && each?.name === next.name);
    if (clash) return;
    const changed = updateModule(document, selected, next);
    change(changed);
    follow(modulesOf(changed).indexOf(next));
    if (next.name !== module.name && shown[module.name] !== undefined) setState(next.name, shown[module.name]);
  };
  const remove = () => { change(removeModule(document, selected)); setSelected(-1); setQuick(false); };
  // Removing a module from the list leaves any other being edited picked.
  const removeAt = index => {
    const next = removeModule(document, index);
    change(next);
    setQuick(false);
    if (focus.kind !== "module") return;
    setSelected(index === selected ? -1 : modulesOf(next).findIndex(each => each?.name === module?.name));
  };

  // The view being built, as written, and the changes made to it.
  const viewing = focus.kind === "view" && dict(module) ? focus : undefined;
  const ownStates = module?.name === undefined ? undefined : document.states?.[module.name];
  const view = viewing && viewOf(module, ownStates, viewing.where);
  // Opens one of the picked module's views in the view builder, with the
  // state that prints it showing.
  const editView = where => {
    setFocus({ kind: "view", index: selected, where, path: [] });
    setQuick(false);
    if (where.slot === "state") setState(module.name, where.state);
  };
  // Changes the module being built on, and its states with it.
  const commit = (nextModule, nextStates) => {
    let next = nextModule === module ? document : updateModule(document, selected, nextModule);
    if (nextStates !== undefined) next = setModuleStates(next, nextModule.name, nextStates);
    change(next);
    follow(modulesOf(next).indexOf(nextModule));
  };
  // A command that prints a view prints JSON, and its click shows a view.
  const printing = () => {
    const click = dict(dict(module.interaction)?.click) ?? {};
    const shows = click.type === "menu" || click.type === "popup";
    if (shows && dict(module.config)?.output === "json") return module;
    return { ...module, config: { ...dict(module.config), output: "json" }, interaction: { ...dict(module.interaction), click: { ...click, type: shows ? click.type : "menu" } } };
  };
  const setView = next => (viewing.where.slot === "state"
    ? commit(next === undefined ? module : printing(), withStateView(ownStates, viewing.where.state, next))
    : update(withView(module, viewing.where.slot, next)));
  // The picked module's states as drawn, and the output of the one showing:
  // what its command prints, with the module's settings where it names them.
  const drawnStates = module?.name === undefined ? undefined : drawnDocument.states?.[module.name];
  const printedNow = (drawnStates?.find(state => state.name === shown[module.name]) ?? drawnStates?.[0])?.output;
  // The module and its states once `starter` is the view being built.
  const startFrom = (starter, kind) => startView(module, ownStates, viewing.where, kind, starter, { shown: shown[module.name], placeholders: viewDrawn?.placeholders });
  const viewEdits = {
    onWhere: editView,
    onView: setView,
    onPath: path => setFocus(now => (now.kind === "view" ? { ...now, path } : now)),
    onKind: type => update({ ...module, interaction: { ...dict(module.interaction), click: { ...dict(dict(module.interaction)?.click), type } } }),
    // A view moved to the config is the click's own, with the module's
    // settings where it named them. One moved to the command's output is
    // printed in every state. A bundled plugin goes on printing its view.
    // The config's is shown in its place.
    onMove: to => {
      const moved = moveView(module, ownStates, to === "config" ? dict(dict(printedNow)?.view) ?? view : view, to, { keep: pluginOf(module, catalog) !== undefined });
      commit(moved.module, moved.states);
      const state = (ownStates?.find(each => each.name === shown[module.name]) ?? ownStates?.[0])?.name;
      setFocus(now => ({ ...now, where: to === "config" ? { slot: "click" } : { slot: "state", state }, path: [] }));
    },
    onShow: state => setState(module.name, state),
    onStates: states => change(setModuleStates(document, module.name, states.length ? states : undefined)),
    onModule: update,
    onCommit: commit,
    onStart: (starter, kind) => {
      const started = startFrom(starter, kind);
      commit(started.module, started.states);
      setFocus(now => (now.kind === "view" ? { ...now, path: [] } : now));
    },
    onDark: () => setDark(!dark),
    onUndo: history.length > 1 ? () => setHistory(past => past.slice(0, -1)) : undefined,
    onClose: () => setSelected(selected),
  };

  // Opens a theme of the document's in the theme editor.
  const editTheme = name => { setFocus({ kind: "theme", name }); setQuick(false); setPane("edit"); };
  const selects = name => selectedThemes(document.config.theme).includes(name);
  const theming = {
    onEdit: editTheme,
    // A new theme is the one the config selects.
    onNew: () => {
      const name = freeThemeName(themes, "my-theme");
      const made = setTheme(document, name, newTheme());
      change({ ...made, config: { ...made.config, theme: name } });
      editTheme(name);
    },
    // A copy of one of kantan's themes takes its place in the config.
    onCopy: from => {
      const name = freeThemeName(themes, `my-${from}`);
      change(renameTheme(setTheme(document, from, structuredClone(catalog.themes[from])), from, name));
      editTheme(name);
    },
    onImport: (name, imported) => { change(setTheme(document, name, imported)); editTheme(name); },
    // The themes of the schemes picked are the ones the config selects,
    // each for its appearance, and the Catppuccin colours the config
    // names follow them. The editor stays on the bar's settings, where
    // the bar is drawn as the config now has it in either appearance.
    onImportSchemes: picks => {
      const held = importSchemes(document, picks, themes);
      const palettes = loadTheme(held.document.config.theme, { ...catalog.themes, ...held.document.themes });
      change(palettes ? adoptSlots(held.document, palettes) : held.document);
    },
    // A theme from a link is the one the config selects, as its sharer's
    // did.
    onImportShared: shared => change(withSharedTheme(document, shared, catalog.themes)),
  };
  const themeEdits = theme && {
    onChange: next => change(setTheme(document, themeName, next)),
    onRename: to => { change(renameTheme(document, themeName, to)); setFocus({ ...focus, name: to }); },
    onRenameFlavour: (from, to) => { change(renameThemeFlavour(document, themeName, from, to)); setFocus({ ...focus, palette: to }); },
    // The config's own uses of a colour follow its new name while the
    // config selects the theme.
    onRenameColor: (from, to) => {
      const renamed = setTheme(document, themeName, renameColor(theme, from, to));
      change(selects(themeName) ? renameColorRefs(renamed, from, to) : renamed);
    },
    // The two palettes of a theme with one for each appearance follow the
    // appearance the bar is drawn in.
    onPalette: key => { setFocus({ ...focus, palette: key }); if (themeKind(theme) === "modes") setDark(key === "dark"); },
    onUse: () => { const { theme: _, ...rest } = document.config; change({ ...document, config: { theme: themeName, ...rest } }); },
    onRemove: () => { change(removeTheme(document, themeName, catalog.themes)); setSelected(-1); },
    onClose: () => setSelected(-1),
  };

  // The document as shared: in the layout chosen, looked at as it is now.
  const makeLink = useCallback(async () => {
    const view = { dark, notch, shown: Object.fromEntries(Object.entries(shown).filter(([name, state]) => {
      const states = document.states?.[name];
      return states !== undefined && states.some(each => each.name === state) && states[0].name !== state;
    })) };
    const fragment = await encodeLink({ ...inLayout(document, layout), view }, catalog);
    return `${window.location.origin}${window.location.pathname}#${fragment}`;
  }, [document, layout, dark, notch, shown]);

  // The picked module as shared on its own, in the state it shows now,
  // with the bar's theme when `themed`.
  const makeModuleLink = useCallback(async themed => {
    const fragment = await encodeModuleLink(module, document.states?.[module.name], shown[module.name], catalog);
    const theme = themed ? `${WITH_THEME}${await encodeThemeLink(document)}` : "";
    return `${window.location.origin}${window.location.pathname}#${fragment}${theme}`;
  }, [document, module, shown]);
  const themeNames = selectedThemes(document.config.theme);

  // The theme the bar is drawn in, shared on its own.
  const makeThemeLink = useCallback(async name => {
    const fragment = await encodeThemeLink(document, name);
    return `${window.location.origin}${window.location.pathname}#${fragment}`;
  }, [document]);
  // The bar's theme as others take it: what the config selects, with the
  // document's own theme files.
  const ownTheme = { selection: document.config.theme, themes: document.themes ?? {} };
  // What the dialog that shares the bar needs to share its theme alone,
  // drawn as the theme's page draws it: on the example bar.
  const themeShare = () => {
    const variants = themeVariants(ownTheme, catalog.themes);
    if (variants.length === 0) return undefined;
    return {
      names: themeNames, makeLink: makeThemeLink, variants,
      barFor: variant => {
        const drawn = themeDocument({ ...ownTheme, selection: variant.selection }, catalog);
        return resolveBar(drawn, { dark: variant.dark, icons: iconSet.icons, themes: catalog.themes, samples: openDrawers(drawn) });
      },
    };
  };
  // A bar holding the picked module alone, as its page draws it, in an
  // appearance: in the bar's theme when `themed`, or the example's.
  const moduleBarFor = (appearance, themed) => resolveBar(
    moduleDocument({ module, states: document.states?.[module.name], theme: themed ? ownTheme : undefined }, catalog),
    { dark: appearance, icons: iconSet.icons, themes: catalog.themes, states: shown });

  // The bar as it is looked at now, in an appearance, for a picture of
  // it: its drawers as they were last left.
  const barFor = appearance => resolveBar(drawnDocument, { dark: appearance, notch, icons: iconSet.icons, themes: catalog.themes, states: shown, samples });

  const files = useMemo(() => documentFiles(inLayout(document, layout)), [document, layout]);
  const themeOutput = useMemo(() => theme && themeFiles(themeName, theme, themeLayout), [themeName, theme, themeLayout]);
  const palette = config.theme?.[dark ? "dark" : "light"];
  const context = useMemo(() => ({ ...iconSet, catalog, schema, outputSchema, palette, dark }), [iconSet, palette, dark]);

  // On a narrow screen the bar shrinks only so far, then scrolls.
  const stage = useRef(null);
  const frame = useRef(null);
  const zoom = useFitZoom(frame, 0.6);
  const element = name => frame.current?.querySelector(`[data-kantan-module="${CSS.escape(name)}"]`);
  const nameAt = target => target.closest?.("[data-kantan-module]")?.dataset.kantanModule;

  // Where the quick settings drop from: the foot of the picked module.
  const [anchor, setAnchor] = useState();
  useLayoutEffect(() => {
    const measure = () => {
      const target = quick && module?.name !== undefined ? element(module.name) : undefined;
      if (!target) return setAnchor(undefined);
      const within = stage.current.getBoundingClientRect(), rect = target.getBoundingClientRect();
      return setAnchor({ x: rect.left + rect.width / 2 - within.left, y: rect.bottom - within.top, width: within.width });
    };
    measure();
    window.addEventListener("resize", measure);
    return () => window.removeEventListener("resize", measure);
  }, [quick, selected, bar, zoom]);

  // With a notch, each side of the screen has only so much room. A window
  // too narrow to give a side the room its modules need says so, in a
  // notice hanging from the notch.
  useLayoutEffect(() => {
    const wide = each => each.getBoundingClientRect().width;
    const measure = () => setCramped(notch && [...frame.current.querySelectorAll("[data-kantan-half]")]
      .some(half => [...half.children].reduce((sum, child) => sum + wide(child), 0) > wide(half) + 1));
    measure();
    window.addEventListener("resize", measure);
    return () => window.removeEventListener("resize", measure);
  }, [bar, zoom, notch]);

  // A click on a module picks it and drops its quick settings. A click
  // anywhere else on the mock lets go of the one picked.
  const pick = event => {
    if (trying) return;
    const index = indexOf(nameAt(event.target));
    if (index < 0 && theme !== undefined) return undefined;
    if (index >= 0) learn("edit");
    setSelected(index);
    return setQuick(index >= 0);
  };

  // A span of the bar, in the bar's own points from its left edge.
  const span = target => {
    const desk = frame.current.getBoundingClientRect(), rect = target.getBoundingClientRect();
    return { left: (rect.left - desk.left) / zoom, right: (rect.right - desk.left) / zoom };
  };

  // Where the pointer would put a module: in the place of the module under
  // it, or in the gap a placement's modules grow into. Undefined over the
  // notch, or over a module that can't give up its place.
  const PLACEMENT_OF = { left: "left", notchleft: "notchleft|left", notchright: "notchright|right", right: "right" };
  // The placements whose modules sit against their right end and grow
  // leftwards.
  const growsLeft = key => key === "right" || key === "notchleft";
  const placedIn = name => Object.keys(bar.placements).find(key => bar.placements[key].some(each => each.name === name));
  const landing = (event, width) => {
    if (event.target.closest?.("[data-kantan-notch]")) return undefined;
    const over = nameAt(event.target);
    if (over !== undefined && !isMasked(modules[indexOf(over)])) {
      if (over === drag || indexOf(over) < 0) return undefined;
      const { left, right } = span(element(over));
      // A module moved along its own placement ends where the other was.
      // One from elsewhere takes the other's place, pushing it the way its
      // placement grows.
      const key = placedIn(over), order = bar.placements[key].map(each => each.name);
      const after = drag !== undefined && placedIn(drag) === key ? order.indexOf(drag) < order.indexOf(over) : growsLeft(key);
      return { name: over, after, x: left, width: right - left };
    }
    const desk = frame.current.getBoundingClientRect();
    const x = (event.clientX - desk.left) / zoom;
    const gaps = Object.keys(PLACEMENT_OF).filter(key => notch || !key.startsWith("notch")).map(key => {
      const { left, right } = span(frame.current.querySelector(`[data-kantan-placement="${key}"]`));
      return growsLeft(key)
        ? { placement: PLACEMENT_OF[key], start: true, x: left - width, away: Math.abs(x - left) }
        : { placement: PLACEMENT_OF[key], start: false, x: right, away: Math.abs(x - right) };
    });
    const { away, ...nearest } = gaps.reduce((best, each) => (each.away < best.away ? each : best));
    return { ...nearest, width };
  };
  const same = (a, b) => JSON.stringify(a) === JSON.stringify(b);

  // What follows the pointer while a module is dragged: the module's own
  // contents and nothing around them. The browser draws it from a copy set
  // down off the page for a moment, in the bar's text settings.
  const dragImage = (event, target) => {
    const content = target.querySelector("[data-kantan-content]");
    if (!content) return;
    const held = content.getBoundingClientRect();
    const text = getComputedStyle(content);
    const copy = window.document.createElement("div");
    copy.style.cssText = `position: fixed; top: -1000px; left: 0; zoom: ${zoom}; display: flex; align-items: center; gap: ${text.gap}; color: ${text.color}; font: ${text.font}; white-space: nowrap; background: transparent;`;
    copy.append(...[...content.cloneNode(true).childNodes]);
    window.document.body.append(copy);
    event.dataTransfer.setDragImage(copy, event.clientX - held.left, event.clientY - held.top);
    setTimeout(() => copy.remove());
  };

  const dragging = {
    onDragStart: event => {
      const name = nameAt(event.target);
      if (trying || name === undefined) return;
      setDrag(name);
      setQuick(false);
      setSlot(undefined);
      event.dataTransfer.effectAllowed = "move";
      event.dataTransfer.setData("text/plain", name);
      dragImage(event, element(name));
    },
    onDragOver: event => {
      if (drag === undefined) return;
      event.preventDefault();
      const { left, right } = span(element(drag));
      const next = landing(event, right - left);
      setSlot(current => (same(current, next) ? current : next));
    },
    onDrop: event => {
      if (drag === undefined) return;
      event.preventDefault();
      const from = indexOf(drag);
      if (slot?.name !== undefined) place(from, indexOf(slot.name), slot.after);
      else if (slot) placeIn(from, slot.placement, slot.start);
      if (slot) learn("move");
      setDrag(undefined);
      setSlot(undefined);
    },
    onDragEnd: () => { setDrag(undefined); setSlot(undefined); },
  };

  // While nothing is dragged or picked, the pointer over an empty part of
  // the bar shows where a new module would go.
  const ADD_WIDTH = 30;
  const hovering = {
    onMouseMove: event => {
      if (trying || drag !== undefined || selected >= 0) return setSlot(undefined);
      if (event.target.closest?.(".kb-slot")) return;
      const empty = event.target.closest?.("[data-kantan-bar]") && nameAt(event.target) === undefined;
      const next = empty ? landing(event, ADD_WIDTH) : undefined;
      setSlot(current => (same(current, next) ? current : next && { ...next, add: true }));
    },
    onMouseLeave: () => drag === undefined && setSlot(undefined),
  };
  const moduleProps = useCallback(each => (trying || each.slot ? undefined : { draggable: true }), [trying]);

  // A module alone on a bar of its own, at the bar's left where a panel
  // has the most room: the one whose view is being built, or one that
  // might be added. `states` are shown in place of the ones it has. One
  // that might be added is drawn `adopted`: in the colours it would take
  // once added, with its states following its settings.
  const barOf = (alone, states, adopted = false) => {
    const { mask: _, ...unmasked } = alone;
    const { modulesDir: __, ...rest } = drawnDocument;
    const only = {
      ...rest,
      config: { ...rest.config, modules: [{ ...unmasked, placement: "left" }] },
      ...(states === undefined ? {} : { states: { ...rest.states, [alone.name]: states } }),
    };
    return resolveBar(adopted ? boundDocument(inSlots(only), catalog) : only, { dark, icons: iconSet.icons, themes: catalog.themes, states: shown, samples });
  };
  const viewBar = useMemo(() => (viewing ? barOf(module) : undefined), [viewing !== undefined, module, drawnDocument, dark, iconSet, shown, samples]);
  const viewDrawn = viewBar && Object.values(viewBar.placements).flat()[0];
  // The module as drawn once `starter` is the view being built.
  const drawStart = (starter, kind) => {
    const started = startFrom(starter, kind);
    return Object.values(barOf(started.module, started.states).placements).flat()[0];
  };

  const tint = cssColor(bar.native ? "primary" : bar.fg, dark);
  const marks = [
    !trying && module?.name !== undefined && `.kb-desk [data-kantan-module="${CSS.escape(module.name)}"] { outline: 1.5px dashed ${dark ? "#fff" : "#000"}; outline-offset: -3px; border-radius: 6px; }`,
    !trying && ".kb-desk [data-kantan-module], .kb-desk [data-kantan-module] * { cursor: grab !important; }",
  ].filter(Boolean).join("\n");

  return (
    <BuilderContext.Provider value={context}>
      <header className="kb-top">
        <a className="kb-brand" href="/"><b>kantan</b><span>builder</span></a>
        <div className="kb-actions">
          <Button icon="file-text" onClick={onStart}>Start over</Button>
          <Button icon="arrow-back-up" disabled={history.length < 2} onClick={undo}>Undo</Button>
          <Button kind="primary" icon="share" onClick={() => setSharing(true)}>Share</Button>
          <SiteLinks />
        </div>
      </header>

      <div className="kb-stage" ref={stage}>
        <div className="kb-stage-inner">
          <div ref={frame} className="kb-desk" style={{ zoom }} onClick={pick} {...dragging} {...hovering}>
            <div className="kb-desk-paper" style={{ background: wallpaper(dark) }} />
            <BarView bar={bar} dark={dark} run={run} toggleDrawer={toggleDrawer} switchWorkspace={switchWorkspace}
              interactive={trying} moduleProps={moduleProps} style={{ borderRadius: "10px 10px 0 0" }} />
            {slot && (
              <button type="button" className={`kb-slot ${slot.add ? "add" : ""}`} tabIndex={slot.add ? 0 : -1}
                aria-label="Add a module here"
                style={{ left: slot.x, top: 4 + bar.gaps.top, width: slot.width, height: bar.height - 8, color: tint, background: faded(tint, slot.name === undefined ? 0.16 : 0.28) }}
                onClick={event => { event.stopPropagation(); learn("add"); setAdding({ placement: slot.placement, start: slot.start }); setSlot(undefined); }}>
                {slot.add && <Ic name="plus" size={14} />}
              </button>
            )}
            {cramped && (
              <div className="kb-notice" role="status" style={{ top: bar.notch.height + 9 }}>
                <span className="arrow" />
                <Ic name="alert-triangle" size={18} />
                <span><b>Not enough room beside the notch</b>Window too narrow: some modules are under the notch.</span>
              </div>
            )}
            <div className="kb-desk-room" style={{ marginTop: -Math.min(bar.gaps.top, 40) }}>
              {hinting && (
                <div className={`kb-hint ${hinted ? "gone" : ""}`} aria-hidden={hinted} style={{ color: dark ? "#cdd6f4" : "#11111b" }}>
                  Click a module to edit it, drag them to move them around, or click a gap to add a new one
                </div>
              )}
            </div>
            <style>{marks}</style>
          </div>
          <div className="kb-stage-controls">
            <div>
              <div className="kb-chips" role="group" aria-label="What a click on the bar does" style={{ padding: 0 }}>
                <button type="button" className="kb-chip kb-tip" aria-pressed={!trying} onClick={() => setTrying(false)}
                  data-tip="Click to edit, drag to move, click a gap to add.">{spell("Customise")}</button>
                <button type="button" className="kb-chip kb-tip" aria-pressed={trying} onClick={() => { setTrying(true); setQuick(false); }}
                  data-tip="Live: hover and click as in kantan.">Try it</button>
              </div>
              <span className="kb-keyhint"><kbd>⇥ Tab</kbd> to switch</span>
            </div>
            <div>
              <Button kind="plain" icon={dark ? "moon" : "sun"} onClick={() => setDark(!dark)}>{dark ? "Dark" : "Light"}</Button>
              <Button kind="plain" icon="device-laptop" on={notch} onClick={() => setNotch(!notch)}>{notch ? "With a notch" : "No notch"}</Button>
            </div>
          </div>
        </div>
        <button type="button" className="kb-fold" aria-expanded={editing} aria-label={editing ? "Hide the editor" : "Show the editor"}
          onClick={() => setEditing(!editing)}>
          {!editing && <span><kbd>Space</kbd> Full editor</span>}
          <Ic name={editing ? "chevron-up" : "chevron-down"} size={30} />
        </button>
        {quick && anchor && dict(module) && (
          <QuickEdit key={selected} module={module} drawn={drawn.find(each => each.name === module.name)} states={document.states?.[module.name]} shown={shown[module.name]}
            at={anchor} width={anchor.width} onChange={update} onShow={state => setState(module.name, state)}
            onEdit={() => { setQuick(false); setPane("edit"); setEditing(true); }} onRemove={remove} onClose={() => setQuick(false)} />
        )}
      </div>

      {opened.problem !== undefined && <div style={{ padding: "0 20px" }}><div className="kb-banner"><span>{opened.problem}</span></div></div>}
      {opened.note !== undefined && <div style={{ padding: "0 20px" }}><div className="kb-banner note"><span>{opened.note}</span></div></div>}

      <div className="kb-tabs" role="tablist" hidden={!editing}>
        {[["modules", "Modules"], ["edit", "Edit"], ["yaml", "YAML"]].map(([key, label]) => (
          <Button key={key} role="tab" aria-selected={pane === key} on={pane === key} onClick={() => setPane(key)}>{label}</Button>
        ))}
      </div>
      <main className="kb-panes" hidden={!editing}>
        <div className={`kb-col ${pane === "modules" ? "on" : ""}`}>
          <button type="button" className={`kb-pane kb-barcard ${selected === -1 && theme === undefined ? "on" : ""}`} onClick={() => select(-1)}>
            <Ic name="adjustments-horizontal" size={18} />
            <span><b>Bar Settings</b></span>
          </button>
          <section className="kb-pane">
            <ModuleList modules={modules} sections={sections} accepted={accepted} selected={selected} onSelect={select}
              onPlace={place} onPlaceIn={placeIn} onAdd={placement => setAdding({ placement, start: false })} onRemove={removeAt} />
          </section>
        </div>
        <section className={`kb-pane ${pane === "edit" ? "on" : ""}`}>
          {theme !== undefined
            ? (
              <ThemeEditor key={themeName} name={themeName} theme={theme} taken={Object.keys(themes).filter(each => each !== themeName)}
                used={selects(themeName)} palette={themePalette} dark={dark} problem={config.problem}
                missing={config.theme ? missingColors(document, config.theme) : []} {...themeEdits} />
            )
            : dict(module)
            ? (
              <ModuleEditor key={selected} module={module} drawn={drawn.find(each => each.name === module.name)}
                accepted={accepted.has(module.name)} masked={isMasked(module)} taken={modules.filter(each => each !== module).map(each => each?.name)}
                states={document.states?.[module.name]} shown={shown[module.name]}
                onChange={update} onShow={state => setState(module.name, state)}
                onStates={states => change(setModuleStates(document, module.name, states.length ? states : undefined))}
                onView={editView} onShare={() => setSharingModule(true)} onRemove={remove} />
            )
            : (
              <BarSettings config={document.config} themes={themes} own={Object.keys(document.themes ?? {})} problem={config.problem} theming={theming}
                onChange={next => change({ ...document, config: { ...next, modules: document.config.modules } })} />
            )}
        </section>
        <section className={`kb-pane ${pane === "yaml" ? "on" : ""}`}>
          {theme !== undefined
            ? (
              <Output title={`Theme: ${themeName}`} files={themeOutput} layout={themeLayout} onLayout={setThemeLayout} archive={`kantan-theme-${themeName}.zip`}
                layouts={themeKind(theme) === "flavours" ? [["file", "One file"], ["dir", spell("A file per flavour")]] : []}
                note={(
                  <>
                    {themeOutput.length === 1 ? <>Save it as <code>~/.config/kantan/{themeOutput[0].path}</code></> : <>Unpack them into <code>~/.config/kantan/</code></>}
                    {" "}and kantan reloads.
                  </>
                )} />
            )
            : (
              <Output title="Config" files={files} layout={layout} onLayout={setLayout} archive="kantan-config.zip"
                layouts={[["single", "One config.yaml"], ["dir", "A file per module in modules.d"]]}
                note={<>{files.length === 1 ? "Save it as" : "Unpack them into"} <code>~/.config/kantan/</code> and kantan reloads.</>} />
            )}
        </section>
      </main>

      {adding && (
        <AddModule onClose={() => setAdding(undefined)} taken={modules.map(each => each?.name)} draw={(alone, states) => barOf(alone, states, true)} dark={dark} onOwn={addOwn}
          onBuiltIn={type => add(doc => addBuiltIn(doc, type))} onPlugin={plugin => add(doc => addPlugin(doc, plugin, catalog))}
          onPasted={(name, pasted) => add(doc => addPasted(doc, name, pasted))}
          onShared={(shared, theme) => add(doc => {
            const added = addShared(doc, shared).document;
            return theme === undefined ? added : withSharedTheme(added, theme, catalog.themes);
          })} />
      )}
      {viewing && (
        <ViewBuilder module={module} bar={viewBar} drawn={viewDrawn} states={ownStates} shown={shown[module.name]} printedOutput={printedNow}
          where={viewing.where} view={view} path={viewing.path} dark={dark} paper={wallpaper(dark)} drawStart={drawStart} {...viewEdits} />
      )}
      {sharingModule && dict(module) && (
        <ShareModule makeLink={makeModuleLink} module={module} plugin={pluginOf(module, catalog)} yaml={() => writeYaml(module)}
          printed={["menu", "popup"].includes(module.interaction?.click?.type) && dict(module.interaction.click.view) === undefined
            && (document.states?.[module.name] ?? []).some(state => dict(dict(state.output)?.view))}
          theme={themeNames.length ? { names: themeNames, named: JSON.stringify([module, document.states?.[module.name]]).includes("{theme(") } : undefined}
          barFor={moduleBarFor} onClose={() => setSharingModule(false)} />
      )}
      {sharing && (
        <Share makeLink={makeLink} source={edited ? undefined : opened.source} barFor={barFor} config={() => documentFiles(toSingle(document))[0].text} theme={themeNames.length ? themeShare() : undefined}
          onClose={() => setSharing(false)} />
      )}
    </BuilderContext.Provider>
  );
}

// Opens what the page's address asks for, or the example bar, and opens
// again whenever the address changes or the bar is started over.
export default function Builder() {
  const iconSet = useIcons();
  const systemDark = useSystemDark();
  const [opened, setOpened] = useState();
  const [session, setSession] = useState(0);
  const [starting, setStarting] = useState(false);

  const open = useCallback(next => {
    setOpened(next);
    setSession(count => count + 1);
    setStarting(false);
  }, []);

  useEffect(() => {
    const load = async () => {
      try {
        open(await fromAddress() ?? { document: exampleDocument() });
      } catch (error) {
        open({ document: exampleDocument(), problem: `${error.message}. This is the example bar instead.` });
      }
    };
    load();
    window.addEventListener("hashchange", load);
    return () => window.removeEventListener("hashchange", load);
  }, [open]);

  // A bar started over is no longer the one the address names.
  const start = next => {
    window.history.replaceState(null, "", window.location.pathname);
    open(next);
  };

  return (
    <div className="kb">
      <style>{STYLES}</style>
      {opened?.shared && (
        <BuilderContext.Provider value={{ ...iconSet, catalog, schema }}>
          <SharedModule key={session} shared={opened.shared} systemDark={systemDark} onBuild={() => open(onExample(opened.shared))} />
        </BuilderContext.Provider>
      )}
      {opened?.sharedTheme && (
        <BuilderContext.Provider value={{ ...iconSet, catalog, schema }}>
          <SharedTheme key={session} shared={opened.sharedTheme} systemDark={systemDark} onBuild={() => open(inTheme(opened.sharedTheme))} />
        </BuilderContext.Provider>
      )}
      {opened?.document && <Workspace key={session} opened={opened} iconSet={iconSet} onStart={() => setStarting(true)} />}
      {starting && (
        <BuilderContext.Provider value={{ ...iconSet, catalog, schema }}>
          <Start onClose={() => setStarting(false)} onOpen={start} />
        </BuilderContext.Provider>
      )}
    </div>
  );
}
