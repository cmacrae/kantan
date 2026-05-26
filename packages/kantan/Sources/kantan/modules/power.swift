import Foundation
import IOKit.ps

/// Style override for a specific power state (charging, plugged, low).
/// Parsed from `config.style.<state>` — supports string shorthand (→ fg)
/// or expanded dict with fg/bg/icon.fg/text.fg.
struct PowerStateStyle: Sendable {
  let fg: String?
  let bg: String?
  let iconFg: String?
  let textFg: String?

  func toDynamicStyle() -> DynamicStyleOverride {
    DynamicStyleOverride(fg: fg, bg: bg, iconFg: iconFg, textFg: textFg)
  }

  static func parse(from yaml: Yaml) -> PowerStateStyle? {
    // Shorthand: string → fg
    if let str = yaml.string {
      return PowerStateStyle(fg: str, bg: nil, iconFg: nil, textFg: nil)
    }
    // Expanded: dict with fg/bg/icon.fg/text.fg
    guard yaml.dictionary != nil else { return nil }
    let fg = yaml["fg"].string
    let bg = yaml["bg"].string
    let iconFg = yaml["icon"]["fg"].string
    let textFg = yaml["text"]["fg"].string
    guard fg != nil || bg != nil || iconFg != nil || textFg != nil else { return nil }
    return PowerStateStyle(fg: fg, bg: bg, iconFg: iconFg, textFg: textFg)
  }
}

struct PowerConfigFactory: ModuleConfigurationFactory {
  /// Default tabler-icons for power/battery states.
  static let defaultChargingIcon = "bolt-filled"
  static let defaultPluggedIcon = "plug"
  static let defaultLevelIcons = [
    "battery-filled", "battery-1-filled", "battery-2-filled",
    "battery-3-filled", "battery-4-filled",
  ]
  static let defaultLowThreshold = 20

  func configuration(from yaml: Yaml, configDir: String?, theme: ThemeConfig?) throws
    -> ModuleConfiguration
  {
    let showLevel = yaml["showLevel"].bool ?? false
    let lowThreshold = yaml["lowThreshold"].int ?? Self.defaultLowThreshold

    let iconsYaml = yaml["icons"]
    let chargingIcon = iconsYaml["charging"].string ?? Self.defaultChargingIcon
    let pluggedIcon = iconsYaml["plugged"].string ?? Self.defaultPluggedIcon
    let levelIcons =
      iconsYaml["level"].array?.compactMap { $0.string } ?? Self.defaultLevelIcons

    guard !levelIcons.isEmpty else {
      throw DecodingError.dataCorrupted(
        DecodingError.Context(
          codingPath: [],
          debugDescription: "PowerConfig requires a non-empty 'icons.level' array"
        ))
    }

    let styleYaml = yaml["style"]
    let chargingStyle = PowerStateStyle.parse(from: styleYaml["charging"])
    let pluggedStyle = PowerStateStyle.parse(from: styleYaml["plugged"])
    let lowPowerModeStyle = PowerStateStyle.parse(from: styleYaml["lowPowerMode"])
    let lowStyle = PowerStateStyle.parse(from: styleYaml["low"])

    return PowerConfig(
      showLevel: showLevel, lowThreshold: lowThreshold,
      levelIcons: levelIcons, chargingIcon: chargingIcon, pluggedIcon: pluggedIcon,
      chargingStyle: chargingStyle, pluggedStyle: pluggedStyle,
      lowPowerModeStyle: lowPowerModeStyle, lowStyle: lowStyle
    )
  }

  func defaultConfiguration() -> ModuleConfiguration? {
    PowerConfig(
      showLevel: false, lowThreshold: Self.defaultLowThreshold,
      levelIcons: Self.defaultLevelIcons,
      chargingIcon: Self.defaultChargingIcon, pluggedIcon: Self.defaultPluggedIcon,
      chargingStyle: nil, pluggedStyle: nil, lowPowerModeStyle: nil, lowStyle: nil
    )
  }
}

struct BatteryStatus: Sendable {
  let level: Int
  let isCharging: Bool
  let isPluggedIn: Bool
  let isLowPowerMode: Bool

  static let unavailable = BatteryStatus(
    level: -1, isCharging: false, isPluggedIn: false, isLowPowerMode: false)
  var isAvailable: Bool { level >= 0 }
}

/// Event-driven battery module using IOKit power source notifications.
/// Registers a CFRunLoopSource that fires only when the system's power
/// state actually changes (plug/unplug, charge level change, etc.).
final class PowerConfig: ModuleConfiguration, EventDrivenModule {
  var type: String { "power" }
  let showLevel: Bool
  let lowThreshold: Int
  let levelIcons: [String]
  let chargingIcon: String
  let pluggedIcon: String
  let chargingStyle: PowerStateStyle?
  let pluggedStyle: PowerStateStyle?
  let lowPowerModeStyle: PowerStateStyle?
  let lowStyle: PowerStateStyle?

