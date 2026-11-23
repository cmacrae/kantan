import AppKit

/// A run of unmasked modules of the right placement with a masked module to
/// its left. A status item of kantan's own, as wide as the run, holds the
/// run's place in the native menu bar, so the items of the masked modules
/// either side of it sit where the config orders them.
///
/// A run right of a module masking the clock or Control Centre has no
/// slot: macOS lets no item sit right of either.
struct MenuBarSlot: Equatable {
  /// The run's modules, left to right.
  let modules: [String]
  /// The masked modules right of the run, nearest first.
  let masksRight: [String]
  /// The masked modules left of the run, nearest first.
  let masksLeft: [String]

  /// Names the slot's status item.
  var name: String { "slot-\(modules[0])" }

  /// The slots of a right placement's modules, given left to right.
  /// `isPinned` marks a module masking an item macOS keeps at the right end.
  static func derive(from modules: [(name: String, isMasked: Bool, isPinned: Bool)])
    -> [MenuBarSlot]
  {
    var slots: [MenuBarSlot] = []
    var index = 0
    while index < modules.count {
      guard !modules[index].isMasked else {
        index += 1
        continue
      }
      let end = modules[index...].firstIndex { $0.isMasked } ?? modules.count
      let masksLeft = modules[..<index].filter(\.isMasked).map(\.name)
      if !masksLeft.isEmpty, !modules[..<index].contains(where: \.isPinned) {
        slots.append(
          MenuBarSlot(
            modules: modules[index..<end].map(\.name),
            masksRight: modules[end...].filter(\.isMasked).map(\.name),
            masksLeft: masksLeft.reversed()))
      }
      index = end
    }
    return slots
  }
}

/// The menu bar item a slot's item belongs directly beside.
struct SlotAnchor {
  let item: NativeMenuBarItem
  /// Whether the slot belongs at the item's left, or at its right.
  let slotIsLeft: Bool
}

/// Where a slot's item sits against where it belongs.
enum SlotOrder {
  case placed, tooFarLeft, tooFarRight

  /// Compares a slot's frame with its anchor's, among the bar's other items.
  static func of(slot: CGRect, beside anchor: SlotAnchor, among items: [NativeMenuBarItem])
    -> SlotOrder
  {
    let anchorX = anchor.item.cgRect.midX
    let between = items.contains {
      let x = $0.cgRect.midX
      return x != anchorX && x > min(slot.midX, anchorX) && x < max(slot.midX, anchorX)
    }
    if anchor.slotIsLeft {
      if slot.midX > anchorX { return .tooFarRight }
      return between ? .tooFarLeft : .placed
    }
    if slot.midX < anchorX { return .tooFarLeft }
    return between ? .tooFarRight : .placed
  }
}

/// Finds the preferred position that puts a slot's item beside its anchor.
///
/// macOS orders status items by preferred position, least at the right. An
/// item's is roughly the content widths of the items to its right added up,
/// but it is kept from when the item last moved and can't be read, so a
/// position is tried, and then moved towards the anchor until the item lands.
struct SlotSeedSearch: Equatable {
  private(set) var seed: Double
  /// The greatest position that left the item too far right.
  private var low: Double?
  /// The least position that left it too far left.
  private var high: Double?
  private var step = 8.0

  /// The least position tried. The menu bar reads zero as no position, puts
  /// such an item at the left end, and from then on keeps every item where
  /// it is, whatever position it is next made at.
  static let minimum = 0.25
  /// The greatest position tried, well past the width of any menu bar.
  static let maximum = 100_000.0

  init(seed: Double) {
    self.seed = Self.bounded(seed)
  }

  /// `seed` within the positions tried.
  private static func bounded(_ seed: Double) -> Double {
    seed.isFinite ? min(max(seed, minimum), maximum) : minimum
  }

