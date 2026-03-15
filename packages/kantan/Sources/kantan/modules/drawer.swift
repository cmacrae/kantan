import Foundation
import Yaml

struct DrawerConfigFactory: ModuleConfigurationFactory {
  func configuration(from yaml: Yaml, configDir: String?, theme: ThemeConfig?) throws
    -> ModuleConfiguration
  {
    let showIcon = fixYamlUnicodeEscapes(yaml["icons"]["show"].string ?? "〈")
    let hideIcon = fixYamlUnicodeEscapes(yaml["icons"]["hide"].string ?? "〉")
    return DrawerConfig(showIcon: showIcon, hideIcon: hideIcon)
  }

  func defaultConfiguration() -> ModuleConfiguration? {
    return DrawerConfig(showIcon: "〈", hideIcon: "〉")
  }
}

struct DrawerConfig: ModuleConfiguration {
  var type: String { "drawer" }
  var redrawInterval: TimeInterval { noPoll }
  let showIcon: String
  let hideIcon: String

  func getValue(completion: @escaping @Sendable (String) -> Void) {
    completion("")
  }

  func getIcon() -> String {
    showIcon
  }
}
