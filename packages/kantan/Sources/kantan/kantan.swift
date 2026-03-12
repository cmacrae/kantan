import AppKit
import Combine
import SwiftUI
import Yaml

// MARK: - Display Instance

@MainActor
class DisplayInstance {
  let screenName: String
  var bgPanel: NSPanel?
  var groupPanels:
    [(panel: NSPanel, hostingView: NSHostingView<ModuleGroupView>, group: ModuleGroup)] = []
  var bgColorCancellable: AnyCancellable?
  var drawerOpen: Bool = false

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

  /// Groups that become empty after filtering are removed entirely.
  private func filterGroups(_ groups: [ModuleGroup], for screen: NSScreen) -> [ModuleGroup] {
    groups.compactMap { group in
      let filtered = group.modules.filter { moduleMatchesDisplay($0, screen: screen) }
      guard !filtered.isEmpty else { return nil }
      return ModuleGroup(
        id: group.id, modules: filtered, isPassthrough: group.isPassthrough,
        alignment: group.alignment, isDrawerContent: group.isDrawerContent)
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

  private func statusBarY(for screen: NSScreen) -> CGFloat {
    screen.frame.origin.y + screen.frame.height - barHeight - config.gaps.top
  }

  private func configurePanelDefaults(_ panel: NSPanel, level: NSWindow.Level) {
    panel.level = level
    panel.collectionBehavior = .canJoinAllSpaces
    panel.isOpaque = false
    panel.hasShadow = false
    panel.backgroundColor = NSColor.clear
  }

  private func computeMaskBoundaries(
    screen: NSScreen,
    nativeItems: [NativeMenuBarItem],
    maskedGroups: [(alignment: String, mask: MaskConfig)]
  ) -> (leftX: CGFloat, rightX: CGFloat) {
    let gaps = config.gaps
    var leftX = screen.frame.origin.x + gaps.left
    var rightX = screen.frame.origin.x + screen.frame.width - gaps.right
    for (alignment, mask) in maskedGroups {
      guard let nativeItem = MenuBarItemDetector.resolveItem(for: mask, from: nativeItems) else {
        continue
      }
      let nativeRect = MenuBarItemDetector.appKitRect(from: nativeItem.cgRect, on: screen)
      if alignment == "right" {
        rightX = min(rightX, nativeRect.origin.x)
      } else {
        leftX = max(leftX, nativeRect.origin.x + nativeRect.width)
      }
    }
    return (leftX, rightX)
  }

  func createPanels(for screen: NSScreen, bar: BarViewModel, theme: ThemeProvider) {
    let gaps = config.gaps
    let radius = config.cornerRadius
    let statusBarY = statusBarY(for: screen)
    let statusWindowLevel = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)))

    let bgRect = NSRect(
      x: screen.frame.origin.x + gaps.left,
      y: statusBarY,
      width: screen.frame.width - gaps.left - gaps.right,
      height: barHeight
    )

    let panel = NSPanel(
      contentRect: bgRect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered,
      defer: false)
    configurePanelDefaults(panel, level: statusWindowLevel)
    panel.ignoresMouseEvents = true
    bgPanel = panel

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

      panel.contentView = effectView

