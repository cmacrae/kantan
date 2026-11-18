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
import { Button, useBuilder } from "./ui.jsx";

// A palette's colours, each with its name: the bar's own, then the rest.
function Palette({ label, palette }) {
  const colors = [["fg", palette.fg], ["bg", palette.bg], ...(palette.shape === undefined ? [] : [["shape", palette.shape]]), ...Object.entries(palette.colors)];
  return (
    <div>
      <div className="kb-h">{label}</div>
      <ul className="kb-swatches">
        {colors.map(([name, color]) => (
          <li key={name}>
            <i style={{ background: color }} />
            <span><b>{name}</b><span>{color}</span></span>
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

      <main className="kb-shared">
        <div>
          <h1>{shared.name ?? names.join(" and ")}</h1>
          <div className="kb-note">A shared theme, on the example bar</div>
        </div>

        <div className="kb-shared-fit">
          <div className="kb-shared-desk" ref={frame} style={{ background: wallpaper(dark), zoom, minWidth: "max-content" }}>
            <BarView bar={bar} dark={dark} run={run} toggleDrawer={toggleDrawer} switchWorkspace={switchWorkspace} style={{ borderRadius: "10px 10px 0 0" }} />
          </div>
        </div>
        <div className="kb-shared-under">
          <Button kind="plain" icon={dark ? "moon" : "sun"} onClick={() => setDark(!dark)}>{dark ? "Dark" : "Light"}</Button>
        </div>

        {palettes === undefined
          ? <div className="kb-problem">kantan can't load this theme.</div>
          : sameValue(palettes.light, palettes.dark)
          ? <Palette label="Its colours" palette={palettes.light} />
          : <><Palette label="In light" palette={palettes.light} /><Palette label="In dark" palette={palettes.dark} /></>}

        {files.length > 0 && (
          <section className="kb-pane">
            <Output title={files.length === 1 ? "Its file" : "Its files"} files={files} archive={archive}
              note={<>Save {files.length === 1 ? "it" : "them"} under <code>~/.config/kantan/</code>, by the {files.length === 1 ? "path" : "paths"} below.</>} />
          </section>
        )}
        <div className="kb-note">
          {files.length === 0 && "kantan bundles this theme. "}
          To use it, set this in <code>config.yaml</code>:
          <pre className="kb-code" style={{ borderRadius: 8, marginTop: 6 }}><code>{selects}</code></pre>
          To use it on a bar in the builder, open that bar and paste this page's link into Import a theme.
        </div>
      </main>
    </>
  );
}
