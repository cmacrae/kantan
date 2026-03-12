import AppKit
import SwiftUI

// MARK: - Module View Model

@MainActor
class ModuleViewModel: ObservableObject, Identifiable {
  let id: String
  let moduleConfig: ModuleConfig

  @Published var displayValue: String?
  @Published var displayIcon: String?
  @Published var isActive: Bool = true
  @Published var shouldDisplay: Bool = true
  @Published var templateVariables: [String: String] = [:]
  @Published var viewTree: ViewNode?
  @Published var data: [String: [[String: String]]] = [:]

  @Published var fgOverride: String?
  @Published var bgOverride: String?

  @Published var dynamicStyle: DynamicStyleOverride?

  /// Closure invoked when this module is clicked with type "drawer".
  /// Set by BarViewModel for the drawer module.
  var toggleAction: (() -> Void)?

  private var updateGeneration: UInt64 = 0
  nonisolated(unsafe) private var timer: Timer?
  nonisolated(unsafe) private var durationTimer: Timer?
  nonisolated(unsafe) private var watchProcess: Process?
  nonisolated(unsafe) private var watchStdinPipe: Pipe?
  nonisolated(unsafe) private var watchRestartCount: Int = 0
  nonisolated(unsafe) private var watchStopped: Bool = false

  init(moduleConfig: ModuleConfig) {
    self.id = moduleConfig.name
    self.moduleConfig = moduleConfig
    self.displayIcon = moduleConfig.icon

    if let eventModule = moduleConfig.config as? EventDrivenModule {
      update()
      startEventObservation(eventModule)
    } else {
      startPolling()
    }

    startWatchIfConfigured()
  }

  deinit {
    (moduleConfig.config as? EventDrivenModule)?.stopObserving()
    timer?.invalidate()
    durationTimer?.invalidate()
    // Inline watch cleanup — can't call @MainActor method from deinit
    if let process = watchProcess {
      try? watchStdinPipe?.fileHandleForWriting.close()
      watchStdinPipe = nil
      if process.isRunning { process.terminate() }
      watchProcess = nil
    }
  }

  func update() {
    guard durationTimer == nil else { return }
    guard let config = moduleConfig.config else { return }

    updateGeneration &+= 1
    let gen = updateGeneration

    let icon = config.getIcon()
    let newIcon = icon.isEmpty ? moduleConfig.icon : icon

    config.getValue { [weak self] newValue in
      DispatchQueue.main.async {
        guard let self else { return }
        guard self.updateGeneration == gen else { return }
        self.displayValue = newValue
        self.displayIcon = newIcon
        self.isActive = config.isActive()
        self.shouldDisplay = config.shouldDisplay()
        self.templateVariables = config.getTemplateVariables()
        self.dynamicStyle = config.getDynamicStyle()
        self.viewTree = config.getViewTree()
        if let cmdConfig = config as? CommandConfig {
          self.data = cmdConfig.getData()
        }
      }
    }
  }

