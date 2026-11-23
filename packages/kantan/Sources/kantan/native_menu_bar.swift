import AppKit

/// Where the native menu bar hides, as its "Automatically hide and show the
/// menu bar" setting has it.
struct NativeMenuBarHiding: Equatable, Sendable {
  /// Whether it hides on a desktop: the setting is "Always" or "On Desktop Only".
  let onDesktop: Bool
  /// Whether it hides in fullscreen apps: "Always" or "In Full Screen Only".
  let inFullscreen: Bool

  /// The setting from the two values System Settings stores it as.
  init(hideMenuBar: Bool, visibleInFullscreen: Bool) {
    onDesktop = hideMenuBar
    inFullscreen = !visibleInFullscreen
  }

  static var current: NativeMenuBarHiding {
    let defaults = UserDefaults.standard
    return NativeMenuBarHiding(
      hideMenuBar: defaults.bool(forKey: "_HIHideMenuBar"),
      visibleInFullscreen: defaults.bool(forKey: "AppleMenuBarVisibleInFullscreen"))
  }

  /// Whether it hides on a fullscreen app's space, or on a desktop.
  func hides(fullscreen: Bool) -> Bool {
    fullscreen ? inFullscreen : onDesktop
  }
}

/// Which displays show a fullscreen app's space.
enum FullscreenSpaces {
  /// The space type `CGSCopyManagedDisplaySpaces` gives a fullscreen app's space.
  static let fullscreenType = 4

  /// Whether the display with `uuid` is on a fullscreen space in
  /// `CGSCopyManagedDisplaySpaces` output. Displays sharing their spaces
  /// are one entry, named "Main".
  static func isFullscreen(display uuid: String, in displaySpaces: [[String: Any]]) -> Bool {
    let named = { (name: String) in
      displaySpaces.first { $0["Display Identifier"] as? String == name }
    }
    let display =
      named(uuid) ?? named("Main") ?? (displaySpaces.count == 1 ? displaySpaces.first : nil)
    let current = display?["Current Space"] as? [String: Any]
    return current?["type"] as? Int == fullscreenType
  }

  static func isFullscreen(_ screen: NSScreen) -> Bool {
    guard
      let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
        as? CGDirectDisplayID,
      let uuid = CGDisplayCreateUUIDFromDisplayID(number)?.takeRetainedValue(),
      let displaySpaces = CGSCopyManagedDisplaySpaces(CGSMainConnectionID()) as? [[String: Any]]
    else { return false }
    return isFullscreen(display: CFUUIDCreateString(nil, uuid) as String, in: displaySpaces)
  }
}