  /// The position likeliest to put an item beside `anchor`: half way
  /// between the anchor's own and its neighbour's on the slot's side.
  static func estimate(beside anchor: SlotAnchor, among items: [NativeMenuBarItem]) -> Double {
    func content(_ item: NativeMenuBarItem) -> Double {
      max(Double(item.cgRect.width - PersistedMenuBarLayout.moduleSpacing), 0)
    }
    let right = items.filter { $0.cgRect.midX > anchor.item.cgRect.midX }
    let position = right.reduce(0) { $0 + content($1) }
    if anchor.slotIsLeft { return position + content(anchor.item) / 2 }
    let neighbour = right.min { $0.cgRect.midX < $1.cgRect.midX }
    return max(position - (neighbour.map(content) ?? 0) / 2, minimum)
  }

  /// Moves the position on from one that left the item out of place.
  mutating func advance(from order: SlotOrder) {
    switch order {
    case .placed:
      return
    case .tooFarRight:
      low = seed
      seed = high.map { (seed + $0) / 2 } ?? seed + step
    case .tooFarLeft:
      high = seed
      seed = low.map { (seed + $0) / 2 } ?? max(seed - step, seed / 2)
    }
    seed = Self.bounded(seed)
    step *= 2
  }
}

/// The status items that hold the config's slots in the native menu bar.
///
/// Each is empty and as wide as its run of modules, which are drawn over it.
/// Items need the live frames of the bar's other items, so there are none
/// while those are reconstructed from saved positions.
@MainActor
final class MenuBarSlots {
  private struct Entry {
    var item: NSStatusItem?
    var search: SlotSeedSearch?
    /// Whether the search began with the name kept from an earlier run,
    /// which the menu bar may have a place for.
    var searchIsKept = false
    /// The masked module the item was last placed beside.
    var anchor: String?
    /// An anchor other than the item's, or none, and when it was first found.
    var unsettled: (anchor: String?, since: Date)?
    var attempts = 0
    /// The menu bar's items as the last position was tried and no place
    /// was found.
    var gaveUpAmong: [String]?
    var changedAt = Date.distantPast
    /// The run's width on each display.
    var widths: [String: CGFloat] = [:]
  }

  /// How long the menu bar's items take to be read again after one changes.
  static let settleTime: TimeInterval = 2.5
  /// How many positions are tried before a slot is left where it is.
  static let maxAttempts = 12

  private(set) var slots: [MenuBarSlot] = []
  private var masks: [String: MaskConfig] = [:]
  private var entries: [String: Entry] = [:]
  private let defaults = UserDefaults.standard
  /// Runs when an item was placed anew, once the menu bar has settled.
  var onChange: (() -> Void)?

  /// Whether the menu bar's items are read live, and so follow the slots.
  static var hasLiveItems: Bool {
    !PersistedMenuBarLayout.isActive || !MenuBarAccessibility.shared.snapshot.isEmpty
  }

  /// Takes on a config's slots, on a main display with or without a notch.
  /// The items of slots it no longer has are removed.
  func configure(modules: [ModuleConfig], hasNotch: Bool) {
    let right = modules.filter { $0.placement.resolve(hasNotch: hasNotch) == "right" }
    slots = MenuBarSlot.derive(
      from: right.map {
        ($0.name, $0.mask != nil, $0.mask.map(MenuBarItemDetector.isPinned) ?? false)
      })
    masks = Dictionary(
      right.compactMap { module in module.mask.map { (module.name, $0) } },
      uniquingKeysWith: { first, _ in first })
    for name in entries.keys where !slots.contains(where: { $0.name == name }) {
      remove(name)
      entries[name] = nil
    }
    prunePositions()
  }

  /// Drops the positions kept under names no slot's item has.
  private func prunePositions() {
    let current = Set(slots.map { positionKey(of: $0.name) })
    for key in defaults.dictionaryRepresentation().keys
    where key.hasPrefix("NSStatusItem Preferred Position slot-") && !current.contains(key) {
      defaults.removeObject(forKey: key)
    }
  }

  /// The slot a group's modules are drawn over.
  func slot(of group: ModuleGroup) -> MenuBarSlot? {
    guard group.placement == "right", let first = group.modules.first,
      first.moduleConfig.mask == nil
    else { return nil }
    return slots.first { $0.modules.contains(first.id) }
  }

