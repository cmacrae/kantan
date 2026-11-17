// The config as kantan reads it: the YAML files, in one file or with a
// file for each module, to copy or download, and the link that shares it.
import { useEffect, useState } from "react";
import { markdownLink } from "../../builder/share.js";
import { zip } from "../../builder/zip.js";
import { highlightYaml } from "../../components/yaml-highlight.jsx";
import { Button, CopyButton, Modal } from "./ui.jsx";

const YAML_COLORS = {
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

// `files` are the config's files, each `{ path, text }`, and `layout`
// which of the two layouts they're in.
export function Output({ files, layout, onLayout }) {
  const single = layout === "single";
  const save = () => (single
    ? download("config.yaml", files[0].text, "text/yaml")
    : download("kantan-config.zip", zip(files), "application/zip"));
  return (
    <>
      <h2>
        <span>Config</span>
        {single && <CopyButton kind="plain" text={files[0].text} />}
        <Button kind="plain" icon="download" onClick={save}>{single ? "Download" : "Download all"}</Button>
      </h2>
      <div className="kb-body" style={{ paddingBottom: 8 }}>
        <div className="kb-chips" role="group" aria-label="Layout" style={{ padding: 0 }}>
          <button type="button" className="kb-chip" aria-pressed={single} onClick={() => onLayout("single")}>One config.yaml</button>
          <button type="button" className="kb-chip" aria-pressed={!single} onClick={() => onLayout("dir")}>A file per module in modules.d</button>
        </div>
        <div className="kb-note">{single ? "Save it as" : "Unpack them into"} <code>~/.config/kantan/</code> and kantan reloads.</div>
      </div>
      {files.map(file => (
        <div key={file.path}>
          {!single && <div className="kb-file"><span>{file.path}</span><CopyButton kind="plain" text={file.text} /></div>}
          <pre className="kb-code"><code>{file.text === "" ? <span style={{ color: "var(--faint)" }}># Nothing yet: kantan's defaults</span> : highlightYaml(file.text, YAML_COLORS)}</code></pre>
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
// still as that file has it.
export function Share({ makeLink, source, onClose }) {
  const [link, setLink] = useState();
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
    <Modal title="Share this bar" onClose={onClose}>
      {link === undefined ? <div className="kb-note">Making the link…</div> : (
        <>
          <div className="kb-note" style={{ paddingBottom: 10 }}>
            The link holds the whole bar: its config, the states its modules show and how you're looking at it. Nothing is stored on this site.
          </div>
          {row(`A link to this bar · ${link.length.toLocaleString()} characters`, link)}
          {link.length > LONG_LINK && (
            <div className="kb-problem" style={{ paddingBottom: 10 }}>
              {link.length > GITHUB_LIMIT
                ? "This link is longer than a GitHub post can hold. Trim the states you've added to shorten it."
                : "This link is long. It works, but it reads better inside a titled link, as below."}
            </div>
          )}
          <div className="kb-h">For a GitHub post</div>
          <div className="kb-row">
            <input type="text" aria-label="The link's title" value={title} onChange={event => setTitle(event.target.value)} />
            <CopyButton kind="primary" text={() => markdownLink(title || "My kantan bar", link)}>Copy for GitHub</CopyButton>
          </div>
          <div className="kb-note">Copies the link as Markdown under that title, so the post shows the title and not the link.</div>
          {source !== undefined && (
            <div style={{ marginTop: 14 }}>
              {row("A short link to the file this bar was opened from", source)}
              <div className="kb-note">It always shows the file as it is now, with each module in the states it starts with.</div>
            </div>
          )}
        </>
      )}
    </Modal>
  );
}
