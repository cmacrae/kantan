import AppKit
import CoreWLAN
import Foundation
import IOKit
import Network

struct WiFiConfigFactory: ModuleConfigurationFactory {
  /// Default tabler-icons for wifi states.
  static let defaultStrengthIcons = ["wifi-1", "wifi-2", "wifi"]
  static let defaultDisconnectedIcon = "wifi-off"
  static let defaultHotspotIcon = "circles-relation"

  func configuration(from yaml: Yaml, configDir: String?, theme: ThemeConfig?) throws
    -> ModuleConfiguration
  {
    let iconsYaml = yaml["icons"]
    let disconnectedIcon = iconsYaml["disconnected"].string ?? Self.defaultDisconnectedIcon
    let strengthIcons =
      iconsYaml["strength"].array?.compactMap { $0.string } ?? Self.defaultStrengthIcons

    guard !strengthIcons.isEmpty else {
      throw DecodingError.dataCorrupted(
        DecodingError.Context(
          codingPath: [],
          debugDescription: "WiFiConfig requires a non-empty 'icons.strength' array"
        ))
    }

    return WiFiConfig(
      strengthIcons: strengthIcons, disconnectedIcon: disconnectedIcon,
      hotspotIcon: iconsYaml["hotspot"].string ?? Self.defaultHotspotIcon
    )
  }

  func defaultConfiguration() -> ModuleConfiguration? {
    WiFiConfig(
      strengthIcons: Self.defaultStrengthIcons,
      disconnectedIcon: Self.defaultDisconnectedIcon, hotspotIcon: Self.defaultHotspotIcon)
  }
}

struct WiFiStatus: Sendable {
  let rssi: Int  // dBm, typically -30 (excellent) to -90 (very weak)
  let isConnected: Bool
  /// Whether the network is a personal hotspot, which macOS marks as expensive.
  var isHotspot = false

  static let disconnected = WiFiStatus(rssi: 0, isConnected: false)

  /// Signal quality as 0.0 – 1.0, mapped from RSSI.
  /// -30 dBm = 1.0 (excellent), -90 dBm = 0.0 (unusable).
  var signalQuality: Float {
    guard isConnected else { return 0 }
    let clamped = max(-90, min(-30, rssi))
    return Float(clamped + 90) / 60.0
  }
}

/// CoreWLAN's events, and whether the WiFi network is a personal hotspot, for
/// every WiFi module observing them, as the shared `CWWiFiClient` has a single
/// delegate. Monitoring runs while at least one module observes.
final class WiFiEvents: NSObject, CWEventDelegate, @unchecked Sendable {
  static let shared = WiFiEvents()

  private struct Observer {
    weak var module: WiFiConfig?
  }

  private let lock = NSLock()
  private var observers: [ObjectIdentifier: Observer] = [:]
  private var pathMonitor: NWPathMonitor?
  private var hotspot = false

  /// Whether the WiFi network is one macOS marks as expensive, as it does a
  /// personal hotspot. Needs no Location Services access, unlike the SSID.
  var isHotspot: Bool { lock.withLock { hotspot } }

  private static let events: [CWEventType] = [
    .ssidDidChange, .bssidDidChange, .linkDidChange, .linkQualityDidChange, .powerDidChange,
  ]

  private var modules: [WiFiConfig] {
    lock.withLock { observers.values.compactMap(\.module) }
  }

  func add(_ module: WiFiConfig) {
    let isFirst = lock.withLock {
      let isFirst = observers.isEmpty
      observers[ObjectIdentifier(module)] = Observer(module: module)
      return isFirst
    }
    guard isFirst else { return }
    startPathMonitor()
    let client = CWWiFiClient.shared()
    client.delegate = self
    for event in Self.events {
      do {
        try client.startMonitoringEvent(with: event)
      } catch {
        print("WiFi: couldn't monitor event \(event.rawValue): \(error)")
      }
    }
  }

  func remove(_ module: WiFiConfig) {
    let isLast = lock.withLock {
      guard observers.removeValue(forKey: ObjectIdentifier(module)) != nil else { return false }
      return observers.isEmpty
    }
    guard isLast else { return }
    let client = CWWiFiClient.shared()
    try? client.stopMonitoringAllEvents()
    client.delegate = nil
    let monitor = lock.withLock {
      defer { pathMonitor = nil }
      return pathMonitor
    }
    monitor?.cancel()
  }

  /// Watches the WiFi path, notifying the modules when it becomes or stops
  /// being a hotspot.
  private func startPathMonitor() {
    let monitor = NWPathMonitor(requiredInterfaceType: .wifi)
    monitor.pathUpdateHandler = { [weak self] path in
      self?.setHotspot(path.status == .satisfied && path.isExpensive)
    }
    lock.withLock { pathMonitor = monitor }
    monitor.start(queue: DispatchQueue(label: "kantan.wifi.path"))
  }

