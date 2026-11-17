// An image of something the page draws, made by the browser: the HTML is
// set in an SVG image as a foreign object, with the fonts it uses held
// within, for the page to draw onto a canvas.

// The styles the builder's page starts every element with.
const RESET = "*, *::before, *::after { margin: 0; padding: 0; box-sizing: border-box; }";

const escapeText = text => text.replaceAll("&", "&amp;").replaceAll("<", "&lt;");

// `bytes` as base64.
export function base64(bytes) {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary);
}

// The `fonts` among which `html` names a family of: an image holds only
// the fonts it draws with.
export const fontsUsed = (html, fonts) => fonts.filter(font => html.includes(font.family));

// The CSS that declares `fonts`, each `{ family, format, data }` with its
// file as base64.
export function fontFaces(fonts) {
  return fonts.map(({ family, format, data }) =>
    `@font-face { font-family: "${family}"; src: url(data:font/${format};base64,${data}) format("${format}"); }`).join("\n");
}

// The SVG image, `width` by `height`, that draws `html`, serialised XHTML,
// with `css` as its styles.
export function imageSvg({ html, css, width, height }) {
  return `<svg xmlns="http://www.w3.org/2000/svg" width="${width}" height="${height}">`
    + `<foreignObject width="100%" height="100%"><div xmlns="http://www.w3.org/1999/xhtml">`
    + `<style>${escapeText(`${RESET}\n${css}`)}</style>${html}</div></foreignObject></svg>`;
}

// The address that holds `svg` itself.
export const svgUrl = svg => `data:image/svg+xml;charset=utf-8,${encodeURIComponent(svg)}`;
