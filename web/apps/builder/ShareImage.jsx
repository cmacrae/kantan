// An image of the bar on the mock desktop, in either appearance or both,
// to copy or download: the desktop is drawn off the page as the builder
// draws it, and the browser makes the image from that.
import { useEffect, useRef, useState } from "react";
import { base64, fontFaces, fontsUsed, imageSvg, svgUrl } from "../../builder/image.js";
import { Desk, DeskWordmark } from "../../components/Desk.jsx";
import { Button } from "./ui.jsx";

// The desktop's width and the height below its bar, and the room around
// it for its shadow, as the README's images have them.
const DESK = { width: 880, height: 260, margin: "44px 40px" };
// The image's pixels to the point.
const SCALE = 2;

const MODES = [["light", "Light"], ["dark", "Dark"], ["both", "Both"]];

// The fonts the page declares, each `{ family, format, url }`.
function pageFonts() {
  const fonts = [];
  for (const sheet of window.document.styleSheets) {
    let rules;
    try {
      rules = sheet.cssRules;
    } catch {
      // A stylesheet from elsewhere keeps its rules to itself.
      continue;
    }
    for (const rule of rules) {
      if (!(rule instanceof CSSFontFaceRule)) continue;
      const family = rule.style.getPropertyValue("font-family").replace(/^["']|["']$/g, "");
      const source = /url\(["']?([^"')]+)["']?\)/.exec(rule.style.getPropertyValue("src"))?.[1];
      if (source === undefined) continue;
      const url = new URL(source, sheet.href ?? window.location.href).href;
      fonts.push({ family, format: /\.([a-z0-9]+)(?:[?#]|$)/i.exec(url)?.[1] ?? "woff2", url });
    }
  }
  return fonts;
}

// Each font's file as base64, once fetched.
const fetched = new Map();
function fontData(url) {
  if (!fetched.has(url)) {
    fetched.set(url, fetch(url).then(async response => {
      if (!response.ok) throw new Error(`A font couldn't be fetched: ${url} answered ${response.status}`);
      return base64(new Uint8Array(await response.arrayBuffer()));
    }));
  }
  return fetched.get(url);
}

// A PNG of `element` as the page draws it, `scale` pixels to the point.
async function picture(element, scale) {
  const rect = element.getBoundingClientRect();
  const width = Math.ceil(rect.width), height = Math.ceil(rect.height);
  const html = new XMLSerializer().serializeToString(element);
  const fonts = await Promise.all(fontsUsed(html, pageFonts()).map(async font => ({ ...font, data: await fontData(font.url) })));
  const image = new Image();
  const loaded = new Promise((resolve, reject) => {
    image.onload = resolve;
    image.onerror = () => reject(new Error("This browser couldn't draw the image"));
  });
  image.src = svgUrl(imageSvg({ html, css: fontFaces(fonts), width, height }));
  await loaded;
  await image.decode?.();
  const canvas = Object.assign(window.document.createElement("canvas"), { width: width * scale, height: height * scale });
  canvas.getContext("2d").drawImage(image, 0, 0, canvas.width, canvas.height);
  const blob = await new Promise(resolve => canvas.toBlob(resolve, "image/png"));
  if (!blob) throw new Error("This browser couldn't make the image");
  return blob;
}

// How much wider a desktop must be for each half of a screen with a notch
// to hold its modules: nothing when they fit.
function shortfall(card) {
  const wide = each => each.getBoundingClientRect().width;
  const over = [...card.querySelectorAll("[data-kantan-half]")]
    .map(half => [...half.children].reduce((sum, child) => sum + wide(child), 0) - wide(half));
  return Math.max(0, Math.ceil(2 * Math.max(0, ...over)));
}

function save(name, blob) {
  const url = URL.createObjectURL(blob);
  Object.assign(window.document.createElement("a"), { href: url, download: name }).click();
  URL.revokeObjectURL(url);
}

// `barFor(dark)` gives the bar as it is looked at now, in an appearance,
// and `dark` is the appearance the builder shows it in.
export function ShareImage({ barFor, dark }) {
  const [mode, setMode] = useState(dark ? "dark" : "light");
  const [bars] = useState(() => ({ light: barFor(false), dark: barFor(true) }));
  const [width, setWidth] = useState(DESK.width);
  const [image, setImage] = useState();
  const [problem, setProblem] = useState();
  const [copied, setCopied] = useState(false);
  const card = useRef(null);

  useEffect(() => {
    let current = true;
    setImage(undefined);
    setProblem(undefined);
    const draw = async () => {
      await window.document.fonts.ready;
      if (!current) return;
      const more = shortfall(card.current);
      if (more > 0) return setWidth(width + more);
      const blob = await picture(card.current, SCALE);
      if (current) setImage({ blob, url: URL.createObjectURL(blob) });
    };
    draw().catch(error => current && setProblem(error.message));
    return () => { current = false; };
  }, [mode, width]);
  useEffect(() => () => image && URL.revokeObjectURL(image.url), [image]);

  const copy = async () => {
    try {
      await navigator.clipboard.write([new ClipboardItem({ "image/png": image.blob })]);
      setCopied(true);
      setTimeout(() => setCopied(false), 1500);
    } catch {
      setProblem("This browser wouldn't copy the image. Download it instead.");
    }
  };

  const shown = mode === "both" ? ["light", "dark"] : [mode];
  return (
    <div>
      <div className="kb-chips" role="group" aria-label="The image's appearance">
        {MODES.map(([key, label]) => (
          <button key={key} type="button" className="kb-chip" aria-pressed={mode === key} onClick={() => setMode(key)}>{label}</button>
        ))}
      </div>
      <div className="kb-shot">
        {image ? <img src={image.url} alt="The bar on a desktop" /> : <span className="kb-note">{problem ?? "Drawing the image…"}</span>}
      </div>
      {image && problem !== undefined && <div className="kb-problem">{problem}</div>}
      <div className="kb-row" style={{ marginTop: 8 }}>
        <Button kind="primary" icon={copied ? "check" : "copy"} disabled={!image} onClick={copy}>{copied ? "Copied" : "Copy image"}</Button>
        <Button icon="download" disabled={!image} onClick={() => save(mode === "both" ? "kantan-bar.png" : `kantan-bar-${mode}.png`, image.blob)}>Download</Button>
      </div>
      <div className="kb-note">
        A PNG with nothing behind the desktop{mode === "both" ? ", light above dark" : ""}. Paste it into a GitHub post beside the link.
      </div>
      {/* The desktop the image is made from, drawn off the page with none
          of the page's styles. */}
      <div aria-hidden="true" style={{ position: "fixed", left: -100000, top: 0, pointerEvents: "none" }}>
        <div ref={card} data-kantan-card style={{ all: "initial", display: "block", width: "max-content" }}>
          {shown.map(each => (
            <div key={each} style={{ padding: DESK.margin }}>
              <Desk bar={bars[each]} dark={each === "dark"} height={DESK.height} interactive={false} style={{ width, minWidth: "max-content" }}>
                <DeskWordmark dark={each === "dark"} />
              </Desk>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}
