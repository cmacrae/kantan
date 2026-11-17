// The config as kantan reads it: the YAML files, in one file or with a
// file for each module, to copy or download, and the link that shares it.
import { useEffect, useState } from "react";
import { markdownLink } from "../../builder/share.js";
import { zip } from "../../builder/zip.js";
import { highlightYaml } from "../../components/yaml-highlight.jsx";
import { ShareImage } from "./ShareImage.jsx";
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

// The files that make something, to read, copy or download. `files` are
// each `{ path, text }` from kantan's config directory. `layouts` are the
// ways they can be laid out, each `[key, label]`, with `layout` the one
// they're in. `note` says where they go, and `archive` names the ZIP file
// that holds them when there are several.
export function Output({ title, files, layouts = [], layout, onLayout, note, archive }) {
  const single = files.length === 1;
  const save = () => (single
    ? download(files[0].path.split("/").pop(), files[0].text, "text/yaml")
    : download(archive, zip(files), "application/zip"));
  return (
    <>
      <h2>
        <span>{title}</span>
        {single && <CopyButton kind="plain" text={files[0].text} />}
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
// still as that file has it. `barFor` and `dark` are `ShareImage`'s.
export function Share({ makeLink, source, barFor, dark, onClose }) {
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
    <Modal title="Share this bar" onClose={onClose} wide>
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
      <div className="kb-h" style={{ marginTop: 16 }}>An image of this bar</div>
      <ShareImage barFor={barFor} dark={dark} />
    </Modal>
  );
}
