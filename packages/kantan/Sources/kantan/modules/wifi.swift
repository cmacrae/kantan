import AppKit
import CoreWLAN
import Foundation
import IOKit

struct WiFiConfigFactory: ModuleConfigurationFactory {
  /// Default tabler-icons for wifi states.
  static let defaultStrengthIcons = ["wifi-1", "wifi-2", "wifi"]
  static let defaultDisconnectedIcon = "wifi-off"

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

    var ssidIcons: [String: String] = [:]
    if let ssidDict = iconsYaml["ssid"].dictionary {
      for (key, value) in ssidDict {
        if let k = key.string, let v = value.string {
          ssidIcons[k] = v
        }
      }
    }

    return WiFiConfig(
      strengthIcons: strengthIcons, disconnectedIcon: disconnectedIcon,
      ssidIcons: ssidIcons
    )
  }

  func defaultConfiguration() -> ModuleConfiguration? {
    WiFiConfig(
      strengthIcons: Self.defaultStrengthIcons,
      disconnectedIcon: Self.defaultDisconnectedIcon, ssidIcons: [:])
  }
}

struct WiFiStatus: Sendable {
  let ssid: String?
  let rssi: Int  // dBm, typically -30 (excellent) to -90 (very weak)
  let isConnected: Bool

  static let disconnected = WiFiStatus(ssid: nil, rssi: 0, isConnected: false)

  /// Signal quality as 0.0 – 1.0, mapped from RSSI.
  /// -30 dBm = 1.0 (excellent), -90 dBm = 0.0 (unusable).
  var signalQuality: Float {
    guard isConnected else { return 0 }
    let clamped = max(-90, min(-30, rssi))
    return Float(clamped + 90) / 60.0
  }
}

