// The config as kantan reads it: the YAML files, in one file or with a
// file for each module, to copy or download, and the link that shares it.
import { useEffect, useMemo, useState } from "react";
import { paletteYaml } from "../../builder/files.js";
import { draftUrl, markdownLink } from "../../builder/share.js";
import { panelSlots } from "../../builder/shared.js";
import { zip } from "../../builder/zip.js";
import { highlightYaml } from "../../components/yaml-highlight.jsx";
import { ModuleCard, ThemeCard } from "./ShareCards.jsx";
import { ShareImage, barCard } from "./ShareImage.jsx";
import { Button, CopyButton, Ic, Modal } from "./ui.jsx";

// The colours YAML is written in.
export const YAML_COLORS = {
  comment: "var(--faint)", key: "var(--accent)", string: "var(--yaml-string)", bool: "var(--yaml-number)",
  number: "var(--yaml-number)", value: "var(--fg)", punct: "var(--faint)",
};

// How wide the image of a module starts.
const MODULE_WIDTH = 520;

// Saves `data` as a file called `name`.
function download(name, data, type) {
  const url = URL.createObjectURL(new Blob([data], { type }));
  const link = Object.assign(document.createElement("a"), { href: url, download: name });
  link.click();
  URL.revokeObjectURL(url);
}

