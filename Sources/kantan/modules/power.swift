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

    func getValue(completion: @escaping (String) -> Void) {
        let batteryLevel = getBatteryLevel()
        let value = showLevel ? "\(batteryLevel)%" : ""
        completion(value)
    }

    func getIcon() -> String {
        let icon: String
        let batteryLevel = getBatteryLevel()
        let isCharging = isCharging()

        if isCharging {
            icon = charging.icon
        } else {
            let index = min(batteryLevel / 25, battery.icons.count - 1)
            icon = battery.icons[index]
        }

        return icon
    }
}

struct ChargingConfig: Codable {
    let icon: String

    init(icon: String) {
        self.icon = icon
    }
}

struct BatteryConfig: Codable {
    let icons: [String]

    init(icons: [String]) {
        self.icons = icons
    }
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

    // if no battery sources found
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

    // if no battery sources found
    return false
}
