import AppKit
import CoreGraphics
import Foundation

struct NativeMenuBarItem {
  var index: Int
  let cgRect: CGRect
  let owner: String
  /// Control Centre identifier (e.g. `WiFi`, `Clock`) of a system item. Set
  /// for items read through Accessibility or reconstructed from Control
  /// Centre's defaults; `nil` for items read from WindowServer windows.
  var identifier: String? = nil
  /// Further names `mask.name` matches, ignoring case: a system item's
  /// Accessibility identifier and name, or the owning app's bundle
  /// identifier, name and executable name.
  var matchNames: [String] = []
}

/// Menu bar item geometry reconstructed from Control Centre's defaults, for
/// macOS 27 and later when kantan lacks Accessibility permission.
///
/// From macOS 27, MenuBarAgent draws every status item into a single menu bar
/// surface, so individual items are no longer WindowServer windows. Control
/// Centre's `NSStatusItem Preferred Position <id>` defaults, which
/// MenuBarAgent migrated its layout from, still place its modules; they
/// record no third-party items.
///
/// A position is the running total of the content widths of the modules to
/// its right. On screen, modules are padded by half of `moduleSpacing` on
/// each side and abut, starting `trailingEdgeInset` from the screen's right
/// edge. Each resulting slot matches the per-item window earlier releases
/// exposed (content + padding).
struct PersistedMenuBarLayout {
  /// Distance from the screen's right edge to the rightmost item's slot.
  static let trailingEdgeInset: CGFloat = 12
  /// Horizontal padding added around a Control Centre module's content.
  static let moduleSpacing: CGFloat = 16
  /// Content width assumed for the leftmost item, whose width no persisted
  /// position bounds. Matches a standard symbol-sized menu bar item.
  static let defaultContentWidth: CGFloat = 22
  /// Distance from the screen's right edge to the point Control Centre's
  /// `NSStatusItem Preferred Position` defaults are measured from.
  static let legacyAnchorInset: Double = 1.5

  static let modulePrefix = "module:"

  /// Whether this macOS release lays out status items inside MenuBarAgent.
  static let isActive = ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27

  /// Positions reconstructed from Control Centre's
  /// `NSStatusItem Preferred Position <id>` defaults, which MenuBarAgent
  /// migrates from and which need no permission to read. Each measures from
  /// `legacyAnchorInset` inside the screen edge to the right edge of an
  /// item's slot, i.e. it also counts the edge inset and the padding of the
  /// modules to its right. macOS 27 no longer updates them, so they go stale
  /// once items are rearranged there.
  static func legacyPositions(controlCentreValue value: (String) -> Any?) -> [String: Double] {
    func isHidden(_ id: String) -> Bool {
      MenuBarItemDetector.isHiddenInControlCentre(id, value: value)
    }
    let modules = MenuBarItemDetector.knownCCIdentifiers
      .filter { !isHidden($0) }
      .compactMap { id in
        (value("NSStatusItem Preferred Position \(id)") as? NSNumber)
          .map { (id: id, position: $0.doubleValue) }
      }
      .sorted { $0.position < $1.position }

    var positions: [String: Double] = [:]
    let hasClock = !isHidden("Clock")
    if hasClock { positions[modulePrefix + "Clock"] = 0 }
    for (rank, module) in modules.enumerated() {
      let modulesToRight = Double(rank + (hasClock ? 1 : 0))
      positions[modulePrefix + module.id] =
        module.position + legacyAnchorInset - Double(trailingEdgeInset)
        - Double(moduleSpacing) * modulesToRight
    }
    return positions
  }