/// Fully event-driven WiFi module using CoreWLAN event monitoring.
/// Listens for SSID, BSSID, link state, link quality (RSSI), and power state
/// changes via CWWiFiClient delegate. No polling — all updates are event-driven.
/// SSID is read from IOKit's IORegistry (no Location Services required).
final class WiFiConfig: NSObject, ModuleConfiguration, EventDrivenModule, CWEventDelegate,
  @unchecked Sendable
{
  var type: String { "wifi" }
  let strengthIcons: [String]
  let disconnectedIcon: String
  /// SSID → icon overrides. When the current SSID matches a key, that icon is shown
  /// instead of the signal-strength icon.
  let ssidIcons: [String: String]

  var redrawInterval: TimeInterval { 0 }

  nonisolated(unsafe) private var onChange: (@Sendable () -> Void)?
  nonisolated(unsafe) private var wifiClient: CWWiFiClient?
  nonisolated(unsafe) private var _cachedStatus: WiFiStatus?
  nonisolated(unsafe) private var _cacheIsFresh = false
  private let _statusLock = NSLock()
  /// Managed exclusively on the main thread — guards against rapid-fire event bursts
  /// during network transitions where IORegistry state may not yet reflect the final state.
  nonisolated(unsafe) private var coalesceWorkItem: DispatchWorkItem?

  init(
    strengthIcons: [String], disconnectedIcon: String,
    ssidIcons: [String: String]
  ) {
    self.strengthIcons = strengthIcons
    self.disconnectedIcon = disconnectedIcon
    self.ssidIcons = ssidIcons
    super.init()
  }

  required init(from decoder: Decoder) throws {
    self.strengthIcons = []
    self.disconnectedIcon = ""
    self.ssidIcons = [:]
    super.init()
  }

  func encode(to encoder: Encoder) throws {}

  // MARK: - EventDrivenModule

  func startObserving(onChange: @escaping @Sendable () -> Void) {
    self.onChange = onChange

    let client = CWWiFiClient.shared()
    client.delegate = self
    do {
      try client.startMonitoringEvent(with: .ssidDidChange)
      try client.startMonitoringEvent(with: .bssidDidChange)
      try client.startMonitoringEvent(with: .linkDidChange)
      try client.startMonitoringEvent(with: .linkQualityDidChange)
      try client.startMonitoringEvent(with: .powerDidChange)
    } catch {}

    self.wifiClient = client
  }

  func stopObserving() {
    // coalesceWorkItem is main-thread-only; dispatch cleanup there
    DispatchQueue.main.async { [weak self] in
      self?.coalesceWorkItem?.cancel()
      self?.coalesceWorkItem = nil
    }

    if let client = wifiClient {
      do {
        try client.stopMonitoringAllEvents()
      } catch {}
      client.delegate = nil
    }
    wifiClient = nil
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
    _statusLock.lock()
    guard let cached = _cachedStatus, cached.isConnected else {
      _statusLock.unlock()
      return
    }
    let oldRssi = cached.rssi
    _cachedStatus = WiFiStatus(ssid: cached.ssid, rssi: rssi, isConnected: true)
    _cacheIsFresh = true
    _statusLock.unlock()

    // Only trigger a UI update if the RSSI change would actually affect the
    // displayed icon. Small fluctuations within the same icon tier are silent.
    let oldLevel = signalLevel(rssi: oldRssi)
    let newLevel = signalLevel(rssi: rssi)
    guard oldLevel != newLevel else { return }
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

  // MARK: - Status Caching

  private func refreshCache() {
    _statusLock.lock()
    let fresh = _cacheIsFresh
    _cacheIsFresh = false
    _statusLock.unlock()

    // Skip the full re-read if the cache was just updated by an event
    // (e.g. linkQualityDidChange delivers RSSI directly).
    guard !fresh else { return }

    let status = Self.readWiFiStatus()
    _statusLock.lock()
    _cachedStatus = status
    _statusLock.unlock()
  }

  private func getCachedStatus() -> WiFiStatus {
    _statusLock.lock()
    defer { _statusLock.unlock() }
    return _cachedStatus ?? .disconnected
  }

  // MARK: - ModuleConfiguration

  func getValue(completion: @escaping @Sendable (String) -> Void) {
    completion("")
  }

  func getIcon() -> String {
    refreshCache()
    let status = getCachedStatus()
    guard status.isConnected else {
      return disconnectedIcon
    }
    if let override = iconForSSID(status.ssid) {
      return override
    }
    let level = Int(status.signalQuality * 100)
    return iconForLevel(level, icons: strengthIcons)
  }

  func getBackgroundIcon() -> String? {
    let status = getCachedStatus()
    guard status.isConnected, strengthIcons.count > 1 else { return nil }
    // No background icon when an SSID-specific icon is active
    if iconForSSID(status.ssid) != nil {
      return nil
    }
    let level = Int(status.signalQuality * 100)
    let currentIcon = iconForLevel(level, icons: strengthIcons)
    let maxIcon = strengthIcons.last!
    // Only show background when not already at full strength
    guard currentIcon != maxIcon else { return nil }
    return maxIcon
  }

  /// Returns an SSID-specific icon override, checking the explicit ssid map first,
  /// then falling back to iPhone hotspot detection (SSIDs ending with "iPhone").
  private func iconForSSID(_ ssid: String?) -> String? {
    guard let ssid else { return nil }
    // Explicit SSID → icon map takes priority
    if let icon = ssidIcons[ssid] {
      return icon
    }
    // Fallback: detect iPhone hotspots by SSID suffix.
    // Default iPhone hotspot names are "<Name>'s iPhone" (with curly apostrophe)
    // or "<Name>'s iPhone" (with straight apostrophe).
    if ssid.hasSuffix("iPhone") {
      return ssidIcons["iPhone"] ?? "circles-relation"
    }
    return nil
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

    // Read SSID and BSSID from IOKit in one pass.
    // BSSID presence is the definitive association indicator — it's only set
    // when the radio is associated with an access point. This is more reliable
    // than RSSI (which can return stale values during transitions).
    let ioInfo = readIORegistryWiFiInfo()

    guard ioInfo.hasBSSID else {
      return .disconnected
    }

    let rssi = interface.rssiValue()
    let ssid = interface.ssid() ?? ioInfo.ssid
    return WiFiStatus(ssid: ssid, rssi: rssi, isConnected: true)
  }

  private struct IORegistryWiFiInfo {
    let ssid: String?
    let hasBSSID: Bool
  }

  /// Reads WiFi SSID and BSSID from IOKit's IORegistry in a single pass.
  /// In-process API — no subprocess, no Location Services required.
  private static func readIORegistryWiFiInfo() -> IORegistryWiFiInfo {
    var iterator: io_iterator_t = 0
    let kr = IOServiceGetMatchingServices(
      kIOMainPortDefault, IOServiceMatching("IOUserNetworkWLAN"), &iterator)
    guard kr == KERN_SUCCESS else { return IORegistryWiFiInfo(ssid: nil, hasBSSID: false) }
    defer { IOObjectRelease(iterator) }

    while true {
      let service = IOIteratorNext(iterator)
      guard service != 0 else { break }
      defer { IOObjectRelease(service) }

      // Check for BSSID — its presence means the radio is associated
      let hasBSSID: Bool
      if let bssidProp = IORegistryEntryCreateCFProperty(
        service, "IO80211BSSID" as CFString, kCFAllocatorDefault, 0)
      {
        let val = bssidProp.takeRetainedValue()
        if let data = val as? Data, !data.isEmpty {
          hasBSSID = true
        } else {
          hasBSSID = false
        }
      } else {
        continue  // Not the infrastructure interface
      }

      // Read SSID
      var ssid: String?
      if let ssidProp = IORegistryEntryCreateCFProperty(
        service, "IO80211SSID" as CFString, kCFAllocatorDefault, 0)
      {
        let val = ssidProp.takeRetainedValue()
        if let s = val as? String, !s.isEmpty {
          ssid = s
        } else if let data = val as? Data,
          let s = String(data: data, encoding: .utf8), !s.isEmpty
        {
          ssid = s
        }
      }

      return IORegistryWiFiInfo(ssid: ssid, hasBSSID: hasBSSID)
    }

    return IORegistryWiFiInfo(ssid: nil, hasBSSID: false)
  }
}
