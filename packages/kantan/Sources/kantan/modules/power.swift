import Foundation
import IOKit.ps

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
    let chargingStyle = StateStyle.parse(from: styleYaml["charging"])
    let pluggedStyle = StateStyle.parse(from: styleYaml["plugged"])
    let lowPowerModeStyle = StateStyle.parse(from: styleYaml["lowPowerMode"])
    let lowStyle = StateStyle.parse(from: styleYaml["low"])

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
  let chargingStyle: StateStyle?
  let pluggedStyle: StateStyle?
  let lowPowerModeStyle: StateStyle?
  let lowStyle: StateStyle?

  var redrawInterval: TimeInterval { noPoll }

  nonisolated(unsafe) private var runLoopSource: CFRunLoopSource?
  nonisolated(unsafe) private var onChange: (@Sendable () -> Void)?
  nonisolated(unsafe) private var lowPowerObserver: NSObjectProtocol?
  private let cache = CachedStatus<BatteryStatus>(fallback: .unavailable)

  init(
    showLevel: Bool, lowThreshold: Int,
    levelIcons: [String], chargingIcon: String, pluggedIcon: String,
    chargingStyle: StateStyle?, pluggedStyle: StateStyle?,
    lowPowerModeStyle: StateStyle?, lowStyle: StateStyle?
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

  // MARK: - ModuleConfiguration

  func getValue(completion: @escaping @Sendable (String) -> Void) {
    let status = cache.get()
    guard status.isAvailable else {
      completion("")
      return
    }
    completion(showLevel ? "\(status.level)%" : "")
  }

  func getIcon() -> String {
    cache.set(Self.readBatteryStatus())
    let status = cache.get()
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
    let status = cache.get()
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

  func getTemplateVariables() -> [String: String] {
    Self.templateVariables(for: cache.get())
  }

  /// `{level}` is the battery level (0–100) and `{state}` is `Charging`,
  /// `Plugged` or `Discharging`. Both are empty without a battery.
  static func templateVariables(for status: BatteryStatus) -> [String: String] {
    guard status.isAvailable else { return ["level": "", "state": ""] }
    let state = status.isCharging ? "Charging" : status.isPluggedIn ? "Plugged" : "Discharging"
    return ["level": "\(status.level)", "state": state]
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