  /// Records whether the network is a hotspot, notifying the modules on a
  /// change. Returns whether it changed.
  @discardableResult
  func setHotspot(_ isHotspot: Bool) -> Bool {
    let changed = lock.withLock {
      defer { hotspot = isHotspot }
      return hotspot != isHotspot
    }
    if changed { modules.forEach { $0.hotspotDidChange() } }
    return changed
  }

  func ssidDidChangeForWiFiInterface(withName interfaceName: String) {
    modules.forEach { $0.ssidDidChangeForWiFiInterface(withName: interfaceName) }
  }

  func bssidDidChangeForWiFiInterface(withName interfaceName: String) {
    modules.forEach { $0.bssidDidChangeForWiFiInterface(withName: interfaceName) }
  }

  func linkDidChangeForWiFiInterface(withName interfaceName: String) {
    modules.forEach { $0.linkDidChangeForWiFiInterface(withName: interfaceName) }
  }

  func linkQualityDidChangeForWiFiInterface(
    withName interfaceName: String, rssi: Int, transmitRate: Double
  ) {
    modules.forEach {
      $0.linkQualityDidChangeForWiFiInterface(
        withName: interfaceName, rssi: rssi, transmitRate: transmitRate)
    }
  }

  func powerStateDidChangeForWiFiInterface(withName interfaceName: String) {
    modules.forEach { $0.powerStateDidChangeForWiFiInterface(withName: interfaceName) }
  }
}

