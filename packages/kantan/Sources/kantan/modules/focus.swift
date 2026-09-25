import AppKit
import CoreGraphics
import Foundation

struct FocusConfigFactory: ModuleConfigurationFactory {
  func configuration(from yaml: Yaml, configDir: String?, theme: ThemeConfig?) throws
    -> ModuleConfiguration
  {
    var icons: [String: String] = [:]
    for (key, value) in yaml["icons"].dictionary ?? [:] {
      if let mode = key.string, let icon = value.string {
        icons[mode] = icon
      }
    }
    var styles: [String: StateStyle] = [:]
    for (key, value) in yaml["style"].dictionary ?? [:] {
      if let mode = key.string, let style = StateStyle.parse(from: value) {
        styles[mode] = style
      }
    }
    return FocusConfig(icons: icons, styles: styles)
  }

  func defaultConfiguration() -> ModuleConfiguration? {
    FocusConfig(icons: [:], styles: [:])
  }
}

/// Focus state as last observed: whether Focus is on and, when known, which mode.
struct FocusStatus: Equatable, Sendable {
  let isActive: Bool
  let mode: FocusMode?

  static let inactive = FocusStatus(isActive: false, mode: nil)
}

/// Focus module showing whether a Focus mode is active, and which one.
///
/// With Full Disk Access, state comes from the Do Not Disturb database
/// (`FocusDatabase`), which names the active mode. Otherwise the module
/// falls back to detecting the system FocusModes menu bar indicator via
/// `MenuBarItemDetector`, which reports presence only.
final class FocusConfig: ModuleConfiguration, @unchecked Sendable {
  var type: String { "focus" }

  /// Polled every 2s. Scheduled Focus starts and ends without any file or
  /// notification event, and both sources are cheap to read.
  var redrawInterval: TimeInterval { 2.0 }

  /// Mode name or identifier → icon. Unmatched modes use the module icon.
  let icons: [String: String]
  /// Mode name or identifier → style. Unmatched modes use the module style.
  let styles: [String: StateStyle]

  private let cache = CachedStatus<FocusStatus>(fallback: .inactive)

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

  init(icons: [String: String], styles: [String: StateStyle]) {
    self.icons = icons
    self.styles = styles
  }

  /// Entry configured for a mode, matched by name then identifier.
  static func entry<Value>(for mode: FocusMode?, in map: [String: Value]) -> Value? {
    guard let mode else { return nil }
    return map[mode.name] ?? map[mode.identifier]
  }

  private func refreshCache() {
    if FullDiskAccess.isGranted, let database = FocusDatabase.load() {
      let mode = database.activeMode(at: Date())
      cache.set(FocusStatus(isActive: mode != nil, mode: mode))
    } else {
      cache.set(FocusStatus(isActive: Self.isFocusIndicatorVisible(), mode: nil))
    }
  }

  // MARK: - ModuleConfiguration

  func shouldDisplay() -> Bool {
    cache.get().isActive
  }

  func getValue(completion: @escaping @Sendable (String) -> Void) {
    completion("")
  }

  /// Refreshes the cached status (called before the other accessors on each
  /// update). An empty result falls back to the module-level `icon`.
  func getIcon() -> String {
    refreshCache()
    return Self.entry(for: cache.get().mode, in: icons) ?? ""
  }

  func getDynamicStyle() -> DynamicStyleOverride? {
    Self.entry(for: cache.get().mode, in: styles)?.toDynamicStyle()
  }

  func getTemplateVariables() -> [String: String] {
    ["mode": cache.get().mode?.name ?? ""]
  }

  // MARK: - Focus Indicator Detection

  /// Checks whether the system FocusModes indicator is present in the menu
  /// bar. Uses `MenuBarItemDetector.resolveItem` (which includes rank-based
  /// fallback for handling position shifts), then applies a tighter position
  /// check to distinguish "Focus active but shifted" from "Focus inactive,
  /// wrong item at that rank."
  ///
  /// On macOS 27+ items come from MenuBarAgent's persisted layout and are
  /// matched by identifier, so a match is the FocusModes slot itself. That
  /// layout records the slot but not whether it is currently drawn.
  private static func isFocusIndicatorVisible() -> Bool {
    guard let screen = NSScreen.main else { return false }

    let items = MenuBarItemDetector.detectItems(for: screen)

    // Use the shared resolver (includes rank-based fallback for shifts).
    guard let candidate = MenuBarItemDetector.resolveItem(for: focusMask, from: items) else {
      return false
    }
    if candidate.identifier != nil { return true }

    guard let preferredPos = focusModesPreferredPosition else { return false }

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
