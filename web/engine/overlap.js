// What happens where the modules beside the notch and an open drawer's
// contents, further out on the same side, want the same room. Whichever is
// being used keeps its place: a drawer opened over the modules beside the
// notch displaces them, until it closes or there is room, and a module
// beside the notch in use closes the drawer it grows into, until it is let
// go, when the drawer opens again.

// How near the two come before one makes room for the other, in points.
export const OVERLAP_MARGIN = 12;

// What to do on one side of the notch: `displace` the modules beside the
// notch behind it, `restore` them, `closeDrawer` for now, `reopenDrawer`,
// or `none`.
//
// `collides` is whether the two want the same room, the modules beside the
// notch at the width they have, or had before being displaced. `drawerOpen`
// is whether the side's drawer is open, `engaged` whether a module beside
// the notch is being used, `displaced` whether those modules are behind
// the notch, and `yielded` whether the drawer is closed for now.
export function resolveOverlap({ collides, drawerOpen, engaged, displaced, yielded }) {
  if (yielded) return engaged || drawerOpen ? "none" : "reopenDrawer";
  if (displaced) return drawerOpen && collides ? "none" : "restore";
  if (!collides || !drawerOpen) return "none";
  return engaged ? "closeDrawer" : "displace";
}
