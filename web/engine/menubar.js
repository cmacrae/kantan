// macOS's own menu bar, which a masked module covers an item of: kantan
// sets the module over that item, as wide as it and centred within it.
// Where the items sit is the system's doing, so the engine lays them out
// from a sample of a menu bar: each item's name and width in points,
// measured on macOS 27 with the clock showing the time alone.

export const MENU_BAR = {
  // The space between the last item and the screen's edge.
  trailing: 12,
  // The system's items from the screen's edge inwards.
  items: [
    { name: "Clock", width: 54 },
    { name: "ControlCenter", width: 40 },
    { name: "Battery", width: 44 },
    { name: "WiFi", width: 36 },
    { name: "Volume", width: 39 },
    { name: "Bluetooth", width: 32 },
    { name: "Focus", width: 37 },
  ],
  // The width of any other item, such as another app's.
  width: 36,
};

// The slots `modules`, the bar's masked modules that are showing, take in
// `menuBar`: each module's name with its slot's width, as they sit from
// left to right. A module over one of the system's items sits where the
// system puts that item, and the others sit inwards of those in the order
// the config lists them.
export function menuBarSlots(modules, menuBar = MENU_BAR) {
  const position = module => {
    const name = module.mask.name?.toLowerCase();
    return menuBar.items.findIndex(item => item.name.toLowerCase() === name);
  };
  const others = modules.filter(module => position(module) < 0)
    .map(module => ({ name: module.name, width: menuBar.width }));
  const system = modules.filter(module => position(module) >= 0)
    .sort((a, b) => position(b) - position(a))
    .map(module => ({ name: module.name, width: menuBar.items[position(module)].width }));
  return [...others, ...system];
}

// The camera housing at the top of a MacBook's screen, in points, as
// measured on a 14-inch MacBook Pro: the room between the two areas macOS
// leaves for the menu bar on either side of it.
export const NOTCH = { width: 185, height: 32 };