  /// Lay out items right-to-left on a screen. Returns items sorted
  /// right-to-left (index 0 = rightmost), each spanning its full slot.
  static func items(
    from positions: [String: Double],
    screenFrame: NSRect,
    primaryHeight: CGFloat,
    menuBarHeight: CGFloat
  ) -> [NativeMenuBarItem] {
    let entries = positions.sorted { ($0.value, $0.key) < ($1.value, $1.key) }
    let cgScreenTop = primaryHeight - screenFrame.maxY
    var slotRight = screenFrame.maxX - trailingEdgeInset
    var items: [NativeMenuBarItem] = []

    for (i, entry) in entries.enumerated() {
      let nextPosition = entries[(i + 1)...].first { $0.value > entry.value }?.value
      let width = nextPosition.map { CGFloat($0 - entry.value) } ?? defaultContentWidth
      let slotWidth = width + moduleSpacing
      slotRight -= slotWidth
      items.append(
        NativeMenuBarItem(
          index: items.count,
          cgRect: CGRect(x: slotRight, y: cgScreenTop, width: slotWidth, height: menuBarHeight),
          owner: "MenuBarAgent",
          identifier: String(entry.key.dropFirst(modulePrefix.count))
        ))
    }
    return items
  }
}

/// TTL-based cache for the raw `CGWindowListCopyWindowInfo` result.
/// Generic over time and fetch so the cache logic is independently testable.
struct WindowListCache {
  private var windows: [[String: Any]] = []
  private var expiresAt: TimeInterval = 0

  mutating func get(
    now: TimeInterval, ttl: TimeInterval, fetch: () -> [[String: Any]]
  ) -> [[String: Any]] {
    if now < expiresAt { return windows }
    let fresh = fetch()
    windows = fresh
    expiresAt = now + ttl
    return fresh
  }

  mutating func invalidate() {
    windows = []
    expiresAt = 0
  }
}

struct MenuBarItemDetector {
  /// Tolerance in points for matching a menu bar item's Y position to a screen edge.
  private static let screenEdgeTolerance: CGFloat = 2
  /// Tolerance in points for matching preferred position to detected item position.
  private static let preferredPositionTolerance: Double = 3.0
  /// How long a `CGWindowListCopyWindowInfo` result stays valid. Long enough
  /// that the 20-tick reposition timer reuses one snapshot for ~1-2 ticks
  /// across all displays; short enough that stale data is corrected within
  /// one human-perceptible frame.
  static let cacheTTL: TimeInterval = 0.15

  nonisolated(unsafe) private static var cache = WindowListCache()
  private static let cacheLock = NSLock()

