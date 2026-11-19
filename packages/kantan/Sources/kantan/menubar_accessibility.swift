import AppKit
import ApplicationServices

/// A status item as the Accessibility API reports it.
struct AccessibleMenuBarItem: Equatable, Sendable {
  /// Global frame in CG coordinates (origin at the primary display's top-left).
  let frame: CGRect
  /// `AXIdentifier` of a system item, e.g. `com.apple.menuextra.wifi`.
  let identifier: String?
  /// Name of the owning app.
  let owner: String
  /// Bundle identifier, name and executable name of the owning app.
  let appNames: [String]
  /// Whether MenuBarAgent draws the item (macOS 27+ system items). Its frame
  /// covers the item's content, without the padding around it.
  let isMenuBarAgentItem: Bool
}

/// Live menu bar items read through the Accessibility API, which reports
/// every status item, system and third-party, with its frame and owning app.
///
/// Needs Accessibility permission. Without it `snapshot` stays empty and
/// item detection falls back to sources that need no permission. Items are
/// read on a background queue, because each read waits on the owning app's
/// reply, and `onChange` runs whenever an item moves, appears or disappears.
final class MenuBarAccessibility: @unchecked Sendable {
  static let shared = MenuBarAccessibility()

  static let menuBarAgentBundleIdentifier = "com.apple.MenuBarAgent"
  static let systemIdentifierPrefix = "com.apple.menuextra."
  /// How often items are re-read.
  static let refreshInterval: TimeInterval = 1
  /// Longest wait for one app's reply, so an unresponsive app can't stall a read.
  static let messagingTimeout: Float = 0.25

  /// Control Centre identifiers of system items whose Accessibility name
  /// differs from them other than by case.
  static let controlCentreIdentifiers: [String: String] = [
    "controlcenter": "BentoBox-0",
    "focusmode": "FocusModes",
  ]

  private let queue = DispatchQueue(label: "kantan.menubar.accessibility")
  private let lock = NSLock()
  private var items: [AccessibleMenuBarItem] = []
  private var timer: DispatchSourceTimer?
  private var generation = 0

  static var isTrusted: Bool { AXIsProcessTrusted() }

  /// Whether a config uses anything Accessibility provides: masks, and the
  /// focus module's on/off state when it can't read the Focus database.
  static func isNeeded(by modules: [ModuleConfig], fullDiskAccess: Bool) -> Bool {
    modules.contains { $0.mask != nil || ($0.type == "focus" && !fullDiskAccess) }
  }

  /// Asks for Accessibility permission: macOS lists kantan under Privacy &
  /// Security → Accessibility and shows its prompt. Does nothing once granted.
  static func requestAccess() {
    // The value of `kAXTrustedCheckOptionPrompt`, a mutable global Swift 6
    // won't read from a nonisolated context.
    _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
  }

  /// The items as last read; empty until read, or without permission.
  var snapshot: [AccessibleMenuBarItem] {
    lock.withLock { items }
  }

  /// Reads items now and every `refreshInterval`, calling `onChange` on the
  /// reading queue whenever they differ from the previous read.
  func start(onChange: @escaping @Sendable () -> Void) {
    let timer = DispatchSource.makeTimerSource(queue: queue)
    let current = lock.withLock { () -> Int in
      self.timer?.cancel()
      self.timer = timer
      generation += 1
      return generation
    }
    timer.schedule(deadline: .now(), repeating: Self.refreshInterval)
    timer.setEventHandler { [weak self] in
      self?.refresh(generation: current, onChange: onChange)
    }
    timer.resume()
  }

  func stop() {
    lock.withLock {
      timer?.cancel()
      timer = nil
      generation += 1
      items = []
    }
  }

  /// Whether the lock screen is up. The system's items can't be read behind
  /// it, and are back where they were once it lifts.
  static var isScreenLocked: Bool {
    let session = CGSessionCopyCurrentDictionary() as? [String: Any]
    return session?["CGSSessionScreenIsLocked"] as? Bool ?? false
  }

  /// Reads the items, keeping the last read while the screen is locked, or
  /// when it locks during the read.
  private func refresh(generation current: Int, onChange: @Sendable () -> Void) {
    guard !Self.isScreenLocked else { return }
    let fresh = Self.isTrusted ? Self.read() : []
    guard !Self.isScreenLocked else { return }
    let changed = lock.withLock { () -> Bool in
      guard generation == current, fresh != items else { return false }
      items = fresh
      return true
    }
    if changed { onChange() }
  }

  // MARK: - Reading

