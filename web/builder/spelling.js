// The site's words are written in British spelling. A reader whose browser
// asks for American or Canadian English first is shown that spelling.

// Each British stem and its American one, a longer stem before one it
// holds, and whether Canadian English spells it the American way.
const STEMS = [
  ["colour", "color", false],
  ["flavour", "flavor", false],
  ["customis", "customiz", true],
  ["centred", "centered", false],
  ["centre", "center", false],
];

// `text` with each of `stems` in its American spelling, each word keeping
// its capital.
const respell = (text, stems) => stems.reduce((spelt, [from, to]) => spelt.replace(new RegExp(from, "gi"),
  found => (found[0] === from[0] ? to : to[0].toUpperCase() + to.slice(1))), text);

export const american = text => respell(text, STEMS);
export const canadian = text => respell(text, STEMS.filter(([, , shared]) => shared));

const browser = globalThis.window?.navigator;
const SPELLINGS = { "en-us": american, "en-ca": canadian };
const spelling = SPELLINGS[(browser?.languages?.[0] ?? browser?.language ?? "").toLowerCase()];

// `text` as this reader spells it.
export const spell = text => spelling?.(text) ?? text;
