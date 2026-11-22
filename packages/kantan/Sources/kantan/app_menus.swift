import AppKit
import ApplicationServices

/// A title in the menu bar's app menus: the Apple menu, the app's own, then
/// File, Edit and the rest.
struct AppMenuTitle: Equatable, Sendable {
  let title: String
  /// Global frame in CG coordinates, or relative to a screen's top left once
  /// placed on one.
  var frame: CGRect
  let isApple: Bool
  let isAppName: Bool
  var isOpen = false
}

/// The menus of the app that owns the menu bar.
struct AppMenus: Equatable, Sendable {
  let titles: [AppMenuTitle]

  /// How far apart two titles can be and still be in one run.
  static let runTolerance: CGFloat = 20

  /// The titles as a screen shows them, relative to its top left. They are
  /// read on one display, and another shows them at the same distance from
  /// its left edge unless a notch splits them on either. There are none
  /// where that can't be told. Screens are in CG coordinates, and
  /// `notchMinX` is relative to the screen's left edge.
  func titles(on screen: CGRect, screens: [CGRect], notchMinX: CGFloat?) -> [AppMenuTitle] {
    guard let first = titles.first?.frame,
      let source = screens.first(where: { $0.contains(CGPoint(x: first.midX, y: first.midY)) })
    else { return [] }
    let placed = titles.map { title in
      var title = title
      title.frame = title.frame.offsetBy(dx: -source.minX, dy: -source.minY)
      return title
    }
    guard source != screen else { return placed }
    let runs = Self.runs(of: placed)
    guard runs.count == 1, let run = runs.first, run.upperBound <= (notchMinX ?? screen.width)
    else { return [] }
    return placed
  }

  /// The spans of adjacent titles, which a notch parts. One starting beside
  /// the screen's left edge reaches it, as a click in the corner opens the
  /// Apple menu.
  static func runs(of titles: [AppMenuTitle]) -> [ClosedRange<CGFloat>] {
    var runs: [ClosedRange<CGFloat>] = []
    for frame in titles.map(\.frame).sorted(by: { $0.minX < $1.minX }) {
      if let last = runs.last, frame.minX <= last.upperBound + runTolerance {
        runs[runs.count - 1] = last.lowerBound...max(last.upperBound, frame.maxX)
      } else {
        runs.append((frame.minX < runTolerance ? 0 : frame.minX)...frame.maxX)
      }
    }
    return runs
  }
}

/// Reads the app menus through Accessibility, on a background queue as each
/// read waits on the app's reply.
@MainActor
final class AppMenuReader {
  /// How old the menus can be as the pointer nears the top of the screen.
  static let staleAfter: TimeInterval = 0.5

  /// The owner's menus, as last read.
  private(set) var menus: AppMenus?
  private var owner: pid_t?
  private var hasRead = false
  private var isReading = false
  private var lastRefresh = Date.distantPast
  private var activation: NSObjectProtocol?
  private var onChange: (() -> Void)?
  private let queue = DispatchQueue(label: "kantan.app-menus")

  /// Whether the owner's menus are still to be read for the first time.
  var isPending: Bool { owner != nil && !hasRead }