  var redrawInterval: TimeInterval { noPoll }

  nonisolated(unsafe) private var runLoopSource: CFRunLoopSource?
  nonisolated(unsafe) private var onChange: (@Sendable () -> Void)?
  nonisolated(unsafe) private var lowPowerObserver: NSObjectProtocol?
  nonisolated(unsafe) private var _cachedStatus: BatteryStatus?
  private let _statusLock = NSLock()

  init(
    showLevel: Bool, lowThreshold: Int,
    levelIcons: [String], chargingIcon: String, pluggedIcon: String,
    chargingStyle: PowerStateStyle?, pluggedStyle: PowerStateStyle?,
    lowPowerModeStyle: PowerStateStyle?, lowStyle: PowerStateStyle?
  ) {
    self.showLevel = showLevel
    self.lowThreshold = lowThreshold
    self.levelIcons = levelIcons
    self.chargingIcon = chargingIcon
    self.pluggedIcon = pluggedIcon
    self.chargingStyle = chargingStyle
    self.pluggedStyle = pluggedStyle
    self.lowPowerModeStyle = lowPowerModeStyle
    self.lowStyle = lowStyle
  }

  deinit {
    stopObserving()
  }

  // MARK: - EventDrivenModule

  func startObserving(onChange: @escaping @Sendable () -> Void) {
    self.onChange = onChange

    let context = Unmanaged.passUnretained(self).toOpaque()
    if let source = IOPSNotificationCreateRunLoopSource(
      { context in
        guard let context = context else { return }
        let config = Unmanaged<PowerConfig>.fromOpaque(context).takeUnretainedValue()
        config.onChange?()
      },
      context
    )?.takeRetainedValue() {
      self.runLoopSource = source
      CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
    }

    // Listen for Low Power Mode changes
    lowPowerObserver = NotificationCenter.default.addObserver(
      forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main
    ) { [weak self] _ in
      self?.onChange?()
    }
  }

  func stopObserving() {
    if let source = runLoopSource {
      CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .defaultMode)
      runLoopSource = nil
    }
    if let observer = lowPowerObserver {
      NotificationCenter.default.removeObserver(observer)
      lowPowerObserver = nil
    }
    onChange = nil
  }

  // MARK: - Status Caching

  private func refreshCache() {
    let status = Self.readBatteryStatus()
    _statusLock.lock()
    _cachedStatus = status
    _statusLock.unlock()
  }

  private func getCachedStatus() -> BatteryStatus {
    _statusLock.lock()
    defer { _statusLock.unlock() }
    return _cachedStatus ?? .unavailable
  }

  // MARK: - ModuleConfiguration

  func getValue(completion: @escaping @Sendable (String) -> Void) {
    let status = getCachedStatus()
    guard status.isAvailable else {
      completion("")
      return
    }
    completion(showLevel ? "\(status.level)%" : "")
  }

  func getIcon() -> String {
    refreshCache()
    let status = getCachedStatus()
    guard status.isAvailable else {
      return levelIcons.first ?? ""
    }
    if status.isCharging {
      return chargingIcon
    }
    if status.isPluggedIn {
      return pluggedIcon
    }
    return iconForLevel(status.level, icons: levelIcons)
  }

  func getDynamicStyle() -> DynamicStyleOverride? {
    let status = getCachedStatus()
    guard status.isAvailable else { return nil }
    // Priority: charging > plugged > lowPower > low
    if status.isCharging, let style = chargingStyle {
      return style.toDynamicStyle()
    }
    if status.isPluggedIn, let style = pluggedStyle {
      return style.toDynamicStyle()
    }
    if !status.isPluggedIn && status.isLowPowerMode, let style = lowPowerModeStyle {
      return style.toDynamicStyle()
    }
    if !status.isPluggedIn && status.level < lowThreshold, let style = lowStyle {
      return style.toDynamicStyle()
    }
    return nil
  }

  // MARK: - IOKit

  static func readBatteryStatus() -> BatteryStatus {
    guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
      let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFDictionary]
    else {
      return .unavailable
    }

    for source in sources {
      guard let sourceDict = source as? [String: Any] else { continue }

      guard let currentCapacity = sourceDict[kIOPSCurrentCapacityKey as String] as? Int,
        let maxCapacity = sourceDict[kIOPSMaxCapacityKey as String] as? Int,
        maxCapacity > 0
      else {
        continue
      }

      let level = (currentCapacity * 100) / maxCapacity
      let isCharging = (sourceDict[kIOPSIsChargingKey as String] as? Bool) ?? false
      let powerSourceState = sourceDict[kIOPSPowerSourceStateKey as String] as? String
      let isPluggedIn = (powerSourceState == kIOPSACPowerValue as String)
      let isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled

      return BatteryStatus(
        level: level, isCharging: isCharging, isPluggedIn: isPluggedIn,
        isLowPowerMode: isLowPowerMode)
    }

    return .unavailable
  }
}
