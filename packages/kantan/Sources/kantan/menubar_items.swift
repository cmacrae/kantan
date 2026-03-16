import AppKit
import CoreGraphics
import Foundation

struct NativeMenuBarItem {
  let index: Int
  let cgRect: CGRect
  let owner: String
}

struct MenuBarItemDetector {
  /// Tolerance in points for matching a menu bar item's Y position to a screen edge.
  private static let screenEdgeTolerance: CGFloat = 2
  /// Tolerance in points for matching preferred position to detected item position.
  private static let preferredPositionTolerance: Double = 3.0

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

  /// Known Control Centre module identifiers that occupy individual menu bar slots.
  /// Used for rank-based fallback matching when absolute position matching fails.
  /// Order doesn't matter — they're sorted by preferred position at runtime.
  private static let knownCCIdentifiers: [String] = [
    "BentoBox-0", "Battery", "WiFi", "Bluetooth", "Sound",
    "FocusModes", "NowPlaying", "AudioVideoModule", "Display",
    "ScreenMirroring", "UserSwitcher", "AccessibilityShortcuts",
    "Hearing", "KeyboardBrightness", "AirDrop", "StageManager",
  ]

  /// Query native menu bar items on a given screen.
  /// Returns items sorted right-to-left (index 0 = rightmost).
  static func detectItems(for screen: NSScreen, excludingOwner: String = "kantan")
    -> [NativeMenuBarItem]
  {
    let windowList =
      CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
    let statusLevel = Int(CGWindowLevelForKey(.statusWindow))

    // Convert NSScreen frame to CG coordinates.
    // CG origin = top-left of primary. NSScreen origin = bottom-left of primary.
    // Primary screen's frame.maxY gives the total height of the primary display
    // in the NSScreen coordinate system.
    let primaryHeight = NSScreen.screens.first?.frame.height ?? screen.frame.height
    let cgScreenTop = primaryHeight - screen.frame.maxY
    let cgScreenLeft = screen.frame.minX
    let cgScreenRight = screen.frame.maxX

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

  /// Resolve a MaskConfig to a specific native menu bar item.
  ///
  /// Resolution chain (highest to lowest priority):
  /// 1. `mask.index` — direct index lookup
  /// 2. `mask.name` — preferred position match (tight tolerance)
  /// 3. `mask.name` — rank-based fallback (immune to position shifts)
  /// 4. `mask.name` — owner name fallback
  ///
  /// Name-based lookup reads `NSStatusItem Preferred Position <Name>` from the
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

      // Check visibility using both "VisibleCC" and "Visible" key patterns.
      let visibleCC = defaults.object(forKey: "NSStatusItem VisibleCC \(id)") as? Int
      let visible = defaults.object(forKey: "NSStatusItem Visible \(id)") as? Int
      // If neither key exists, assume visible (item has a position but no toggle).
      // If a key exists with value 0, the item is hidden.
      if let v = visibleCC ?? visible, v == 0 { continue }

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
    return NSRect(
      x: cgRect.origin.x,
      y: primaryHeight - cgRect.origin.y - cgRect.height,
      width: cgRect.width,
      height: cgRect.height
    )
  }
}
