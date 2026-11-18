// Share links: a whole document in a URL's fragment, so a link shows a bar
// without the site storing anything. The fragment is the codec's version, a
// dot, then base64url of the deflated JSON of a packed document.
//
// Packing keeps a link short in three ways. What the site already has is
// left out: a module's states when they are the ones it starts with, or
// the ones it has in the example bar. What
// says nothing is left out: empty parts, and a view that is the default.
// And the words nearly every config uses are swapped for short tokens.
//
// Deflating keeps it shorter still: the JSON is deflated against a
// dictionary of packed bars the site offers, so what a document shares
// with them costs it next to nothing.
//
// A fragment may instead name a config file to fetch: `from=<url>`,
// `gh=<user>/<repo>/<path>` or `gist=<id>`.
//
// A link can also share one module on its own, to add to any bar: its
// config and the states it shows, packed the same way, after `m` and the
// module codec's version. And one a bar's theme: what its config selects
// and the theme files of its own that names, after `t` and the theme
// codec's version. A module's link carries the theme it is drawn in as a
// theme's link after it, the two joined by `~`.
import { deflateSync, inflateSync } from "fflate";
import { DICTIONARY } from "./dictionary.js";
import { sameValue } from "./equal.js";
import { DOCUMENT_VERSION } from "../engine/document.js";
import { dict, str } from "../engine/values.js";
import { defaultStates } from "./catalog.js";
import { modulesOf } from "./edit.js";
import { selectedThemes } from "./theme.js";
import { WORDS } from "./words.js";

export const CODEC_VERSION = "1";
export const MODULE_CODEC_VERSION = "m1";
export const THEME_CODEC_VERSION = "t1";

const DICTIONARY_BYTES = new TextEncoder().encode(DICTIONARY);

// Tokens count in base 62 from the start of the word list.
const DIGITS = "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ";
function digits(n) {
  let text = "";
  do {
    text = DIGITS[n % 62] + text;
    n = Math.floor(n / 62);
  } while (n > 0);
  return text;
}
const TOKEN_OF = new Map(WORDS.map((word, i) => [word, `^${digits(i)}`]));
const WORD_OF = new Map(WORDS.map((word, i) => [`^${digits(i)}`, word]));

// A string as it's packed: its token when the list has it, and a string
// that starts as a token does marked with a second caret.
const packString = text => TOKEN_OF.get(text) ?? (text.startsWith("^") ? `^${text}` : text);
function unpackString(text) {
  if (!text.startsWith("^")) return text;
  if (text.startsWith("^^")) return text.slice(1);
  if (!WORD_OF.has(text)) throw new Error("The link uses a word this site doesn't know");
  return WORD_OF.get(text);
}

// `value` with `each` applied to every string in it, keys included.
function mapStrings(value, each) {
  if (typeof value === "string") return each(value);
  if (Array.isArray(value)) return value.map(item => mapStrings(item, each));
  if (value === null || typeof value !== "object") return value;
  return Object.fromEntries(Object.entries(value).map(([key, item]) => [each(key), mapStrings(item, each)]));
}

const present = value => dict(value) !== undefined && Object.keys(value).length > 0;

// The packed form of `document`: `c` its config, `m` its modules.d, `t`
// its themes, `s` the states that are its own, `b` the modules whose
// states are the ones they start with, `e` those whose states are the
// example bar's for a module of that name, and `v` its view.
export function packDocument(document, catalog) {
  const modules = Object.fromEntries(modulesOf(document).filter(dict).map(module => [module.name, module]));
  const states = {}, bundled = [], example = [];
  for (const [name, own] of Object.entries(document.states ?? {})) {
    const starting = modules[name] && defaultStates(modules[name], catalog);
    if (starting !== undefined && sameValue(own, starting)) bundled.push(name);
    else if (sameValue(own, catalog.example?.states?.[name])) example.push(name);
    else states[name] = own;
  }

  const view = { ...document.view };
  if (view.dark === false) delete view.dark;
  if (view.notch === false) delete view.notch;
  if (!present(view.shown)) delete view.shown;

  const packed = { c: document.config };
  if (present(document.modulesDir)) packed.m = document.modulesDir;
  if (present(document.themes)) packed.t = document.themes;
  if (present(states)) packed.s = states;
  if (bundled.length) packed.b = bundled;
  if (example.length) packed.e = example;
  if (present(view)) packed.v = view;
  return mapStrings(packed, packString);
}

