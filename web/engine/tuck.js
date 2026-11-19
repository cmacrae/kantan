// How one side of the notch is shared between the modules that give way,
// those with a `tuck`, and the others: a module that gives way waits behind
// the notch while another on its side shows.

// How long a module arriving stays out before it slides behind the notch,
// in seconds, when its `peek` isn't set.
export const TUCK_PEEK = 5;

// A module's `tuck`: `true` for the defaults, or a mapping of its settings.
// Undefined when the key is absent, false or anything else.
export function parseTuck(value) {
  if (value === true) return { peek: TUCK_PEEK };
  if (typeof value !== "object" || value === null || Array.isArray(value)) return undefined;
  return { peek: typeof value.peek === "number" && Number.isFinite(value.peek) && value.peek >= 0 ? value.peek : TUCK_PEEK };
}

// The phase of one side of the notch: `idle`, where every module shows as
// it would alone, `tucked`, where those that give way wait behind the
// notch, or `revealed`, where they are out in place of the others.
//
// `tucking` is whether a module that gives way has something to show,
// `holding` whether another module on the side does, and `revealing`
// whether those that give way are wanted out: one has just arrived, or the
// pointer is at the notch.
export function resolveTuck({ tucking, holding, revealing }) {
  if (!tucking || !holding) return "idle";
  return revealing ? "revealed" : "tucked";
}

// Whether a module is out of the bar in `phase`: one that gives way while
// tucked, any other while those are revealed.
export function tuckHides(phase, givesWay) {
  return phase === "tucked" ? givesWay : phase === "revealed" ? !givesWay : false;
}