/// Fully event-driven WiFi module using CoreWLAN event monitoring.
/// Listens for SSID, BSSID, link state, link quality (RSSI), and power state
/// changes via CWWiFiClient delegate. No polling — all updates are event-driven.
/// A personal hotspot is recognised by Network.framework marking the WiFi
/// path as expensive.
final class WiFiConfig: NSObject, ModuleConfiguration, EventDrivenModule, CWEventDelegate,
  @unchecked Sendable
{
  var type: String { "wifi" }
  let strengthIcons: [String]
  let disconnectedIcon: String
  /// Icon shown in place of the signal-strength icons while on a personal hotspot.
  let hotspotIcon: String

  var redrawInterval: TimeInterval { noPoll }

  nonisolated(unsafe) private var onChange: (@Sendable () -> Void)?
  private let cache = CachedStatus<WiFiStatus>(fallback: .disconnected)
  /// Only touched inside `cache.mutate { ... }` so it shares the cache lock.
  /// Set by `linkQualityDidChange` (RSSI delivered directly), consumed by
  /// `refreshCache()` to skip an otherwise-redundant IOKit + CWInterface read.
  nonisolated(unsafe) private var _cacheIsFresh = false
  /// Managed exclusively on the main thread — guards against rapid-fire event bursts
  /// during network transitions where IORegistry state may not yet reflect the final state.
  nonisolated(unsafe) private var coalesceWorkItem: DispatchWorkItem?

  init(
    strengthIcons: [String], disconnectedIcon: String,
    hotspotIcon: String
  ) {
    self.strengthIcons = strengthIcons
    self.disconnectedIcon = disconnectedIcon
    self.hotspotIcon = hotspotIcon
    super.init()
  }

  // MARK: - EventDrivenModule

  func startObserving(onChange: @escaping @Sendable () -> Void) {
    self.onChange = onChange
    WiFiEvents.shared.add(self)
  }

  func stopObserving() {
    // coalesceWorkItem is main-thread-only; dispatch cleanup there
    DispatchQueue.main.async { [weak self] in
      self?.coalesceWorkItem?.cancel()
      self?.coalesceWorkItem = nil
    }

    WiFiEvents.shared.remove(self)
    onChange = nil
  }

  // MARK: - CWEventDelegate

  /// Fires onChange immediately, then schedules a coalesced re-read after a brief delay.
  /// Network transitions produce a burst of events and the underlying state (IORegistry,
  /// CWInterface) may not reflect the final state when the first event fires.
  private func notifyWithCoalescing() {
    onChange?()

    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      self.coalesceWorkItem?.cancel()
      let work = DispatchWorkItem { [weak self] in
        self?.onChange?()
      }
      self.coalesceWorkItem = work
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }
  }

  func ssidDidChangeForWiFiInterface(withName interfaceName: String) {
    notifyWithCoalescing()
  }

  func bssidDidChangeForWiFiInterface(withName interfaceName: String) {
    notifyWithCoalescing()
  }

  func linkDidChangeForWiFiInterface(withName interfaceName: String) {
    notifyWithCoalescing()
  }

  func linkQualityDidChangeForWiFiInterface(
    withName interfaceName: String, rssi: Int, transmitRate: Double
  ) {
    // RSSI is delivered directly — update the cache without a full re-read.
    // This is the most frequent event; avoids ~5ms of CWInterface + IOKit calls.
    // The _cacheIsFresh flag tells getIcon() to skip refreshCache().
    let levels: (old: Int, new: Int)? = cache.mutate { current in
      guard let cached = current, cached.isConnected else { return nil }
      let oldRssi = cached.rssi
      current = WiFiStatus(rssi: rssi, isConnected: true, isHotspot: cached.isHotspot)
      _cacheIsFresh = true
      return (signalLevel(rssi: oldRssi), signalLevel(rssi: rssi))
    }

    // Only trigger a UI update if the RSSI change would actually affect the
    // displayed icon. Small fluctuations within the same icon tier are silent.
    guard let levels, levels.old != levels.new else { return }
    onChange?()
  }

  /// Maps RSSI to a signal level index for the configured strength icons.
  /// Used to detect whether an RSSI change crosses an icon threshold.
  private func signalLevel(rssi: Int) -> Int {
    let clamped = max(-90, min(-30, rssi))
    let quality = Int(Float(clamped + 90) / 60.0 * 100)
    let step = max(1, 100 / strengthIcons.count)
    return min(quality / step, strengthIcons.count - 1)
  }

  func powerStateDidChangeForWiFiInterface(withName interfaceName: String) {
    notifyWithCoalescing()
  }

  func hotspotDidChange() {
    notifyWithCoalescing()
  }

  // MARK: - ModuleConfiguration

  func getValue(completion: @escaping @Sendable (String) -> Void) {
    completion("")
  }

  func getIcon() -> String {
    // Skip the full re-read if the cache was just updated by an event
    // (e.g. linkQualityDidChange delivers RSSI directly).
    let fresh: Bool = cache.mutate { _ in
      let f = _cacheIsFresh
      _cacheIsFresh = false
      return f
    }
    if !fresh {
      cache.set(Self.readWiFiStatus())
    }

    return icon(for: cache.get())
  }

  func getBackgroundIcon() -> String? {
    backgroundIcon(for: cache.get())
  }

  /// The icon for `status`: disconnected, hotspot, or its signal strength.
  func icon(for status: WiFiStatus) -> String {
    guard status.isConnected else { return disconnectedIcon }
    if status.isHotspot { return hotspotIcon }
    return iconForLevel(Int(status.signalQuality * 100), icons: strengthIcons)
  }

  /// The full-strength icon dimmed behind a weaker signal-strength icon, or nil
  /// while disconnected, on a hotspot or at full strength.
  func backgroundIcon(for status: WiFiStatus) -> String? {
    guard status.isConnected, !status.isHotspot, let maxIcon = strengthIcons.last,
      strengthIcons.count > 1
    else {
      return nil
    }
    let currentIcon = iconForLevel(Int(status.signalQuality * 100), icons: strengthIcons)
    return currentIcon == maxIcon ? nil : maxIcon
  }

  // MARK: - WiFi Status Reading

  static func readWiFiStatus() -> WiFiStatus {
    let client = CWWiFiClient.shared()
    guard let interface = client.interface() else {
      return .disconnected
    }

    guard interface.powerOn() else {
      return .disconnected
    }

    // A BSSID is only set when the radio is associated with an access point,
    // which is more reliable than RSSI (which can return stale values during
    // transitions) unless macOS withholds the BSSID.
    let rssi = interface.rssiValue()
    guard isAssociated(bssid: readIORegistryBSSID(), rssi: rssi) else {
      return .disconnected
    }

    return WiFiStatus(rssi: rssi, isConnected: true, isHotspot: WiFiEvents.shared.isHotspot)
  }

  /// Whether the radio is associated with an access point: it has a BSSID.
  /// An all-zero BSSID is the placeholder macOS reports when it withholds
  /// the BSSID, so association then depends on a signal reading, which is 0
  /// while unassociated.
  static func isAssociated(bssid: Data?, rssi: Int) -> Bool {
    guard let bssid, !bssid.isEmpty else { return false }
    return bssid.contains { $0 != 0 } || rssi != 0
  }

  /// Reads the infrastructure WiFi interface's BSSID from IOKit's IORegistry,
  /// or nil when no interface has one.
  private static func readIORegistryBSSID() -> Data? {
    var iterator: io_iterator_t = 0
    let kr = IOServiceGetMatchingServices(
      kIOMainPortDefault, IOServiceMatching("IOUserNetworkWLAN"), &iterator)
    guard kr == KERN_SUCCESS else { return nil }
    defer { IOObjectRelease(iterator) }

    while true {
      let service = IOIteratorNext(iterator)
      guard service != 0 else { return nil }
      defer { IOObjectRelease(service) }

      if let bssid = IORegistryEntryCreateCFProperty(
        service, "IO80211BSSID" as CFString, kCFAllocatorDefault, 0)
      {
        return bssid.takeRetainedValue() as? Data
      }
    }
  }
}