      bgColorCancellable = theme.$isDarkMode.sink { [weak self] isDark in
        guard let self = self,
          let bgPanel = self.bgPanel,
          let effectView = bgPanel.contentView as? NSVisualEffectView,
          let tintView = effectView.subviews.first
        else { return }
        let mode = self.resolveStyleMode(isDark: isDark)
        tintView.layer?.backgroundColor =
          NSColor(hex: mode.bg ?? "000000").withAlphaComponent(tintOpacity).cgColor
      }
    } else if config.appearance == .native {
      let effectView = NSVisualEffectView(frame: NSRect(origin: .zero, size: bgRect.size))
      effectView.material = .headerView
      effectView.state = .active
      effectView.blendingMode = .behindWindow
      effectView.wantsLayer = true
      effectView.layer?.cornerRadius = radius
      effectView.layer?.masksToBounds = true
      effectView.autoresizingMask = [.width, .height]
      panel.contentView = effectView
    } else {
      let bgView = NSView(frame: NSRect(origin: .zero, size: bgRect.size))
      bgView.wantsLayer = true
      let globalStyle = resolveStyleMode(isDark: theme.isDarkMode)
      bgView.layer?.backgroundColor = NSColor(hex: globalStyle.bg ?? "000000").cgColor
      bgView.layer?.cornerRadius = radius
      bgView.layer?.masksToBounds = true
      bgView.autoresizingMask = [.width, .height]
      panel.contentView = bgView

      bgColorCancellable = theme.$isDarkMode.sink { [weak self] isDark in
        guard let self = self,
          let bgPanel = self.bgPanel,
          let view = bgPanel.contentView
        else { return }
        let mode = self.resolveStyleMode(isDark: isDark)
        view.layer?.backgroundColor = NSColor(hex: mode.bg ?? "000000").cgColor
      }
    }

    panel.orderFrontRegardless()

    let moduleGroupLevel = NSWindow.Level(rawValue: statusWindowLevel.rawValue + 1)
    let allGroups = filterGroups(bar.leftGroups + bar.rightGroups.reversed(), for: screen)

    let nativeItems = MenuBarItemDetector.detectItems(for: screen)

    let maskedGroups = allGroups.compactMap { group -> (alignment: String, mask: MaskConfig)? in
      guard group.modules.count == 1, let mask = group.modules[0].moduleConfig.mask else {
        return nil
      }
      return (group.alignment, mask)
    }
    var (leftX, rightX) = computeMaskBoundaries(
      screen: screen, nativeItems: nativeItems, maskedGroups: maskedGroups)

    for group in allGroups {
      let groupView = ModuleGroupView(
        modules: group.modules,
        popupManager: bar.popupManager,
        themeProvider: theme
      )
      let hostingView = NSHostingView(rootView: groupView)

      // Skip drawer content in positioning when drawer is closed
      let skipPositioning = group.isDrawerContent && !drawerOpen

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
        panelRect = NSRect(x: rightX, y: statusBarY, width: 0, height: barHeight)
      } else {
        let fittingWidth = hostingView.fittingSize.width
        let panelX: CGFloat
        if group.alignment == "left" {
          panelX = leftX
          leftX += fittingWidth
        } else {
          rightX -= fittingWidth
          panelX = rightX
        }
        panelRect = NSRect(x: panelX, y: statusBarY, width: fittingWidth, height: barHeight)
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
  }

  func repositionPanels() {
    guard let screen = resolveScreen(),
      let bgPanel = bgPanel
    else { return }
    let gaps = config.gaps
    let statusBarY = statusBarY(for: screen)

    let bgFrame = NSRect(
      x: screen.frame.origin.x + gaps.left,
      y: statusBarY,
      width: screen.frame.width - gaps.left - gaps.right,
      height: barHeight
    )
    bgPanel.setFrame(bgFrame, display: true)

    let nativeItems = MenuBarItemDetector.detectItems(for: screen)

    let maskedEntries = groupPanels.compactMap { entry -> (alignment: String, mask: MaskConfig)? in
      guard entry.group.modules.count == 1, let mask = entry.group.modules[0].moduleConfig.mask
      else { return nil }
      return (entry.group.alignment, mask)
    }
    var (leftX, rightX) = computeMaskBoundaries(
      screen: screen, nativeItems: nativeItems, maskedGroups: maskedEntries)

    for entry in groupPanels {
      guard entry.group.modules.count == 1,
        let mask = entry.group.modules[0].moduleConfig.mask
      else { continue }

      guard let nativeItem = MenuBarItemDetector.resolveItem(for: mask, from: nativeItems) else {
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

    for entry in groupPanels {
      if entry.group.modules.count == 1 && entry.group.modules[0].moduleConfig.mask != nil {
        continue
      }

      // Skip drawer content panels when drawer is closed
      if entry.group.isDrawerContent && !drawerOpen {
        continue
      }

      let fittingWidth = entry.hostingView.fittingSize.width

      let panelX: CGFloat
      if entry.group.alignment == "left" {
        panelX = leftX
        leftX += fittingWidth
      } else {
        rightX -= fittingWidth
        panelX = rightX
      }

      let panelFrame = NSRect(x: panelX, y: statusBarY, width: fittingWidth, height: barHeight)
      entry.panel.setFrame(panelFrame, display: true)
    }
  }

  // MARK: - Drawer Animation

  func animateDrawerToggle(open: Bool) {
    guard let screen = resolveScreen() else { return }
    drawerOpen = open
    let statusBarY = statusBarY(for: screen)

    let nativeItems = MenuBarItemDetector.detectItems(for: screen)
    let maskedEntries = groupPanels.compactMap { entry -> (alignment: String, mask: MaskConfig)? in
      guard entry.group.modules.count == 1, let mask = entry.group.modules[0].moduleConfig.mask
      else { return nil }
      return (entry.group.alignment, mask)
    }
    var (leftX, rightX) = computeMaskBoundaries(
      screen: screen, nativeItems: nativeItems, maskedGroups: maskedEntries)

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

      // Skip drawer content when closing
      if entry.group.isDrawerContent && !open {
        continue
      }

      let fittingWidth = entry.hostingView.fittingSize.width
      let panelX: CGFloat
      if entry.group.alignment == "left" {
        panelX = leftX
        leftX += fittingWidth
      } else {
        rightX -= fittingWidth
        panelX = rightX
      }

      let frame = NSRect(x: panelX, y: statusBarY, width: fittingWidth, height: barHeight)
      targetFrames.append((entry: entry, frame: frame))
    }

    let drawerContentPanels = groupPanels.filter { $0.group.isDrawerContent }

    if open {
      // Opening: position drawer-content panels at target with alpha 0, then animate in
      for entry in drawerContentPanels {
        if let target = targetFrames.first(where: { $0.entry.panel === entry.panel }) {
          entry.panel.setFrame(target.frame, display: true)
        }
        entry.panel.alphaValue = 0
        entry.panel.orderFrontRegardless()
      }

      NSAnimationContext.runAnimationGroup { context in
        context.duration = 0.25
        context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)

        // Fade in drawer content
        for entry in drawerContentPanels {
          entry.panel.animator().alphaValue = 1
        }

        // Slide non-drawer-content panels to their new positions
        for target in targetFrames where !target.entry.group.isDrawerContent {
          target.entry.panel.animator().setFrame(target.frame, display: true)
        }
      }
    } else {
      // Closing: animate drawer-content panels out, slide others to closed positions
      NSAnimationContext.runAnimationGroup(
        { context in
          context.duration = 0.25
          context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)

          // Fade out drawer content
          for entry in drawerContentPanels {
            entry.panel.animator().alphaValue = 0
          }

          // Slide non-drawer-content panels to their closed positions
          for target in targetFrames {
            target.entry.panel.animator().setFrame(target.frame, display: true)
          }
        },
        completionHandler: {
          DispatchQueue.main.async {
            MainActor.assumeIsolated {
              for entry in drawerContentPanels {
                entry.panel.orderOut(nil)
              }
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

  /// All panels that should be visible (excludes drawer-content panels when closed).
  var visiblePanels: [NSPanel] {
    [bgPanel].compactMap { $0 }
      + groupPanels.filter { !$0.group.isDrawerContent || drawerOpen }.map { $0.panel }
  }

  /// All panels including hidden drawer-content panels.
  var allPanels: [NSPanel] {
    [bgPanel].compactMap { $0 } + groupPanels.map { $0.panel }
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
    for panel in allPanels {
      panel.orderOut(nil)
    }
    groupPanels.removeAll()
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
  var configFilePath: String?
  var modulesDirPath: String?
  nonisolated(unsafe) var configFileSource: DispatchSourceFileSystemObject?
  nonisolated(unsafe) var modulesDirSource: DispatchSourceFileSystemObject?
  nonisolated(unsafe) var moduleFileSources: [DispatchSourceFileSystemObject] = []
  nonisolated(unsafe) var reloadDebounceTimer: Timer?

  func applicationDidFinishLaunching(_ aNotification: Notification) {
    NSApp.setActivationPolicy(.accessory)

    guard let configPath = resolveConfigPath(explicit: Kantan.configPath) else {
      print("Configuration not found")
      return
    }
    self.configFilePath = configPath

    let modulesDirPath = resolveModulesDir(explicit: Kantan.modulesDirPath, configPath: configPath)
    self.modulesDirPath = modulesDirPath

    let configDir = URL(fileURLWithPath: configPath).deletingLastPathComponent().path

    guard let fileData = loadFileContents(filePath: configPath) else {
      print("Failed to load file contents")
      return
    }

    let yaml: Yaml
    do {
      yaml = try Yaml.load(fileData)
    } catch {
      print(error)
      return
    }

    guard var config = loadConfig(from: yaml, configDir: configDir) else {
      print("Configuration not loaded")
      return
    }

    let extraModules = loadModulesFromDirectory(path: modulesDirPath)
    config.modules = mergeModules(base: config.modules, extra: extraModules)

    self.config = config
    barHeight = CGFloat(config.height)
    autohideConfig = config.autohide

    buildBar(with: config)

    NotificationCenter.default.addObserver(
      self, selector: #selector(screenDidChange),
      name: NSApplication.didChangeScreenParametersNotification, object: nil
    )

    startWatchingConfig(path: configPath)
    startWatchingModulesDir(path: modulesDirPath)
  }

  // MARK: - Bar Lifecycle

  private func buildBar(with config: Config) {
    let theme = ThemeProvider(config: config)
    let bar = BarViewModel(config: config)
    bar.popupManager.themeProvider = theme
    bar.popupManager.appearance = config.appearance

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
      vm.$shouldDisplay
        .removeDuplicates()
        .debounce(for: .milliseconds(50), scheduler: RunLoop.main)
        .sink { [weak self] _ in
          self?.repositionAllDisplays()
        }
        .store(in: &visibilityCancellables)

      vm.$displayValue
        .removeDuplicates()
        .debounce(for: .milliseconds(50), scheduler: RunLoop.main)
        .sink { [weak self] _ in
          self?.repositionAllDisplays()
        }
        .store(in: &visibilityCancellables)

      vm.$displayIcon
        .removeDuplicates()
        .debounce(for: .milliseconds(50), scheduler: RunLoop.main)
        .sink { [weak self] _ in
          self?.repositionAllDisplays()
        }
        .store(in: &visibilityCancellables)
    }

    // Subscribe to drawer state changes and animate panels
    bar.$drawerOpen
      .removeDuplicates()
      .dropFirst()
      .sink { [weak self] open in
        guard let self else { return }
        for instance in self.displayInstances {
          instance.animateDrawerToggle(open: open)
        }
      }
      .store(in: &visibilityCancellables)

    restartRepositionTimer()

    if autohideConfig.enabled {
      startMenuBarMonitoring()
    }
  }

  private func teardownBar() {
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

    let targetScreens = resolveTargetScreens(config.displays)
    let targetNames = Set(targetScreens.map { $0.localizedName })
    let existingNames = Set(displayInstances.map { $0.screenName })

    for instance in displayInstances where !targetNames.contains(instance.screenName) {
      instance.teardown()
    }
    displayInstances.removeAll { !targetNames.contains($0.screenName) }

    for screen in targetScreens where !existingNames.contains(screen.localizedName) {
      let instance = DisplayInstance(
        screenName: screen.localizedName, barHeight: barHeight, config: config)
      instance.createPanels(for: screen, bar: bar, theme: theme)
      displayInstances.append(instance)
    }

    repositionAllDisplays()
    restartRepositionTimer()
  }

  // MARK: - Repositioning

  func repositionAllDisplays() {
    for instance in displayInstances {
      instance.repositionPanels()
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

    guard let fileData = loadFileContents(filePath: path) else {
      print("Hot-reload: failed to read config file")
      return
    }

    let configDir = URL(fileURLWithPath: path).deletingLastPathComponent().path
    var newConfig: Config?
    do {
      let yaml = try Yaml.load(fileData)
      newConfig = loadConfig(from: yaml, configDir: configDir)
    } catch {
      print("Hot-reload: failed to parse config -- \(error)")
      return
    }

    guard var newConfig = newConfig else {
      print("Hot-reload: invalid config, keeping current bar")
      return
    }

    if let dir = modulesDirPath {
      let extraModules = loadModulesFromDirectory(path: dir)
      newConfig.modules = mergeModules(base: newConfig.modules, extra: extraModules)
    }

    print("Hot-reload: config changed, rebuilding bar")

    teardownBar()

    self.config = newConfig
    barHeight = CGFloat(newConfig.height)
    autohideConfig = newConfig.autohide

    buildBar(with: newConfig)
  }

  func applicationWillTerminate(_ aNotification: Notification) {
    configFileSource?.cancel()
    configFileSource = nil
    modulesDirSource?.cancel()
    modulesDirSource = nil
    cancelModuleFileWatchers()
    reloadDebounceTimer?.invalidate()
    teardownBar()
  }
}

@main
struct Kantan {
  nonisolated(unsafe) static var configPath: String?
  nonisolated(unsafe) static var modulesDirPath: String?

  static func main() {
    let args = CommandLine.arguments

    var positionalArgs: [String] = [args[0]]
    var i = 1
    while i < args.count {
      switch args[i] {
      case "--config":
        if i + 1 < args.count {
          configPath = (args[i + 1] as NSString).expandingTildeInPath
          i += 2
        } else {
          print("--config requires a path argument")
          i += 1
        }
      case "--modules-dir":
        if i + 1 < args.count {
          modulesDirPath = (args[i + 1] as NSString).expandingTildeInPath
          i += 2
        } else {
          print("--modules-dir requires a path argument")
          i += 1
        }
      default:
        positionalArgs.append(args[i])
        i += 1
      }
    }

    if positionalArgs.count >= 4 && positionalArgs[1] == "trigger" {
      let module = positionalArgs[2]
      let action = positionalArgs[3]

      var userInfo: [String: String] = [
        "module": module,
        "action": action,
      ]

      for arg in positionalArgs.dropFirst(4) {
        let parts = arg.split(separator: "=", maxSplits: 1)
        if parts.count == 2 {
          userInfo[String(parts[0])] = String(parts[1])
        }
      }

      DistributedNotificationCenter.default().postNotificationName(
        NSNotification.Name("com.kantan.event"),
        object: nil,
        userInfo: userInfo,
        deliverImmediately: true
      )
      return
    }

    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
  }
}