  func scheduleDurationReset(_ duration: Double) {
    durationTimer?.invalidate()
    durationTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) {
      [weak self] _ in
      MainActor.assumeIsolated {
        guard let self else { return }
        self.durationTimer = nil
        self.fgOverride = nil
        self.bgOverride = nil
        self.update()
      }
    }
  }

  func pause() {
    if let eventModule = moduleConfig.config as? EventDrivenModule {
      eventModule.stopObserving()
    }
    timer?.invalidate()
    timer = nil
    stopWatch()
  }

  func resume() {
    if let eventModule = moduleConfig.config as? EventDrivenModule {
      startEventObservation(eventModule)
    } else {
      startPolling()
    }
    startWatchIfConfigured()
    update()
  }

  private func startEventObservation(_ eventModule: EventDrivenModule) {
    eventModule.startObserving { [weak self] in
      DispatchQueue.main.async {
        MainActor.assumeIsolated {
          self?.update()
        }
      }
    }
  }

  private func startPolling() {
    update()
    // When a watch process is configured, it is responsible for triggering
    // all subsequent refreshes (via `kantan trigger`). Running a polling
    // timer alongside it causes redundant command invocations and potential
    // cache races on the shared CommandOutputData.
    if let watchCmd = moduleConfig.config?.getWatchCommand(), !watchCmd.isEmpty {
      return
    }
    let interval = moduleConfig.config?.redrawInterval ?? 1.0
    guard interval > 0 else { return }
    let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated {
        self?.update()
      }
    }
    RunLoop.main.add(t, forMode: .common)
    timer = t
  }

  // MARK: - Watch Process

  private func startWatchIfConfigured() {
    guard let watchCmd = moduleConfig.config?.getWatchCommand(), !watchCmd.isEmpty else { return }
    guard watchProcess == nil || watchProcess?.isRunning != true else { return }
    watchStopped = false
    launchWatch(command: watchCmd)
  }

  private func launchWatch(command: String) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/sh")
    process.arguments = ["-c", command]

    var env = ProcessInfo.processInfo.environment
    env["KANTAN_MODULE_NAME"] = self.id
    if let cmdConfig = moduleConfig.config as? CommandConfig {
      if let settings = cmdConfig.settingsJSON {
        env["KANTAN_SETTINGS"] = settings
      }
    }
    let names: [NSAppearance.Name] = [.darkAqua, .aqua]
    let isDark = NSApp.effectiveAppearance.bestMatch(from: names) == .darkAqua
    env["KANTAN_APPEARANCE"] = isDark ? "dark" : "light"
    env["KANTAN_PID"] = "\(ProcessInfo.processInfo.processIdentifier)"
    process.environment = env

    // Provide a stdin pipe so the watch process can detect kantan exit
    // (reads on stdin return EOF when kantan terminates).
    let stdinPipe = Pipe()
    process.standardInput = stdinPipe
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice

    process.terminationHandler = { [weak self] proc in
      DispatchQueue.main.async {
        MainActor.assumeIsolated {
          self?.handleWatchTermination(exitCode: proc.terminationStatus)
        }
      }
    }

    do {
      try process.run()
      watchProcess = process
      watchStdinPipe = stdinPipe
      watchRestartCount = 0
    } catch {
      print("Failed to launch watch process: \(error)")
    }
  }

  private func handleWatchTermination(exitCode: Int32) {
    watchProcess = nil
    watchStdinPipe = nil

    // Don't restart if we intentionally stopped the watch
    guard !watchStopped else { return }

    // Exponential backoff
    let maxRestarts = 10
    guard watchRestartCount < maxRestarts else {
      print("Watch process for '\(id)' exceeded \(maxRestarts) restarts, giving up")
      return
    }

    watchRestartCount += 1
    let delay = min(Double(1 << min(watchRestartCount - 1, 4)), 30.0)
    print("Watch process for '\(id)' exited (\(exitCode)), restarting in \(delay)s")

    DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
      MainActor.assumeIsolated {
        guard let self, !self.watchStopped else { return }
        guard let watchCmd = self.moduleConfig.config?.getWatchCommand(), !watchCmd.isEmpty else {
          return
        }
        self.launchWatch(command: watchCmd)
      }
    }
  }

  private func stopWatch() {
    watchStopped = true
    terminateWatch()
  }

  private func terminateWatch() {
    guard let process = watchProcess else { return }
    // Close stdin pipe first — the watch process should exit on EOF
    try? watchStdinPipe?.fileHandleForWriting.close()
    watchStdinPipe = nil

    // Give the process a moment to exit gracefully, then force terminate
    if process.isRunning {
      process.terminate()
    }
    watchProcess = nil
  }
}

// MARK: - Module Group

struct ModuleGroup: Identifiable {
  let id: String
  let modules: [ModuleViewModel]
  let isPassthrough: Bool
  let placement: String
  let isDrawerContent: Bool
}

// MARK: - Bar View Model

@MainActor
class BarViewModel: ObservableObject {
  let leftModules: [ModuleViewModel]
  let rightModules: [ModuleViewModel]
  let config: Config
  let popupManager = PopupManager()
  private var eventObserver: EventObserver?

  let allModules: [ModuleViewModel]
  let leftGroups: [ModuleGroup]
  let rightGroups: [ModuleGroup]

  @Published var drawerOpen: Bool = false
  private(set) var hasDrawer: Bool = false
  private var drawerVM: ModuleViewModel?
  private var drawerShowIcon: String = "〈"
  private var drawerHideIcon: String = "〉"

  init(config: Config) {
    self.config = config

    var left: [ModuleViewModel] = []
    var right: [ModuleViewModel] = []

    for moduleConfig in config.modules {
      let vm = ModuleViewModel(moduleConfig: moduleConfig)
      if moduleConfig.placement == "right" {
        right.append(vm)
      } else {
        left.append(vm)
      }
    }

    self.leftModules = left
    self.rightModules = right
    self.allModules = left + right
    self.leftGroups = BarViewModel.buildGroups(from: left, placement: "left")
    self.rightGroups = BarViewModel.buildGroups(from: right, placement: "right")

    // Wire up drawer module
    if let dvm = allModules.first(where: { $0.moduleConfig.type == "drawer" }) {
      self.hasDrawer = true
      self.drawerVM = dvm
      if let drawerConfig = dvm.moduleConfig.config as? DrawerConfig {
        self.drawerShowIcon = drawerConfig.showIcon
        self.drawerHideIcon = drawerConfig.hideIcon
      }
      dvm.displayIcon = drawerShowIcon
      dvm.toggleAction = { [weak self] in
        self?.toggleDrawer()
      }
    }

    eventObserver = EventObserver(
      onRefresh: { [weak self] in
        self?.refreshAll()
      },
      onSleep: { [weak self] in
        self?.pauseAll()
      },
      onWake: { [weak self] in
        self?.resumeAll()
      },
      onEvent: { [weak self] module, action, userInfo in
        self?.handleEvent(module: module, action: action, userInfo: userInfo)
      }
    )
  }

