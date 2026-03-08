import AppKit
import CoreWLAN
import Foundation
import Yaml

struct WiFiConfigFactory: ModuleConfigurationFactory {
    func configuration(from yaml: Yaml) throws -> ModuleConfiguration {
        let showSSID = yaml["showSSID"].bool ?? false

        guard let iconsYaml = yaml["icons"].array,
              let icons = Optional(iconsYaml.compactMap({ $0.string })),
              !icons.isEmpty else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: [],
                    debugDescription: "WiFiConfig requires a non-empty 'icons' array"
                ))
        }

        let disconnectedIcon = yaml["disconnectedIcon"].string ?? icons.first ?? ""

        return WiFiConfig(showSSID: showSSID, icons: icons, disconnectedIcon: disconnectedIcon)
    }
}

struct WiFiStatus: Sendable {
    let ssid: String?
    let rssi: Int         // dBm, typically -30 (excellent) to -90 (very weak)
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

struct WiFiNetwork: Sendable, Identifiable {
    let ssid: String
    let rssi: Int
    let isSecure: Bool
    let isConnected: Bool

    var id: String { ssid }

    var signalQuality: Float {
        let clamped = max(-90, min(-30, rssi))
        return Float(clamped + 90) / 60.0
    }
}

/// Event-driven WiFi module using CoreWLAN event monitoring.
/// Listens for SSID changes, link state changes, and power state changes
/// via CWWiFiClient delegate. Keeps a 30s poll for RSSI updates only,
/// since signal strength has no event API.
final class WiFiConfig: NSObject, ModuleConfiguration, EventDrivenModule, @unchecked Sendable {
    var type: String { "wifi" }
    let showSSID: Bool
    let icons: [String]
    let disconnectedIcon: String

    var redrawInterval: TimeInterval { 0 }

    nonisolated(unsafe) private var onChange: (@Sendable () -> Void)?
    nonisolated(unsafe) private var rssiTimer: Timer?
    nonisolated(unsafe) private var wifiClient: CWWiFiClient?

    init(showSSID: Bool, icons: [String], disconnectedIcon: String) {
        self.showSSID = showSSID
        self.icons = icons
        self.disconnectedIcon = disconnectedIcon
        super.init()
    }

    required init(from decoder: Decoder) throws {
        self.showSSID = false
        self.icons = []
        self.disconnectedIcon = ""
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
            try client.startMonitoringEvent(with: .linkDidChange)
            try client.startMonitoringEvent(with: .powerDidChange)
        } catch {
            print("WiFi event monitoring failed: \(error)")
        }
        self.wifiClient = client

