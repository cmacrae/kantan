// The config as kantan reads it: the YAML files, in one file or with a
// file for each module, to copy or download, and the link that shares it.
import { useEffect, useState } from "react";
import { markdownLink } from "../../builder/share.js";
import { zip } from "../../builder/zip.js";
import { highlightYaml } from "../../components/yaml-highlight.jsx";
import { ShareImage } from "./ShareImage.jsx";
import { Button, CopyButton, Ic, Modal } from "./ui.jsx";

// The colours YAML is written in.
export const YAML_COLORS = {
  comment: "var(--faint)", key: "var(--accent)", string: "var(--yaml-string)", bool: "var(--yaml-number)",
  number: "var(--yaml-number)", value: "var(--fg)", punct: "var(--faint)",
};

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

// The dialog that shares the bar. `makeLink` resolves to the link holding
// it, and `source` is the link to the file it was opened from, while it is
// still as that file has it. `makeThemeLink(name)` resolves to the link
// holding its theme alone, under a name, when it has a theme: `themeNames`
// are the themes it selects. `barFor` and `dark` are `ShareImage`'s.
export function Share({ makeLink, makeThemeLink, themeNames = [], source, barFor, dark, onClose }) {
  const [link, setLink] = useState();
  const [themeLink, setThemeLink] = useState();
  const [themeName, setThemeName] = useState("");
  useEffect(() => {
    let current = true;
    makeThemeLink?.(themeName.trim()).then(made => current && setThemeLink(made));
    return () => { current = false; };
  }, [makeThemeLink, themeName]);
  const [title, setTitle] = useState("My kantan bar");
  useEffect(() => {
    let current = true;
    makeLink().then(made => current && setLink(made));
    return () => { current = false; };
  }, [makeLink]);

  const row = (label, url) => (
    <div style={{ marginBottom: 12 }}>
      <div className="kb-h">{label}</div>
      <div className="kb-row">
        <input type="text" readOnly aria-label={label} value={url} onFocus={event => event.target.select()} />
        <CopyButton text={url}>Copy link</CopyButton>
      </div>
    </div>
  );
  return (
    <Modal title="Share this bar" onClose={onClose} wide>
      {link === undefined ? <div className="kb-note">Making the link…</div> : (
        <>
          {row("A link to this bar", link)}
          {link.length > LONG_LINK && (
            <div className="kb-problem" style={{ paddingBottom: 10 }}>
              {link.length > GITHUB_LIMIT
                ? "This link is longer than a GitHub post can hold. Trim the states you've added to shorten it."
                : "Long link. Use the titled form below."}
            </div>
          )}
          <div className="kb-h">For a GitHub post</div>
          <div className="kb-row">
            <input type="text" aria-label="The link's title" value={title} onChange={event => setTitle(event.target.value)} />
            <CopyButton kind="primary" text={() => markdownLink(title || "My kantan bar", link)}>Copy for GitHub</CopyButton>
          </div>
          <div className="kb-note">Copies a Markdown link with that title.</div>
          {source !== undefined && (
            <div style={{ marginTop: 14 }}>
              {row("A short link to the file this bar was opened from", source)}
              <div className="kb-note">It always shows the file as it is now, with each module in the states it starts with.</div>
            </div>
          )}
          {themeLink !== undefined && (
            <div style={{ marginTop: 14 }}>
              {row("Just the theme", themeLink)}
              <div className="kb-row">
                <input type="text" aria-label="The theme's name" value={themeName} placeholder={`Name it: ${themeNames.join(" and ")}`}
                  onChange={event => setThemeName(event.target.value)} />
              </div>
              <div className="kb-note">Opens on a page of its own, under that name, for another bar to take.</div>
            </div>
          )}
        </>
      )}
      <div className="kb-h" style={{ marginTop: 16 }}>An image of this bar</div>
      <ShareImage barFor={barFor} dark={dark} />
    </Modal>
  );
}

// The dialog that shares one module. `makeLink` resolves to the link
// holding it, `module` is its config, `plugin` the bundled plugin it runs,
// if any, and `printed` says whether its menu or popup is one its command
// prints. `yaml` is the module as written to a config. `theme` is
// `{ names, named }` when the bar has a theme: the themes it selects, and
// whether the module names their colours. `makeLink(themed)` makes the
// link with that theme or without.
export function ShareModule({ makeLink, module, plugin, printed, yaml, theme, onClose }) {
  const [themed, setThemed] = useState(theme?.named === true);
  const [link, setLink] = useState();
  const [title, setTitle] = useState(`My kantan ${module.name} module`);
  useEffect(() => {
    let current = true;
    makeLink(themed).then(made => current && setLink(made));
    return () => { current = false; };
  }, [makeLink, themed]);
  const command = module.type === "command" ? module.config?.command : undefined;
  return (
    <Modal title={`Share ${module.name}`} onClose={onClose} wide>
      {link === undefined ? <div className="kb-note">Making the link…</div> : (
        <>
          <div className="kb-note" style={{ paddingBottom: 10 }}>
            Holds the module's config, views and states. It opens on a page of its own.
          </div>
          <div className="kb-h">A link to this module · {link.length.toLocaleString()} characters</div>
          <div className="kb-row" style={{ marginBottom: 12 }}>
            <input type="text" readOnly aria-label="A link to this module" value={link} onFocus={event => event.target.select()} />
            <CopyButton text={link}>Copy link</CopyButton>
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
          <div className="kb-h">For a GitHub post</div>
          <div className="kb-row">
            <input type="text" aria-label="The link's title" value={title} onChange={event => setTitle(event.target.value)} />
            <CopyButton kind="primary" text={() => markdownLink(title || module.name, link)}>Copy for GitHub</CopyButton>
          </div>
          {plugin !== undefined && (
            <div className="kb-note" style={{ paddingTop: 10 }}>
              Bundled plugin: unedited states aren't in the link.
            </div>
          )}
          {plugin === undefined && typeof command === "string" && (
            <div className="kb-note" style={{ paddingTop: 10 }}>
              The command <code>{command}</code> isn't in the link. Its states are.
            </div>
          )}
          {printed && (
            <div className="kb-problem" style={{ paddingTop: 6 }}>
              Its {module.interaction.click.type} is a view its command prints, which kantan shows only while that command prints it. To share the
              view itself, open it in the view editor and copy it into the config.
            </div>
          )}
        </>
      )}
      <div className="kb-h" style={{ marginTop: 16 }}>Its YAML</div>
      <div className="kb-row"><CopyButton text={yaml}>Copy the module's YAML</CopyButton></div>
    </Modal>
  );
}
