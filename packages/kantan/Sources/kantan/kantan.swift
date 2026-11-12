import AppKit
import Combine
import SwiftUI

// MARK: - NSScreen Notch Detection

extension NSScreen {
  /// Whether this screen has a camera housing (notch) at the top.
  var hasNotch: Bool {
    safeAreaInsets.top != 0
  }

  /// The usable area to the left of the notch (the left "ear").
  /// Returns .zero on non-notch screens.
  var notchLeftArea: NSRect {
    auxiliaryTopLeftArea ?? .zero
  }

  /// The usable area to the right of the notch (the right "ear").
  /// Returns .zero on non-notch screens.
  var notchRightArea: NSRect {
    auxiliaryTopRightArea ?? .zero
  }
}

/// Returns "left" or "right" for any placement value.
private func drawerSide(for placement: String) -> String {
  placement.contains("right") ? "right" : "left"
}

// MARK: - Screen Layout

/// Bar geometry derived from a screen frame, gap config, and bar height.
/// Centralises the math used when creating, repositioning, and animating
/// panels so the same screen-frame + gap arithmetic isn't restated each
/// time a panel needs to be placed.
struct ScreenLayout {
  let statusBarY: CGFloat
  let screenLeft: CGFloat
  let screenRight: CGFloat
  let barFrame: NSRect

  init(screenFrame: NSRect, gaps: GapsConfig, height: CGFloat) {
    self.screenLeft = screenFrame.origin.x
    self.screenRight = screenFrame.origin.x + screenFrame.width
    self.statusBarY = screenFrame.origin.y + screenFrame.height - height - gaps.top
    self.barFrame = NSRect(
      x: screenLeft + gaps.left,
      y: statusBarY,
      width: screenFrame.width - gaps.left - gaps.right,
      height: height)
  }

  init(screen: NSScreen, gaps: GapsConfig, height: CGFloat) {
    self.init(screenFrame: screen.frame, gaps: gaps, height: height)
  }
}

// MARK: - Screen Diff

/// Result of diffing a set of existing displays against a desired target set.
/// `toAdd` preserves the order of the target list so newly added displays
/// appear in the same order the caller resolved them.
struct ScreenDiff: Equatable {
  let toRemove: Set<String>
  let toAdd: [String]
}

/// Diff a list of currently-managed display names against the desired list.
/// Symmetric set difference; `toAdd` is filtered from `target` to preserve order.
func computeScreenDiff(existing: [String], target: [String]) -> ScreenDiff {
  let existingSet = Set(existing)
  let targetSet = Set(target)
  return ScreenDiff(
    toRemove: existingSet.subtracting(targetSet),
    toAdd: target.filter { !existingSet.contains($0) }
  )
}

// MARK: - Drawer Click View

/// Content view for drawer-toggle panels that cover gaps between module
/// group panels. Catches clicks and forwards them as screen-coordinate
/// points to the `onClick` closure (drawer toggle logic).
class DrawerClickView: NSView {
  var onClick: ((NSPoint) -> Void)?

  override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
    return true
  }

  override func hitTest(_ point: NSPoint) -> NSView? {
    return self
  }

  override func mouseDown(with event: NSEvent) {
    guard let window = self.window else { return }
    let screenPoint = window.convertPoint(toScreen: event.locationInWindow)
    onClick?(screenPoint)
  }
}

// MARK: - Command Line

/// What kantan's positional arguments ask it to do.
enum KantanCommand: Equatable {
  /// Run the bar.
  case run
  /// Print the usage.
  case help
  /// Print kantan's version.
  case version
  /// Post a trigger event with these fields to the running bar.
  case trigger([String: String])
  /// The arguments aren't a command kantan knows.
  case usageError(String)
}

let kantanUsage = """
  usage: kantan [--config <path>] [--modules-dir <path>] [--fonts-dir <path>] [--themes-dir <path>]
         kantan trigger <module> <action> [key=value ...]
         kantan --help | --version

    --config <path>       config file to load
    --modules-dir <path>  modules.d directory to load
    --fonts-dir <path>    bundled fonts directory
    --themes-dir <path>   bundled themes directory
    -h, --help            show this help
    -V, --version         show kantan's version

    trigger <module> <action> [key=value ...]
                          send an action (refresh, set, ...) to a running bar;
                          <module> is a module's name, or '*' for all
  """

/// The paths kantan's flags set, with `~` expanded.
struct KantanOptions: Equatable {
  var configPath: String?
  var modulesDirPath: String?
  var fontsDirPath: String?
  var themesDirPath: String?
}

/// kantan's command-line arguments, after the program name: the options
/// its flags set and the command they ask for. An unknown `--` flag, or a
/// path flag without its path, is a usage error; other arguments starting
/// with `-` are ignored, as macOS may pass its own.
func parseArguments(_ args: some Collection<String>) -> (
  options: KantanOptions, command: KantanCommand
) {
  let paths: [String: WritableKeyPath<KantanOptions, String?>] = [
    "--config": \.configPath, "--modules-dir": \.modulesDirPath,
    "--fonts-dir": \.fontsDirPath, "--themes-dir": \.themesDirPath,
  ]
  var options = KantanOptions()
  var words: [String] = []
  var remaining = Array(args)[...]
  while let arg = remaining.popFirst() {
    if arg == "-h" || arg == "--help" { return (options, .help) }
    if arg == "-V" || arg == "--version" { return (options, .version) }
    if let path = paths[arg] {
      guard let value = remaining.popFirst() else {
        return (options, .usageError("\(arg) needs a path"))
      }
      options[keyPath: path] = (value as NSString).expandingTildeInPath
    } else if arg.hasPrefix("--") {
      return (options, .usageError("unknown option '\(arg)'"))
    } else {
      words.append(arg)
    }
  }
  return (options, parseCommand(words))
}

/// The command for the positional arguments that follow the program name.
/// Arguments starting with `-` are ignored, as macOS may pass its own.
func parseCommand(_ args: some Collection<String>) -> KantanCommand {
  let words = args.filter { !$0.hasPrefix("-") }
  guard let command = words.first else { return .run }
  guard command == "trigger" else { return .usageError("unknown command '\(command)'") }
  guard words.count >= 3 else { return .usageError("trigger needs a module and an action") }
  var fields = parseTriggerFields(words.dropFirst(3))
  fields["module"] = words[1]
  fields["action"] = words[2]
  return .trigger(fields)
}

// MARK: - Trigger Fields

/// The `key=value` arguments of `kantan trigger`, keeping empty values such
/// as `value=`, which clear what they name. Arguments without `=` are ignored.
func parseTriggerFields(_ args: some Sequence<String>) -> [String: String] {
  args.reduce(into: [:]) { fields, arg in
    let parts = arg.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
    if parts.count == 2, !parts[0].isEmpty {
      fields[String(parts[0])] = String(parts[1])
    }
  }
}

// MARK: - Display Instance

