// macOS's own menu bar, which a masked module covers an item of: kantan
// sets the module over that item, as wide as it and centred within it.
// Where the items sit is the system's doing, so the engine lays them out
// from a sample of a menu bar: each item's name and width in points,
// measured on macOS 27 with the clock showing the time alone.

export const MENU_BAR = {
  // The space between the last item and the screen's edge.
  trailing: 12,
  // The system's items from the screen's edge inwards. macOS keeps a
  // `pinned` item at the right end, and lets no other sit right of it.
  items: [
    { name: "Clock", width: 54, pinned: true },
    { name: "ControlCenter", width: 40, pinned: true },
    { name: "Battery", width: 44 },
    { name: "WiFi", width: 36 },
    { name: "Volume", width: 39 },
    { name: "Bluetooth", width: 32 },
    { name: "Focus", width: 37 },
  ],
  // The width of any other item, such as another app's.
  width: 36,
};

// The modules drawn over `menuBar`, as they sit from left to right: each
// one's name, with its item's `width` when it is masked, and `fixed` when
// it can't be moved along the bar.
//
// `right` are the right placement's modules that are showing, in the
// config's order, each with its `mask` when it has one. Menu bar items
// can be arranged, so the masked ones sit in that order, but for those
// over a pinned item, which sit at the right end as macOS has them. With
// `slots`, an unmasked module listed after a masked one keeps its place
// among them: kantan holds it room in the menu bar. One listed after a
// pinned item's module has no place to keep, and sits inwards of them all
// with the rest of its placement. `strays` are the masked modules of other
// placements, which sit over their items all the same, inwards of the rest.
export function menuBarModules({ right, strays = [], slots = true }, menuBar = MENU_BAR) {
  const position = module => {
    const name = module.mask?.name?.toLowerCase();
    return menuBar.items.findIndex(item => item.name.toLowerCase() === name);
  };
  const pinned = module => menuBar.items[position(module)]?.pinned === true;
  const masked = module => ({ name: module.name, width: menuBar.items[position(module)]?.width ?? menuBar.width });

  const ordered = [];
  let masksBefore = false, pinnedBefore = false;
  for (const module of right) {
    if (!module.mask) {
      if (slots && masksBefore && !pinnedBefore) ordered.push({ name: module.name });
    } else if (pinned(module)) {
      pinnedBefore = true;
    } else {
      masksBefore = true;
      ordered.push(masked(module));
    }
  }
  const fixed = module => ({ ...masked(module), fixed: true });
  const atEnd = [...right.filter(module => module.mask), ...strays].filter(pinned)
    .sort((a, b) => position(b) - position(a));
  return [...strays.filter(module => !pinned(module)).map(fixed), ...ordered, ...atEnd.map(fixed)];
}

// The camera housing at the top of a MacBook's screen, in points, as
// measured on a 14-inch MacBook Pro: the room between the two areas macOS
// leaves for the menu bar on either side of it.
export const NOTCH = { width: 185, height: 32 };
