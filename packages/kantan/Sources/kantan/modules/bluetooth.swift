import AppKit
import Foundation
import IOBluetooth

struct BluetoothConfigFactory: ModuleConfigurationFactory {
  /// Default tabler-icons for bluetooth states.
  static let defaultIcon = "bluetooth"
  static let defaultDisabledIcon = "bluetooth-off"

  func configuration(from yaml: Yaml, configDir: String?, theme: ThemeConfig?) throws
    -> ModuleConfiguration
  {
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

/// Event-driven Bluetooth module using IOBluetooth notifications.
/// Registers for device connect/disconnect events and power state changes.
final class BluetoothConfig: NSObject, ModuleConfiguration, EventDrivenModule,
  @unchecked Sendable
{
  var type: String { "bluetooth" }
  let showCount: Bool
  let icon: String
  let disabledIcon: String

  var redrawInterval: TimeInterval { 0 }

  nonisolated(unsafe) private var onChange: (@Sendable () -> Void)?
  nonisolated(unsafe) private var connectNotification: IOBluetoothUserNotification?
  nonisolated(unsafe) private var disconnectNotifications: [IOBluetoothUserNotification] = []
  nonisolated(unsafe) private var _cachedStatus: (connected: [String], total: Int)?
  private let _statusLock = NSLock()

  init(showCount: Bool, icon: String, disabledIcon: String) {
    self.showCount = showCount
    self.icon = icon
    self.disabledIcon = disabledIcon
    super.init()
  }

  required init(from decoder: Decoder) throws {
    self.showCount = false
    self.icon = ""
    self.disabledIcon = ""
    super.init()
  }

  deinit {
    stopObserving()
  }

  func encode(to encoder: Encoder) throws {}

  // MARK: - EventDrivenModule

  func startObserving(onChange: @escaping @Sendable () -> Void) {
    self.onChange = onChange

    // Listen for any Bluetooth device connecting
    connectNotification = IOBluetoothDevice.register(
      forConnectNotifications: self,
      selector: #selector(deviceConnected(_:device:))
    )

    // Register disconnect notifications on all currently paired devices
    registerDisconnectNotifications()

    // Listen for Bluetooth power state changes
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(powerStateChanged),
      name: .IOBluetoothHostControllerPoweredOn,
      object: nil
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(powerStateChanged),
      name: .IOBluetoothHostControllerPoweredOff,
      object: nil
    )
  }

  func stopObserving() {
    connectNotification?.unregister()
    connectNotification = nil

    for notif in disconnectNotifications {
      notif.unregister()
    }
    disconnectNotifications.removeAll()

    NotificationCenter.default.removeObserver(self)
    onChange = nil
  }

  // MARK: - IOBluetooth Notifications

  @objc private func deviceConnected(
    _ notification: IOBluetoothUserNotification, device: IOBluetoothDevice
  ) {
    // Register for this device's future disconnect
    if let notif = device.register(
      forDisconnectNotification: self,
      selector: #selector(deviceDisconnected(_:device:))
    ) {
      disconnectNotifications.append(notif)
    }
    DispatchQueue.main.async { [weak self] in
      self?.onChange?()
    }
  }

  @objc private func deviceDisconnected(
    _ notification: IOBluetoothUserNotification, device: IOBluetoothDevice
  ) {
    DispatchQueue.main.async { [weak self] in
      self?.onChange?()
    }
  }

  @objc private func powerStateChanged(_ notification: Notification) {
    // Re-register disconnect notifications since device list may have changed
    for notif in disconnectNotifications {
      notif.unregister()
    }
    disconnectNotifications.removeAll()
    registerDisconnectNotifications()

    DispatchQueue.main.async { [weak self] in
      self?.onChange?()
    }
  }

  /// Register disconnect notifications on all currently paired devices.
  private func registerDisconnectNotifications() {
    guard let devices = IOBluetoothDevice.pairedDevices() else { return }
    for item in devices {
      guard let device = item as? IOBluetoothDevice else { continue }
      if let notif = device.register(
        forDisconnectNotification: self,
        selector: #selector(deviceDisconnected(_:device:))
      ) {
        disconnectNotifications.append(notif)
      }
    }
  }

  // MARK: - Status Caching

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

  // MARK: - ModuleConfiguration

  func getValue(completion: @escaping @Sendable (String) -> Void) {
    let cached = getCachedStatus()
    if showCount && !cached.connected.isEmpty {
      completion("\(cached.connected.count)")
    } else {
      completion("")
    }
  }

  func getIcon() -> String {
    refreshCache()
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
