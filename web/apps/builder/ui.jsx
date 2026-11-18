// What the builder's parts share: the things they all read, its icons and
// buttons, a dialog, and a field that holds text until it reads as a value.
import { createContext, useContext, useEffect, useRef, useState } from "react";
import { readYaml, writeYaml } from "../../builder/files.js";

// `{ icons, catalog, schema, palette, dark }`: the icon lookup, what can be
// added to a bar, the module config schema, the bar's theme colours for
// the appearance it's drawn in, and that appearance.
export const BuilderContext = createContext(null);
export const useBuilder = () => useContext(BuilderContext);

// What this browser keeps for the page, by key. A browser that keeps
// nothing gives nothing back.
export function remembered(key) {
  try {
    return window.localStorage.getItem(key);
  } catch {
    return null;
  }
}
export function remember(key, value) {
  try {
    window.localStorage.setItem(key, value);
  } catch {
    // Nothing to do: the page works without it.
  }
}

// A Tabler icon by name, at `size` points. A name the fonts lack, or any
// name before the fonts' table has loaded, draws nothing.
export function Ic({ name, size = 15, style }) {
  const entry = useBuilder().icons(name);
  return (
    <span className="kb-ic" aria-hidden="true" style={{ fontFamily: entry && `'${entry.font}'`, fontSize: size, width: size, height: size, ...style }}>
      {entry?.char}
    </span>
  );
}

// The links out of the builder that end each page's header, as the
// landing page has them: the docs and kantan's repository.
export function SiteLinks() {
  return (
    <>
      <a className="kb-nav" href="/docs/" title="Docs"><Ic name="book" size={18} /><span>Docs</span></a>
      <a className="kb-nav" href="https://github.com/cmacrae/kantan" target="_blank" rel="noopener noreferrer" title="GitHub">
        <Ic name="brand-github" size={18} /><span>GitHub</span>
      </a>
    </>
  );
}

export function Button({ icon, children, kind = "", on, ...rest }) {
  return (
    <button type="button" className={`kb-btn ${kind} ${on ? "on" : ""}`} {...rest}>
      {icon && <Ic name={icon} />}
      {children}
    </button>
  );
}

// A dialog over the page, closed by Escape or a click outside it.
export function Modal({ title, onClose, children, wide }) {
  useEffect(() => {
    const key = event => event.key === "Escape" && onClose();
    window.addEventListener("keydown", key);
    return () => window.removeEventListener("keydown", key);
  }, [onClose]);
  return (
    <div className="kb-shade" onMouseDown={event => event.target === event.currentTarget && onClose()}>
      <div className="kb-modal" role="dialog" aria-label={title} style={wide ? { width: "min(820px, 100%)" } : undefined}>
        <h2><span>{title}</span><Button kind="plain" icon="x" aria-label="Close" onClick={onClose} /></h2>
        <div>{children}</div>
      </div>
    </div>
  );
}

// Text someone is typing that stands for `value`: `field`, the props of
// the input or textarea holding it, and `problem` while the text doesn't
// read as a value. `write` turns a value to text and `read` text to
// `{ value }` or `{ problem }`. Text that reads is passed to `onChange`.
// A value changed from elsewhere replaces the text, once the field isn't
// being typed in.
export function useDraft(value, onChange, write, read) {
  const [text, setText] = useState(() => write(value));
  const [problem, setProblem] = useState();
  const focused = useRef(false);
  const shown = useRef(value);
  useEffect(() => {
    if (focused.current || shown.current === value) return;
    shown.current = value;
    setText(write(value));
    setProblem(undefined);
  });
  const field = {
    value: text,
    spellCheck: false,
    onFocus: () => { focused.current = true; },
    onBlur: () => {
      focused.current = false;
      if (problem === undefined) {
        shown.current = value;
        setText(write(value));
      }
    },
    onChange: event => {
      setText(event.target.value);
      const result = read(event.target.value);
      setProblem(result.problem);
      if (result.problem === undefined) onChange(result.value);
    },
  };
  return { field, problem };
}

const yamlText = value => (value === undefined ? "" : writeYaml(value));
const yamlValue = text => {
  if (text.trim() === "") return { value: undefined };
  const { value, problem } = readYaml(text);
  return problem === undefined ? { value: value ?? undefined } : { problem };
};

// A value edited as YAML.
export function YamlArea({ value, onChange, rows = 5, label }) {
  const { field, problem } = useDraft(value, onChange, yamlText, yamlValue);
  return (
    <div>
      <textarea aria-label={label} rows={rows} {...field} />
      {problem !== undefined && <div className="kb-problem">{problem}</div>}
    </div>
  );
}

const jsonText = value => (value === undefined ? "" : typeof value === "string" ? value : JSON.stringify(value, null, 2));

// A module's output edited as text: JSON when `json`, and text as it is
// otherwise.
export function OutputArea({ value, onChange, json, rows = 10 }) {
  const read = text => {
    if (!json) return { value: text };
    try {
      const parsed = JSON.parse(text);
      return parsed !== null && typeof parsed === "object" && !Array.isArray(parsed) ? { value: parsed } : { problem: "The output must be a JSON object" };
    } catch (error) {
      return { problem: error.message };
    }
  };
  const { field, problem } = useDraft(value, onChange, jsonText, read);
  return (
    <div>
      <textarea aria-label="Output" rows={rows} {...field} />
      {problem !== undefined && <div className="kb-problem">{problem}</div>}
    </div>
  );
}

// Copies `text` to the clipboard, and says so on the button for a moment.
export function CopyButton({ text, children = "Copy", kind }) {
  const [copied, setCopied] = useState(false);
  const copy = async () => {
    await navigator.clipboard.writeText(typeof text === "function" ? text() : text);
    setCopied(true);
    setTimeout(() => setCopied(false), 1500);
  };
  return <Button kind={kind} icon={copied ? "check" : "copy"} onClick={copy}>{copied ? "Copied" : children}</Button>;
}