  /// A slot's frame on a screen, in AppKit coordinates. Every display's menu
  /// bar shows an item at the same distance from its right edge.
  func frame(of slot: MenuBarSlot, on screen: NSScreen) -> NSRect? {
    guard let window = entries[slot.name]?.item?.button?.window, let source = window.screen,
      window.frame.width > 0
    else { return nil }
    var frame = window.frame
    frame.origin.x += screen.frame.maxX - source.frame.maxX
    return frame
  }

  /// Records how wide a slot's run of modules is on a display. The item is
  /// as wide as the run is on the display where it is widest.
  func setWidth(_ width: CGFloat, of slot: MenuBarSlot, display: String) {
    entries[slot.name, default: Entry()].widths[display] = width
    guard let item = entries[slot.name]?.item else { return }
    let length = self.length(of: slot.name)
    if abs(item.length - length) >= 0.5 {
      item.length = length
    }
  }

  /// Drops a display's widths once it has gone.
  func forget(display: String) {
    for name in entries.keys {
      entries[name]?.widths[display] = nil
    }
  }

  /// Makes each slot's item, and moves any that isn't beside the masked
  /// item the config orders it against. `items` are the menu bar's on
  /// `screen`, without kantan's own.
  func reconcile(items: [NativeMenuBarItem], on screen: NSScreen) {
    guard Self.hasLiveItems else {
      for name in entries.keys { remove(name) }
      return
    }
    // Behind the lock screen the items are as they were last read, and the
    // slots' own frames can't be relied on.
    guard !MenuBarAccessibility.isScreenLocked else { return }
    let now = Date()
    for slot in slots {
      var entry = entries[slot.name, default: Entry()]
      defer { entries[slot.name] = entry }

      // One read of the menu bar can miss items. An item moves or goes only
      // once its anchor has been another, or missing, for as long as the
      // menu bar takes to settle.
      let found = anchor(of: slot, among: items)
      if entry.item != nil, found?.module != entry.anchor {
        guard let unsettled = entry.unsettled, unsettled.anchor == found?.module else {
          entry.unsettled = (found?.module, now)
          scheduleChange()
          continue
        }
        guard now.timeIntervalSince(unsettled.since) >= Self.settleTime else { continue }
      }
      entry.unsettled = nil

      guard let (module, anchor) = found else {
        if let item = entry.item {
          discard(item, named: slot.name)
          entry.item = nil
        }
        continue
      }
      if entry.anchor != module {
        entry.anchor = module
        entry.search = nil
        entry.attempts = 0
        entry.gaveUpAmong = nil
      }

      guard entry.item != nil else {
        if entry.search == nil {
          entry.searchIsKept = itemName(of: slot.name) != nil
          if !entry.searchIsKept { rename(slot.name) }
          let kept = defaults.double(forKey: positionKey(of: slot.name))
          entry.search = SlotSeedSearch(
            seed: kept > 0 ? kept : SlotSeedSearch.estimate(beside: anchor, among: items))
        }
        entry.item = makeItem(named: slot.name, at: entry.search?.seed ?? 0)
        entry.changedAt = Date()
        scheduleChange()
        continue
      }

      guard now.timeIntervalSince(entry.changedAt) >= Self.settleTime,
        let frame = frame(of: slot, on: screen)
      else { continue }
      let order = SlotOrder.of(slot: frame, beside: anchor, among: items)
      guard order != .placed else {
        entry.attempts = 0
        entry.gaveUpAmong = nil
        continue
      }
      // A slot no place was found for is tried again once the menu bar's
      // items have changed.
      let among = items.map { "\($0.owner)/\($0.identifier ?? "")" }
      if entry.attempts >= Self.maxAttempts {
        guard entry.gaveUpAmong != among else { continue }
        entry.attempts = 0
        entry.search = nil
      }

      // An item under a kept name may be where the menu bar kept it, not at
      // the position tried, so a miss tells the search nothing and it starts
      // from an estimate. An item whose anchor changed has no search yet,
      // and starts from one too.
      if entry.searchIsKept || entry.search == nil {
        entry.searchIsKept = false
        entry.search = SlotSeedSearch(
          seed: SlotSeedSearch.estimate(beside: anchor, among: items))
      } else {
        entry.search?.advance(from: order)
      }
      entry.attempts += 1
      if entry.attempts == Self.maxAttempts {
        entry.gaveUpAmong = among
        print("warning: no place found for the menu bar slot of '\(slot.modules[0])'")
      }
      if let item = entry.item {
        NSStatusBar.system.removeStatusItem(item)
      }
      rename(slot.name)
      entry.item = makeItem(named: slot.name, at: entry.search?.seed ?? 0)
      entry.changedAt = Date()
      scheduleChange()
    }
  }

