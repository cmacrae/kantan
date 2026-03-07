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

struct WiFiConfig: ModuleConfiguration {
    var type: String { "wifi" }
    let showSSID: Bool
    let icons: [String]
    let disconnectedIcon: String

    var redrawInterval: TimeInterval { 5.0 }

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
}
