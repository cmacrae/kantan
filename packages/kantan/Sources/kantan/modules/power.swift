import Foundation
import IOKit.ps
import Yaml

struct PowerConfigFactory: ModuleConfigurationFactory {
  /// Default tabler-icons for power/battery states.
  static let defaultChargingIcon = "bolt-filled"
  static let defaultBatteryIcons = [
    "battery-filled", "battery-1-filled", "battery-2-filled",
    "battery-3-filled", "battery-4-filled",
  ]

  func configuration(from yaml: Yaml, configDir: String?, theme: ThemeConfig?) throws
    -> ModuleConfiguration
  {
    let showLevel = yaml["showLevel"].bool ?? false

    let chargingIcon =
      yaml["charging"].dictionary?["icon"]?.string ?? Self.defaultChargingIcon
    let batteryIcons =
      yaml["battery"].dictionary?["icons"]?.array?.compactMap({ $0.string })
      ?? Self.defaultBatteryIcons

    guard !batteryIcons.isEmpty else {
      throw DecodingError.dataCorrupted(
        DecodingError.Context(
          codingPath: [],
          debugDescription: "PowerConfig requires a non-empty 'battery.icons' array"
        ))
    }

    let chargingConfig = ChargingConfig(icon: chargingIcon)
    let batteryConfig = BatteryConfig(icons: batteryIcons)

    return PowerConfig(showLevel: showLevel, charging: chargingConfig, battery: batteryConfig)
  }

  func defaultConfiguration() -> ModuleConfiguration? {
    PowerConfig(
      showLevel: false,
      charging: ChargingConfig(icon: Self.defaultChargingIcon),
      battery: BatteryConfig(icons: Self.defaultBatteryIcons)
    )
  }
}

struct BatteryStatus: Sendable {
  let level: Int
  let isCharging: Bool
  let isPluggedIn: Bool

  static let unavailable = BatteryStatus(level: -1, isCharging: false, isPluggedIn: false)
  var isAvailable: Bool { level >= 0 }
}

/// Event-driven battery module using IOKit power source notifications.
/// Instead of polling every 5s, registers a CFRunLoopSource that fires
/// only when the system's power state actually changes (plug/unplug,
/// charge level change, etc.).
final class PowerConfig: ModuleConfiguration, EventDrivenModule {
  var type: String { "power" }
  let showLevel: Bool
  let charging: ChargingConfig
  let battery: BatteryConfig

  var redrawInterval: TimeInterval { 0 }

  nonisolated(unsafe) private var runLoopSource: CFRunLoopSource?
  nonisolated(unsafe) private var onChange: (@Sendable () -> Void)?
  nonisolated(unsafe) private var _cachedStatus: BatteryStatus?
  private let _statusLock = NSLock()

  init(showLevel: Bool, charging: ChargingConfig, battery: BatteryConfig) {
    self.showLevel = showLevel
    self.charging = charging
    self.battery = battery
  }

  required init(from decoder: Decoder) throws {
    self.showLevel = false
    self.charging = ChargingConfig(icon: "")
    self.battery = BatteryConfig(icons: [])
  }

  func encode(to encoder: Encoder) throws {}

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
  }

  func stopObserving() {
    if let source = runLoopSource {
      CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .defaultMode)
      runLoopSource = nil
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
      return battery.icons.first ?? ""
    }
    if status.isCharging || status.isPluggedIn {
      return charging.icon
    }
    return iconForLevel(status.level, icons: battery.icons)
  }

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

      return BatteryStatus(level: level, isCharging: isCharging, isPluggedIn: isPluggedIn)
    }

    return .unavailable
  }
}

struct ChargingConfig: Codable, Sendable {
  let icon: String
}

struct BatteryConfig: Codable, Sendable {
  let icons: [String]
}
