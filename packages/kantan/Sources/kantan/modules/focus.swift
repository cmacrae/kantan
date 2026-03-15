import CoreGraphics
import Foundation
import Yaml

struct FocusConfigFactory: ModuleConfigurationFactory {
  func configuration(from yaml: Yaml, configDir: String?, theme: ThemeConfig?) throws
    -> ModuleConfiguration
  {
    FocusConfig()
  }
}

/// Focus module using menu bar indicator detection.
///
/// macOS Tahoe removed the `_NSDoNotDisturbEnabledNotification` /
/// `_NSDoNotDisturbDisabledNotification` distributed notifications, so
/// event-driven detection is not possible. Instead, this module detects
/// focus state by checking whether the system FocusModes indicator window
/// exists in the menu bar via `CGWindowListCopyWindowInfo`. This is the same
/// mechanism kantan uses for menu bar masking — fast (~1ms) and requires
/// no permissions.
final class FocusConfig: ModuleConfiguration, @unchecked Sendable {
  var type: String { "focus" }

  /// Poll every 2s. Focus toggles are infrequent; this is the same interval
  /// bluetooth uses, and CGWindowListCopyWindowInfo is very fast (~1ms).
  var redrawInterval: TimeInterval { 2.0 }

  nonisolated(unsafe) private var _cachedActive: Bool = false
  private let _lock = NSLock()

  /// Cached preferred position for the FocusModes indicator, read once
  /// from `com.apple.controlcenter` defaults.
  private static let focusModesPreferredPosition: Double? = {
    let defaults = UserDefaults(suiteName: "com.apple.controlcenter")
    return defaults?.object(forKey: "NSStatusItem Preferred Position FocusModes") as? Double
  }()

  /// Tolerance in points for matching preferred position to detected item.
  private static let positionTolerance: Double = 3.0

  init() {}

  required init(from decoder: Decoder) throws {}

  func encode(to encoder: Encoder) throws {}

  // MARK: - Status Caching

  private func refreshCache() {
    let active = Self.isFocusIndicatorVisible()
    _lock.lock()
    _cachedActive = active
    _lock.unlock()
  }

  private func getCachedActive() -> Bool {
    _lock.lock()
    defer { _lock.unlock() }
    return _cachedActive
  }

  // MARK: - ModuleConfiguration

  func shouldDisplay() -> Bool {
    getCachedActive()
  }

  func getValue(completion: @escaping @Sendable (String) -> Void) {
    completion("")
  }

  func getIcon() -> String {
    refreshCache()
    // Return empty string — the module-level `icon` from config is used
    // as the display icon by ModuleViewModel's standard fallback path.
    return ""
  }

  // MARK: - Focus Indicator Detection

  /// Checks whether the system FocusModes indicator window is present in
  /// the menu bar by scanning CGWindowList for a Control Centre status-bar
  /// window at the FocusModes preferred position.
  /// Fast (~1ms), no permissions required.
  private static func isFocusIndicatorVisible() -> Bool {
    guard let preferredPos = focusModesPreferredPosition else { return false }

    let windowList =
      CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
    let statusLevel = Int(CGWindowLevelForKey(.statusWindow))

    var items: [(maxX: Double, owner: String)] = []

    for window in windowList {
      let level = window[kCGWindowLayer as String] as? Int ?? -999
      guard level == statusLevel else { continue }

      let owner = window[kCGWindowOwnerName as String] as? String ?? ""
      guard owner != "kantan" else { continue }

      guard let boundsDict = window[kCGWindowBounds as String] as? NSDictionary,
        let bounds = CGRect(dictionaryRepresentation: boundsDict)
      else { continue }
      // Only menu bar items (top of primary screen, y ≈ 0)
      guard bounds.origin.y < 30 else { continue }
      items.append((maxX: Double(bounds.maxX), owner: owner))
    }

    guard !items.isEmpty else { return false }

    let effectiveRightEdge = items.map(\.maxX).max() ?? 0

    for item in items {
      let rightEdgeDist = effectiveRightEdge - item.maxX
      if abs(rightEdgeDist - preferredPos) < positionTolerance {
        return true
      }
    }

    return false
  }
}
