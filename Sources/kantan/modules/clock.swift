import Foundation
import Yaml

struct ClockConfigFactory: ModuleConfigurationFactory {
    func configuration(from yaml: Yaml) throws -> ModuleConfiguration {
        guard let _ = yaml["format"].string else {
            throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: [], debugDescription: "Unable to decode clock configuration"))
        }
        return try ClockConfig(yaml: yaml)
    }
}

struct ClockConfig: ModuleConfiguration {
    var type: String { "clock" }
    let format: String

    init(yaml: Yaml) throws {
        guard let format = yaml["format"].string else {
            throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: [], debugDescription: "Unable to decode clock configuration"))
        }
        self.format = format
    }
    
    // var redrawInterval: TimeInterval { return 1.0 }
    var redrawInterval: TimeInterval { 1.0 }

    func getNewValue() -> String {
        return getClockText(format: format)
    }
}

func getClockText(format: String) -> String {
    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = format
    return dateFormatter.string(from: Date())
}

