import Foundation
import Yaml

struct IconConfigFactory: ModuleConfigurationFactory {
  func configuration(from yaml: Yaml, configDir: String?, theme: ThemeConfig?) throws
    -> ModuleConfiguration
  {
    return IconConfig()
  }

  func defaultConfiguration() -> ModuleConfiguration? {
    return IconConfig()
  }
}

struct IconConfig: ModuleConfiguration {
  var type: String { "icon" }

  var redrawInterval: TimeInterval { noPoll }

  func getValue(completion: @escaping @Sendable (String) -> Void) {
    completion("")
  }
}
