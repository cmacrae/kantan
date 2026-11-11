import Foundation

struct DrawerConfigFactory: ModuleConfigurationFactory {
  func configuration(from yaml: Yaml, configDir: String?, theme: ThemeConfig?) throws
    -> ModuleConfiguration
  {
    let showIcon = yaml["icons"]["show"].string ?? "〈"
    let hideIcon = yaml["icons"]["hide"].string ?? "〉"
    return DrawerConfig(showIcon: showIcon, hideIcon: hideIcon)
  }

  func defaultConfiguration() -> ModuleConfiguration? {
    return DrawerConfig(showIcon: "〈", hideIcon: "〉")
  }
}

/// Whether a drawer is open, shared by every copy of its config.
final class DrawerState: @unchecked Sendable {
  private let lock = NSLock()
  private var open = false

  var isOpen: Bool {
    get { lock.withLock { open } }
    set { lock.withLock { open = newValue } }
  }
}

struct DrawerConfig: ModuleConfiguration {
  var type: String { "drawer" }
  var redrawInterval: TimeInterval { noPoll }
  let showIcon: String
  let hideIcon: String
  let state = DrawerState()

  func getValue(completion: @escaping @Sendable (String) -> Void) {
    completion("")
  }

  /// The hide icon while the drawer is open, the show icon otherwise.
  func getIcon() -> String {
    state.isOpen ? hideIcon : showIcon
  }
}