// The document a packed form holds. A module whose starting states the
// site no longer has shows none.
export function unpackDocument(packed, catalog) {
  if (!dict(packed)) throw new Error("The link doesn't hold a bar");
  const { c, m, t, s, b, e, v } = mapStrings(packed, unpackString);
  const document = { version: DOCUMENT_VERSION, config: dict(c) ?? {} };
  if (present(m)) document.modulesDir = m;
  if (present(t)) document.themes = t;
  const states = { ...dict(s) };
  const modules = Object.fromEntries(modulesOf(document).filter(dict).map(module => [module.name, module]));
  for (const name of Array.isArray(b) ? b : []) {
    const starting = modules[name] && defaultStates(modules[name], catalog);
    if (starting !== undefined) states[name] = starting;
  }
  for (const name of Array.isArray(e) ? e : []) {
    const shown = catalog.example?.states?.[name];
    if (shown !== undefined) states[name] = shown;
  }
  if (present(states)) document.states = states;
  if (present(v)) document.view = v;
  return document;
}

function toBase64Url(bytes) {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replaceAll("+", "-").replaceAll("/", "_").replace(/=+$/, "");
}

function fromBase64Url(text) {
  const binary = atob(text.replaceAll("-", "+").replaceAll("_", "/"));
  return Uint8Array.from(binary, char => char.charCodeAt(0));
}

// The fragment that holds the packed form `packed`, after `version`.
async function encodeFragment(version, packed) {
  const deflated = deflateSync(new TextEncoder().encode(JSON.stringify(packed)), { level: 9, dictionary: DICTIONARY_BYTES });
  return `${version}.${toBase64Url(deflated)}`;
}

// The packed form a fragment of `version` holds. Throws an error saying
// what's wrong with a fragment that isn't one.
async function decodeFragment(version, fragment) {
  const dot = fragment.indexOf(".");
  if (dot < 0 || fragment.slice(0, dot) !== version) throw new Error("The link is in a format this site doesn't read");
  try {
    const inflated = inflateSync(fromBase64Url(fragment.slice(dot + 1)), { dictionary: DICTIONARY_BYTES });
    return JSON.parse(new TextDecoder().decode(inflated));
  } catch {
    throw new Error("The link is damaged");
  }
}

// The fragment, without its `#`, that shares `document`.
export const encodeLink = async (document, catalog) => encodeFragment(CODEC_VERSION, packDocument(document, catalog));

// The document a fragment made by `encodeLink` shares. Throws an error
// saying what's wrong with a fragment that isn't one.
export const decodeLink = async (fragment, catalog) => unpackDocument(await decodeFragment(CODEC_VERSION, fragment), catalog);

// The packed form of one module: `o` the module, `s` its states when they
// are its own, `b` set when they are the ones it starts with, and `h` the
// name of the state it is shown in when that isn't its first.
export function packModule(module, states, shown, catalog) {
  const packed = { o: module };
  const starting = defaultStates(module, catalog);
  if (states !== undefined && starting !== undefined && sameValue(states, starting)) packed.b = 1;
  else if (states !== undefined) packed.s = states;
  if (shown !== undefined && states?.some(state => state.name === shown) && states[0].name !== shown) packed.h = shown;
  return mapStrings(packed, packString);
}

// The module a packed form holds, as `{ module, states, shown }`. A
// module whose starting states the site no longer has shows none.
export function unpackModule(packed, catalog) {
  if (!dict(packed)) throw new Error("The link doesn't hold a module");
  const { o, s, b, h } = mapStrings(packed, unpackString);
  if (!dict(o) || str(o.name) === undefined) throw new Error("The link doesn't hold a module");
  const shared = { module: o };
  const states = b ? defaultStates(o, catalog) : Array.isArray(s) ? s : undefined;
  if (states !== undefined) shared.states = states;
  if (typeof h === "string") shared.shown = h;
  return shared;
}