@MainActor
class DisplayInstance {
  let screenName: String
  var bgPanel: NSPanel?
  var groupPanels:
    [(panel: NSPanel, hostingView: NSHostingView<ModuleGroupView>, group: ModuleGroup)] = []
  var drawerClickPanels: [NSPanel] = []
  var bgColorCancellable: AnyCancellable?
  /// View whose layer background tracks light/dark mode changes
  /// (the tint view inside the effect view when blur is on, or the
  /// solid background view otherwise). `nil` for native appearance mode.
  private weak var themedBackgroundView: NSView?
  var leftDrawerOpen: Bool = false
  var rightDrawerOpen: Bool = false
  private weak var barViewModel: BarViewModel?

  var isMenuBarShowing: Bool = false
  var isHoveringTopEdge: Bool = false
  var enteredFromAbove: Bool = false
  nonisolated(unsafe) var autohideDelayTimer: Timer?

  private let barHeight: CGFloat
  private let config: Config

  init(screenName: String, barHeight: CGFloat, config: Config) {
    self.screenName = screenName
    self.barHeight = barHeight
    self.config = config
  }

  /// `nil` displays means show everywhere.
  private func moduleMatchesDisplay(_ vm: ModuleViewModel, screen: NSScreen) -> Bool {
    guard let displays = vm.moduleConfig.displays else { return true }
    switch displays {
    case .all:
      return true
    case .main:
      return screen == NSScreen.main || (NSScreen.main == nil && screen == NSScreen.screens.first)
    case .named(let names):
      return names.contains(screen.localizedName)
    }
  }

  /// Whether the drawer for the given side is open.
  func isDrawerOpen(side: String) -> Bool {
    side == "left" ? leftDrawerOpen : rightDrawerOpen
  }

  /// Whether a drawer-content group should currently be hidden.
  func isDrawerContentHidden(_ group: ModuleGroup) -> Bool {
    guard group.isDrawerContent else { return false }
    return !isDrawerOpen(side: drawerSide(for: group.placement))
  }

  /// Groups that become empty after filtering are removed entirely.
  private func filterGroups(_ groups: [ModuleGroup], for screen: NSScreen) -> [ModuleGroup] {
    groups.compactMap { group in
      let filtered = group.modules.filter { moduleMatchesDisplay($0, screen: screen) }
      guard !filtered.isEmpty else { return nil }
      return ModuleGroup(
        id: group.id, modules: filtered, isPassthrough: group.isPassthrough,
        placement: group.placement, isDrawerContent: group.isDrawerContent)
    }
  }

  func resolveScreen() -> NSScreen? {
    NSScreen.screens.first { $0.localizedName == screenName }
  }

  private func resolveStyleMode(isDark: Bool) -> StyleModeConfig {
    if isDark {
      return config.style.dark ?? config.style.light
        ?? StyleModeConfig(fg: "FFFFFF", bg: "000000", text: nil, icon: nil, shape: nil)
    } else {
      return config.style.light ?? config.style.dark
        ?? StyleModeConfig(fg: "FFFFFF", bg: "000000", text: nil, icon: nil, shape: nil)
    }
  }

  private func screenLayout(for screen: NSScreen) -> ScreenLayout {
    ScreenLayout(screen: screen, gaps: config.gaps, height: barHeight)
  }

  private func configurePanelDefaults(_ panel: NSPanel, level: NSWindow.Level) {
    panel.level = level
    panel.collectionBehavior = .canJoinAllSpaces
    panel.isOpaque = false
    panel.hasShadow = false
    panel.backgroundColor = NSColor.clear
  }

  /// Positioning boundaries for all four placement zones.
  struct PlacementBounds {
    /// Left placement: grows rightward from screen left edge.
    var leftX: CGFloat
    /// Left placement: maximum X boundary (notch left edge or screen center).
    var leftBound: CGFloat
    /// Right placement: grows leftward from screen right edge.
    var rightX: CGFloat
    /// Right placement: minimum X boundary (notch right edge or screen center).
    var rightBound: CGFloat
    /// Notchleft placement: grows leftward from notch left edge.
    var notchLeftX: CGFloat
    /// Notchleft placement: minimum X boundary.
    var notchLeftBound: CGFloat
    /// Notchright placement: grows rightward from notch right edge.
    var notchRightX: CGFloat
    /// Notchright placement: maximum X boundary.
    var notchRightBound: CGFloat
  }

  /// Masked groups that occupy their native item's slot. A hidden masked
  /// module (e.g. focus while no Focus mode is on) releases its slot.
  private func occupiedMasks(in groups: [ModuleGroup]) -> [(placement: String, mask: MaskConfig)] {
    groups.compactMap { group in
      guard group.modules.count == 1, group.modules[0].shouldDisplay,
        let mask = group.modules[0].moduleConfig.mask
      else { return nil }
      return (group.placement, mask)
    }
  }

  private func computePlacementBounds(
    screen: NSScreen,
    nativeItems: [NativeMenuBarItem],
    maskedGroups: [(placement: String, mask: MaskConfig)]
  ) -> PlacementBounds {
    let gaps = config.gaps
    let layout = screenLayout(for: screen)
    let screenLeft = layout.screenLeft
    let screenRight = layout.screenRight

    var leftX = screenLeft + gaps.left
    var rightX = screenRight - gaps.right

    var notchLeftX: CGFloat = 0
    var notchLeftBound: CGFloat = 0
    var notchRightX: CGFloat = 0
    var notchRightBound: CGFloat = 0
    var leftBound = screenRight
    var rightBound = screenLeft

    if screen.hasNotch {
      let leftEar = screen.notchLeftArea
      let rightEar = screen.notchRightArea
      // Left placement bounded by notch left edge
      leftBound = leftEar.maxX
      // Right placement bounded by notch right edge
      rightBound = rightEar.minX
      // Notchleft: starts at notch left edge, grows leftward
      notchLeftX = leftEar.maxX
      notchLeftBound = screenLeft + gaps.left
      // Notchright: starts at notch right edge, grows rightward
      notchRightX = rightEar.minX
      notchRightBound = screenRight - gaps.right
    }

    // Adjust boundaries for masked modules
    for (placement, mask) in maskedGroups {
      guard let nativeItem = MenuBarItemDetector.resolveItem(for: mask, from: nativeItems) else {
        continue
      }
      let nativeRect = MenuBarItemDetector.appKitRect(from: nativeItem.cgRect, on: screen)
      switch placement {
      case "right":
        rightX = min(rightX, nativeRect.origin.x)
      case "left":
        leftX = max(leftX, nativeRect.origin.x + nativeRect.width)
      case "notchleft":
        notchLeftX = min(notchLeftX, nativeRect.origin.x)
      case "notchright":
        notchRightX = max(notchRightX, nativeRect.origin.x + nativeRect.width)
      default:
        break
      }
    }

    return PlacementBounds(
      leftX: leftX, leftBound: leftBound,
      rightX: rightX, rightBound: rightBound,
      notchLeftX: notchLeftX, notchLeftBound: notchLeftBound,
      notchRightX: notchRightX, notchRightBound: notchRightBound)
  }