  private static func cachedWindowList() -> [[String: Any]] {
    cacheLock.lock()
    defer { cacheLock.unlock() }
    return cache.get(
      now: Date().timeIntervalSinceReferenceDate,
      ttl: cacheTTL,
      fetch: {
        CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID)
          as? [[String: Any]] ?? []
      })
  }

  /// Drop the cached window list so the next `detectItems` call re-queries
  /// the WindowServer. Call on screen layout changes where a stale snapshot
  /// would place panels using the previous configuration.
  static func invalidateCache() {
    cacheLock.lock()
    cache.invalidate()
    cacheLock.unlock()
  }

  /// User-friendly aliases for Control Center item names.
  /// Maps user-facing config names to the internal plist identifier
  /// used in `NSStatusItem Preferred Position <identifier>`.
  private static let nameAliases: [String: String] = [
    "ControlCenter": "BentoBox-0",
    "Volume": "Sound",
    "Camera": "AudioVideoModule",
    "Microphone": "AudioVideoModule",
    "Focus": "FocusModes",
  ]

  /// Names of the items macOS keeps at the menu bar's right end, in lower case.
  private static let pinnedNames: Set<String> = Set(
    ["clock", "controlcenter", "bentobox-0"].flatMap {
      [$0, MenuBarAccessibility.systemIdentifierPrefix + $0]
    })

  /// Whether a mask names the clock or Control Centre. macOS keeps both at
  /// the menu bar's right end, and lets no item sit right of either.
  static func isPinned(_ mask: MaskConfig) -> Bool {
    guard let name = mask.name else { return false }
    return pinnedNames.contains((nameAliases[name] ?? name).lowercased())
  }

  /// Known Control Centre module identifiers that occupy individual menu bar slots.
  /// Used for rank-based fallback matching when absolute position matching fails.
  /// Order doesn't matter — they're sorted by preferred position at runtime.
  static let knownCCIdentifiers: [String] = [
    "BentoBox-0", "Battery", "WiFi", "Bluetooth", "Sound",
    "FocusModes", "NowPlaying", "AudioVideoModule", "Display",
    "ScreenMirroring", "UserSwitcher", "AccessibilityShortcuts",
    "Hearing", "KeyboardBrightness", "AirDrop", "StageManager",
  ]

  /// Query native menu bar items on a given screen.
  /// Returns items sorted right-to-left (index 0 = rightmost).
  /// With Accessibility permission, items are the live ones
  /// `MenuBarAccessibility` reads, system and third-party. Otherwise macOS 27+
  /// reconstructs Control Centre's items from its defaults, and earlier
  /// releases read status-level WindowServer windows. The underlying
  /// `CGWindowListCopyWindowInfo` result is cached briefly (`cacheTTL`) so the
  /// per-display reposition fan-out doesn't repeatedly query the WindowServer.
  static func detectItems(for screen: NSScreen, excludingOwner: String = "kantan")
    -> [NativeMenuBarItem]
  {
    // CG origin = top-left of primary. NSScreen origin = bottom-left of primary.
    // Primary screen's frame.maxY gives the total height of the primary display
    // in the NSScreen coordinate system.
    let primaryHeight = NSScreen.screens.first?.frame.height ?? screen.frame.height
    let menuBarHeight = max(screen.frame.maxY - screen.visibleFrame.maxY, 0)

    let accessible = MenuBarAccessibility.shared.snapshot
    if !accessible.isEmpty {
      return MenuBarAccessibility.items(
        from: accessible,
        screenFrame: screen.frame,
        screenFrames: NSScreen.screens.map(\.frame),
        primaryHeight: primaryHeight,
        menuBarHeight: menuBarHeight
      )
    }

    if PersistedMenuBarLayout.isActive {
      let controlCentre = UserDefaults(suiteName: "com.apple.controlcenter")
      return PersistedMenuBarLayout.items(
        from: PersistedMenuBarLayout.legacyPositions(
          controlCentreValue: { controlCentre?.object(forKey: $0) }),
        screenFrame: screen.frame,
        primaryHeight: primaryHeight,
        menuBarHeight: menuBarHeight
      )
    }

    return filterMenuBarItems(
      from: cachedWindowList(),
      primaryHeight: primaryHeight,
      screenFrame: screen.frame,
      excludingOwner: excludingOwner
    )
  }

  /// Pure filter+sort for a window list. Independently testable: given a
  /// synthetic `CGWindowListCopyWindowInfo`-shaped array, returns the same
  /// menu bar items `detectItems` would have produced.
  static func filterMenuBarItems(
    from windowList: [[String: Any]],
    primaryHeight: CGFloat,
    screenFrame: NSRect,
    excludingOwner: String = "kantan"
  ) -> [NativeMenuBarItem] {
    let statusLevel = Int(CGWindowLevelForKey(.statusWindow))
    let cgScreenTop = primaryHeight - screenFrame.maxY
    let cgScreenLeft = screenFrame.minX
    let cgScreenRight = screenFrame.maxX

    var items: [(cgRect: CGRect, owner: String)] = []

    for window in windowList {
      let level = window[kCGWindowLayer as String] as? Int ?? -999
      guard level == statusLevel else { continue }

      let owner = window[kCGWindowOwnerName as String] as? String ?? ""
      // Exclude kantan's own panels. The process name may be wrapped
      // by Nix (e.g. ".kantan-wrapped"), so use a substring check.
      guard !owner.contains(excludingOwner) else { continue }

      guard let boundsDict = window[kCGWindowBounds as String] as? NSDictionary,
        let bounds = CGRect(dictionaryRepresentation: boundsDict)
      else { continue }

      // Filter to items on this screen: CG Y should match the screen's
      // top edge (menu bar sits at the very top), and X should be within
      // the screen's horizontal range.
      guard abs(bounds.origin.y - cgScreenTop) < screenEdgeTolerance else { continue }
      guard bounds.maxX > cgScreenLeft && bounds.origin.x < cgScreenRight else { continue }

      items.append((cgRect: bounds, owner: owner))
    }

    items.sort { $0.cgRect.origin.x > $1.cgRect.origin.x }

    return items.enumerated().map { (i, item) in
      NativeMenuBarItem(
        index: i,
        cgRect: item.cgRect,
        owner: item.owner
      )
    }
  }

  /// Whether a Control Centre item is hidden by its visibility default.
  /// Checks both `NSStatusItem VisibleCC <id>` and `NSStatusItem Visible <id>`;
  /// an item with neither key is treated as visible.
  static func isHiddenInControlCentre(_ id: String, value: (String) -> Any?) -> Bool {
    let visibleCC = value("NSStatusItem VisibleCC \(id)") as? Int
    let visible = value("NSStatusItem Visible \(id)") as? Int
    guard let v = visibleCC ?? visible else { return false }
    return v == 0
  }

  /// Resolve a MaskConfig to a specific native menu bar item.
  ///
  /// Resolution chain (highest to lowest priority):
  /// 1. `mask.index` — direct index lookup
  /// 2. `mask.name` — name match, for items that carry names (read through
  ///    Accessibility, or reconstructed on macOS 27+). Compared ignoring case
  ///    against the Control Centre identifier and `matchNames`, so a
  ///    third-party item matches its app's bundle identifier, name or
  ///    executable name. The rightmost match wins.
  /// 3. `mask.name` — preferred position match (tight tolerance)
  /// 4. `mask.name` — rank-based fallback (immune to position shifts)
  /// 5. `mask.name` — owner name fallback
  ///
  /// For WindowServer windows, name-based lookup reads `NSStatusItem Preferred Position <Name>` from the
  /// `com.apple.controlcenter` defaults. If that fails, falls back to rank-based
  /// matching: when menu bar items shift uniformly (e.g. battery percentage
  /// toggle), absolute positions change but relative order is preserved.
  ///
  /// User-friendly aliases are supported (e.g. "ControlCenter" → "BentoBox-0",
  /// "Volume" → "Sound"). The raw plist names also work directly.
  ///
  /// "Clock" is handled specially: it has no preferred position in the plist,
  /// but when enabled it is identifiable as the Control Centre window at
  /// rightEdgeDist=0 (the rightmost position, occupied by the clock when
  /// the menu bar clock is visible).
  static func resolveItem(for mask: MaskConfig, from items: [NativeMenuBarItem])
    -> NativeMenuBarItem?
  {
    // 1. Index-based lookup
    if let index = mask.index {
      guard index >= 0 && index < items.count else { return nil }
      return items[index]
    }

    // 2. Name-based lookup
    guard let name = mask.name else { return nil }

    // Resolve aliases to plist identifiers
    let plistName = nameAliases[name] ?? name

    // Named items are matched directly.
    if items.contains(where: { $0.identifier != nil || !$0.matchNames.isEmpty }) {
      let wanted = Set([name, plistName].map { $0.lowercased() })
      return items.first { item in
        ([item.identifier].compactMap { $0 } + item.matchNames).contains {
          wanted.contains($0.lowercased())
        }
      }
    }

    let controlCenterDefaults = UserDefaults(suiteName: "com.apple.controlcenter")

    // Special case: Clock has no preferred position in the plist.
    // When the clock is enabled, it occupies the rightmost position
    // — the item at index 0 in our right-to-left sorted array.
    if plistName == "Clock" {
      if let defaults = controlCenterDefaults,
        let clockVisible = defaults.object(forKey: "NSStatusItem VisibleCC Clock") as? Int,
        clockVisible != 0,
        let firstItem = items.first
      {
        return firstItem
      }
      return nil
    }

    // Standard lookup via preferred position.
    // macOS stores the preferred position as the distance from the
    // effective right edge of the menu bar (which may extend past the
    // screen boundary — the rightmost item often overflows by a few px)
    // to the right edge of the item. We compute the effective right edge
    // from the detected items themselves rather than using screenWidth.
    let effectiveRightEdge = items.map { Double($0.cgRect.maxX) }.max() ?? 0

    if let defaults = controlCenterDefaults {
      let key = "NSStatusItem Preferred Position \(plistName)"
      if let preferredPos = defaults.object(forKey: key) as? Double {
        // Tight tolerance: works when plist positions are up to date.
        for item in items {
          let rightEdgeDist = effectiveRightEdge - Double(item.cgRect.maxX)
          if abs(rightEdgeDist - preferredPos) < preferredPositionTolerance {
            return item
          }
        }

        // Rank-based fallback: when a menu bar item changes size (e.g.
        // battery percentage toggle), items shift and the plist may lag
        // behind. The items' relative order is always preserved, so we
        // build a catalog of all visible CC items sorted by preferred
        // position and match the target's rank against detected items.
        if let ranked = resolveByRank(
          plistName: plistName, defaults: defaults, items: items,
          effectiveRightEdge: effectiveRightEdge, preferredPos: preferredPos)
        {
          return ranked
        }
      }
    }

    // Fallback: match against window owner name (case-insensitive).
    return items.first { $0.owner.lowercased() == name.lowercased() }
  }

  /// Rank-based item resolution. Builds a catalog of all visible Control Centre
  /// items from the plist, sorts by preferred position (rightmost first), and
  /// maps the target's catalog rank to the corresponding detected item index.
  ///
  /// This is immune to uniform position shifts because relative ordering is
  /// preserved even when absolute positions change.
  private static func resolveByRank(
    plistName: String, defaults: UserDefaults, items: [NativeMenuBarItem],
    effectiveRightEdge: Double, preferredPos: Double
  ) -> NativeMenuBarItem? {
    // Build catalog of CC items that have preferred positions and are visible.
    var catalog: [(name: String, pos: Double)] = []
    for id in knownCCIdentifiers {
      let posKey = "NSStatusItem Preferred Position \(id)"
      guard let pos = defaults.object(forKey: posKey) as? Double else { continue }
      if isHiddenInControlCentre(id, value: { defaults.object(forKey: $0) }) { continue }

      catalog.append((name: id, pos: pos))
    }
    catalog.sort { $0.pos < $1.pos }

    guard let targetRank = catalog.firstIndex(where: { $0.name == plistName }) else {
      return nil
    }

    // The clock (when visible) occupies index 0 in the detected items
    // but has no preferred position in the catalog.
    let clockVisible =
      (defaults.object(forKey: "NSStatusItem VisibleCC Clock") as? Int ?? 0) != 0
    let adjustedRank = targetRank + (clockVisible ? 1 : 0)

    guard adjustedRank >= 0 && adjustedRank < items.count else { return nil }

    let candidate = items[adjustedRank]

    // Sanity check: the candidate should be reasonably close to the expected
    // position. A shift of up to ~80px is plausible (e.g. battery percentage
    // adding width); much more suggests the rank mapping is wrong.
    let candidateDist = effectiveRightEdge - Double(candidate.cgRect.maxX)
    guard abs(candidateDist - preferredPos) < 80 else { return nil }

    return candidate
  }

  /// Convert CG rect to AppKit screen coordinates.
  /// CG origin = top-left of primary. NSScreen origin = bottom-left of primary.
  static func appKitRect(from cgRect: CGRect, on screen: NSScreen) -> NSRect {
    let primaryHeight = NSScreen.screens.first?.frame.height ?? screen.frame.height
    return appKitRect(from: cgRect, primaryHeight: primaryHeight)
  }

  /// Pure CG→AppKit conversion given an explicit primary screen height.
  static func appKitRect(from cgRect: CGRect, primaryHeight: CGFloat) -> NSRect {
    NSRect(
      x: cgRect.origin.x,
      y: primaryHeight - cgRect.origin.y - cgRect.height,
      width: cgRect.width,
      height: cgRect.height
    )
  }
}
