// Draws each plugin's preview on its docs page: a strip of bar holding the
// plugin's module as kantan draws it, in the theme matching the docs'.
// Clicking the module does what kantan does, and a command run from its
// menu moves the preview to the state that command leads to. A picker below
// the bar shows any state.
//
// A page asks for a preview with <div class="kantan-preview"
// data-preview="name">, and the loader starts this script with `base`, the
// address the previews are served from.
import { useEffect, useMemo, useState } from "react";
import { createRoot } from "react-dom/client";
import { BarView } from "../../components/BarView.jsx";
import { iconTable, nextState, resolveBar } from "../../engine/index.js";

const DARK_THEMES = ["coal", "navy", "ayu"];

// Whether the docs show one of mdBook's dark themes, following changes.
function useDarkTheme() {
  const isDark = () => DARK_THEMES.some(theme => document.documentElement.classList.contains(theme));
  const [dark, setDark] = useState(isDark);
  useEffect(() => {
    const observer = new MutationObserver(() => setDark(isDark()));
    observer.observe(document.documentElement, { attributes: true, attributeFilter: ["class"] });
    return () => observer.disconnect();
  }, []);
  return dark;
}

// What clicking the module does, as a hint below the bar.
function hint(module) {
  if (!module || module.hidden) return "The module hides itself in this state";
  if (module.click?.type === "toggle") return "Click the module to toggle it";
  if (module.click?.type === "menu") return "Click the module to open its menu";
  if (module.click?.type === "popup") return "Click the module to open its popup";
  return module.tooltip ? "Hover over the module for its tooltip" : "";
}

// A plugin's interactive preview: its module in a strip of bar, in the
// state picked below it or reached by running a command from the last.
function Preview({ preview, icons }) {
  const dark = useDarkTheme();
  const [name, states] = Object.entries(preview.states)[0];
  const [current, setCurrent] = useState(states[0].name);

  const bar = useMemo(
    () => resolveBar(preview, { dark, states: { [name]: current }, icons }),
    [preview, dark, name, current, icons]);
  const module = Object.values(bar.placements).flat()[0];

  const run = (_, command) => {
    const next = nextState(preview, name, current, command);
    if (next !== undefined) setCurrent(next);
  };

  return (
    <figure className="kantan-preview-figure">
      <div className={`kantan-preview-frame ${dark ? "dark" : "light"}`}>
        <BarView bar={bar} dark={dark} run={run} style={{ borderRadius: "8px 8px 0 0" }} />
      </div>
      <figcaption>
        {states.length > 1 && (
          <div className="kantan-preview-states" role="group" aria-label="Preview state">
            {states.map(state => (
              <button key={state.name} type="button" aria-pressed={state.name === current} onClick={() => setCurrent(state.name)}>
                {state.name}
              </button>
            ))}
          </div>
        )}
        <span className="kantan-preview-hint">{hint(module)}</span>
      </figcaption>
    </figure>
  );
}

async function start(base) {
  const fetchJson = async path => (await fetch(`${base}${path}`)).json();
  const placeholders = [...document.querySelectorAll(".kantan-preview[data-preview]")];
  const [table, ...previews] = await Promise.all([
    fetchJson("icons.json"),
    ...placeholders.map(placeholder => fetchJson(`${placeholder.dataset.preview}.json`)),
  ]);
  const icons = iconTable(table);
  placeholders.forEach((placeholder, i) => {
    createRoot(placeholder).render(<Preview preview={previews[i]} icons={icons} />);
  });
}

start(document.currentScript.dataset.base);
