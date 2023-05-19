import Foundation
import Yaml

struct TextConfigFactory: ModuleConfigurationFactory {
    func configuration(from yaml: Yaml) throws -> ModuleConfiguration {
        guard let _ = yaml["value"].string else {
            throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: [], debugDescription: "Unable to decode TextConfig from Yaml"))
        }
        return try TextConfig(yaml: yaml)
    }
}

struct TextConfig: ModuleConfiguration {
    var type: String { "text" }
    let value: String

    init(yaml: Yaml) throws {
        guard let value = yaml["value"].string else {
            throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: [], debugDescription: "Unable to decode TextConfig from Yaml"))
        }
        self.value = value
    }


    var redrawInterval: TimeInterval { 1.0 }

    func getValue() -> String {
        return self.value
    }

    // NOTE: rely on module's 'icon' as we have no special icon to return
    func getIcon() -> String {
        return ""
    }
}