  /// Reads the menus now and as each app comes to the front, calling
  /// `onChange` when they differ, or are first read for an app.
  func start(onChange: @escaping () -> Void) {
    stop()
    self.onChange = onChange
    activation = NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated { self?.refresh() }
    }
    refresh()
  }

  func stop() {
    if let activation { NSWorkspace.shared.notificationCenter.removeObserver(activation) }
    activation = nil
    onChange = nil
    owner = nil
    menus = nil
    hasRead = false
  }

  func refreshIfStale() {
    if Date().timeIntervalSince(lastRefresh) >= Self.staleAfter { refresh() }
  }

  func refresh() {
    guard onChange != nil else { return }
    lastRefresh = Date()
    let current = MenuBarAccessibility.isTrusted ? Self.menuBarOwner() : nil
    if current != owner {
      owner = current
      menus = nil
      hasRead = false
    }
    guard let current, !isReading else { return }
    isReading = true
    queue.async { [weak self] in
      let fresh = Self.read(current)
      DispatchQueue.main.async {
        MainActor.assumeIsolated { self?.finishReading(fresh, of: current) }
      }
    }
  }

  /// Takes a read, keeping the last one when an app too busy to answer
  /// gives none.
  private func finishReading(_ fresh: AppMenus?, of pid: pid_t) {
    isReading = false
    guard pid == owner else {
      refresh()
      return
    }
    let isFirst = !hasRead
    hasRead = true
    let changed = fresh != nil && fresh != menus
    if let fresh { menus = fresh }
    if isFirst || changed { onChange?() }
  }

  /// The process whose menus the menu bar shows. `NSRunningApplication`
  /// reports some running apps' identifiers as -1, though looking one up by
  /// its real identifier still finds it.
  private static func menuBarOwner() -> pid_t? {
    guard let app = NSWorkspace.shared.menuBarOwningApplication else { return nil }
    let pid = app.processIdentifier
    if pid > 0 { return pid == ProcessInfo.processInfo.processIdentifier ? nil : pid }
    // Room for processes started between counting and listing them.
    var pids = [pid_t](repeating: 0, count: Int(proc_listallpids(nil, 0)) + 64)
    let count = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.stride))
    return pids.prefix(max(Int(count), 0)).first {
      $0 > 0 && NSRunningApplication(processIdentifier: $0)?.isEqual(app) == true
    }
  }

  /// An app's menus, or nil when it doesn't answer or has none on screen.
  nonisolated private static func read(_ pid: pid_t) -> AppMenus? {
    // Set on the system-wide element, the timeout covers the elements read
    // from the app too.
    AXUIElementSetMessagingTimeout(
      AXUIElementCreateSystemWide(), MenuBarAccessibility.messagingTimeout)
    let app = AXUIElementCreateApplication(pid)
    AXUIElementSetMessagingTimeout(app, MenuBarAccessibility.messagingTimeout)
    guard let value = copy(app, kAXMenuBarAttribute), CFGetTypeID(value) == AXUIElementGetTypeID()
    else { return nil }
    let bar = value as! AXUIElement
    guard let items = copy(bar, kAXChildrenAttribute) as? [AXUIElement] else { return nil }
    let open = copy(bar, kAXSelectedChildrenAttribute) as? [AXUIElement] ?? []

    let attributes = [kAXTitleAttribute, kAXPositionAttribute, kAXSizeAttribute] as CFArray
    var titles: [AppMenuTitle] = []
    for (index, item) in items.enumerated() {
      var result: CFArray?
      guard AXUIElementCopyMultipleAttributeValues(item, attributes, [], &result) == .success,
        let values = result as? [AnyObject], values.count == 3
      else { return nil }
      guard CFGetTypeID(values[1]) == AXValueGetTypeID(),
        CFGetTypeID(values[2]) == AXValueGetTypeID()
      else { continue }
      var origin = CGPoint.zero
      var size = CGSize.zero
      // An app that has yet to own the menu bar gives its titles empty frames.
      guard AXValueGetValue(values[1] as! AXValue, .cgPoint, &origin),
        AXValueGetValue(values[2] as! AXValue, .cgSize, &size),
        size.width > 0, size.height > 0
      else { continue }
      titles.append(
        AppMenuTitle(
          title: values[0] as? String ?? "", frame: CGRect(origin: origin, size: size),
          isApple: index == 0, isAppName: index == 1,
          isOpen: open.contains { CFEqual($0, item) }))
    }
    return titles.isEmpty ? nil : AppMenus(titles: titles)
  }

  nonisolated private static func copy(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success
    else { return nil }
    return value
  }
}
