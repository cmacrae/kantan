// The page a link to a theme opens: the example bar drawn in the theme,
// the colours it names in each appearance, and its files to copy or
// download.
import { useMemo, useRef, useState } from "react";
import { BarView } from "../../components/BarView.jsx";
import { wallpaper } from "../../components/Desk.jsx";
import { useBar } from "../../components/useBar.js";
import { useFitZoom } from "../../components/useFitZoom.js";
import { schemeFileName } from "../../builder/base16.js";
import { sameValue } from "../../builder/equal.js";
import { themeFiles, writeYaml } from "../../builder/files.js";
import { openDrawers, themeDocument, themeVariants } from "../../builder/shared.js";
import { selectedThemes } from "../../builder/theme.js";
import { Output } from "./Output.jsx";
import { Button, CopyButton, SiteLinks, useBuilder } from "./ui.jsx";

// A palette's colours, each with its name: the bar's own, then the rest.
// A click on one copies it, and it says so for a moment. `uses` are the
// appearances the theme uses the palette for, each a pill by its label.
function Palette({ label, palette, uses = [] }) {
  const colors = [["fg", palette.fg], ["bg", palette.bg], ...(palette.shape === undefined ? [] : [["shape", palette.shape]]), ...Object.entries(palette.colors)];
  const [copied, setCopied] = useState();
  const copy = async (name, color) => {
    await navigator.clipboard.writeText(color);
    setCopied(name);
    setTimeout(() => setCopied(now => (now === name ? undefined : now)), 1500);
  };
  return (
    <div>
      <div className="kb-h">
        {label}
        {uses.map(mode => <span key={mode} className="kb-pill">{mode === "dark" ? "Dark" : "Light"}</span>)}
      </div>
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
  const names = selectedThemes(shared.selection);
  // What the theme can be drawn as: its flavours, or its light and its
  // dark. It starts as the one it uses in the system's appearance.
  const variants = useMemo(() => themeVariants(shared, catalog.themes), [shared]);
  const flavoured = variants.some(each => each.key !== "light" && each.key !== "dark");
  const [picked, setPicked] = useState(() => variants.find(each => each.uses.includes(systemDark ? "dark" : "light"))?.key);
  const variant = variants.find(each => each.key === picked) ?? variants[0];
  const dark = variant?.dark ?? systemDark;

  // The example bar in the theme, in the states the landing page shows.
  const document = useMemo(() => themeDocument(variant ? { ...shared, selection: variant.selection } : shared, catalog), [shared, variant?.selection]);
  // Every drawer is open, so the theme shows on every module.
  const samples = useMemo(() => openDrawers(document), [document]);
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
          <SiteLinks />
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
            {flavoured
              ? (
                <div className="kb-chips" role="group" aria-label="The flavour shown" style={{ padding: 0 }}>
                  {variants.map(each => (
                    <button key={each.key} type="button" className="kb-chip" aria-pressed={each === variant} onClick={() => setPicked(each.key)}>{each.label}</button>
                  ))}
                </div>
              )
              : variants.length > 0 && (
                <Button kind="plain" icon={dark ? "moon" : "sun"} onClick={() => setPicked(dark ? "light" : "dark")}>{dark ? "Dark" : "Light"}</Button>
              )}
          </div>
        </div>
      </div>

      <main className="kb-shared">

        {variants.length === 0
          ? <div className="kb-problem">kantan can't load this theme.</div>
          : !flavoured && sameValue(variants[0].palette, variants[1].palette)
          ? <Palette label="Its colours" palette={variants[0].palette} />
          : variants.map(each => (
            <Palette key={each.key} palette={each.palette} label={each.label} uses={flavoured ? each.uses : []} />
          ))}

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
