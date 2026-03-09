import AppKit
import CoreGraphics
import Foundation

struct NativeMenuBarItem {
    let index: Int
    let cgRect: CGRect
    let owner: String
}

struct MenuBarItemDetector {
    /// User-friendly aliases for Control Center item names.
    /// Maps user-facing config names to the internal plist identifier
    /// used in `NSStatusItem Preferred Position <identifier>`.
    private static let nameAliases: [String: String] = [
        "ControlCenter": "BentoBox-0",
        "Volume": "Sound",
        "Camera": "AudioVideoModule",
        "Microphone": "AudioVideoModule",
    ]

    /// Query native menu bar items on the primary screen.
    /// Returns items sorted right-to-left (index 0 = rightmost).
    static func detectItems(excludingOwner: String = "kantan") -> [NativeMenuBarItem] {
        let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        let statusLevel = Int(CGWindowLevelForKey(.statusWindow))

        var items: [(x: CGFloat, w: CGFloat, h: CGFloat, owner: String)] = []

        for window in windowList {
            let level = window[kCGWindowLayer as String] as? Int ?? -999
            guard level == statusLevel else { continue }

            let owner = window[kCGWindowOwnerName as String] as? String ?? ""
            guard owner != excludingOwner else { continue }

            let bounds = window[kCGWindowBounds as String] as? [String: Any] ?? [:]
            let x = (bounds["X"] as? NSNumber)?.doubleValue ?? 0
            let y = (bounds["Y"] as? NSNumber)?.doubleValue ?? 0
            let w = (bounds["Width"] as? NSNumber)?.doubleValue ?? 0
            let h = (bounds["Height"] as? NSNumber)?.doubleValue ?? 0

            // Primary screen only (CG Y=0 at top, so primary screen items have Y=0)
            guard y == 0 && x >= 0 else { continue }

            items.append((x: CGFloat(x), w: CGFloat(w), h: CGFloat(h), owner: owner))
        }

        // Sort right-to-left (descending X)
        items.sort { $0.x > $1.x }

        return items.enumerated().map { (i, item) in
            NativeMenuBarItem(
                index: i,
                cgRect: CGRect(x: item.x, y: 0, width: item.w, height: item.h),
                owner: item.owner
            )
        }
    }

    /// Resolve a MaskConfig to a specific native menu bar item.
    /// Supports index-based lookup (mask.index) and name-based lookup (mask.name).
    ///
    /// Name-based lookup reads `NSStatusItem Preferred Position <Name>` from the
    /// `com.apple.controlcenter` defaults. The value is the distance in points from
    /// the effective right edge of the menu bar to the item's right edge. We match
    /// this against each detected window's computed rightEdgeDist.
    ///
    /// User-friendly aliases are supported (e.g. "ControlCenter" → "BentoBox-0",
    /// "Volume" → "Sound"). The raw plist names also work directly.
    ///
    /// "Clock" is handled specially: it has no preferred position in the plist,
    /// but when enabled it is identifiable as the Control Centre window at
    /// rightEdgeDist=0 (the rightmost position, occupied by the clock when
    /// the menu bar clock is visible).
    static func resolveItem(for mask: MaskConfig, from items: [NativeMenuBarItem]) -> NativeMenuBarItem? {
        if let index = mask.index {
            guard index >= 0 && index < items.count else { return nil }
            return items[index]
        }

        guard let name = mask.name else { return nil }

        // Resolve aliases to plist identifiers
        let plistName = nameAliases[name] ?? name

        // Special case: Clock has no preferred position in the plist.
        // When the clock is enabled, it occupies the rightmost position
        // — the item at index 0 in our right-to-left sorted array.
        if plistName == "Clock" {
            if let defaults = UserDefaults(suiteName: "com.apple.controlcenter"),
               let clockVisible = defaults.object(forKey: "NSStatusItem VisibleCC Clock") as? Int,
               clockVisible != 0,
               let firstItem = items.first {
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
        let effectiveRightEdge = items.map { Double($0.cgRect.origin.x + $0.cgRect.width) }.max() ?? 0

        if let defaults = UserDefaults(suiteName: "com.apple.controlcenter") {
            let key = "NSStatusItem Preferred Position \(plistName)"
            if let preferredPos = defaults.object(forKey: key) as? Double {
                for item in items {
                    let rightEdgeDist = effectiveRightEdge - Double(item.cgRect.origin.x) - Double(item.cgRect.width)
                    if abs(rightEdgeDist - preferredPos) < 3.0 {
                        return item
                    }
                }
            }
        }

        return nil
    }

    /// Convert CG rect to AppKit screen coordinates.
    static func appKitRect(from cgRect: CGRect, screenHeight: CGFloat) -> NSRect {
        NSRect(
            x: cgRect.origin.x,
            y: screenHeight - cgRect.origin.y - cgRect.height,
            width: cgRect.width,
            height: cgRect.height
        )
    }
}
