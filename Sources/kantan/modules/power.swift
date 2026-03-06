import Foundation
import Yaml
import IOKit.ps

struct PowerConfigFactory: ModuleConfigurationFactory {
    func configuration(from yaml: Yaml) throws -> ModuleConfiguration {
        guard let showLevel = yaml["showLevel"].bool,
              let chargingYaml = yaml["charging"].dictionary,
              let batteryYaml = yaml["battery"].dictionary,
              let chargingIcon = chargingYaml["icon"]?.string,
              let batteryIcons = batteryYaml["icons"]?.array?.compactMap({ $0.string }) else {
            throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: [], debugDescription: "Unable to decode PowerConfig from Yaml"))
        }

        let chargingConfig = ChargingConfig(icon: chargingIcon)
        let batteryConfig = BatteryConfig(icons: batteryIcons)

        return PowerConfig(showLevel: showLevel, charging: chargingConfig, battery: batteryConfig)
    }
}

struct BatteryStatus: Sendable {
    let level: Int
    let isCharging: Bool
    let isPluggedIn: Bool

    static let unavailable = BatteryStatus(level: -1, isCharging: false, isPluggedIn: false)
    var isAvailable: Bool { level >= 0 }
}

struct PowerConfig: ModuleConfiguration {
    var type: String { "power" }
    let showLevel: Bool
    let charging: ChargingConfig
    let battery: BatteryConfig

    var redrawInterval: TimeInterval { 5.0 }

    init(showLevel: Bool, charging: ChargingConfig, battery: BatteryConfig) {
        self.showLevel = showLevel
        self.charging = charging
        self.battery = battery
    }

    func getValue(completion: @escaping @Sendable (String) -> Void) {
        let status = Self.readBatteryStatus()
        guard status.isAvailable else {
            completion("")
            return
        }
        completion(showLevel ? "\(status.level)%" : "")
    }

    func getIcon() -> String {
        let status = Self.readBatteryStatus()
        guard status.isAvailable else {
            return battery.icons.first ?? ""
        }
        if status.isCharging || status.isPluggedIn {
            return charging.icon
        }
        let index = min(status.level / 25, battery.icons.count - 1)
        return battery.icons[max(0, index)]
    }

    private static func readBatteryStatus() -> BatteryStatus {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFDictionary] else {
            return .unavailable
        }

        for source in sources {
            guard let sourceDict = source as? [String: Any] else { continue }

            guard let currentCapacity = sourceDict[kIOPSCurrentCapacityKey as String] as? Int,
                  let maxCapacity = sourceDict[kIOPSMaxCapacityKey as String] as? Int,
                  maxCapacity > 0 else {
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
