import AppKit
import SwiftUI

// MARK: - Module Animation

/// Timing shared by animated module content and the panels that resize
/// with it, so both move together.
enum ModuleAnimation {
  static let duration: TimeInterval = 0.3
  static let content = Animation.timingCurve(0.4, 0, 0.2, 1, duration: duration)
  /// Content leaving clears in the first half of a change, while content
  /// arriving fades in from a third of the way through, so the two don't
  /// pile up where they overlap.
  static let exit = Animation.timingCurve(0.4, 0, 1, 1, duration: duration / 2)
  static let entrance = Animation.timingCurve(0, 0, 0.2, 1, duration: duration * 2 / 3)
    .delay(duration / 3)
  static var panelTiming: CAMediaTimingFunction {
    CAMediaTimingFunction(controlPoints: 0.4, 0, 0.2, 1)
  }
}

// MARK: - Module View Model

@MainActor
class ModuleViewModel: ObservableObject, Identifiable {
  let id: String
  let moduleConfig: ModuleConfig

  @Published var displayValue: String?
  @Published var displayIcon: String?
  @Published var iconFontNameOverride: String?
  @Published var iconScaleFactor: CGFloat = 1.0
  @Published var backgroundIcon: String?
  @Published var isActive: Bool = true
  @Published var shouldDisplay: Bool = true
  @Published var templateVariables: [String: String] = [:]
  @Published var viewTree: ViewNode?
  @Published var data: [String: [[String: String]]] = [:]
  /// The value's coloured parts, drawn in its place when there are any.
  @Published var segments: [ValueSegment] = []

  @Published var fgOverride: String?
  @Published var bgOverride: String?

  @Published var dynamicStyle: DynamicStyleOverride?

  /// Closure invoked when this module is clicked with type "drawer".
  /// Set by BarViewModel for the drawer module.
  var toggleAction: (() -> Void)?

  /// Whether this module is suspended because no display currently shows it
  /// (e.g. notch-only placement on all non-notch screens). Separate from
  /// sleep pause — suspension only applies to placement-based hiding.
  private(set) var isSuspended: Bool = false

  /// Whether the module animates changes to its content: workspace modules
  /// do, as their segments come and go.
  var animatesContent: Bool {
    moduleConfig.config is WorkspaceConfig
  }