  private static func buildGroups(from modules: [ModuleViewModel], placement: String)
    -> [ModuleGroup]
  {
    guard !modules.isEmpty else { return [] }

    // Find the drawer module index (if any) to mark pre-drawer groups as drawer content.
    // Modules at indices before the drawer are hidden behind it.
    let drawerIndex = modules.firstIndex { $0.moduleConfig.type == "drawer" }

    // Tag each module with whether it's drawer content
    let isDrawerContent: [Bool] = modules.enumerated().map { idx, _ in
      guard let di = drawerIndex else { return false }
      return idx < di
    }

    var groups: [ModuleGroup] = []
    var current: [ModuleViewModel] = []
    var currentPassthrough = false
    var currentDrawerContent = false

    func flushCurrent() {
      guard !current.isEmpty else { return }
      groups.append(
        ModuleGroup(
          id: "\(placement)-\(groups.count)",
          modules: current,
          isPassthrough: currentPassthrough,
          placement: placement,
          isDrawerContent: currentDrawerContent
        ))
      current = []
    }

    for (idx, vm) in modules.enumerated() {
      let isMasked = vm.moduleConfig.mask != nil
      let pt = vm.moduleConfig.isPassthrough
      let dc = isDrawerContent[idx]

      if isMasked {
        flushCurrent()
        groups.append(
          ModuleGroup(
            id: "\(placement)-\(groups.count)",
            modules: [vm],
            isPassthrough: true,
            placement: placement,
            isDrawerContent: dc
          ))
      } else {
        if current.isEmpty {
          currentPassthrough = pt
          currentDrawerContent = dc
          current.append(vm)
        } else if pt == currentPassthrough && dc == currentDrawerContent {
          current.append(vm)
        } else {
          flushCurrent()
          current = [vm]
          currentPassthrough = pt
          currentDrawerContent = dc
        }
      }
    }

    flushCurrent()
    return groups
  }

  func toggleDrawer() {
    drawerOpen.toggle()
    drawerVM?.displayIcon = drawerOpen ? drawerHideIcon : drawerShowIcon
  }

  func refreshAll() {
    for vm in allModules {
      vm.update()
    }
  }

  func pauseAll() {
    for vm in allModules {
      vm.pause()
    }
  }

  func resumeAll() {
    for vm in allModules {
      vm.resume()
    }
  }

  func handleEvent(module moduleName: String, action: String, userInfo: [String: String]) {
    let targets: [ModuleViewModel]
    if moduleName == "*" {
      targets = allModules
    } else {
      targets = allModules.filter { $0.id == moduleName }
    }

    guard !targets.isEmpty else { return }

    for vm in targets {
      switch action {
      case "refresh":
        vm.update()

      case "set":
        if let value = userInfo["value"] {
          vm.displayValue = value.isEmpty ? nil : value
        }
        if let icon = userInfo["icon"] {
          vm.displayIcon = icon.isEmpty ? nil : icon
        }
        if let fg = userInfo["fg"] {
          vm.fgOverride = fg.isEmpty ? nil : fg
        }
        if let bg = userInfo["bg"] {
          vm.bgOverride = bg.isEmpty ? nil : bg
        }
        if let durationStr = userInfo["duration"],
          let duration = Double(durationStr), duration > 0
        {
          vm.scheduleDurationReset(duration)
        }

      default:
        break
      }
    }
  }
}

// MARK: - Theme Provider

private let defaultStyleMode = StyleModeConfig(
  fg: "FFFFFF", bg: "000000", text: nil, icon: nil, shape: nil)
private let defaultFontConfig = FontConfig(descriptor: "HelveticaNeue:regular:14")

@MainActor
class ThemeProvider: ObservableObject {
  @Published var isDarkMode: Bool = true
  let config: Config
  private var appearanceObservation: NSKeyValueObservation?

  var isNative: Bool {
    config.appearance == .native
  }

  init(config: Config) {
    self.config = config
    self.isDarkMode = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    observeAppearance()
  }

