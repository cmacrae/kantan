// Keeps a document's bar as someone uses it: which state each module
// shows, which drawers are open, which workspace is active and what the
// time is.
import { useCallback, useEffect, useMemo, useState } from "react";
import { nextState, resolveBar } from "../engine/index.js";
import { dict, list, own } from "../engine/values.js";

// The bar `document` draws, with what `BarView` needs to answer clicks.
// `options` are `resolveBar`'s. `states` and `samples` among them say how
// the bar starts, and a sample given there stays as given. A clock
// without one keeps the time.
//
// Returns the `bar`; `run`, `toggleDrawer` and `switchWorkspace` for
// `BarView`; `states` with `setState(module, name)`, the state each
// module shows; and `samples`, the readings that using the bar has
// changed: the drawers opened and the workspaces switched to.
export function useBar(document, { dark, icons, themes, notch, states: initialStates, samples: fixedSamples } = {}) {
  const [states, setStates] = useState(initialStates ?? {});
  const [samples, setSamples] = useState({});
  const [now, setNow] = useState(() => Date.now());

  const bar = useMemo(
    () => resolveBar(document, { dark, icons, themes, notch, states, samples: { ...samples, ...fixedSamples } }),
    // `now` is here for the clocks, which read the time themselves.
    [document, dark, icons, themes, notch, states, samples, fixedSamples, now]);
  const modules = useMemo(() => Object.values(bar.placements).flat(), [bar]);

  const ticking = modules.some(module => module.type === "clock" && fixedSamples?.[module.name] === undefined);
  useEffect(() => {
    if (!ticking) return undefined;
    const timer = setInterval(() => setNow(Date.now()), 1000);
    return () => clearInterval(timer);
  }, [ticking]);

  const setState = useCallback((module, name) => setStates(current => ({ ...current, [module]: name })), []);

  // A command moves its module to the state the document says it leads to.
  const run = useCallback((module, command) => {
    setStates(current => {
      const next = nextState(document, module, current[module], command);
      return next === undefined ? current : { ...current, [module]: next };
    });
  }, [document]);

  const toggleDrawer = useCallback(name => {
    const open = modules.find(module => module.name === name)?.open === true;
    setSamples(current => ({ ...current, [name]: { open: !open } }));
  }, [modules]);

  // Switching makes the target the active workspace, or the selected
  // window of the active workspace's scroll.
  const switchWorkspace = useCallback((name, target) => {
    setSamples(current => {
      const listed = (list(own(document.states, name)) ?? []).filter(dict);
      const picked = listed.find(state => state.name === own(states, name)) ?? listed[0];
      const sample = dict(own(current, name)) ?? dict(picked?.output) ?? {};
      // The workspaces as the engine reads them: the mappings among them.
      const workspaces = (list(sample.workspaces) ?? []).filter(dict).map((space, position) => (
        target.workspace !== undefined
          ? { ...space, active: (space.index ?? position) === target.workspace }
          : { ...space, scroll: list(space.scroll)?.filter(dict).map(window => ({ ...window, selected: window.id === target.window })) }
      ));
      return { ...current, [name]: { ...sample, workspaces } };
    });
  }, [document, states]);

  return { bar, run, toggleDrawer, switchWorkspace, states, setState, samples };
}
