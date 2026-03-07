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

    // Static value — no polling needed. CLI triggers can still update
    // via BarViewModel.handleEvent(), and EventObserver.refreshAll()
    // will call update() on wake/space-change.
    var redrawInterval: TimeInterval { 3600.0 }

    func getValue(completion: @escaping @Sendable (String) -> Void) {
        completion(self.value)
    }

    func getIcon() -> String {
        return ""
    }
}
