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

struct PowerConfig: ModuleConfiguration {
    var type: String { "power" }
    let showLevel: Bool
    let charging: ChargingConfig
    let battery: BatteryConfig

    var redrawInterval: TimeInterval { 1.0 }

    init(showLevel: Bool, charging: ChargingConfig, battery: BatteryConfig) {
        self.showLevel = showLevel
        self.charging = charging
        self.battery = battery
    }

    func getValue(completion: @escaping @Sendable (String) -> Void) {
        completion(getValueSync())
    }

    func getValueSync() -> String {
        let batteryLevel = getBatteryLevel()
        return showLevel ? "\(batteryLevel)%" : ""
    }

    func getIcon() -> String {
        let batteryLevel = getBatteryLevel()
        let charging = isCharging()

        if charging {
            return self.charging.icon
        } else {
            let index = min(batteryLevel / 25, battery.icons.count - 1)
            return battery.icons[index]
        }
    }
}

struct ChargingConfig: Codable, Sendable {
    let icon: String
}

struct BatteryConfig: Codable, Sendable {
    let icons: [String]
}

func getBatteryLevel() -> Int {
    let snapshot = IOPSCopyPowerSourcesInfo().takeRetainedValue()
    let sources = IOPSCopyPowerSourcesList(snapshot).takeRetainedValue() as! [CFDictionary]

    for source in sources {
        if let sourceDict = source as? Dictionary<String, Any> {
            if let currentCapacity = sourceDict[kIOPSCurrentCapacityKey as String] as? Int,
               let maxCapacity = sourceDict[kIOPSMaxCapacityKey as String] as? Int {
                let level = (currentCapacity * 100) / maxCapacity
                return level
            }
        }
    }

    return -1
}

func isCharging() -> Bool {
    let snapshot = IOPSCopyPowerSourcesInfo().takeRetainedValue()
    let sources = IOPSCopyPowerSourcesList(snapshot).takeRetainedValue() as! [CFDictionary]

    for source in sources {
        if let sourceDict = source as? Dictionary<String, Any> {
            if let chargingStatus = sourceDict[kIOPSIsChargingKey as String] as? Bool {
                return chargingStatus
            }
        }
    }

    return false
}