  /// The animation for a change to the module's content, or nil to show it
  /// at once, as with Reduce Motion on.
  var contentAnimation: Animation? {
    guard animatesContent, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
      return nil
    }
    return ModuleAnimation.content
  }

  private var updateGeneration: UInt64 = 0
  nonisolated(unsafe) private var timer: Timer?
  nonisolated(unsafe) private var durationTimer: Timer?
  nonisolated(unsafe) private var watchProcess: Process?
  nonisolated(unsafe) private var watchStdinPipe: Pipe?
  /// Consecutive exits of the watch process that restarts have followed.
  nonisolated(unsafe) private var watchRestartCount: Int = 0
  /// When the running watch process was launched.
  private var watchLaunchDate = Date()
  nonisolated(unsafe) private var watchStopped: Bool = false
  /// Counts watch process launches, so events from a replaced process are
  /// ignored.
  private var watchLaunch: UInt64 = 0
  /// The running watch process's stdout, split into lines.
  private var watchOutput = LineBuffer()
  /// The appearance the running watch process was given.
  private var watchAppearance: String?
  private var appearanceObservation: NSKeyValueObservation?

  /// Sets the display icon, resolving named icons (e.g. "bell") to glyphs.
  func setIcon(_ raw: String?) {
    guard let raw, !raw.isEmpty else {
      displayIcon = raw
      iconFontNameOverride = nil
      iconScaleFactor = 1.0
      return
    }
    let resolved = resolveIconName(raw)
    displayIcon = resolved.glyph
    iconFontNameOverride = resolved.fontNameOverride
    iconScaleFactor = resolved.scaleFactor
  }

  init(moduleConfig: ModuleConfig) {
    self.id = moduleConfig.name
    self.moduleConfig = moduleConfig
    // Resolve named icons at init time
    if let icon = moduleConfig.icon {
      let resolved = resolveIconName(icon)
      self.displayIcon = resolved.glyph
      self.iconFontNameOverride = resolved.fontNameOverride
      self.iconScaleFactor = resolved.scaleFactor
    }

    if let eventModule = moduleConfig.config as? EventDrivenModule {
      update()
      startEventObservation(eventModule)
    } else {
      startPolling()
    }

    startWatchIfConfigured()
    if moduleConfig.config?.getWatchCommand()?.isEmpty == false {
      appearanceObservation = NSApp.observe(\.effectiveAppearance) { [weak self] _, _ in
        DispatchQueue.main.async {
          MainActor.assumeIsolated {
            self?.relaunchWatchIfAppearanceChanged()
          }
        }
      }
    }
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
    let bgIcon = config.getBackgroundIcon()
    let resolvedBgGlyph = bgIcon.map { resolveIconName($0).glyph }

    config.getValue { [weak self] newValue in
      DispatchQueue.main.async {
        guard let self else { return }
        guard self.updateGeneration == gen else { return }
        // A command's icon comes from the output getValue just produced.
        let currentIcon = config is CommandConfig ? config.getIcon() : icon
        self.show(newValue, icon: currentIcon, backgroundIcon: resolvedBgGlyph, of: config)
      }
    }
  }

  /// Publishes `value`, `icon` (or the module's own when empty) and the rest
  /// of `config`'s current state.
  private func show(
    _ value: String, icon: String, backgroundIcon: String?, of config: ModuleConfiguration
  ) {
    let rawIcon = icon.isEmpty ? moduleConfig.icon : icon
    let resolved = rawIcon.map { resolveIconName($0) }
    withAnimation(contentAnimation) {
      displayValue = value
      displayIcon = resolved?.glyph ?? rawIcon
      iconFontNameOverride = resolved?.fontNameOverride
      iconScaleFactor = resolved?.scaleFactor ?? 1.0
      self.backgroundIcon = backgroundIcon
      isActive = config.isActive()
      shouldDisplay = config.shouldDisplay()
      templateVariables = config.getTemplateVariables()
      dynamicStyle = config.getDynamicStyle()
      viewTree = config.getViewTree()
      if let cmdConfig = config as? CommandConfig {
        data = cmdConfig.getData()
        segments = cmdConfig.getSegments()
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
    // Don't resume if suspended (notch-only module on non-notch displays).
    // unsuspend() will call resume() when a notched display appears.
    guard !isSuspended else { return }
    if let eventModule = moduleConfig.config as? EventDrivenModule {
      startEventObservation(eventModule)
    } else {
      startPolling()
    }
    startWatchIfConfigured()
    update()
  }

  /// Suspend this module because no display currently shows it.
  func suspend() {
    guard !isSuspended else { return }
    isSuspended = true
    pause()
  }

  /// Unsuspend this module because at least one display now shows it.
  func unsuspend() {
    guard isSuspended else { return }
    isSuspended = false
    resume()
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
    // When a watch process is configured, it is responsible for all
    // subsequent refreshes, printing output or running `kantan trigger`.
    // Running a polling timer alongside it causes redundant command
    // invocations and potential cache races on the shared CommandOutputData.
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
    watchRestartCount = 0
    launchWatch(command: watchCmd)
  }

  private func launchWatch(command: String) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/sh")
    process.arguments = ["-c", command]

    var env = ProcessInfo.processInfo.environment
    env["KANTAN_MODULE_NAME"] = self.id
    let appearance = Self.appearance
    if let cmdConfig = moduleConfig.config as? CommandConfig {
      if let settings = cmdConfig.resolvedSettings(isDark: appearance == "dark") {
        env["KANTAN_SETTINGS"] = settings
      }
    }
    env["KANTAN_APPEARANCE"] = appearance
    env["KANTAN_PID"] = "\(ProcessInfo.processInfo.processIdentifier)"
    process.environment = env

    // Provide a stdin pipe so the watch process can detect kantan exit
    // (reads on stdin return EOF when kantan terminates).
    let stdinPipe = Pipe()
    let stdoutPipe = Pipe()
    process.standardInput = stdinPipe
    process.standardOutput = stdoutPipe
    process.standardError = FileHandle.nullDevice

    watchLaunch &+= 1
    let launch = watchLaunch
    watchOutput = LineBuffer()
    stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
      let output = handle.availableData
      guard !output.isEmpty else {
        handle.readabilityHandler = nil
        return
      }
      DispatchQueue.main.async {
        MainActor.assumeIsolated {
          self?.receiveWatchOutput(output, from: launch)
        }
      }
    }
    process.terminationHandler = { [weak self] proc in
      DispatchQueue.main.async {
        MainActor.assumeIsolated {
          self?.handleWatchTermination(exitCode: proc.terminationStatus, from: launch)
        }
      }
    }

    do {
      try process.run()
      watchProcess = process
      watchStdinPipe = stdinPipe
      watchAppearance = appearance
      watchLaunchDate = Date()
    } catch {
      stdoutPipe.fileHandleForReading.readabilityHandler = nil
      print("Failed to launch watch process: \(error)")
    }
  }

  nonisolated static let maxWatchRestarts = 10
  /// How long a watch process runs before exiting for its exit to start
  /// the restart count afresh.
  nonisolated static let stableWatchRun: TimeInterval = 30

  /// The restart attempt following an exit after `ranFor` seconds, when
  /// `count` consecutive restarts came before: the next one, or the first
  /// once the watch ran for `stableWatchRun`.
  nonisolated static func watchRestartAttempt(after count: Int, ranFor: TimeInterval) -> Int {
    ranFor >= stableWatchRun ? 1 : count + 1
  }

  /// Backoff delay (seconds) for the Nth restart attempt (1-indexed).
  /// Returns nil once the attempt would exceed `maxWatchRestarts`.
  /// Doubles each attempt and caps at 16s (1 << 4).
  nonisolated static func watchRestartDelay(forAttempt attempt: Int) -> Double? {
    guard attempt >= 1, attempt <= maxWatchRestarts else { return nil }
    return min(Double(1 << min(attempt - 1, 4)), 30.0)
  }

  /// The appearance plugins are given, as `KANTAN_APPEARANCE`.
  private static var appearance: String {
    NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? "dark" : "light"
  }

  /// Shows each JSON object line the watch process prints as the command's
  /// output, as though the command had printed it.
  private func receiveWatchOutput(_ output: Data, from launch: UInt64) {
    guard launch == watchLaunch else { return }
    for line in watchOutput.append(output) {
      guard durationTimer == nil, let config = moduleConfig.config as? CommandConfig,
        let value = config.cacheWatchOutput(line)
      else { continue }
      // Supersedes any command run still in flight.
      updateGeneration &+= 1
      show(
        value, icon: config.getIcon(),
        backgroundIcon: config.getBackgroundIcon().map { resolveIconName($0).glyph }, of: config)
    }
  }

  /// Relaunches the watch process once the appearance differs from the one
  /// it was given, so it has settings resolved for the new appearance.
  private func relaunchWatchIfAppearanceChanged() {
    guard watchProcess != nil, Self.appearance != watchAppearance,
      let watchCmd = moduleConfig.config?.getWatchCommand(), !watchCmd.isEmpty
    else { return }
    terminateWatch()
    launchWatch(command: watchCmd)
  }

  private func handleWatchTermination(exitCode: Int32, from launch: UInt64) {
    guard launch == watchLaunch else { return }
    watchProcess = nil
    watchStdinPipe = nil

    // Don't restart if we intentionally stopped the watch
    guard !watchStopped else { return }

    let attempt = Self.watchRestartAttempt(
      after: watchRestartCount, ranFor: Date().timeIntervalSince(watchLaunchDate))
    guard let delay = Self.watchRestartDelay(forAttempt: attempt) else {
      print(
        "Watch process for '\(id)' exceeded \(Self.maxWatchRestarts) restarts, giving up")
      return
    }
    watchRestartCount = attempt
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
  let config: Config
  let popupManager = PopupManager()
  private var eventObserver: EventObserver?

  let allModules: [ModuleViewModel]

  @Published var leftDrawerOpen: Bool = false
  @Published var rightDrawerOpen: Bool = false
  private(set) var hasLeftDrawer: Bool = false
  private(set) var hasRightDrawer: Bool = false
  private var drawerVMs: [String: ModuleViewModel] = [:]  // side ("left"/"right") → drawer VM

  var hasDrawer: Bool { hasLeftDrawer || hasRightDrawer }

  init(config: Config) {
    self.config = config

    var modules: [ModuleViewModel] = []
    for moduleConfig in config.modules {
      modules.append(ModuleViewModel(moduleConfig: moduleConfig))
    }
    self.allModules = modules

    // Wire up drawer modules — one per side (left/right)
    for dvm in allModules where dvm.moduleConfig.type == "drawer" {
      let side = dvm.moduleConfig.placement.isRightSide ? "right" : "left"
      // Only one drawer per side; first wins
      guard drawerVMs[side] == nil else { continue }
      drawerVMs[side] = dvm
      if side == "left" {
        hasLeftDrawer = true
      } else {
        hasRightDrawer = true
      }
      dvm.toggleAction = { [weak self] in
        self?.toggleDrawer(side: side)
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

  /// Build module groups for a specific screen, resolving placement specs
  /// based on whether the screen has a notch.
  func buildGroups(hasNotch: Bool) -> [ModuleGroup] {
    // Resolve each module's effective placement for this screen.
    // Modules that resolve to nil (notch-only on non-notch screen) are excluded.
    struct ResolvedModule {
      let vm: ModuleViewModel
      let placement: String
    }

    var resolved: [ResolvedModule] = []
    for vm in allModules {
      guard let placement = vm.moduleConfig.placement.resolve(hasNotch: hasNotch) else {
        continue
      }
      resolved.append(ResolvedModule(vm: vm, placement: placement))
    }

    // Partition by effective placement. Config order is preserved within each bucket.
    // Layout order: left → notchleft → [NOTCH] → notchright → right
    let buckets: [(placement: String, modules: [ResolvedModule])] = [
      ("left", resolved.filter { $0.placement == "left" }),
      ("notchleft", resolved.filter { $0.placement == "notchleft" }),
      ("notchright", resolved.filter { $0.placement == "notchright" }),
      ("right", resolved.filter { $0.placement == "right" }),
    ]

    var allGroups: [ModuleGroup] = []
    for (placement, bucket) in buckets {
      var groups = BarViewModel.buildGroupsForPlacement(
        from: bucket.map { $0.vm }, placement: placement)
      // Right-to-left placements (right, notchleft) need groups reversed so the
      // positioning loop processes the outermost group (closest to screen/notch edge)
      // first, consuming space inward.
      if placement == "right" || placement == "notchleft" {
        groups.reverse()
      }
      allGroups.append(contentsOf: groups)
    }
    return allGroups
  }

  static func buildGroupsForPlacement(
    from modules: [ModuleViewModel], placement: String
  )
    -> [ModuleGroup]
  {
    guard !modules.isEmpty else { return [] }

    // Find the drawer module index (if any) to mark drawer content.
    // For right-to-left placements (right, notchleft) the drawer comes AFTER
    // its content in config order, so content = indices before the drawer.
    // For left-to-right placements (left, notchright) the drawer comes BEFORE
    // its content, so content = indices after the drawer.
    let drawerIndex = modules.firstIndex { $0.moduleConfig.type == "drawer" }
    let isRightToLeft = placement == "right" || placement == "notchleft"

    // Tag each module with whether it's drawer content
    let isDrawerContent: [Bool] = modules.enumerated().map { idx, _ in
      guard let di = drawerIndex else { return false }
      return isRightToLeft ? idx < di : idx > di
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
            isPassthrough: pt,
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

  func toggleDrawer(side: String) {
    if side == "left" {
      leftDrawerOpen.toggle()
    } else {
      rightDrawerOpen.toggle()
    }
    guard let drawer = drawerVMs[side] else { return }
    (drawer.moduleConfig.config as? DrawerConfig)?.state.isOpen =
      side == "left" ? leftDrawerOpen : rightDrawerOpen
    drawer.update()
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
          vm.segments = []
        }
        if let icon = userInfo["icon"] {
          vm.setIcon(icon.isEmpty ? nil : icon)
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
private let defaultTextFontConfig = FontConfig(
  descriptor: "Helvetica Neue:13", source: .system)
private let defaultIconFontConfig = FontConfig(
  descriptor: "tabler-icons:regular:15", source: .bundled)

@MainActor
class ThemeProvider: ObservableObject {
  @Published var isDarkMode: Bool = true
  let config: Config
  private var appearanceObservation: NSKeyValueObservation?

  var isNative: Bool {
    config.isNativeAppearance
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

  // MARK: - Theme Template Resolution

  /// The active theme palette for the current appearance mode.
  private var activePalette: ThemePalette? {
    guard let theme = config.theme else { return nil }
    return isDarkMode ? theme.darkPalette : theme.lightPalette
  }

  /// Resolve a raw colour string (hex or `{theme(name)}` template) to a SwiftUI Color.
  func resolvedColor(_ value: String) -> Color {
    Color(nsColor: NSColor(hex: resolveColor(value)))
  }

  /// Resolve a raw colour string to its hex representation. Used by
  /// TemplateResolver's fallbackResolver to handle `{theme(name)}` patterns.
  func resolveColorString(_ value: String) -> String {
    resolveColor(value)
  }

  /// Resolve a colour string that may be a `{theme(name)}` template.
  /// Returns the resolved hex colour, or the original string if not a template.
  private func resolveColor(_ value: String) -> String {
    guard let palette = activePalette else { return value }
    return resolveThemeTemplate(value, palette: palette)
  }

  /// Returns true when the value is a `{theme(...)}` template that cannot
  /// be resolved because no theme palette is loaded (native mode).
  private func isUnresolvableTemplate(_ value: String) -> Bool {
    activePalette == nil && value.hasPrefix("{theme(") && value.hasSuffix(")}")
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
      Color(nsColor: NSColor(hex: resolveColor(mode.fg ?? "FFFFFF"))),
      Color(nsColor: NSColor(hex: resolveColor(mode.bg ?? "000000")))
    )
  }

  func globalFgNSColor() -> NSColor {
    if isNative { return .labelColor }
    let mode = resolveGlobalStyleMode()
    return NSColor(hex: resolveColor(mode.fg ?? "FFFFFF"))
  }

  func globalBgNSColor() -> NSColor {
    if isNative { return .windowBackgroundColor }
    let mode = resolveGlobalStyleMode()
    return NSColor(hex: resolveColor(mode.bg ?? "000000"))
  }

  private func elementFgColor(
    for vm: ModuleViewModel,
    dynamicFg: KeyPath<DynamicStyleOverride, String?>,
    elementFg: KeyPath<StyleModeConfig, ElementStyle?>
  ) -> Color {
    // Override is a raw hex value from a plugin; bypasses theme resolution.
    if let override = vm.fgOverride {
      return Color(nsColor: NSColor(hex: override))
    }

    // Dynamic style values may contain `{theme(...)}` templates that can't
    // resolve without a palette; skip those so we fall through to defaults.
    let ds = vm.dynamicStyle
    let dynamicCandidates: [String?] = [
      ds?[keyPath: dynamicFg],
      ds?.fg,
    ]
    if let fg = dynamicCandidates.compactMap({ $0 })
      .first(where: { !isUnresolvableTemplate($0) })
    {
      return resolvedColor(fg)
    }

    if isNative { return Color(nsColor: .labelColor) }

    let moduleMode = resolveModuleStyleMode(vm.moduleConfig.style)
    let globalMode = resolveGlobalStyleMode()
    let staticCandidates: [String?] = [
      moduleMode?[keyPath: elementFg]?.fg,
      moduleMode?.fg,
      globalMode[keyPath: elementFg]?.fg,
      globalMode.fg,
    ]
    return resolvedColor(staticCandidates.compactMap({ $0 }).first ?? "FFFFFF")
  }

  func textFgColor(for vm: ModuleViewModel) -> Color {
    elementFgColor(for: vm, dynamicFg: \.textFg, elementFg: \.text)
  }

  /// The module's value, each of its segments in its own colour, or the
  /// module's text colour for a segment without one. An `fg` override,
  /// and the native appearance, colour it all alike.
  func valueText(for vm: ModuleViewModel) -> AttributedString {
    let fg = textFgColor(for: vm)
    let colours = vm.fgOverride == nil && !isNative
    let segments =
      vm.segments.isEmpty ? [ValueSegment(text: vm.displayValue ?? "", fg: nil)] : vm.segments
    return segments.reduce(into: AttributedString()) { text, segment in
      var part = AttributedString(segment.text)
      part.foregroundColor =
        segment.fg.flatMap { colours && !isUnresolvableTemplate($0) ? resolvedColor($0) : nil }
        ?? fg
      text += part
    }
  }

  func iconFgColor(for vm: ModuleViewModel) -> Color {
    elementFgColor(for: vm, dynamicFg: \.iconFg, elementFg: \.icon)
  }

  func bgColor(for vm: ModuleViewModel) -> Color {
    if let override = vm.bgOverride {
      return Color(nsColor: NSColor(hex: override))
    }
    if let ds = vm.dynamicStyle, let bg = ds.bg, !bg.isEmpty, !isUnresolvableTemplate(bg) {
      return Color(nsColor: NSColor(hex: resolveColor(bg)))
    }
    if isNative { return .clear }

    let moduleMode = resolveModuleStyleMode(vm.moduleConfig.style)
    let globalMode = resolveGlobalStyleMode()

    if let bg = moduleMode?.bg { return Color(nsColor: NSColor(hex: resolveColor(bg))) }

    // When a module has a shape but no explicit bg, use the theme's shape
    // colour so the shape is visible against the bar background.
    if moduleMode?.shape != nil, let palette = activePalette, let shapeBg = palette.shape {
      return Color(nsColor: NSColor(hex: shapeBg))
    }

    return Color(nsColor: NSColor(hex: resolveColor(globalMode.bg ?? "000000")))
  }

  func barBgColor() -> Color {
    if isNative { return .clear }
    let mode = resolveGlobalStyleMode()
    return Color(nsColor: NSColor(hex: resolveColor(mode.bg ?? "000000")))
  }

  func shape(for vm: ModuleViewModel) -> ModuleShape? {
    let moduleMode = resolveModuleStyleMode(vm.moduleConfig.style)
    return moduleMode?.shape
  }

  // MARK: - Font Resolution

  func iconFont(for vm: ModuleViewModel) -> Font {
    let base = vm.moduleConfig.iconFont ?? config.iconFont ?? defaultIconFontConfig
    let scaledSize = Int(round(base.size * vm.iconScaleFactor))
    // If the icon was resolved from a named glyph (e.g. "bell"), override
    // the font family name and apply the dynamic scale factor.
    if let override = vm.iconFontNameOverride {
      let overrideConfig = FontConfig(
        descriptor: "\(override):\(scaledSize)", source: .bundled)
      return overrideConfig.swiftUIFont
    }
    // No font name override but still apply scale factor for literal glyphs
    // from a bundled font that were resolved with a scale.
    if vm.iconScaleFactor != 1.0 {
      let scaledConfig = FontConfig(
        descriptor: "\(base.name):\(scaledSize)", source: base.source)
      return scaledConfig.swiftUIFont
    }
    return base.swiftUIFont
  }

  func textFont(for vm: ModuleViewModel) -> Font {
    let fontConfig = vm.moduleConfig.textFont ?? config.textFont ?? defaultTextFontConfig
    return fontConfig.swiftUIFont
  }

  // MARK: - Layout

  var iconTextSpacing: CGFloat {
    CGFloat(config.iconTextSpacing)
  }
}
