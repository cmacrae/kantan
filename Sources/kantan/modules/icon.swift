import Foundation
import Yaml

struct IconConfigFactory: ModuleConfigurationFactory {
    func configuration(from yaml: Yaml) throws -> ModuleConfiguration {
        return IconConfig()
    }

    func defaultConfiguration() -> ModuleConfiguration? {
        return IconConfig()
    }
}

struct IconConfig: ModuleConfiguration {
    var type: String { "icon" }

    var redrawInterval: TimeInterval { 3600.0 }

    func getValue(completion: @escaping @Sendable (String) -> Void) {
        completion("")
    }

    func getIcon() -> String {
        return ""
    }
}