  func createPanels(for screen: NSScreen, bar: BarViewModel, theme: ThemeProvider) {
    let radius = config.cornerRadius
    let layout = screenLayout(for: screen)
    let statusBarY = layout.statusBarY
    let statusWindowLevel = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)))

    let bgRect = layout.barFrame

    let panel = NSPanel(
      contentRect: bgRect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered,
      defer: false)
    configurePanelDefaults(panel, level: statusWindowLevel)
    panel.ignoresMouseEvents = true
    bgPanel = panel
    self.barViewModel = bar

    let containerView = NSView(frame: NSRect(origin: .zero, size: bgRect.size))
    containerView.autoresizingMask = [.width, .height]
    panel.contentView = containerView

    if config.blur > 0 {
      // blur 1 = most transparent (heavy blur), 6 = most opaque (subtle blur)
      let tintOpacity = CGFloat(config.blur) / 7.0

      let effectView = NSVisualEffectView(frame: NSRect(origin: .zero, size: bgRect.size))
      effectView.material = .fullScreenUI
      effectView.state = .active
      effectView.blendingMode = .behindWindow
      effectView.wantsLayer = true
      effectView.layer?.cornerRadius = radius
      effectView.layer?.masksToBounds = true
      effectView.autoresizingMask = [.width, .height]

      let globalStyle = resolveStyleMode(isDark: theme.isDarkMode)
      let tintView = NSView(frame: NSRect(origin: .zero, size: bgRect.size))
      tintView.wantsLayer = true
      tintView.layer?.backgroundColor =
        NSColor(hex: globalStyle.bg ?? "000000").withAlphaComponent(tintOpacity).cgColor
      tintView.autoresizingMask = [.width, .height]
      effectView.addSubview(tintView)

      containerView.addSubview(effectView)
      themedBackgroundView = tintView

      bgColorCancellable = theme.$isDarkMode.sink { [weak self] isDark in
        guard let self = self, let tintView = self.themedBackgroundView else { return }
        let mode = self.resolveStyleMode(isDark: isDark)
        tintView.layer?.backgroundColor =
          NSColor(hex: mode.bg ?? "000000").withAlphaComponent(tintOpacity).cgColor
      }
    } else if config.isNativeAppearance {
      let effectView = NSVisualEffectView(frame: NSRect(origin: .zero, size: bgRect.size))
      effectView.material = .headerView
      effectView.state = .active
      effectView.blendingMode = .behindWindow
      effectView.wantsLayer = true
      effectView.layer?.cornerRadius = radius
      effectView.layer?.masksToBounds = true
      effectView.autoresizingMask = [.width, .height]
      containerView.addSubview(effectView)
    } else {
      let bgView = NSView(frame: NSRect(origin: .zero, size: bgRect.size))
      bgView.wantsLayer = true
      let globalStyle = resolveStyleMode(isDark: theme.isDarkMode)
      bgView.layer?.backgroundColor = NSColor(hex: globalStyle.bg ?? "000000").cgColor
      bgView.layer?.cornerRadius = radius
      bgView.layer?.masksToBounds = true
      bgView.autoresizingMask = [.width, .height]
      containerView.addSubview(bgView)
      themedBackgroundView = bgView

      bgColorCancellable = theme.$isDarkMode.sink { [weak self] isDark in
        guard let self = self, let bgView = self.themedBackgroundView else { return }
        let mode = self.resolveStyleMode(isDark: isDark)
        bgView.layer?.backgroundColor = NSColor(hex: mode.bg ?? "000000").cgColor
      }
    }

    panel.orderFrontRegardless()

    let moduleGroupLevel = NSWindow.Level(rawValue: statusWindowLevel.rawValue + 1)
    let allGroups = filterGroups(bar.buildGroups(hasNotch: screen.hasNotch), for: screen)

    let nativeItems = MenuBarItemDetector.detectItems(for: screen)

    var bounds = computePlacementBounds(
      screen: screen, nativeItems: nativeItems, maskedGroups: occupiedMasks(in: allGroups))

    for group in allGroups {
      let groupView = ModuleGroupView(
        modules: group.modules,
        placement: group.placement,
        popupManager: bar.popupManager,
        themeProvider: theme
      )
      let hostingView = NSHostingView(rootView: groupView)

      // Skip drawer content in positioning when its side's drawer is closed
      let skipPositioning = isDrawerContentHidden(group)

      let panelRect: NSRect
      if group.modules.count == 1,
        let mask = group.modules[0].moduleConfig.mask,
        let nativeItem = MenuBarItemDetector.resolveItem(for: mask, from: nativeItems)
      {
        let nativeRect = MenuBarItemDetector.appKitRect(from: nativeItem.cgRect, on: screen)
        panelRect = NSRect(
          x: nativeRect.origin.x, y: statusBarY, width: nativeRect.width, height: barHeight)
      } else if skipPositioning {
        // Place off-screen; will be positioned correctly when drawer opens
        panelRect = NSRect(x: bounds.rightX, y: statusBarY, width: 0, height: barHeight)
      } else {
        let fittingWidth = hostingView.fittingSize.width
        panelRect = positionPanel(
          placement: group.placement, fittingWidth: fittingWidth,
          statusBarY: statusBarY, bounds: &bounds)
      }

      let groupPanel = NSPanel(
        contentRect: panelRect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered,
        defer: false)
      configurePanelDefaults(groupPanel, level: moduleGroupLevel)
      groupPanel.ignoresMouseEvents = group.isPassthrough

      hostingView.frame = NSRect(origin: .zero, size: panelRect.size)
      hostingView.autoresizingMask = [.width, .height]
      groupPanel.contentView = hostingView

      if skipPositioning {
        groupPanel.orderOut(nil)
      } else {
        groupPanel.orderFrontRegardless()
      }

      groupPanels.append((panel: groupPanel, hostingView: hostingView, group: group))
    }

    updateDrawerClickPanels()
  }

  /// Position a panel within a placement zone and advance the boundary cursor.
  private func positionPanel(
    placement: String, fittingWidth: CGFloat, statusBarY: CGFloat,
    bounds: inout PlacementBounds
  ) -> NSRect {
    let panelX: CGFloat
    switch placement {
    case "left":
      panelX = bounds.leftX
      bounds.leftX += fittingWidth
    case "right":
      bounds.rightX -= fittingWidth
      panelX = bounds.rightX
    case "notchleft":
      // Grows leftward from notch left edge
      bounds.notchLeftX -= fittingWidth
      panelX = bounds.notchLeftX
    case "notchright":
      // Grows rightward from notch right edge
      panelX = bounds.notchRightX
      bounds.notchRightX += fittingWidth
    default:
      panelX = bounds.leftX
      bounds.leftX += fittingWidth
    }
    return NSRect(x: panelX, y: statusBarY, width: fittingWidth, height: barHeight)
  }

  /// Moves every panel into place. `animated` animates the unmasked panels
  /// in step with module content changing size.
  func repositionPanels(animated: Bool = false) {
    guard let screen = resolveScreen(),
      let bgPanel = bgPanel
    else { return }
    let layout = screenLayout(for: screen)
    let statusBarY = layout.statusBarY
    bgPanel.setFrame(layout.barFrame, display: true)

    let nativeItems = MenuBarItemDetector.detectItems(for: screen)

    var bounds = computePlacementBounds(
      screen: screen, nativeItems: nativeItems,
      maskedGroups: occupiedMasks(in: groupPanels.map { $0.group }))

    for entry in groupPanels {
      guard entry.group.modules.count == 1,
        let mask = entry.group.modules[0].moduleConfig.mask
      else { continue }

      guard entry.group.modules[0].shouldDisplay,
        let nativeItem = MenuBarItemDetector.resolveItem(for: mask, from: nativeItems)
      else {
        entry.panel.orderOut(nil)
        continue
      }

      let nativeRect = MenuBarItemDetector.appKitRect(from: nativeItem.cgRect, on: screen)
      let panelFrame = NSRect(
        x: nativeRect.origin.x, y: statusBarY, width: nativeRect.width, height: barHeight)
      entry.panel.setFrame(panelFrame, display: true)
      if !entry.panel.isVisible {
        entry.panel.orderFrontRegardless()
      }
    }

    var targets: [(panel: NSPanel, frame: NSRect)] = []
    for entry in groupPanels {
      if entry.group.modules.count == 1 && entry.group.modules[0].moduleConfig.mask != nil {
        continue
      }

      // Skip drawer content panels when their side's drawer is closed
      if isDrawerContentHidden(entry.group) {
        continue
      }

      let fittingWidth = entry.hostingView.fittingSize.width
      let panelFrame = positionPanel(
        placement: entry.group.placement, fittingWidth: fittingWidth,
        statusBarY: statusBarY, bounds: &bounds)
      targets.append((entry.panel, panelFrame))
    }

    guard animated, targets.contains(where: { $0.panel.frame != $0.frame }) else {
      for target in targets {
        target.panel.setFrame(target.frame, display: true)
      }
      updateDrawerClickPanels()
      return
    }
    NSAnimationContext.runAnimationGroup(
      { context in
        context.duration = ModuleAnimation.duration
        context.timingFunction = ModuleAnimation.panelTiming
        for target in targets {
          target.panel.animator().setFrame(target.frame, display: true)
        }
      },
      completionHandler: { [weak self] in
        DispatchQueue.main.async {
          MainActor.assumeIsolated {
            self?.updateDrawerClickPanels()
          }
        }
      })
  }

  // MARK: - Drawer Click Panels

  /// Creates transparent panels in the horizontal gaps between group panels.
  /// These catch clicks for the "click empty space to toggle drawer" feature
  /// while keeping the bgPanel fully `ignoresMouseEvents` for passthrough.
  func updateDrawerClickPanels() {
    for panel in drawerClickPanels { panel.orderOut(nil) }
    drawerClickPanels.removeAll()

    guard let bgPanel = bgPanel, let bar = barViewModel, bar.hasDrawer else { return }

    let barFrame = bgPanel.frame
    let level = bgPanel.level

    // Collect x-ranges of all visible group panels.
    var ranges: [(minX: CGFloat, maxX: CGFloat)] = []
    for entry in groupPanels where entry.panel.isVisible {
      let f = entry.panel.frame
      ranges.append((f.minX, f.maxX))
    }
    ranges.sort { $0.minX < $1.minX }

    // Merge overlapping/adjacent ranges.
    var merged: [(minX: CGFloat, maxX: CGFloat)] = []
    for r in ranges {
      if let last = merged.last, r.minX <= last.maxX {
        merged[merged.count - 1].maxX = max(last.maxX, r.maxX)
      } else {
        merged.append(r)
      }
    }

    // Compute gap rects.
    var gapRects: [NSRect] = []
    var x = barFrame.minX
    for r in merged {
      if r.minX > x {
        gapRects.append(NSRect(x: x, y: barFrame.minY, width: r.minX - x, height: barFrame.height))
      }
      x = r.maxX
    }
    if x < barFrame.maxX {
      gapRects.append(
        NSRect(x: x, y: barFrame.minY, width: barFrame.maxX - x, height: barFrame.height))
    }

    for rect in gapRects {
      let panel = NSPanel(
        contentRect: rect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered,
        defer: false)
      configurePanelDefaults(panel, level: level)
      // A fully transparent window is skipped by the WindowServer for hit
      // testing. Use a near-invisible background so it registers as a click
      // target (same principle as .background(.black.opacity(0.001)) in SwiftUI).
      panel.backgroundColor = NSColor.black.withAlphaComponent(0.001)

      let clickView = DrawerClickView(frame: NSRect(origin: .zero, size: rect.size))
      clickView.autoresizingMask = [.width, .height]
      clickView.onClick = { [weak bar, weak self] screenPoint in
        guard let bar, let self, let screen = self.resolveScreen() else { return }
        let screenMidX = screen.frame.origin.x + screen.frame.width / 2
        if screenPoint.x < screenMidX && bar.hasLeftDrawer {
          bar.toggleDrawer(side: "left")
        } else if screenPoint.x >= screenMidX && bar.hasRightDrawer {
          bar.toggleDrawer(side: "right")
        }
      }
      panel.contentView = clickView
      panel.orderFrontRegardless()
      drawerClickPanels.append(panel)
    }
  }

  // MARK: - Drawer Animation

  func animateDrawerToggle(side: String, open: Bool) {
    guard let screen = resolveScreen() else { return }
    if side == "left" {
      leftDrawerOpen = open
    } else {
      rightDrawerOpen = open
    }
    let statusBarY = screenLayout(for: screen).statusBarY

    let nativeItems = MenuBarItemDetector.detectItems(for: screen)
    var bounds = computePlacementBounds(
      screen: screen, nativeItems: nativeItems,
      maskedGroups: occupiedMasks(in: groupPanels.map { $0.group }))

    // Helper: is this group's drawer content for the toggled side?
    let isToggledDrawerContent = { (group: ModuleGroup) -> Bool in
      group.isDrawerContent && drawerSide(for: group.placement) == side
    }

    // Calculate target frames for all non-masked panels
    var targetFrames:
      [(
        entry: (panel: NSPanel, hostingView: NSHostingView<ModuleGroupView>, group: ModuleGroup),
        frame: NSRect
      )] = []

    for entry in groupPanels {
      // Skip masked panels (they don't move)
      if entry.group.modules.count == 1 && entry.group.modules[0].moduleConfig.mask != nil {
        continue
      }

      // Skip this side's drawer content when closing
      if isToggledDrawerContent(entry.group) && !open {
        continue
      }

      // Skip the OTHER side's drawer content if that side is closed
      if entry.group.isDrawerContent && !isToggledDrawerContent(entry.group)
        && !isDrawerOpen(side: drawerSide(for: entry.group.placement))
      {
        continue
      }

      let fittingWidth = entry.hostingView.fittingSize.width
      let frame = positionPanel(
        placement: entry.group.placement, fittingWidth: fittingWidth,
        statusBarY: statusBarY, bounds: &bounds)
      targetFrames.append((entry: entry, frame: frame))
    }

    let drawerContentPanels = groupPanels.filter { isToggledDrawerContent($0.group) }

    // Detect notch-placed panels that would be overlapped by the toggled side's
    // expanded drawer content. Only drawer content rects can displace notch panels.
    let isNotchPlacement = { (p: String) in p == "notchleft" || p == "notchright" }

    if open {
      let drawerContentRects = targetFrames.filter { isToggledDrawerContent($0.entry.group) }.map {
        $0.frame
      }
      let displacedNotchPanels = groupPanels.filter { entry in
        guard isNotchPlacement(entry.group.placement) else { return false }
        let panelFrame = entry.panel.frame
        return drawerContentRects.contains { $0.intersects(panelFrame) }
      }
      // Opening: position drawer-content panels at target with alpha 0, then animate in
      for entry in drawerContentPanels {
        if let target = targetFrames.first(where: { $0.entry.panel === entry.panel }) {
          entry.panel.setFrame(target.frame, display: true)
        }
        entry.panel.alphaValue = 0
        entry.panel.orderFrontRegardless()
      }

      NSAnimationContext.runAnimationGroup(
        { context in
          context.duration = 0.25
          context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)

          for entry in drawerContentPanels {
            entry.panel.animator().alphaValue = 1
          }

          for target in targetFrames where !isToggledDrawerContent(target.entry.group) {
            target.entry.panel.animator().setFrame(target.frame, display: true)
          }

          for entry in displacedNotchPanels {
            entry.panel.animator().alphaValue = 0
          }
        },
        completionHandler: { [weak self] in
          DispatchQueue.main.async {
            MainActor.assumeIsolated {
              self?.updateDrawerClickPanels()
            }
          }
        })
    } else {
      let displacedNotchPanels = groupPanels.filter { entry in
        isNotchPlacement(entry.group.placement) && entry.panel.alphaValue == 0
      }

      NSAnimationContext.runAnimationGroup(
        { context in
          context.duration = 0.25
          context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)

          for entry in drawerContentPanels {
            entry.panel.animator().alphaValue = 0
          }

          for target in targetFrames {
            target.entry.panel.animator().setFrame(target.frame, display: true)
          }

          for entry in displacedNotchPanels {
            entry.panel.animator().alphaValue = 1
          }
        },
        completionHandler: { [weak self] in
          DispatchQueue.main.async {
            MainActor.assumeIsolated {
              for entry in drawerContentPanels {
                entry.panel.orderOut(nil)
              }
              self?.updateDrawerClickPanels()
            }
          }
        })
    }
  }

  // MARK: - Autohide

  func checkMenuBar(mouseLocation: NSPoint, autohideConfig: AutohideConfig) {
    guard let screen = resolveScreen() else { return }
    let mouseX = mouseLocation.x
    let mouseY = mouseLocation.y
    let screenTop = screen.frame.maxY
    let menuBarRegion = screen.frame.maxY - screen.visibleFrame.maxY

    // When the cursor is at or beyond screenTop and within this screen's X range,
    // check if there's actually a screen above. If not, the cursor is physically
    // clamped at the top edge and should be treated as on-screen.
    let atPhysicalTop =
      mouseY >= screenTop
      && mouseX >= screen.frame.minX && mouseX <= screen.frame.maxX
    let hasScreenAbove =
      atPhysicalTop
      && NSScreen.screens.contains(where: { other in
        other !== screen
          && other.frame.minY >= screenTop - 1
          && mouseX >= other.frame.minX && mouseX <= other.frame.maxX
      })
    let clampedAtTop = atPhysicalTop && !hasScreenAbove

    let onScreen =
      (mouseX >= screen.frame.minX && mouseX <= screen.frame.maxX
        && mouseY >= screen.frame.minY && mouseY < screenTop)
      || clampedAtTop
    let inTriggerZone = onScreen && mouseY >= screenTop - 4

    if !onScreen {
      enteredFromAbove = true
    } else if enteredFromAbove && !inTriggerZone {
      enteredFromAbove = false
    }

    let atTopEdge = inTriggerZone && !enteredFromAbove

    if !isMenuBarShowing && atTopEdge {
      if !isHoveringTopEdge {
        isHoveringTopEdge = true
        if autohideConfig.delay <= 0 {
          isMenuBarShowing = true
          slideOut()
        } else {
          autohideDelayTimer?.invalidate()
          autohideDelayTimer = Timer.scheduledTimer(
            withTimeInterval: autohideConfig.delay, repeats: false
          ) { [weak self] _ in
            MainActor.assumeIsolated {
              guard let self = self, self.isHoveringTopEdge else { return }
              self.isMenuBarShowing = true
              self.slideOut()
            }
          }
        }
      }
    } else if !atTopEdge {
      if isHoveringTopEdge {
        isHoveringTopEdge = false
        autohideDelayTimer?.invalidate()
        autohideDelayTimer = nil
      }
      if isMenuBarShowing && (!onScreen || mouseY < screenTop - menuBarRegion) {
        isMenuBarShowing = false
        slideIn()
      }
    }
  }

  // MARK: - Slide Animation

  /// All panels that should be visible (excludes drawer-content panels when their side is closed).
  var visiblePanels: [NSPanel] {
    [bgPanel].compactMap { $0 }
      + groupPanels.filter { !isDrawerContentHidden($0.group) }.map { $0.panel }
      + drawerClickPanels
  }

  /// All panels including hidden drawer-content panels.
  var allPanels: [NSPanel] {
    [bgPanel].compactMap { $0 } + groupPanels.map { $0.panel } + drawerClickPanels
  }

  func slideOut() {
    let panels = visiblePanels
    NSAnimationContext.runAnimationGroup(
      { context in
        context.duration = 0.2
        context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        for panel in panels {
          panel.animator().alphaValue = 0
        }
      },
      completionHandler: {
        DispatchQueue.main.async {
          MainActor.assumeIsolated { [weak self] in
            guard let self = self, self.isMenuBarShowing else { return }
            for panel in panels {
              panel.orderOut(nil)
            }
          }
        }
      })
  }

  func slideIn() {
    repositionPanels()

    let panels = visiblePanels
    for panel in panels {
      panel.alphaValue = 0
      panel.orderFrontRegardless()
    }

    NSAnimationContext.runAnimationGroup { context in
      context.duration = 0.2
      context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
      for panel in panels {
        panel.animator().alphaValue = 1
      }
    }
  }

  func teardown() {
    autohideDelayTimer?.invalidate()
    autohideDelayTimer = nil
    bgColorCancellable?.cancel()
    bgColorCancellable = nil
    themedBackgroundView = nil
    for panel in allPanels {
      panel.orderOut(nil)
    }
    groupPanels.removeAll()
    drawerClickPanels.removeAll()
    bgPanel = nil
  }
}

