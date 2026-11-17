import Foundation

struct DrawerConfigFactory: ModuleConfigurationFactory {
  /// Default tabler-icons for a closed and an open drawer.
  static let defaultShowIcon = "box-align-right"
  static let defaultHideIcon = "box-align-left"

  func configuration(from yaml: Yaml, configDir: String?, theme: ThemeConfig?) throws
    -> ModuleConfiguration
  {
    let showIcon = yaml["icons"]["show"].string ?? Self.defaultShowIcon
    let hideIcon = yaml["icons"]["hide"].string ?? Self.defaultHideIcon
    return DrawerConfig(showIcon: showIcon, hideIcon: hideIcon)
  }

  func defaultConfiguration() -> ModuleConfiguration? {
    return DrawerConfig(showIcon: Self.defaultShowIcon, hideIcon: Self.defaultHideIcon)
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

  func getIcon() -> String {
    icon(open: state.isOpen)
  }

  /// The hide icon while the drawer is open, the show icon otherwise.
  func icon(open: Bool) -> String {
    open ? hideIcon : showIcon
  }
}
