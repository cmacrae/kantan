import AppKit
import Foundation
import IOBluetooth
import Yaml

struct BluetoothConfigFactory: ModuleConfigurationFactory {
  /// Default tabler-icons for bluetooth states.
  static let defaultIcon = "bluetooth"
  static let defaultDisabledIcon = "bluetooth-off"

  func configuration(from yaml: Yaml, configDir: String?) throws -> ModuleConfiguration {
    let showCount = yaml["showCount"].bool ?? false
    let icon = yaml["icon"].string ?? Self.defaultIcon
    let disabledIcon = yaml["disabledIcon"].string ?? Self.defaultDisabledIcon

    return BluetoothConfig(showCount: showCount, icon: icon, disabledIcon: disabledIcon)
  }

  func defaultConfiguration() -> ModuleConfiguration? {
    BluetoothConfig(
      showCount: false, icon: Self.defaultIcon, disabledIcon: Self.defaultDisabledIcon)
  }
}

struct BluetoothDeviceInfo: Sendable {
  let name: String
  let address: String
  let isConnected: Bool
  let majorClass: UInt32
  let minorClass: UInt32
}

struct BluetoothStatus: Sendable {
  let isPoweredOn: Bool
  let pairedDevices: [BluetoothDeviceInfo]

  static let unavailable = BluetoothStatus(isPoweredOn: false, pairedDevices: [])

  var connectedDevices: [BluetoothDeviceInfo] {
    pairedDevices.filter { $0.isConnected }
  }

  var connectedCount: Int { connectedDevices.count }
  var hasConnectedDevices: Bool { connectedCount > 0 }
}

final class BluetoothConfig: ModuleConfiguration, @unchecked Sendable {
  var type: String { "bluetooth" }
  let showCount: Bool
  let icon: String
  let disabledIcon: String

  var redrawInterval: TimeInterval { 5.0 }

  nonisolated(unsafe) private var _cachedStatus: (connected: [String], total: Int)?
  private let _statusLock = NSLock()

  init(showCount: Bool, icon: String, disabledIcon: String) {
    self.showCount = showCount
    self.icon = icon
    self.disabledIcon = disabledIcon
  }

  required init(from decoder: Decoder) throws {
    self.showCount = false
    self.icon = ""
    self.disabledIcon = ""
  }

  func encode(to encoder: Encoder) throws {}

  private func getCachedStatus() -> (connected: [String], total: Int) {
    _statusLock.lock()
    defer { _statusLock.unlock() }
    return _cachedStatus ?? (connected: [], total: 0)
  }

  private func refreshCache() {
    let status = Self.readBluetoothStatus()
    let connectedNames = status.connectedDevices.map { $0.name }
    let total = status.isPoweredOn ? status.pairedDevices.count : -1
    _statusLock.lock()
    _cachedStatus = (connected: connectedNames, total: total)
    _statusLock.unlock()
  }

  func getValue(completion: @escaping @Sendable (String) -> Void) {
    refreshCache()
    let cached = getCachedStatus()
    if showCount && !cached.connected.isEmpty {
      completion("\(cached.connected.count)")
    } else {
      completion("")
    }
  }

  func getIcon() -> String {
    let cached = getCachedStatus()
    if cached.total < 0 {
      return disabledIcon
    }
    return icon
  }

  /// Returns false when Bluetooth is on but no devices are connected,
  /// causing drawModule() to dim the icon (like inactive workspace indicators).
  func isActive() -> Bool {
    let cached = getCachedStatus()
    if cached.total < 0 { return false }
    return !cached.connected.isEmpty
  }

  // MARK: - IOBluetooth

  static func readBluetoothStatus() -> BluetoothStatus {
    guard let controller = IOBluetoothHostController.default() else {
      return .unavailable
    }

    let isPoweredOn = controller.powerState == kBluetoothHCIPowerStateON

    guard isPoweredOn else {
      return BluetoothStatus(isPoweredOn: false, pairedDevices: [])
    }

    guard let devices = IOBluetoothDevice.pairedDevices() else {
      return BluetoothStatus(isPoweredOn: true, pairedDevices: [])
    }

    let infos: [BluetoothDeviceInfo] = devices.compactMap { item in
      guard let device = item as? IOBluetoothDevice else { return nil }
      return BluetoothDeviceInfo(
        name: device.nameOrAddress ?? "Unknown",
        address: device.addressString ?? "",
        isConnected: device.isConnected(),
        majorClass: device.deviceClassMajor,
        minorClass: device.deviceClassMinor
      )
    }

    return BluetoothStatus(isPoweredOn: true, pairedDevices: infos)
  }

}