// The fragment, without its `#`, that shares one module with the states
// it shows.
export const encodeModuleLink = async (module, states, shown, catalog) =>
  encodeFragment(MODULE_CODEC_VERSION, packModule(module, states, shown, catalog));

// The module a fragment made by `encodeModuleLink` shares.
export const decodeModuleLink = async (fragment, catalog) => unpackModule(await decodeFragment(MODULE_CODEC_VERSION, fragment), catalog);

// The packed form of the theme a document is drawn in: `k` what its
// config's `theme` selects, and `t` the theme files of its own that
// names. A theme kantan bundles goes by its name alone.
export function packTheme(document) {
  const selection = document.config?.theme;
  const themes = Object.fromEntries(selectedThemes(selection).filter(name => dict(document.themes?.[name])).map(name => [name, document.themes[name]]));
  return mapStrings({ k: selection, ...(present(themes) ? { t: themes } : {}) }, packString);
}

// The theme a packed form holds, as `{ selection, themes }`.
export function unpackTheme(packed) {
  if (!dict(packed)) throw new Error("The link doesn't hold a theme");
  const { k, t } = mapStrings(packed, unpackString);
  if (selectedThemes(k).length === 0) throw new Error("The link doesn't hold a theme");
  return { selection: k, themes: dict(t) ?? {} };
}

// The fragment, without its `#`, that shares the theme `document` is
// drawn in.
export const encodeThemeLink = async document => encodeFragment(THEME_CODEC_VERSION, packTheme(document));

// The theme a fragment made by `encodeThemeLink` shares.
export const decodeThemeLink = async fragment => unpackTheme(await decodeFragment(THEME_CODEC_VERSION, fragment));

// What joins a module's link to the link of the theme it is drawn in.
export const WITH_THEME = "~";

// What a fragment asks the builder to open: `{ link }` for a shared
// document, `{ module }` for a shared module, with `theme` when the theme
// it is drawn in comes with it, `{ theme }` for a shared theme, `{ url }`
// for a config file to fetch, with `gist` when the file is a gist's first
// YAML file, or undefined for anything else.
export function readFragment(fragment) {
  const text = fragment.replace(/^#/, "");
  if (text === "") return undefined;
  const equals = text.indexOf("=");
  const key = equals < 0 ? "" : text.slice(0, equals);
  const value = equals < 0 ? "" : decodeURIComponent(text.slice(equals + 1));
  if (key === "from" && /^https:\/\//.test(value)) return { url: value };
  if (key === "gh") {
    const [user, repo, ...path] = value.split("/");
    if (!user || !repo || path.length === 0) return undefined;
    return { url: `https://raw.githubusercontent.com/${user}/${repo}/HEAD/${path.join("/")}` };
  }
  if (key === "gist" && /^[0-9a-f]+$/i.test(value)) return { url: `https://api.github.com/gists/${value}`, gist: true };
  if (/^[0-9]+\./.test(text)) return { link: text };
  const [first, second] = text.split(WITH_THEME);
  if (/^m[0-9]+\./.test(first)) return { module: first, ...(/^t[0-9]+\./.test(second ?? "") ? { theme: second } : {}) };
  if (/^t[0-9]+\./.test(text)) return { theme: text };
  return undefined;
}

// The config.yaml within what a fetch of `readFragment`'s URL returned:
// the body itself, or for a gist its config.yaml or first YAML file.
export function configText(body, { gist } = {}) {
  if (!gist) return body;
  const files = Object.values(dict(JSON.parse(body).files) ?? {});
  const yaml = files.filter(file => /\.ya?ml$/.test(str(file?.filename) ?? ""));
  const file = yaml.find(file => file.filename === "config.yaml") ?? yaml[0];
  if (!file || typeof file.content !== "string") throw new Error("The gist holds no YAML file");
  return file.content;
}

// The Markdown that links `url` under `title`, for a GitHub post.
export const markdownLink = (title, url) => `[${title.replace(/([\\[\]])/g, "\\$1")}](${url})`;
