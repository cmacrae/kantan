import Foundation
import Yaml
import IOKit.ps

struct PowerConfig: ModuleConfiguration {
    var type: String { "power" }
    let showLevel: Bool
    let charging: ChargingConfig
    let battery: BatteryConfig

    var redrawInterval: TimeInterval { 1.0 }

    init(yaml: Yaml) throws {
        guard let showLevel = yaml["showLevel"].bool else {
            throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: [], debugDescription: "Unable to decode 'showLevel' from Yaml"))
        }

        guard let chargingYaml = yaml["charging"].dictionary else {
            throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: [], debugDescription: "Unable to decode 'charging' from Yaml"))
        }

        guard let batteryYaml = yaml["battery"].dictionary else {
            throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: [], debugDescription: "Unable to decode 'battery' from Yaml"))
        }

        self.showLevel = showLevel
        self.charging = try ChargingConfig(yaml: Yaml.dictionary(chargingYaml))
        self.battery = try BatteryConfig(yaml: Yaml.dictionary(batteryYaml))
    }


    func getNewValue() -> String {
        let batteryLevel = getBatteryLevel()
        return showLevel ? "\(batteryLevel)%" : ""
    }
}

struct ChargingConfig: Codable {
    let icon: String

    init(yaml: Yaml) throws {
        guard let icon = yaml["icon"].string else {
            throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: [], debugDescription: "Unable to decode 'icon' from Yaml"))
        }

        self.icon = icon
    }
}

struct BatteryConfig: Codable {
    let icons: [String]

    init(yaml: Yaml) throws {
        guard let icons = yaml["icons"].array?.compactMap({ $0.string }) else {
            throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: [], debugDescription: "Unable to decode 'icons' from Yaml"))
        }

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
