// The page a link to one module opens: the module alone on a bar, with
// its menu, popup or tooltip held open on a desktop as large as that
// needs, the states it was shared with, and its YAML to copy.
import { useLayoutEffect, useMemo, useRef, useState } from "react";
import { BarView } from "../../components/BarView.jsx";
import { wallpaper } from "../../components/Desk.jsx";
import { useBar } from "../../components/useBar.js";
import { highlightYaml } from "../../components/yaml-highlight.jsx";
import { BUILT_INS, PLUGIN_ABOUT, pluginOf } from "../../builder/catalog.js";
import { writeYaml } from "../../builder/files.js";
import { moduleDocument, panelSlots } from "../../builder/shared.js";
import { missingColors, selectedThemes } from "../../builder/theme.js";
import { loadTheme } from "../../engine/index.js";
import { YAML_COLORS } from "./Output.jsx";
import { Button, CopyButton, useBuilder } from "./ui.jsx";

// What a held panel is called, by the slot that opens it.
const HELD = { click: "On click", hover: "On hover" };

// `shared` is the module a link holds, `{ module, states, shown }`, with
// `theme`, the theme that came with it, and `themeLink`, the fragment
// that holds that theme alone. `systemDark` is whether the system's
// appearance is dark. `onBuild` opens the module in the builder.
export function SharedModule({ shared, systemDark, onBuild }) {
  const { catalog, icons } = useBuilder();
  const { module, states = [] } = shared;
  const [dark, setDark] = useState(systemDark);

  // The module alone at the left of the example's bar, where a panel has
  // the most room, in the theme that came with it or the example's.
  const document = useMemo(() => moduleDocument(shared, catalog), [shared]);
  // The colours the module names that the theme it is drawn in lacks.
  const missing = useMemo(() => {
    const palettes = loadTheme(document.config.theme, { ...catalog.themes, ...document.themes });
    return palettes ? missingColors(document, palettes) : [];
  }, [document]);
  const themeNames = shared.theme && selectedThemes(shared.theme.selection).join(" and ");
  const { bar, run, toggleDrawer, switchWorkspace, states: showing, setState } = useBar(document, {
    dark, icons, themes: catalog.themes, states: shared.shown === undefined ? undefined : { [module.name]: shared.shown },
  });
  const drawn = Object.values(bar.placements).flat()[0];
  const current = states.find(state => state.name === showing[module.name]) ?? states[0];

  // The panels the module opens. One is held open, and a module with
  // none answers clicks as it does in kantan.
  const slots = panelSlots(drawn);
  const [wanted, setWanted] = useState();
  const slot = slots.includes(wanted) ? wanted : slots[0];

  // The desktop is as wide and as tall as the panel held open needs.
  const desk = useRef(null);
  const [room, setRoom] = useState({});
  useLayoutEffect(() => {
    const measure = () => {
      const panel = desk.current.querySelector("[data-kantan-panel]");
      if (!panel) return setRoom({});
      const within = desk.current.getBoundingClientRect(), rect = panel.getBoundingClientRect();
      return setRoom({ minHeight: Math.ceil(rect.bottom - within.top) + 28, minWidth: Math.ceil(rect.right - within.left) + 16 });
    };
    measure();
    // The panel takes its size once its fonts have loaded.
    let current = true;
    window.document.fonts.ready.then(() => current && measure());
    window.addEventListener("resize", measure);
    return () => { current = false; window.removeEventListener("resize", measure); };
  }, [bar, slot]);

  const yaml = useMemo(() => writeYaml(module), [module]);
  const plugin = pluginOf(module, catalog);
  const about = plugin !== undefined ? `${PLUGIN_ABOUT[plugin] ?? plugin} plugin` : BUILT_INS[module.type]?.label ?? module.type;

  return (
    <>
      <header className="kb-top">
        <a className="kb-brand" href="/"><b>kantan</b><span>builder</span></a>
        <div className="kb-actions">
          <Button kind="primary" icon="pencil" onClick={onBuild}>Open in the builder</Button>
          <a className="kb-btn plain" href="/docs/">Docs</a>
        </div>
      </header>

      <main className="kb-shared">
        <div>
          <h1>{module.name}</h1>
          <div className="kb-note">
            A shared module{about ? ` · ${about}` : ""}
            {themeNames && <> · in its theme, <a href={`#${shared.themeLink}`}>{themeNames}</a></>}
          </div>
        </div>
        {missing.length > 0 && (
          <div className="kb-problem">
            {themeNames ? "Its theme lacks" : "The link holds no theme, and the example bar's lacks"} {missing.length === 1 ? "a colour" : "colours"} the
            module names: {missing.join(", ")}.
          </div>
        )}

        <div className="kb-shared-desk" ref={desk} style={{ background: wallpaper(dark), ...room }}>
          <BarView bar={bar} dark={dark} run={run} toggleDrawer={toggleDrawer} switchWorkspace={switchWorkspace}
            interactive={slot === undefined} pinned={slot && { module: module.name, slot }} style={{ borderRadius: "10px 10px 0 0" }} />
          {drawn?.hidden && <div className="empty">The module is hidden in this state.</div>}
        </div>

        <div className="kb-shared-under">
          {states.length > 1 && (
            <div className="kb-chips" role="group" aria-label="The state shown">
              {states.map(state => (
                <button key={state.name} type="button" className="kb-chip" aria-pressed={state === current} onClick={() => setState(module.name, state.name)}>{state.name}</button>
              ))}
            </div>
          )}
          {slots.length > 1 && (
            <div className="kb-chips" role="group" aria-label="The panel held open">
              {slots.map(each => (
                <button key={each} type="button" className="kb-chip" aria-pressed={each === slot} onClick={() => setWanted(each)}>{HELD[each]}</button>
              ))}
            </div>
          )}
          <Button kind="plain" icon={dark ? "moon" : "sun"} onClick={() => setDark(!dark)}>{dark ? "Dark" : "Light"}</Button>
        </div>

        <section className="kb-pane">
          <h2>
            <span>Its YAML</span>
            <CopyButton kind="plain" text={yaml} />
          </h2>
          <pre className="kb-code"><code>{highlightYaml(yaml, YAML_COLORS)}</code></pre>
        </section>
        <div className="kb-note">
          Paste the YAML into the <code>modules</code> of a config, or save it as a file in <code>modules.d</code>. To add the module to a bar in
          the builder, open that bar and paste this page's link into Add a module.
        </div>
      </main>
    </>
  );
}
