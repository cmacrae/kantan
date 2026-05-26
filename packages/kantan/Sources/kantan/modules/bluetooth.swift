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
    let icon = yaml["icon"].string ?? Self.defaultIcon
    let disabledIcon = yaml["disabledIcon"].string ?? Self.defaultDisabledIcon

    return BluetoothConfig(icon: icon, disabledIcon: disabledIcon)
  }

  func defaultConfiguration() -> ModuleConfiguration? {
    BluetoothConfig(icon: Self.defaultIcon, disabledIcon: Self.defaultDisabledIcon)
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

}

/// Event-driven Bluetooth module using IOBluetooth notifications.
/// Registers for device connect/disconnect events and power state changes.
final class BluetoothConfig: NSObject, ModuleConfiguration, EventDrivenModule,
  @unchecked Sendable
{
  var type: String { "bluetooth" }
  let icon: String
  let disabledIcon: String

  var redrawInterval: TimeInterval { noPoll }

  nonisolated(unsafe) private var onChange: (@Sendable () -> Void)?
  nonisolated(unsafe) private var connectNotification: IOBluetoothUserNotification?
  nonisolated(unsafe) private var disconnectNotifications: [String: IOBluetoothUserNotification] =
    [:]
  private let _notificationsLock = NSLock()
  nonisolated(unsafe) private var _cachedStatus: (connected: [String], total: Int)?
  private let _statusLock = NSLock()

  init(icon: String, disabledIcon: String) {
    self.icon = icon
    self.disabledIcon = disabledIcon
    super.init()
  }

  deinit {
    stopObserving()
  }

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

    clearDisconnectNotifications()

    NotificationCenter.default.removeObserver(self)
    onChange = nil
  }

  // MARK: - IOBluetooth Notifications

  @objc private func deviceConnected(
    _ notification: IOBluetoothUserNotification, device: IOBluetoothDevice
  ) {
    ensureDisconnectRegistered(for: device)
    DispatchQueue.main.async { [weak self] in
      self?.onChange?()
    }
  }

  @objc private func deviceDisconnected(
    _ notification: IOBluetoothUserNotification, device: IOBluetoothDevice
  ) {
    if let address = device.addressString {
      _notificationsLock.lock()
      let notif = disconnectNotifications.removeValue(forKey: address)
      _notificationsLock.unlock()
      notif?.unregister()
    }
    DispatchQueue.main.async { [weak self] in
      self?.onChange?()
    }
  }

  @objc private func powerStateChanged(_ notification: Notification) {
    // Reset disconnect notifications — IOKit state may have been invalidated
    // by the power cycle. Idempotent re-registration is safe even if a
    // connect callback races us, since ensureDisconnectRegistered dedupes
    // by address.
    clearDisconnectNotifications()
    registerDisconnectNotifications()

    DispatchQueue.main.async { [weak self] in
      self?.onChange?()
    }
  }

  /// Register disconnect notifications on all currently paired devices.
  /// Idempotent — safe to call repeatedly without leaking registrations.
  private func registerDisconnectNotifications() {
    guard let devices = IOBluetoothDevice.pairedDevices() else { return }
    for item in devices {
      guard let device = item as? IOBluetoothDevice else { continue }
      ensureDisconnectRegistered(for: device)
    }
  }

  /// Registers a disconnect notification for `device` if one is not already
  /// tracked under its address. Uses a double-check around the IOKit call so
  /// that a racing concurrent caller doesn't leak a stray registration: the
  /// loser unregisters its duplicate before returning.
  private func ensureDisconnectRegistered(for device: IOBluetoothDevice) {
    guard let address = device.addressString else { return }
    _notificationsLock.lock()
    let alreadyTracked = disconnectNotifications[address] != nil
    _notificationsLock.unlock()
    if alreadyTracked { return }

    guard
      let notif = device.register(
        forDisconnectNotification: self,
        selector: #selector(deviceDisconnected(_:device:))
      )
    else { return }

    _notificationsLock.lock()
    if disconnectNotifications[address] == nil {
      disconnectNotifications[address] = notif
      _notificationsLock.unlock()
    } else {
      _notificationsLock.unlock()
      notif.unregister()
    }
  }

  /// Unregister and drop every tracked disconnect notification.
  private func clearDisconnectNotifications() {
    _notificationsLock.lock()
    let notifs = disconnectNotifications
    disconnectNotifications.removeAll()
    _notificationsLock.unlock()
    for (_, notif) in notifs {
      notif.unregister()
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
    completion("")
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
