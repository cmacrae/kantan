import AppKit
import CoreGraphics
import Foundation

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
/// exists in the menu bar via `MenuBarItemDetector`. This is the same
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

  /// Maximum distance (in points) between a candidate item's actual
  /// rightEdgeDist and the plist preferred position for FocusModes.
  /// Must be large enough to handle position shifts (e.g. battery
  /// percentage expanding the battery indicator by ~25px) but small
  /// enough to reject the next item over when Focus is inactive
  /// (typical gap ≥ 38px). 35px satisfies both constraints.
  private static let focusPresenceTolerance: Double = 35.0

  private static let focusMask = MaskConfig(name: "Focus")

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
  /// the menu bar. Uses `MenuBarItemDetector.resolveItem` (which includes
  /// rank-based fallback for handling position shifts), then applies a
  /// tighter position check to distinguish "Focus active but shifted"
  /// from "Focus inactive, wrong item at that rank."
  private static func isFocusIndicatorVisible() -> Bool {
    guard let preferredPos = focusModesPreferredPosition,
      let screen = NSScreen.main
    else { return false }

    let items = MenuBarItemDetector.detectItems(for: screen)
    guard !items.isEmpty else { return false }

    // Use the shared resolver (includes rank-based fallback for shifts).
    guard let candidate = MenuBarItemDetector.resolveItem(for: focusMask, from: items) else {
      return false
    }

    // The resolver's rank-based fallback uses an 80px sanity check, which
    // is too loose for presence detection — when Focus is inactive the
    // next item over (~38px gap) would pass. Apply a tighter check:
    // the candidate must be within focusPresenceTolerance of the expected
    // position to confirm it's actually the FocusModes indicator.
    let effectiveRightEdge = items.map { Double($0.cgRect.maxX) }.max() ?? 0
    let candidateDist = effectiveRightEdge - Double(candidate.cgRect.maxX)
    return abs(candidateDist - preferredPos) < focusPresenceTolerance
  }
}