        // RSSI has no event API — poll at a reduced 30s interval
        rssiTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            self?.onChange?()
        }
    }

    func stopObserving() {
        rssiTimer?.invalidate()
        rssiTimer = nil

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

    func ssidDidChangeForWiFiInterface(withName interfaceName: String) {
        onChange?()
    }

    func linkDidChangeForWiFiInterface(withName interfaceName: String) {
        onChange?()
    }

    func powerStateDidChangeForWiFiInterface(withName interfaceName: String) {
        onChange?()
    }

    // MARK: - ModuleConfiguration

    func getValue(completion: @escaping @Sendable (String) -> Void) {
        let status = Self.readWiFiStatus()
        if showSSID {
            completion(status.ssid ?? "")
        } else {
            completion("")
        }
    }

    func getIcon() -> String {
        let status = Self.readWiFiStatus()
        guard status.isConnected else {
            return disconnectedIcon
        }
        guard !icons.isEmpty else { return "" }
        let step = 1.0 / Float(icons.count)
        let index = min(Int(status.signalQuality / step), icons.count - 1)
        return icons[max(0, index)]
    }

    func getTemplateVariables() -> [String: String] {
        let status = Self.readWiFiStatus()
        let state: String
        if status.isConnected {
            state = "connected"
        } else {
            state = "disconnected"
        }
        return [
            "ssid": status.ssid ?? "—",
            "rssi": status.isConnected ? "\(status.rssi) dBm" : "—",
            "signal": status.isConnected ? "\(Int(status.signalQuality * 100))%" : "—",
            "state": state,
        ]
    }

    // MARK: - WiFi Status Reading

    static func readWiFiStatus() -> WiFiStatus {
        let client = CWWiFiClient.shared()
        guard let interface = client.interface() else {
            return .disconnected
        }

        // Check power state first
        guard interface.powerOn() else {
            return .disconnected
        }

        let rssi = interface.rssiValue()

        // Detect connection: if powered on and RSSI is non-zero,
        // the interface is associated with a network
        guard rssi != 0 else {
            return .disconnected
        }

        // Try CoreWLAN SSID first (requires location authorization)
        if let ssid = interface.ssid() {
            return WiFiStatus(ssid: ssid, rssi: rssi, isConnected: true)
        }

        // Fallback: read SSID from IORegistry (fast, no permissions needed)
        let ssid = readSSIDFromIORegistry()
        return WiFiStatus(ssid: ssid, rssi: rssi, isConnected: true)
    }

    /// Reads the WiFi SSID from the IORegistry via ioreg.
    /// This works without Location Services authorization.
    /// Takes ~20ms — fast enough for periodic polling.
    private static func readSSIDFromIORegistry() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/ioreg")
        process.arguments = ["-r", "-c", "IOUserNetworkWLAN"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return nil
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard let output = String(data: data, encoding: .utf8) else {
            return nil
        }

        // Parse: "IO80211SSID" = "NetworkName"
        for line in output.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.contains("\"IO80211SSID\"") && !trimmed.contains("BSSID") {
                // Extract value between last pair of quotes
                let parts = trimmed.components(separatedBy: "\"")
                // Format: "IO80211SSID" = "value"
                // parts: ["", "IO80211SSID", " = ", "value", ""]
                if parts.count >= 4 {
                    return parts[3]
                }
            }
        }

        return nil
    }

    // MARK: - WiFi Control

    static func setPower(_ enabled: Bool) {
        let client = CWWiFiClient.shared()
        guard let interface = client.interface() else { return }
        do {
            try interface.setPower(enabled)
        } catch {
            print("WiFi setPower failed: \(error)")
        }
    }

    static func isPoweredOn() -> Bool {
        let client = CWWiFiClient.shared()
        guard let interface = client.interface() else { return false }
        return interface.powerOn()
    }

    static func scanForNetworks() -> [WiFiNetwork] {
        let client = CWWiFiClient.shared()
        guard let interface = client.interface() else { return [] }

        do {
            let networks = try interface.scanForNetworks(withSSID: nil)
            let currentSSID = interface.ssid()

            // Deduplicate by SSID, keeping strongest signal
            var bestBySSID: [String: CWNetwork] = [:]
            for network in networks {
                guard let ssid = network.ssid, !ssid.isEmpty else { continue }
                if let existing = bestBySSID[ssid] {
                    if network.rssiValue > existing.rssiValue {
                        bestBySSID[ssid] = network
                    }
                } else {
                    bestBySSID[ssid] = network
                }
            }

            return bestBySSID.values
                .compactMap { network -> WiFiNetwork? in
                    guard let ssid = network.ssid else { return nil }
                    let isConnected = ssid == currentSSID
                    return WiFiNetwork(
                        ssid: ssid,
                        rssi: network.rssiValue,
                        isSecure: !network.supportsSecurity(.none),
                        isConnected: isConnected
                    )
                }
                .filter { !$0.isConnected }
                .sorted { $0.rssi > $1.rssi }
        } catch {
            print("WiFi scan failed: \(error)")
            return []
        }
    }

    static func connectToNetwork(ssid: String) {
        let client = CWWiFiClient.shared()
        guard let interface = client.interface() else { return }

        do {
            let networks = try interface.scanForNetworks(withSSID: ssid.data(using: .utf8))
            guard let network = networks.first else { return }
            try interface.associate(to: network, password: nil)
        } catch {
            print("WiFi connect failed: \(error)")
        }
    }

    static func openWiFiSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.wifi-settings-extension") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Dynamic Menu

    static func buildMenuDescriptors() -> [MenuItemDescriptor] {
        let status = readWiFiStatus()
        let powered = isPoweredOn()
        var descriptors: [MenuItemDescriptor] = []

        descriptors.append(.toggle("Wi-Fi", isOn: powered) { completion in
            DispatchQueue.global(qos: .userInitiated).async {
                WiFiConfig.setPower(!powered)
                // Brief delay for radio state to settle
                Thread.sleep(forTimeInterval: 0.5)
                DispatchQueue.main.async { completion() }
            }
        })
        descriptors.append(.separator())

        if powered {
            if status.isConnected, let ssid = status.ssid {
                let indicator = makeIndicatorView(isConnected: true)
                let signal = Int(status.signalQuality * 100)
                descriptors.append(.item("\(ssid) (\(signal)%)", icon: indicator) {})
            } else {
                let indicator = makeIndicatorView(isConnected: false)
                descriptors.append(.item("Not Connected", icon: indicator) {})
            }

            descriptors.append(.separator())

            // Scan for available networks (blocking, ~2-4s)
            let networks = scanForNetworks()
            if !networks.isEmpty {
                descriptors.append(.header("Other Networks"))
                for network in networks.prefix(15) {
                    let ssid = network.ssid
                    let signal = Int(network.signalQuality * 100)
                    let label = network.isSecure ? "\(ssid) (\(signal)%) \u{f023}" : "\(ssid) (\(signal)%)"
                    descriptors.append(.item(label) {
                        DispatchQueue.global(qos: .userInitiated).async {
                            WiFiConfig.connectToNetwork(ssid: ssid)
                        }
                    })
                }
                descriptors.append(.separator())
            }
        }

        descriptors.append(.item("Wi-Fi Settings\u{2026}") {
            WiFiConfig.openWiFiSettings()
        })

        return descriptors
    }

    private static func makeIndicatorView(isConnected: Bool) -> NSView {
        let size: CGFloat = 10
        let view = NSView(frame: NSRect(x: 0, y: 0, width: size, height: size))
        view.wantsLayer = true
        view.layer?.cornerRadius = size / 2
        if isConnected {
            view.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
        } else {
            view.layer?.backgroundColor = NSColor.clear.cgColor
            view.layer?.borderColor = NSColor.tertiaryLabelColor.cgColor
            view.layer?.borderWidth = 1.5
        }
        return view
    }
}