// The files that make something, to read, copy or download, each folded
// away under its name until opened. `files` are each `{ path, text }`
// from kantan's config directory. `layouts` are the ways they can be laid
// out, each `[key, label]`, with `layout` the one they're in. `note` says
// where they go, and `archive` names the ZIP file that holds them when
// there are several.
export function Output({ title, files, layouts = [], layout, onLayout, note, archive }) {
  const single = files.length === 1;
  const [open, setOpen] = useState(() => new Set());
  const toggle = path => setOpen(now => {
    const next = new Set(now);
    if (!next.delete(path)) next.add(path);
    return next;
  });
  const save = () => (single
    ? download(files[0].path.split("/").pop(), files[0].text, "text/yaml")
    : download(archive, zip(files), "application/zip"));
  return (
    <>
      <h2>
        <span>{title}</span>
        <Button kind="plain" icon="download" onClick={save}>{single ? "Download" : "Download all"}</Button>
      </h2>
      <div className="kb-body" style={{ paddingBottom: 8 }}>
        {layouts.length > 1 && (
          <div className="kb-chips" role="group" aria-label="Layout" style={{ padding: 0 }}>
            {layouts.map(([key, label]) => (
              <button key={key} type="button" className="kb-chip" aria-pressed={layout === key} onClick={() => onLayout(key)}>{label}</button>
            ))}
          </div>
        )}
        <div className="kb-note">{note}</div>
      </div>
      {files.map(file => (
        <div key={file.path}>
          <div className="kb-file">
            <button type="button" aria-expanded={open.has(file.path)} onClick={() => toggle(file.path)}>
              <Ic name={open.has(file.path) ? "chevron-down" : "chevron-right"} size={14} />
              <span>{file.path}</span>
            </button>
            <CopyButton kind="plain" text={file.text} />
          </div>
          {open.has(file.path) && (
            <pre className="kb-code"><code>{file.text === "" ? <span style={{ color: "var(--faint)" }}># Nothing yet: kantan's defaults</span> : highlightYaml(file.text, YAML_COLORS)}</code></pre>
          )}
        </div>
      ))}
    </>
  );
}

// Past this many characters a link is long enough to say so.
const LONG_LINK = 8000;
// The most characters a GitHub post holds.
const GITHUB_LIMIT = 65536;

// The link `make` resolves to, once it has: undefined until then, and
// made again when `deps` change.
function useLink(make, deps) {
  const [link, setLink] = useState();
  useEffect(() => {
    let current = true;
    make?.().then(made => current && setLink(made));
    return () => { current = false; };
  }, deps);
  return link;
}

function LinkRow({ label, url }) {
  return (
    <div style={{ marginBottom: 12 }}>
      <div className="kb-h">{label}</div>
      <div className="kb-row">
        <input type="text" readOnly aria-label={label} value={url} onFocus={event => event.target.select()} />
        <CopyButton text={url}>Copy link</CopyButton>
      </div>
    </div>
  );
}

// What puts something in a GitHub post: one button copies its image and
// opens a new discussion that holds its link, for the image to be pasted
// into. The image and the link can be copied one at a time too, for a
// post anywhere else. `link` is the link, `kind` what it shares, and
// `title` what that is called, changed with `onTitle` when it is given:
// a post is titled with both. `image(onImage, actions)` draws the image
// to copy, telling `onImage` each one it makes, with what `actions(mode)`
// gives beside its own buttons: `config(mode)`, a button that copies the
// config of what is shared in the appearance picked, and the buttons
// here, when there is no title to set them beside.
function Post({ link, kind, title, onTitle, config, image }) {
  const [made, setMade] = useState();
  const [problem, setProblem] = useState();
  const titled = `${kind}: ${title}`;
  const markdown = markdownLink(titled, link);
  const draft = draftUrl(titled, link);
  // The copy starts before the draft opens, while this page still has the
  // keyboard, and both start from the one click.
  const post = async () => {
    setProblem(undefined);
    const copying = navigator.clipboard.write([new ClipboardItem({ "image/png": made })]);
    window.open(draft, "_blank", "noopener");
    try {
      await copying;
    } catch {
      setProblem("This browser wouldn't copy the image. Copy it above, then paste it into the draft.");
    }
  };
  const buttons = (
    <>
      <Button kind="primary" icon="brand-github" disabled={made === undefined || draft === undefined} onClick={post}>Post to Discussions</Button>
      <CopyButton text={markdown}>Markdown Link</CopyButton>
    </>
  );
  return (
    <>
      <div className="kb-h" style={{ marginTop: 16 }}>Preview</div>
      {image(setMade, mode => <>{config(mode)}{!onTitle && buttons}</>)}
      {onTitle && (
        <div className="kb-row" style={{ marginTop: 10 }}>
          <input type="text" aria-label="The post's title" value={title} onChange={event => onTitle(event.target.value)} />
          {buttons}
        </div>
      )}
      {problem !== undefined && <div className="kb-problem">{problem}</div>}
      <div className="kb-note">
        {draft === undefined
          ? "This link is too long for a draft to hold. Copy the image and paste it into a post, then copy the Markdown link and paste it under the image."
          : `Post to Discussions copies the image and opens a draft titled ${titled}, with the link under Preview. Paste the image there and post it. Markdown Link copies the link alone.`}
      </div>
    </>
  );
}

// The dialog that shares the bar, or its theme alone. `makeLink` resolves
// to the link holding the bar, and `source` is the link to the file it
// was opened from, while it is still as that file has it. `barFor(dark)`
// gives the bar in an appearance, and `config()` its config.yaml.
// `theme` is there when the bar has a theme: `names`, the themes it
// selects, `makeLink(name)`, which resolves to the link holding them
// under a name, `barFor(dark)`, the example bar in them, and `palettes`,
// their light and dark colours.
export function Share({ makeLink, source, barFor, config, theme, onClose }) {
  const [what, setWhat] = useState("bar");
  const [title, setTitle] = useState("My kantan bar");
  const [themeName, setThemeName] = useState("");
  const link = useLink(makeLink, [makeLink]);
  const themeLink = useLink(theme && (() => theme.makeLink(themeName.trim())), [theme?.makeLink, themeName]);
  const [drawBar] = useState(() => barCard(barFor));
  const [themeBars] = useState(() => theme && { false: theme.barFor(false), true: theme.barFor(true) });
  const themeTitle = themeName.trim() || theme?.names.join(" and ");

  return (
    <Modal title="Share this bar" onClose={onClose} wide>
      {theme && (
        <div className="kb-chips" role="group" aria-label="What to share">
          <button type="button" className="kb-chip" aria-pressed={what === "bar"} onClick={() => setWhat("bar")}>The bar</button>
          <button type="button" className="kb-chip" aria-pressed={what === "theme"} onClick={() => setWhat("theme")}>Just the theme</button>
        </div>
      )}
      {what === "bar" && (link === undefined ? <div className="kb-note">Making the link…</div> : (
        <>
          <LinkRow label="A link to this bar" url={link} />
          {link.length > LONG_LINK && (
            <div className="kb-problem" style={{ paddingBottom: 10 }}>
              {link.length > GITHUB_LIMIT
                ? "This link is longer than a GitHub post can hold. Trim the states you've added to shorten it."
                : "Long link. Use the titled form below."}
            </div>
          )}
          {source !== undefined && (
            <>
              <LinkRow label="A short link to the file this bar was opened from" url={source} />
              <div className="kb-note">It always shows the file as it is now, with each module in the states it starts with.</div>
            </>
          )}
          <Post link={link} kind="Bar" title={title || "My kantan bar"} onTitle={setTitle} config={() => <CopyButton text={config}>Bar config</CopyButton>} image={(onImage, actions) => <ShareImage draw={drawBar} onImage={onImage} actions={actions} />} />
        </>
      ))}
      {what === "theme" && (themeLink === undefined ? <div className="kb-note">Making the link…</div> : (
        <>
          <div className="kb-h">The theme's name</div>
          <div className="kb-row" style={{ marginBottom: 12 }}>
            <input type="text" aria-label="The theme's name" value={themeName} placeholder={theme.names.join(" and ")}
              onChange={event => setThemeName(event.target.value)} />
          </div>
          <LinkRow label="A link to the theme" url={themeLink} />
          <div className="kb-note">Opens on a page of its own, under that name, for another bar to take.</div>
          <Post link={themeLink} kind="Theme" title={themeTitle} config={mode => <CopyButton text={() => paletteYaml(theme.palettes, mode)}>Theme config</CopyButton>} image={(onImage, actions) => (
            <ShareImage file="kantan-theme" alt="The example bar in the theme, over its colours" onImage={onImage} actions={actions}
              draw={(appearance, width) => (
                <ThemeCard bar={themeBars[appearance]} palette={appearance ? theme.palettes.dark : theme.palettes.light} dark={appearance} width={width} />
              )} />
          )} />
        </>
      ))}
    </Modal>
  );
}

// The dialog that shares one module. `makeLink(themed)` resolves to the
// link holding it, with the bar's theme or without. `module` is its
// config, `plugin` the bundled plugin it runs, if any, and `printed` says
// whether its menu or popup is one its command prints. `yaml` is the
// module as written to a config. `theme` is `{ names, named }` when the
// bar has a theme: the themes it selects, and whether the module names
// their colours. `barFor(dark, themed)` gives a bar holding the module
// alone, in an appearance, in the bar's theme or the example's.
export function ShareModule({ makeLink, module, plugin, printed, yaml, theme, barFor, onClose }) {
  const [themed, setThemed] = useState(theme?.named === true);
  const [title, setTitle] = useState(module.name);
  const link = useLink(() => makeLink(themed), [makeLink, themed]);
  const bars = useMemo(() => ({ false: barFor(false, themed), true: barFor(true, themed) }), [themed]);
  const command = module.type === "command" ? module.config?.command : undefined;
  return (
    <Modal title={`Share ${module.name}`} onClose={onClose} wide>
      {link === undefined ? <div className="kb-note">Making the link…</div> : (
        <>
          <LinkRow label="A link to this module" url={link} />
          <div className="kb-note" style={{ marginTop: -8, paddingBottom: 10 }}>
            Holds the module's config, views and states. It opens on a page of its own.
          </div>
          {theme !== undefined && (
            <div style={{ marginBottom: 12 }}>
              <label className="kb-row">
                <input type="checkbox" checked={themed} onChange={event => setThemed(event.target.checked)} />
                <span>With the bar's theme, {theme.names.join(" and ")}</span>
              </label>
              <div className="kb-note">
                {theme.named
                  ? "The module names the theme's colours. Without the theme it is drawn in the example bar's, which may lack them."
                  : "The module is drawn in the theme where the link opens. Without it, in the example bar's."}
              </div>
            </div>
          )}
          {plugin !== undefined && <div className="kb-note">Bundled plugin: unedited states aren't in the link.</div>}
          {plugin === undefined && typeof command === "string" && (
            <div className="kb-note">The command <code>{command}</code> isn't in the link. Its states are.</div>
          )}
          {printed && (
            <div className="kb-problem" style={{ paddingTop: 6 }}>
              Its {module.interaction.click.type} is a view its command prints, which kantan shows only while that command prints it. To share the
              view itself, open it in the view editor and copy it into the config.
            </div>
          )}
          <Post link={link} kind="Module" title={title || module.name} onTitle={setTitle} config={() => <CopyButton text={yaml}>Module config</CopyButton>} image={(onImage, actions) => (
            <ShareImage key={String(themed)} width={MODULE_WIDTH} file={`kantan-${module.name}`} alt="The module on a bar" onImage={onImage} actions={actions}
              draw={(appearance, width) => {
                const bar = bars[appearance];
                const slot = panelSlots(Object.values(bar.placements).flat()[0])[0];
                return <ModuleCard bar={bar} dark={appearance} width={width} pinned={slot && { module: module.name, slot }} />;
              }} />
          )} />
        </>
      )}
    </Modal>
  );
}