  /// The masked module a slot belongs beside, with its menu bar item: the
  /// nearest to its right that has one, or else the nearest to its left.
  private func anchor(of slot: MenuBarSlot, among items: [NativeMenuBarItem])
    -> (module: String, anchor: SlotAnchor)?
  {
    func find(_ modules: [String], slotIsLeft: Bool) -> (String, SlotAnchor)? {
      for module in modules {
        if let mask = masks[module],
          let item = MenuBarItemDetector.resolveItem(for: mask, from: items)
        {
          return (module, SlotAnchor(item: item, slotIsLeft: slotIsLeft))
        }
      }
      return nil
    }
    // Only the masked modules to its left need a slot to hold them there.
    guard let left = find(slot.masksLeft, slotIsLeft: false) else { return nil }
    return find(slot.masksRight, slotIsLeft: true) ?? left
  }

  private func length(of name: String) -> CGFloat {
    let width = entries[name]?.widths.values.max() ?? 0
    return max(width - PersistedMenuBarLayout.moduleSpacing, 1)
  }

  private func nameKey(of slot: String) -> String {
    "MenuBarSlot Name \(slot)"
  }

  /// The name of a slot's status item, kept from when it was last named.
  private func itemName(of slot: String) -> String? {
    defaults.string(forKey: nameKey(of: slot))
  }

  /// Gives a slot's item a name no item has had. The menu bar keeps the
  /// place of an item it has seen under its name, and puts it back there
  /// whatever position it is made at, so an item that has to move is made
  /// under a new name. The name is random, so it is new whatever is kept
  /// of the names before it.
  private func rename(_ slot: String) {
    let suffix = UUID().uuidString.prefix(8).lowercased()
    defaults.set("\(slot)-\(suffix)", forKey: nameKey(of: slot))
  }

  private func positionKey(of name: String) -> String {
    "NSStatusItem Preferred Position \(itemName(of: name) ?? name)"
  }

  /// Makes a blank status item at a preferred position, which macOS reads
  /// from the defaults as the item takes its name.
  private func makeItem(named name: String, at seed: Double) -> NSStatusItem {
    defaults.set(max(seed, SlotSeedSearch.minimum), forKey: positionKey(of: name))
    let item = NSStatusBar.system.statusItem(withLength: length(of: name))
    item.autosaveName = itemName(of: name) ?? name
    // The menu bar makes no room for an item with nothing to draw, so the
    // item draws a clear image.
    item.button?.image = NSImage(size: NSSize(width: 1, height: 1))
    return item
  }

  /// Takes an item out of the menu bar, keeping its position for when it
  /// is next made.
  private func discard(_ item: NSStatusItem, named name: String) {
    let key = positionKey(of: name)
    let seed = defaults.double(forKey: key)
    NSStatusBar.system.removeStatusItem(item)
    if seed > 0 { defaults.set(seed, forKey: key) }
  }

  /// Removes a slot's item and what was learnt placing it.
  private func remove(_ name: String) {
    guard let item = entries[name]?.item else { return }
    discard(item, named: name)
    entries[name]?.item = nil
    entries[name]?.search = nil
    entries[name]?.anchor = nil
    entries[name]?.unsettled = nil
    entries[name]?.attempts = 0
    entries[name]?.gaveUpAmong = nil
  }

  private func scheduleChange() {
    DispatchQueue.main.asyncAfter(deadline: .now() + Self.settleTime + 0.1) { [weak self] in
      MainActor.assumeIsolated { self?.onChange?() }
    }
  }
}