  private func observeAppearance() {
    appearanceObservation = NSApp.observe(\.effectiveAppearance) { [weak self] _, _ in
      DispatchQueue.main.async {
        self?.isDarkMode =
          NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
      }
    }
  }

  // MARK: - Style Resolution Helpers

  private func resolveGlobalStyleMode() -> StyleModeConfig {
    if isDarkMode {
      return config.style.dark ?? config.style.light ?? defaultStyleMode
    } else {
      return config.style.light ?? config.style.dark ?? defaultStyleMode
    }
  }

  private func resolveModuleStyleMode(_ style: StyleConfig?) -> StyleModeConfig? {
    guard let style = style else { return nil }
    return isDarkMode ? style.dark : style.light
  }

  // MARK: - Color Resolution

  func globalColors() -> (fg: Color, bg: Color) {
    let mode = resolveGlobalStyleMode()
    return (
      Color(nsColor: NSColor(hex: mode.fg ?? "FFFFFF")),
      Color(nsColor: NSColor(hex: mode.bg ?? "000000"))
    )
  }

  func globalFgNSColor() -> NSColor {
    if isNative { return .labelColor }
    let mode = resolveGlobalStyleMode()
    return NSColor(hex: mode.fg ?? "FFFFFF")
  }

  func globalBgNSColor() -> NSColor {
    if isNative { return .windowBackgroundColor }
    let mode = resolveGlobalStyleMode()
    return NSColor(hex: mode.bg ?? "000000")
  }

  private func elementFgColor(
    for vm: ModuleViewModel,
    dynamicFg: KeyPath<DynamicStyleOverride, String?>,
    elementFg: KeyPath<StyleModeConfig, ElementStyle?>
  ) -> Color {
    if let override = vm.fgOverride {
      return Color(nsColor: NSColor(hex: override))
    }
    if let ds = vm.dynamicStyle {
      if let fg = ds[keyPath: dynamicFg] { return Color(nsColor: NSColor(hex: fg)) }
      if let fg = ds.fg { return Color(nsColor: NSColor(hex: fg)) }
    }
    if isNative { return Color(nsColor: .labelColor) }
    let moduleMode = resolveModuleStyleMode(vm.moduleConfig.style)
    let globalMode = resolveGlobalStyleMode()
    if let fg = moduleMode?[keyPath: elementFg]?.fg { return Color(nsColor: NSColor(hex: fg)) }
    if let fg = moduleMode?.fg { return Color(nsColor: NSColor(hex: fg)) }
    if let fg = globalMode[keyPath: elementFg]?.fg { return Color(nsColor: NSColor(hex: fg)) }
    return Color(nsColor: NSColor(hex: globalMode.fg ?? "FFFFFF"))
  }

  func textFgColor(for vm: ModuleViewModel) -> Color {
    elementFgColor(for: vm, dynamicFg: \.textFg, elementFg: \.text)
  }

  func iconFgColor(for vm: ModuleViewModel) -> Color {
    elementFgColor(for: vm, dynamicFg: \.iconFg, elementFg: \.icon)
  }

  func bgColor(for vm: ModuleViewModel) -> Color {
    if let override = vm.bgOverride {
      return Color(nsColor: NSColor(hex: override))
    }
    if let ds = vm.dynamicStyle, let bg = ds.bg, !bg.isEmpty {
      return Color(nsColor: NSColor(hex: bg))
    }
    if isNative { return .clear }

    let moduleMode = resolveModuleStyleMode(vm.moduleConfig.style)
    let globalMode = resolveGlobalStyleMode()

    if let bg = moduleMode?.bg { return Color(nsColor: NSColor(hex: bg)) }
    return Color(nsColor: NSColor(hex: globalMode.bg ?? "000000"))
  }

  func barBgColor() -> Color {
    if isNative { return .clear }
    let mode = resolveGlobalStyleMode()
    return Color(nsColor: NSColor(hex: mode.bg ?? "000000"))
  }

  func shape(for vm: ModuleViewModel) -> ModuleShape? {
    let moduleMode = resolveModuleStyleMode(vm.moduleConfig.style)
    return moduleMode?.shape
  }

  // MARK: - Font Resolution

  func iconFont(for vm: ModuleViewModel) -> Font {
    let fontConfig = vm.moduleConfig.iconFont ?? config.iconFont ?? defaultFontConfig
    return fontConfig.swiftUIFont
  }

  func textFont(for vm: ModuleViewModel) -> Font {
    let fontConfig = vm.moduleConfig.textFont ?? config.textFont ?? defaultFontConfig
    return fontConfig.swiftUIFont
  }

  // MARK: - Layout

  var iconTextSpacing: CGFloat {
    CGFloat(config.iconTextSpacing)
  }
}
