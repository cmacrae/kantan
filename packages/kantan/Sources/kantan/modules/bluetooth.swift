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
///
/// Bluetooth state is read on a background queue: IOBluetooth's first call
/// blocks until kantan's Bluetooth permission prompt is answered, and
/// `system_profiler` takes ~70ms. The icon renders from the last read.
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
  /// Bumped on each start/stop (main thread) so a read finishing after
  /// `stopObserving` doesn't register notifications.
  nonisolated(unsafe) private var observation = 0
  private let _notificationsLock = NSLock()
  private let readStatus: @Sendable () -> BluetoothStatus
  private let readQueue = DispatchQueue(label: "kantan.bluetooth.status")
  private let cache = CachedStatus<(connected: [String], total: Int)>(
    fallback: (connected: [], total: 0))

  init(
    icon: String, disabledIcon: String,
    readStatus: @escaping @Sendable () -> BluetoothStatus = {
      BluetoothConfig.readBluetoothStatus()
    }
  ) {
    self.icon = icon
    self.disabledIcon = disabledIcon
    self.readStatus = readStatus
    super.init()
  }

  deinit {
    stopObserving()
  }

  // MARK: - EventDrivenModule

  func startObserving(onChange: @escaping @Sendable () -> Void) {
    self.onChange = onChange
    observation += 1
    let current = observation

    // The first read initialises IOBluetooth, so registering afterwards
    // can't block the main thread on the permission prompt.
    refresh { [weak self] in
      guard let self, self.observation == current else { return }
      self.registerNotifications()
      self.onChange?()
    }
  }

  private func registerNotifications() {
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
    observation += 1
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
    refresh { [weak self] in self?.onChange?() }
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
    refresh { [weak self] in self?.onChange?() }
  }

  @objc private func powerStateChanged(_ notification: Notification) {
    // Reset disconnect notifications — IOKit state may have been invalidated
    // by the power cycle. Idempotent re-registration is safe even if a
    // connect callback races us, since ensureDisconnectRegistered dedupes
    // by address.
    clearDisconnectNotifications()
    registerDisconnectNotifications()

    refresh { [weak self] in self?.onChange?() }
  }

  /// Reads Bluetooth state on `readQueue` into the cache, then runs `then`
  /// on the main thread.
  func refresh(then: @escaping @Sendable () -> Void) {
    readQueue.async { [weak self] in
      guard let self else { return }
      let status = self.readStatus()
      self.cache.set(
        (
          connected: status.connectedDevices.map { $0.name },
          total: status.isPoweredOn ? status.pairedDevices.count : -1
        ))
      DispatchQueue.main.async(execute: then)
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

  // MARK: - ModuleConfiguration

  func getValue(completion: @escaping @Sendable (String) -> Void) {
    completion("")
  }

  func getIcon() -> String {
    cache.get().total < 0 ? disabledIcon : icon
  }

  /// Returns false when Bluetooth is on but no devices are connected,
  /// causing drawModule() to dim the icon (like inactive workspace indicators).
  func isActive() -> Bool {
    let cached = cache.get()
    if cached.total < 0 { return false }
    return !cached.connected.isEmpty
  }

  /// `{state}` is `Off`, `On` or `Connected`; `{devices}` lists the
  /// connected devices' names.
  func getTemplateVariables() -> [String: String] {
    let cached = cache.get()
    let state = cached.total < 0 ? "Off" : cached.connected.isEmpty ? "On" : "Connected"
    return ["state": state, "devices": cached.connected.joined(separator: ", ")]
  }

  // MARK: - IOBluetooth

  /// Reads current Bluetooth state.
  ///
  /// Power state comes from `IOBluetoothHostController` (fast, accurate).
  /// Per-device connection state comes from `system_profiler`, which queries
  /// `bluetoothd` via XPC and matches what System Settings shows. We avoid
  /// `IOBluetoothDevice.isConnected()` because the deprecated API returns
  /// stale `true` values for paired-but-disconnected devices on macOS Tahoe,
  /// leaving the bar icon stuck at full brightness when it should dim.
  /// `system_profiler` costs ~70ms and only runs on event-driven refreshes,
  /// off the main thread, so the overhead is acceptable.
  static func readBluetoothStatus() -> BluetoothStatus {
    guard let controller = IOBluetoothHostController.default() else {
      return .unavailable
    }

    let isPoweredOn = controller.powerState == kBluetoothHCIPowerStateON

    guard isPoweredOn else {
      return BluetoothStatus(isPoweredOn: false, pairedDevices: [])
    }

    return querySystemProfiler() ?? BluetoothStatus(isPoweredOn: true, pairedDevices: [])
  }

  // MARK: - system_profiler

  /// Invokes `system_profiler SPBluetoothDataType -json` and returns the
  /// parsed status, or nil if the call failed.
  private static func querySystemProfiler() -> BluetoothStatus? {
    // A system_profiler that hangs would hold up every later query.
    runCommandSync(
      path: "/usr/sbin/system_profiler", arguments: ["SPBluetoothDataType", "-json"],
      timeout: 15
    ).flatMap(parseSPBluetoothData)
  }

  /// Parse the JSON output of `system_profiler SPBluetoothDataType -json`
  /// into a `BluetoothStatus`. Returns nil only when the top-level shape is
  /// unrecognisable — an empty `device_connected` / `device_not_connected`
  /// is normal and yields a status with no devices.
  static func parseSPBluetoothData(_ data: Data) -> BluetoothStatus? {
    guard
      let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let entries = root["SPBluetoothDataType"] as? [[String: Any]],
      let first = entries.first
    else { return nil }

    let isPoweredOn: Bool = {
      guard let props = first["controller_properties"] as? [String: Any],
        let state = props["controller_state"] as? String
      else { return true }
      return state == "attrib_on"
    }()

    let connected = extractDevices(from: first["device_connected"], isConnected: true)
    let notConnected = extractDevices(from: first["device_not_connected"], isConnected: false)

    return BluetoothStatus(isPoweredOn: isPoweredOn, pairedDevices: connected + notConnected)
  }

  /// Each `device_connected` / `device_not_connected` entry is a single-key
  /// dictionary `{ "<device name>": { "device_address": ..., ... } }`.
  private static func extractDevices(from value: Any?, isConnected: Bool) -> [BluetoothDeviceInfo] {
    guard let array = value as? [[String: Any]] else { return [] }
    return array.flatMap { entry -> [BluetoothDeviceInfo] in
      entry.compactMap { name, props -> BluetoothDeviceInfo? in
        guard let props = props as? [String: Any],
          let address = props["device_address"] as? String
        else { return nil }
        return BluetoothDeviceInfo(
          name: name,
          address: address.lowercased(),
          isConnected: isConnected
        )
      }
    }
  }

}
