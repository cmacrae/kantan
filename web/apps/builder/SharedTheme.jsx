// The page a link to a theme opens: the example bar drawn in the theme,
// the colours it names in each appearance, and its files to copy or
// download.
import { useMemo, useRef, useState } from "react";
import { BarView } from "../../components/BarView.jsx";
import { wallpaper } from "../../components/Desk.jsx";
import { useBar } from "../../components/useBar.js";
import { useFitZoom } from "../../components/useFitZoom.js";
import { loadTheme } from "../../engine/index.js";
import { schemeFileName, withSharedTheme } from "../../builder/base16.js";
import { boundDocument, modulesOf } from "../../builder/edit.js";
import { sameValue } from "../../builder/equal.js";
import { themeFiles, writeYaml } from "../../builder/files.js";
import { selectedThemes } from "../../builder/theme.js";
import { Output } from "./Output.jsx";
import { Button, CopyButton, useBuilder } from "./ui.jsx";

// A palette's colours, each with its name: the bar's own, then the rest.
// A click on one copies it, and it says so for a moment.
function Palette({ label, palette }) {
  const colors = [["fg", palette.fg], ["bg", palette.bg], ...(palette.shape === undefined ? [] : [["shape", palette.shape]]), ...Object.entries(palette.colors)];
  const [copied, setCopied] = useState();
  const copy = async (name, color) => {
    await navigator.clipboard.writeText(color);
    setCopied(name);
    setTimeout(() => setCopied(now => (now === name ? undefined : now)), 1500);
  };
  return (
    <div>
      <div className="kb-h">{label}</div>
      <ul className="kb-swatches">
        {colors.map(([name, color]) => (
          <li key={name}>
            <button type="button" aria-label={`Copy ${name}, ${color}`} onClick={() => copy(name, color)}>
              <i style={{ background: color }} />
              <span><b>{name}</b><span>{copied === name ? "Copied" : color}</span></span>
            </button>
          </li>
        ))}
      </ul>
    </div>
  );
}

// `shared` is the theme a link holds, `{ selection, themes, name }`, and
// `systemDark` whether the system's appearance is dark. `onBuild` opens
// the example bar in the builder, drawn in the theme.
export function SharedTheme({ shared, systemDark, onBuild }) {
  const { catalog, icons } = useBuilder();
  const [dark, setDark] = useState(systemDark);
  const names = selectedThemes(shared.selection);
  const palettes = useMemo(() => loadTheme(shared.selection, { ...catalog.themes, ...shared.themes }), [shared]);

  // The example bar in the theme, in the states the landing page shows.
  const document = useMemo(() => boundDocument(withSharedTheme(catalog.example, shared, catalog.themes), catalog), [shared]);
  // Every drawer is open, so the theme shows on every module.
  const samples = useMemo(() => Object.fromEntries(modulesOf(document).filter(each => each?.type === "drawer").map(each => [each.name, { open: true }])), [document]);
  const { bar, run, toggleDrawer, switchWorkspace } = useBar(document, { dark, icons, themes: catalog.themes, samples });
  const frame = useRef(null);
  const zoom = useFitZoom(frame, 0.6);

  const files = useMemo(() => Object.entries(shared.themes).flatMap(([name, theme]) => themeFiles(name, theme)), [shared]);
  // The archive its files download as: under the name it was given, when
  // that makes a file name.
  const given = schemeFileName(shared.name ?? "");
  const archive = given === "" ? "kantan-theme.zip" : `${given}-kantan-theme.zip`;
  const selects = useMemo(() => writeYaml({ theme: shared.selection }).trim(), [shared]);

  return (
    <>
      <header className="kb-top">
        <a className="kb-brand" href="/"><b>kantan</b><span>builder</span></a>
        <div className="kb-actions">
          <Button kind="primary" icon="pencil" onClick={onBuild}>Open in the builder</Button>
          <a className="kb-btn plain" href="/docs/">Docs</a>
        </div>
      </header>

      <div className="kb-stage">
        <div className="kb-stage-inner">
          <h1 className="kb-shared-name">{shared.name ?? names.join(" and ")}</h1>
          <div ref={frame} className="kb-desk" style={{ zoom }}>
            <div className="kb-desk-paper" style={{ background: wallpaper(dark) }} />
            <BarView bar={bar} dark={dark} run={run} toggleDrawer={toggleDrawer} switchWorkspace={switchWorkspace} style={{ borderRadius: "10px 10px 0 0" }} />
            <div className="kb-desk-room" style={{ marginTop: -Math.min(bar.gaps.top, 40) }} />
          </div>
          <div className="kb-stage-controls" style={{ justifyContent: "flex-end" }}>
            <Button kind="plain" icon={dark ? "moon" : "sun"} onClick={() => setDark(!dark)}>{dark ? "Dark" : "Light"}</Button>
          </div>
        </div>
      </div>

      <main className="kb-shared">

        {palettes === undefined
          ? <div className="kb-problem">kantan can't load this theme.</div>
          : sameValue(palettes.light, palettes.dark)
          ? <Palette label="Its colours" palette={palettes.light} />
          : <><Palette label="Light" palette={palettes.light} /><Palette label="Dark" palette={palettes.dark} /></>}

        {files.length > 0 && (
          <section className="kb-pane kb-files">
            <Output title={files.length === 1 ? "File" : "Files"} files={files} archive={archive}
              note={<>Save {files.length === 1 ? "it" : "them"} under <code>~/.config/kantan/</code>, by the {files.length === 1 ? "path" : "paths"} below.</>} />
          </section>
        )}
        <div className="kb-note">
          {files.length === 0 && "kantan bundles this theme. "}
          To use it, set this in <code>config.yaml</code>:
          <div className="kb-snippet">
            <pre className="kb-code"><code>{selects}</code></pre>
            <CopyButton kind="plain" text={selects} />
          </div>
          To use it on a bar in the builder, open that bar and paste this page's link into Import a theme.
        </div>
      </main>
    </>
  );
}