// MARK: - App Delegate

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
  var displayInstances: [DisplayInstance] = []
  var barViewModel: BarViewModel?
  var themeProvider: ThemeProvider?
  var config: Config?
  var barHeight: CGFloat = 0
  var autohideConfig: AutohideConfig = .default
  nonisolated(unsafe) var menuBarMonitor: Any?
  nonisolated(unsafe) var repositionTimer: Timer?
  var visibilityCancellables: [AnyCancellable] = []
  /// Whether this launch has asked for Accessibility permission, so config
  /// reloads don't ask again.
  var requestedAccessibility = false
  var configFilePath: String?
  var modulesDirPath: String?
  nonisolated(unsafe) var configFileSource: DispatchSourceFileSystemObject?
  nonisolated(unsafe) var configSymlinkDirSource: DispatchSourceFileSystemObject?
  var resolvedConfigPath: String?
  nonisolated(unsafe) var modulesDirSource: DispatchSourceFileSystemObject?
  nonisolated(unsafe) var moduleFileSources: [DispatchSourceFileSystemObject] = []
  nonisolated(unsafe) var reloadDebounceTimer: Timer?
  nonisolated(unsafe) var configPollTimer: Timer?

  func applicationDidFinishLaunching(_ aNotification: Notification) {
    NSApp.setActivationPolicy(.accessory)

    let config: Config

    if let configPath = resolveConfigPath(explicit: Kantan.configPath) {
      self.configFilePath = configPath

      let modulesDirPath = resolveModulesDir(
        explicit: Kantan.modulesDirPath, configPath: configPath)
      self.modulesDirPath = modulesDirPath

      switch loadConfigFile(at: configPath, modulesDir: modulesDirPath) {
      case .success(let loaded):
        config = loaded
      case .failure(let error):
        print("Config \(configPath) \(error.summary)\(Self.detail(of: error))")
        config = .loadError(error, path: configPath)
      }
    } else {
      config = .welcome
    }

    if config.needsBundledIconFonts {
      initIconFonts()
    }

    self.config = config
    barHeight = CGFloat(config.height)
    autohideConfig = config.autohide

    buildBar(with: config)

    NotificationCenter.default.addObserver(
      self, selector: #selector(screenDidChange),
      name: NSApplication.didChangeScreenParametersNotification, object: nil
    )

    if let configPath = configFilePath {
      startWatchingConfig(path: configPath)
    } else {
      startPollingForConfig()
    }
    if let modulesDirPath = modulesDirPath {
      startWatchingModulesDir(path: modulesDirPath)
    }
  }

  // MARK: - Bar Lifecycle

  private func buildBar(with config: Config) {
    let theme = ThemeProvider(config: config)
    let bar = BarViewModel(config: config)
    bar.popupManager.themeProvider = theme
    bar.popupManager.isNativeAppearance = config.isNativeAppearance

    self.barViewModel = bar
    self.themeProvider = theme

    let targetScreens = resolveTargetScreens(config.displays)
    for screen in targetScreens {
      let instance = DisplayInstance(
        screenName: screen.localizedName, barHeight: barHeight, config: config)
      instance.createPanels(for: screen, bar: bar, theme: theme)
      displayInstances.append(instance)
    }

    for vm in bar.allModules {
      let shouldDisplay = vm.$shouldDisplay.removeDuplicates().map { _ in () }
      let displayValue = vm.$displayValue.removeDuplicates().map { _ in () }
      let displayIcon = vm.$displayIcon.removeDuplicates().map { _ in () }
      // Animated content starts moving at once, so its panels follow
      // straight after the update instead of after a pause.
      Publishers.Merge3(shouldDisplay, displayValue, displayIcon)
        .debounce(for: .milliseconds(vm.animatesContent ? 0 : 50), scheduler: RunLoop.main)
        .sink { [weak self, weak vm] _ in
          self?.repositionAllDisplays(animated: vm?.contentAnimation != nil)
        }
        .store(in: &visibilityCancellables)
    }

    // Subscribe to drawer state changes and animate panels per-side
    bar.$leftDrawerOpen
      .removeDuplicates()
      .dropFirst()
      .sink { [weak self] open in
        guard let self else { return }
        for instance in self.displayInstances {
          instance.animateDrawerToggle(side: "left", open: open)
        }
      }
      .store(in: &visibilityCancellables)

    bar.$rightDrawerOpen
      .removeDuplicates()
      .dropFirst()
      .sink { [weak self] open in
        guard let self else { return }
        for instance in self.displayInstances {
          instance.animateDrawerToggle(side: "right", open: open)
        }
      }
      .store(in: &visibilityCancellables)

    updateModuleSuspension()
    restartRepositionTimer()
    startMenuBarAccessibility(for: config)

    if autohideConfig.enabled {
      startMenuBarMonitoring()
    }

    warnIfMenuBarAutoHides()

  }

  /// Reads menu bar items through Accessibility when the config uses them,
  /// asking for permission if kantan lacks it, and repositions masked
  /// modules whenever the items move.
  private func startMenuBarAccessibility(for config: Config) {
    guard
      MenuBarAccessibility.isNeeded(
        by: config.modules, fullDiskAccess: FullDiskAccess.isGranted)
    else { return }
    if !requestedAccessibility {
      requestedAccessibility = true
      MenuBarAccessibility.requestAccess()
    }
    MenuBarAccessibility.shared.start { [weak self] in
      DispatchQueue.main.async {
        MainActor.assumeIsolated { self?.repositionAllDisplays() }
      }
    }
  }

  private func teardownBar() {
    MenuBarAccessibility.shared.stop()
    stopMenuBarMonitoring()
    repositionTimer?.invalidate()
    repositionTimer = nil
    visibilityCancellables.removeAll()
    for instance in displayInstances {
      instance.teardown()
    }
    displayInstances.removeAll()
    barViewModel = nil
    themeProvider = nil
  }

  // MARK: - Screen Resolution

  func resolveTargetScreens(_ displays: DisplaysConfig) -> [NSScreen] {
    switch displays {
    case .main:
      if let main = NSScreen.main {
        return [main]
      }
      if let first = NSScreen.screens.first {
        return [first]
      }
      return []
    case .all:
      return NSScreen.screens
    case .named(let names):
      return NSScreen.screens.filter { names.contains($0.localizedName) }
    }
  }

  // MARK: - Screen Change Handling

  @objc func screenDidChange(_ notification: Notification) {
    guard let config = config, let bar = barViewModel, let theme = themeProvider else { return }

    // The cached window list reflects the previous screen layout; drop it so
    // the reposition triggered below queries the WindowServer fresh.
    MenuBarItemDetector.invalidateCache()

    let targetScreens = resolveTargetScreens(config.displays)
    let diff = computeScreenDiff(
      existing: displayInstances.map { $0.screenName },
      target: targetScreens.map { $0.localizedName })

    for instance in displayInstances where diff.toRemove.contains(instance.screenName) {
      instance.teardown()
    }
    displayInstances.removeAll { diff.toRemove.contains($0.screenName) }

    for screen in targetScreens where diff.toAdd.contains(screen.localizedName) {
      let instance = DisplayInstance(
        screenName: screen.localizedName, barHeight: barHeight, config: config)
      instance.createPanels(for: screen, bar: bar, theme: theme)
      displayInstances.append(instance)
    }

    updateModuleSuspension()
    restartRepositionTimer()
  }

  // MARK: - Repositioning

  func repositionAllDisplays(animated: Bool = false) {
    for instance in displayInstances {
      instance.repositionPanels(animated: animated)
    }
  }

  /// Suspend modules that are not visible on any active display (e.g. notch-only
  /// placement when all displays lack a notch). Unsuspend modules that become
  /// visible on at least one display.
  func updateModuleSuspension() {
    guard let bar = barViewModel else { return }
    for vm in bar.allModules {
      let visibleOnAny = displayInstances.contains { instance in
        guard let screen = instance.resolveScreen() else { return false }
        return vm.moduleConfig.placement.resolve(hasNotch: screen.hasNotch) != nil
      }
      if visibleOnAny {
        vm.unsuspend()
      } else {
        vm.suspend()
      }
    }
  }

  func restartRepositionTimer() {
    repositionTimer?.invalidate()
    var repositionCount = 0
    repositionTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated {
        self?.repositionAllDisplays()
        repositionCount += 1
        if repositionCount >= 20 {
          self?.repositionTimer?.invalidate()
          self?.repositionTimer = nil
        }
      }
    }
  }

  // MARK: - Menu Bar Visibility Monitoring

  func startMenuBarMonitoring() {
    menuBarMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
      DispatchQueue.main.async {
        MainActor.assumeIsolated {
          self?.checkMenuBar()
        }
      }
    }
  }

  func stopMenuBarMonitoring() {
    if let monitor = menuBarMonitor {
      NSEvent.removeMonitor(monitor)
      menuBarMonitor = nil
    }
  }

  func checkMenuBar() {
    let mouseLocation = NSEvent.mouseLocation
    for instance in displayInstances {
      instance.checkMenuBar(mouseLocation: mouseLocation, autohideConfig: autohideConfig)
    }
  }

  // MARK: - Menu Bar Auto-Hide Warning

  /// Emit a warning at startup if the user's system menu bar is configured to auto-hide.
  /// Masked menu bar items won't render correctly when the native menu bar is hidden.
  func warnIfMenuBarAutoHides() {
    let defaults = UserDefaults.standard
    let hideOnDesktop = defaults.bool(forKey: "_HIHideMenuBar")
    let visibleInFullscreen: Bool
    if defaults.object(forKey: "AppleMenuBarVisibleInFullscreen") != nil {
      visibleInFullscreen = defaults.bool(forKey: "AppleMenuBarVisibleInFullscreen")
    } else {
      visibleInFullscreen = false
    }

    let mode: String
    switch (hideOnDesktop, visibleInFullscreen) {
    case (false, true):
      return  // "Never" — nothing to warn about
    case (false, false):
      mode = "In Full Screen Only"
    case (true, true):
      mode = "On Desktop Only"
    case (true, false):
      mode = "Always"
    }

    print(
      "warning: system menu bar is set to hide (\(mode)). "
        + "Masked menu bar items may not render correctly when the native menu bar is hidden."
    )
  }

  // MARK: - Config Discovery Polling

  /// Periodically re-run config path resolution until a config file appears.
  /// Used when kantan starts with no config (welcome mode).
  private func startPollingForConfig() {
    configPollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) {
      [weak self] _ in
      MainActor.assumeIsolated {
        guard let self = self else { return }
        guard let configPath = resolveConfigPath(explicit: Kantan.configPath, silent: true)
        else { return }

        self.configPollTimer?.invalidate()
        self.configPollTimer = nil

        self.configFilePath = configPath
        let modulesDirPath = resolveModulesDir(
          explicit: Kantan.modulesDirPath, configPath: configPath)
        self.modulesDirPath = modulesDirPath

        self.reloadConfig()
        self.startWatchingConfig(path: configPath)
        self.startWatchingModulesDir(path: modulesDirPath)
      }
    }
  }

  // MARK: - Config Hot-Reload

  func startWatchingConfig(path: String) {
    configFileSource?.cancel()
    let fd = open(path, O_EVTONLY)
    guard fd >= 0 else {
      print("Unable to open config file for watching: \(path)")
      return
    }

    let source = DispatchSource.makeFileSystemObjectSource(
      fileDescriptor: fd,
      eventMask: [.write, .delete, .rename],
      queue: .main
    )

    source.setEventHandler { [weak self] in
      MainActor.assumeIsolated {
        guard let self = self else { return }
        let flags = source.data
        if flags.contains(.delete) || flags.contains(.rename) {
          // Editor did atomic save (write to tmp + rename)
          source.cancel()
          self.configFileSource = nil
          DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            MainActor.assumeIsolated {
              guard let path = self.configFilePath else { return }
              self.startWatchingConfig(path: path)
              self.scheduleReload()
            }
          }
        } else {
          self.scheduleReload()
        }
      }
    }

    source.setCancelHandler {
      close(fd)
    }

    self.configFileSource = source
    source.resume()

    // If the config path is a symlink, also watch the parent directory.
    // open() follows symlinks, so the fd above watches the target inode
    // (e.g. /nix/store/...) which never changes when the symlink is replaced.
    // Watching the parent directory catches symlink replacements.
    startWatchingConfigSymlink(path: path)
  }

  private func startWatchingConfigSymlink(path: String) {
    configSymlinkDirSource?.cancel()
    configSymlinkDirSource = nil

    let fm = FileManager.default
    guard let attrs = try? fm.attributesOfItem(atPath: path),
      let fileType = attrs[.type] as? FileAttributeType,
      fileType == .typeSymbolicLink
    else { return }

    // Store the resolved target so we can detect when it changes.
    resolvedConfigPath = (try? fm.destinationOfSymbolicLink(atPath: path))
      .flatMap { target in
        if target.hasPrefix("/") { return target }
        let dir = (path as NSString).deletingLastPathComponent
        return (dir as NSString).appendingPathComponent(target)
      }

    let parentDir = (path as NSString).deletingLastPathComponent
    let fd = open(parentDir, O_EVTONLY)
    guard fd >= 0 else { return }

    let source = DispatchSource.makeFileSystemObjectSource(
      fileDescriptor: fd,
      eventMask: [.write],
      queue: .main
    )

    source.setEventHandler { [weak self] in
      MainActor.assumeIsolated {
        guard let self = self, let configPath = self.configFilePath else { return }

        // Check if the symlink target actually changed.
        guard
          let newTarget = try? fm.destinationOfSymbolicLink(atPath: configPath)
        else { return }
        let resolved =
          newTarget.hasPrefix("/")
          ? newTarget
          : ((configPath as NSString).deletingLastPathComponent as NSString)
            .appendingPathComponent(newTarget)

        guard resolved != self.resolvedConfigPath else { return }
        self.resolvedConfigPath = resolved

        // Symlink target changed — re-watch the new target and reload.
        self.configFileSource?.cancel()
        self.configFileSource = nil
        self.startWatchingConfig(path: configPath)
        self.scheduleReload()
      }
    }

    source.setCancelHandler {
      close(fd)
    }

    self.configSymlinkDirSource = source
    source.resume()
  }

  func startWatchingModulesDir(path: String) {
    modulesDirSource?.cancel()
    cancelModuleFileWatchers()
    guard FileManager.default.fileExists(atPath: path) else { return }

    let fd = open(path, O_EVTONLY)
    guard fd >= 0 else {
      print("Unable to open modules directory for watching: \(path)")
      return
    }

    // Watch the directory itself for structural changes (files added/removed).
    let source = DispatchSource.makeFileSystemObjectSource(
      fileDescriptor: fd,
      eventMask: [.write, .delete, .rename],
      queue: .main
    )

    source.setEventHandler { [weak self] in
      MainActor.assumeIsolated {
        guard let self = self else { return }
        // Directory structure changed — re-watch individual files and reload.
        self.watchModuleFiles(in: path)
        self.scheduleReload()
      }
    }

    source.setCancelHandler {
      close(fd)
    }

    self.modulesDirSource = source
    source.resume()

    // Also watch each existing file for content changes.
    watchModuleFiles(in: path)
  }

  private func cancelModuleFileWatchers() {
    for source in moduleFileSources {
      source.cancel()
    }
    moduleFileSources.removeAll()
  }

  private func watchModuleFiles(in dirPath: String) {
    cancelModuleFileWatchers()
    guard let entries = try? FileManager.default.contentsOfDirectory(atPath: dirPath) else {
      return
    }

    for entry in entries {
      guard entry.hasSuffix(".yaml") || entry.hasSuffix(".yml") else { continue }
      let filePath = (dirPath as NSString).appendingPathComponent(entry)
      let fileFd = open(filePath, O_EVTONLY)
      guard fileFd >= 0 else { continue }

      let fileSource = DispatchSource.makeFileSystemObjectSource(
        fileDescriptor: fileFd,
        eventMask: [.write, .delete, .rename],
        queue: .main
      )

      fileSource.setEventHandler { [weak self] in
        MainActor.assumeIsolated {
          guard let self = self else { return }
          let flags = fileSource.data
          if flags.contains(.delete) || flags.contains(.rename) {
            // Atomic save — re-watch all files after a brief delay.
            fileSource.cancel()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
              MainActor.assumeIsolated {
                guard let dir = self.modulesDirPath else { return }
                self.watchModuleFiles(in: dir)
                self.scheduleReload()
              }
            }
          } else {
            self.scheduleReload()
          }
        }
      }

      fileSource.setCancelHandler {
        close(fileFd)
      }

      moduleFileSources.append(fileSource)
      fileSource.resume()
    }
  }

  private func scheduleReload() {
    reloadDebounceTimer?.invalidate()
    reloadDebounceTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: false) {
      [weak self] _ in
      MainActor.assumeIsolated {
        self?.reloadConfig()
      }
    }
  }

  func reloadConfig() {
    guard let path = configFilePath else { return }

    let newConfig: Config
    switch loadConfigFile(at: path, modulesDir: modulesDirPath) {
    case .success(let loaded):
      newConfig = loaded
    case .failure(let error):
      print("Hot-reload: config \(error.summary)\(Self.detail(of: error)), keeping current bar")
      return
    }

    if newConfig.needsBundledIconFonts {
      initIconFonts()
    }

    print("Hot-reload: config changed, rebuilding bar")

    teardownBar()
    cancelFileWatchers()

    self.config = newConfig
    barHeight = CGFloat(newConfig.height)
    autohideConfig = newConfig.autohide

    buildBar(with: newConfig)

    if let configPath = configFilePath {
      startWatchingConfig(path: configPath)
    }
    if let dir = modulesDirPath {
      startWatchingModulesDir(path: dir)
    }
  }

  /// The parser's message for an invalid YAML error, set apart for the log.
  private static func detail(of error: ConfigLoadError) -> String {
    if case .invalidYaml(let message) = error { return " -- \(message)" }
    return ""
  }

  /// Cancel every config/modules-dir file-system watcher. Owned by the
  /// AppDelegate but tied to the bar lifecycle so they are re-created on
  /// hot-reload alongside teardownBar()/buildBar().
  private func cancelFileWatchers() {
    configFileSource?.cancel()
    configFileSource = nil
    configSymlinkDirSource?.cancel()
    configSymlinkDirSource = nil
    modulesDirSource?.cancel()
    modulesDirSource = nil
    cancelModuleFileWatchers()
  }

  func applicationWillTerminate(_ aNotification: Notification) {
    configPollTimer?.invalidate()
    configPollTimer = nil
    cancelFileWatchers()
    reloadDebounceTimer?.invalidate()
    teardownBar()
  }
}

@main
struct Kantan {
  nonisolated(unsafe) static var configPath: String?
  nonisolated(unsafe) static var modulesDirPath: String?
  nonisolated(unsafe) static var fontsDirPath: String?
  nonisolated(unsafe) static var themesDirPath: String?

  static func main() {
    let arguments = parseArguments(CommandLine.arguments.dropFirst())
    configPath = arguments.options.configPath
    modulesDirPath = arguments.options.modulesDirPath
    fontsDirPath = arguments.options.fontsDirPath
    themesDirPath = arguments.options.themesDirPath

    switch arguments.command {
    case .run:
      break
    case .help:
      print(kantanUsage)
      return
    case .version:
      print("kantan \(kantanVersion)")
      return
    case .trigger(let userInfo):
      DistributedNotificationCenter.default().postNotificationName(
        NSNotification.Name("com.kantan.event"),
        object: nil,
        userInfo: userInfo,
        deliverImmediately: true
      )
      return
    case .usageError(let message):
      FileHandle.standardError.write(Data("kantan: \(message)\n\(kantanUsage)\n".utf8))
      exit(2)
    }

    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
  }
}