  /// Reads the status items of every app that can own one. Background-only
  /// processes can't, and are skipped: many never answer Accessibility
  /// requests, so each would cost a full `messagingTimeout`.
  static func read() -> [AccessibleMenuBarItem] {
    let ownPID = ProcessInfo.processInfo.processIdentifier
    // A timeout set on an element covers that element only. Set on the
    // system-wide element, it also covers the elements read from each app.
    AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), messagingTimeout)
    var result: [AccessibleMenuBarItem] = []
    for app in NSWorkspace.shared.runningApplications
    where app.activationPolicy != .prohibited && app.processIdentifier != ownPID {
      let application = AXUIElementCreateApplication(app.processIdentifier)
      AXUIElementSetMessagingTimeout(application, messagingTimeout)
      guard let menuBar = element(application, kAXExtrasMenuBarAttribute) else { continue }
      let executable = app.executableURL?.lastPathComponent
      let appNames = [app.bundleIdentifier, app.localizedName, executable].compactMap { $0 }
      let isMenuBarAgent = app.bundleIdentifier == menuBarAgentBundleIdentifier
      for item in children(of: menuBar) {
        guard let frame = frame(of: item) else { continue }
        // MenuBarAgent wraps each item in a hosting view; the item inside
        // carries the identifier.
        let identifier =
          string(item, kAXIdentifierAttribute)
          ?? children(of: item).lazy.compactMap { string($0, kAXIdentifierAttribute) }.first
        result.append(
          AccessibleMenuBarItem(
            frame: frame,
            identifier: identifier.flatMap { $0.hasPrefix(systemIdentifierPrefix) ? $0 : nil },
            owner: app.localizedName ?? executable ?? "",
            appNames: appNames,
            isMenuBarAgentItem: isMenuBarAgent))
      }
    }
    return result
  }

  private static func copy(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success
    else { return nil }
    return value
  }

  private static func element(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
    guard let value = copy(element, attribute), CFGetTypeID(value) == AXUIElementGetTypeID()
    else { return nil }
    return (value as! AXUIElement)
  }

  private static func children(of element: AXUIElement) -> [AXUIElement] {
    copy(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
  }

  private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
    copy(element, attribute) as? String
  }

  private static func frame(of element: AXUIElement) -> CGRect? {
    guard let position = copy(element, kAXPositionAttribute),
      let size = copy(element, kAXSizeAttribute),
      CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID()
    else { return nil }
    var origin = CGPoint.zero
    var extent = CGSize.zero
    guard AXValueGetValue(position as! AXValue, .cgPoint, &origin),
      AXValueGetValue(size as! AXValue, .cgSize, &extent)
    else { return nil }
    return CGRect(origin: origin, size: extent)
  }

  // MARK: - Layout

  /// The items shown on a screen, right to left (index 0 = rightmost), each
  /// spanning its full slot. Every display's menu bar shows the same items
  /// at the same distance from its right edge, so items reported on another
  /// display are moved across. Screen frames are in AppKit coordinates.
  static func items(
    from accessible: [AccessibleMenuBarItem],
    screenFrame: NSRect,
    screenFrames: [NSRect],
    primaryHeight: CGFloat,
    menuBarHeight: CGFloat
  ) -> [NativeMenuBarItem] {
    let cgScreenTop = primaryHeight - screenFrame.maxY
    let cgScreens = screenFrames.map {
      CGRect(x: $0.minX, y: primaryHeight - $0.maxY, width: $0.width, height: $0.height)
    }
    let padding = PersistedMenuBarLayout.moduleSpacing

    let slots = accessible.compactMap { item -> NativeMenuBarItem? in
      guard
        let source = cgScreens.first(where: {
          $0.contains(CGPoint(x: item.frame.midX, y: item.frame.midY))
        })
      else { return nil }
      var slot = item.frame
      slot.origin.x += screenFrame.maxX - source.maxX
      if item.isMenuBarAgentItem {
        slot = slot.insetBy(dx: -padding / 2, dy: 0)
      }
      slot.origin.y = cgScreenTop
      slot.size.height = menuBarHeight

      if let identifier = item.identifier {
        let name = String(identifier.dropFirst(systemIdentifierPrefix.count))
        return NativeMenuBarItem(
          index: 0, cgRect: slot, owner: item.owner,
          identifier: controlCentreIdentifier(forName: name),
          matchNames: [identifier, name])
      }
      return NativeMenuBarItem(
        index: 0, cgRect: slot, owner: item.owner, matchNames: item.appNames)
    }

    return slots.sorted { $0.cgRect.maxX > $1.cgRect.maxX }.enumerated().map { index, item in
      var item = item
      item.index = index
      return item
    }
  }

  /// The Control Centre identifier (e.g. `WiFi`) for a system item's
  /// Accessibility name (e.g. `wifi`), or the name itself when it has none.
  static func controlCentreIdentifier(forName name: String) -> String {
    controlCentreIdentifiers[name]
      ?? (MenuBarItemDetector.knownCCIdentifiers + ["Clock"]).first { $0.lowercased() == name }
      ?? name
  }
}
