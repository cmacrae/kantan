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
  /// How far right of its place the icon is drawn, as a fraction of its
  /// font size, to sit on the icon behind it.
  @Published var iconShift: CGFloat = 0
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

  /// Whether the pointer is over a module that reveals on hover.
  @Published var isHovered = false
  /// Whether the module's menu or popup is open.
  @Published var isPopupOpen = false
  /// Whether the module's output marks its icon as hidden until a hover,
  /// or nil when it says nothing of what a hover reveals.
  @Published var outputRevealsIcon: Bool?

  /// Whether the module keeps some of itself hidden until the pointer is
  /// over it.
  var revealsOnHover: Bool {
    moduleConfig.interaction?.hover?.type == "reveal"
  }

  /// Whether what a hover reveals is showing: under the pointer, or while
  /// the module's menu or popup is open when its hover persists.
  var isRevealed: Bool {
    isHovered || (isPopupOpen && moduleConfig.interaction?.hover?.persist == true)
  }

  /// Whether `part` stays hidden until a hover reveals it.
  func hidesUntilRevealed(_ part: RevealPart) -> Bool {
    moduleConfig.interaction?.hover?.hides(
      part, outputRevealsIcon: outputRevealsIcon, segments: segments) ?? false
  }

  /// The animation for the module sliding in and out as it shows and
  /// hides, or nil when it appears at once.
  var visibilityAnimation: Animation? {
    guard moduleConfig.slidesSomewhere,
      !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    else { return nil }
    return ModuleAnimation.content
  }

  /// The animation for the module's text sliding out and back, or nil to
  /// show it at once, as with Reduce Motion on.
  var revealAnimation: Animation? {
    NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil : ModuleAnimation.content
  }

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
  /// How many reads of the module's value are under way.
  private var updatesInFlight = 0
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

    update()
    if let eventModule = moduleConfig.config as? EventDrivenModule {
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
    updatesInFlight += 1

    updateGeneration &+= 1
    let gen = updateGeneration

    let icon = config.getIcon()
    let bgIcon = config.getBackgroundIcon()

    config.getValue { [weak self] newValue in
      DispatchQueue.main.async {
        guard let self else { return }
        self.updatesInFlight -= 1
        // Superseded by a later update, or by a `set` trigger's duration.
        guard self.updateGeneration == gen, self.durationTimer == nil else { return }
        // A command's icon comes from the output getValue just produced.
        let currentIcon = config is CommandConfig ? config.getIcon() : icon
        self.show(newValue, icon: currentIcon, backgroundIcon: bgIcon, of: config)
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
    var shift: CGFloat = 0
    if let backgroundIcon, let rawIcon, config.alignsBackgroundIconLeading() {
      shift = iconInkLeading(backgroundIcon) - iconInkLeading(rawIcon)
    }
    // A module showing or hiding slides when its transition says so.
    let appears = shouldDisplay != config.shouldDisplay()
    withAnimation(contentAnimation ?? (appears ? visibilityAnimation : nil)) {
      displayValue = value
      displayIcon = resolved?.glyph ?? rawIcon
      iconFontNameOverride = resolved?.fontNameOverride
      iconScaleFactor = resolved?.scaleFactor ?? 1.0
      self.backgroundIcon = backgroundIcon.map { resolveIconName($0).glyph }
      iconShift = shift
      isActive = config.isActive()
      shouldDisplay = config.shouldDisplay()
      templateVariables = config.getTemplateVariables()
      dynamicStyle = config.getDynamicStyle()
      viewTree = config.getViewTree()
      if let cmdConfig = config as? CommandConfig {
        data = cmdConfig.getData()
        segments = cmdConfig.getSegments()
        outputRevealsIcon = cmdConfig.revealsIcon()
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

  /// Starts the module's polling timer; the caller runs the first update.
  private func startPolling() {
    // When a watch process is configured, it is responsible for all
    // subsequent refreshes, printing output or running `kantan trigger`.
    // Running a polling timer alongside it causes redundant command
    // invocations and potential cache races on the shared CommandOutputData.
    if let watchCmd = moduleConfig.config?.getWatchCommand(), !watchCmd.isEmpty {
      return
    }
    let interval = moduleConfig.config?.redrawInterval ?? 1.0
    guard interval > 0 else { return }
    // Replaces any timer already running, so resuming twice polls once.
    timer?.invalidate()
    // A tick while the last one's value is still being read is skipped.
    let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated {
        guard let self, self.updatesInFlight == 0 else { return }
        self.update()
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
    process.arguments = ["-c", Self.watchScript, "sh", command]

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

  /// How long a stopped watch process has to exit on stdin EOF before
  /// it's sent SIGTERM.
  nonisolated static let watchStopGrace: TimeInterval = 1

  /// Runs the watch command `$1` with kantan's stdin, and once stdin reaches
  /// EOF, however kantan stopped, gives it `watchStopGrace` to exit before
  /// sending SIGTERM to its process group, so nothing it started outlives
  /// kantan.
  nonisolated static let watchScript = """
    exec 3<&0
    { read -r _ <&3; sleep \(Int(watchStopGrace)); kill -TERM 0; } &
    watcher=$!
    trap 'kill "$watcher" 2>/dev/null' EXIT
    /bin/sh -c "$1" 3<&-
    """

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
        backgroundIcon: config.getBackgroundIcon(), of: config)
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
        // Not if the watch was stopped, or launched again meanwhile.
        guard let self, !self.watchStopped, self.watchLaunch == launch else { return }
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
    // Close stdin so the watch process can exit on EOF, and send SIGTERM
    // if it's still running once the grace period is up.
    try? watchStdinPipe?.fileHandleForWriting.close()
    watchStdinPipe = nil
    watchProcess = nil
    DispatchQueue.main.asyncAfter(deadline: .now() + Self.watchStopGrace) {
      if process.isRunning { process.terminate() }
    }
  }
}

// MARK: - Module Group

struct ModuleGroup: Identifiable {
  let id: String
  let modules: [ModuleViewModel]
  let isPassthrough: Bool
  let placement: String
  let isDrawerContent: Bool
  /// The anchor of the screen's centre, which every group of a screen
  /// with one shares.
  var anchor: CenterAnchor? = nil
}

/// The module whose icon sits on the bar's centre on a screen without a
/// notch, and where that icon has been drawn.
@MainActor
final class CenterAnchor {
  let module: String
  /// Whether the icon is at the module's right.
  let iconTrails: Bool
  /// The module on the icon's side, drawn against it as its text is: the
  /// padding between the two gives way to the room between icon and text.
  let neighbour: String?
  /// The icon's centre within its group, while it is drawn.
  private(set) var iconMidX: CGFloat?
  /// Called as the icon moves within its group.
  var onMove: (() -> Void)?

  init(module: String, iconTrails: Bool, neighbour: String?) {
    self.module = module
    self.iconTrails = iconTrails
    self.neighbour = neighbour
  }

  func setIconMidX(_ midX: CGFloat?) {
    if let midX, let iconMidX, abs(midX - iconMidX) < 0.5 { return }
    guard midX != iconMidX else { return }
    iconMidX = midX
    onMove?()
  }

  /// The anchor among `modules`, those around the centre of a screen
  /// without a notch from left to right with where each resolves to: the
  /// first that names one.
  nonisolated static func find(in modules: [(config: ModuleConfig, placement: String)])
    -> (module: String, iconTrails: Bool, neighbour: String?)?
  {
    guard let index = modules.firstIndex(where: { $0.config.anchor == .icon }) else { return nil }
    let trails = modules[index].config.iconTrails(at: modules[index].placement)
    let beside = trails ? index + 1 : index - 1
    return (
      modules[index].config.name, trails,
      modules.indices.contains(beside) ? modules[beside].config.name : nil
    )
  }
}

// MARK: - Overlap

/// What happens where the modules beside the notch and an open drawer's
/// contents, further out on the same side, want the same room.
enum OverlapAction: Equatable {
  case none
  /// The modules beside the notch slide behind it.
  case displace
  /// They slide back out.
  case restore
  /// The drawer closes for now.
  case closeDrawer
  /// The drawer opens again.
  case reopenDrawer

  /// What to do on one side of the notch. Whichever is being used keeps
  /// its place: a drawer opened over the modules beside the notch displaces
  /// them, until it closes or there is room. A module beside the notch
  /// under the pointer, or with its popup open, closes the drawer it grows
  /// into, until it is let go, when the drawer opens again.
  ///
  /// - collides: whether the two want the same room, the modules beside
  ///   the notch at the width they have, or had before being displaced.
  /// - drawerOpen: whether the side's drawer is open with contents further
  ///   out than the notch's modules.
  /// - engaged: whether a module beside the notch is being used.
  /// - displaced: whether the modules beside the notch are behind it.
  /// - yielded: whether the drawer is closed for now.
  static func resolve(
    collides: Bool, drawerOpen: Bool, engaged: Bool, displaced: Bool, yielded: Bool
  ) -> OverlapAction {
    if yielded {
      // The drawer waits for the module that closed it to be let go.
      return engaged || drawerOpen ? .none : .reopenDrawer
    }
    if displaced {
      return drawerOpen && collides ? .none : .restore
    }
    guard collides, drawerOpen else { return .none }
    return engaged ? .closeDrawer : .displace
  }
}

/// The placements whose modules a display has slid behind its notch.
@MainActor
final class DisplacedPlacements: ObservableObject {
  @Published var placements: Set<String> = []
}

// MARK: - Tuck

/// How one side of the notch is shared between the modules that give way,
/// those with a `tuck`, and the others.
enum TuckPhase: Equatable {
  /// Every module shows as it would alone.
  case idle
  /// The modules that give way wait behind the notch.
  case tucked
  /// They are out, in place of the others.
  case revealed

  /// The phase of one side of the notch.
  ///
  /// - tucking: whether a module that gives way has something to show.
  /// - holding: whether another module on the side does.
  /// - revealing: whether those that give way are wanted out: one has just
  ///   arrived, the pointer is at the notch, or one has its popup open.
  static func resolve(tucking: Bool, holding: Bool, revealing: Bool) -> TuckPhase {
    guard tucking, holding else { return .idle }
    return revealing ? .revealed : .tucked
  }

  /// Whether a module is out of the bar in this phase: one that gives way
  /// while tucked, any other while those are revealed.
  func hides(givesWay: Bool) -> Bool {
    switch self {
    case .idle: false
    case .tucked: givesWay
    case .revealed: !givesWay
    }
  }
}

/// The phase of each side of a display's notch, by placement.
@MainActor
final class NotchTucks: ObservableObject {
  @Published var phases: [String: TuckPhase] = [:]
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
    // Layout order: left → notchleft → [NOTCH] or center → notchright → right
    let buckets: [(placement: String, modules: [ResolvedModule])] = [
      ("left", resolved.filter { $0.placement == "left" }),
      ("notchleft", resolved.filter { $0.placement == "notchleft" }),
      ("center", resolved.filter { $0.placement == "center" }),
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

    // Without a notch, the modules around the bar's centre may anchor it.
    guard !hasNotch else { return allGroups }
    let anchor = CenterAnchor.find(
      in: ["notchleft", "center", "notchright"].flatMap { placement in
        resolved.filter { $0.placement == placement }.map { ($0.vm.moduleConfig, placement) }
      }
    ).map(CenterAnchor.init)
    return allGroups.map { group in
      var group = group
      group.anchor = anchor
      return group
    }
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
    // The centre has no direction to fold in, so a drawer there has no content.
    let drawerIndex =
      placement == "center" ? nil : modules.firstIndex { $0.moduleConfig.type == "drawer" }
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

  /// The sides whose drawer is closed for now, to make room for a module
  /// beside the notch being used, and opens again once it isn't.
  private(set) var yieldedDrawers: Set<String> = []

  /// Opens or closes a side's drawer as its module's click does. A drawer
  /// the user sets is no longer one waiting to open again.
  func toggleDrawer(side: String) {
    yieldedDrawers.remove(side)
    setDrawer(side: side, open: !(side == "left" ? leftDrawerOpen : rightDrawerOpen))
  }

  /// Closes a side's open drawer for now, or opens it again afterwards.
  func yieldDrawer(side: String, _ yields: Bool) {
    guard yields != yieldedDrawers.contains(side) else { return }
    if yields { yieldedDrawers.insert(side) } else { yieldedDrawers.remove(side) }
    setDrawer(side: side, open: !yields)
  }

  private func setDrawer(side: String, open: Bool) {
    if side == "left" {
      leftDrawerOpen = open
    } else {
      rightDrawerOpen = open
    }
    guard let drawer = drawerVMs[side] else { return }
    (drawer.moduleConfig.config as? DrawerConfig)?.state.isOpen = open
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

  /// The longest a `set` trigger's `duration` lasts, in seconds.
  nonisolated static let maxTriggerDuration: TimeInterval = 3600

  /// The seconds a `set` trigger's `duration` field asks for, at most
  /// `maxTriggerDuration`, or nil for a value that isn't a positive number.
  nonisolated static func triggerDuration(_ field: String) -> TimeInterval? {
    guard let duration = Double(field), duration > 0, !duration.isNaN else { return nil }
    return min(duration, maxTriggerDuration)
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
        if let duration = userInfo["duration"].flatMap(Self.triggerDuration) {
          vm.scheduleDurationReset(duration)
        }

      default:
        break
      }
    }
  }
}

// MARK: - Theme Provider

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

  // MARK: - Style Resolution

  /// The config's styles for the current appearance.
  var styles: StyleResolver {
    StyleResolver(config: config, isDark: isDarkMode)
  }

  /// The SwiftUI colour `color` draws as.
  private func swiftUIColor(_ color: StyleColor) -> Color {
    switch color {
    case .value(let hex): Color(nsColor: NSColor(hex: hex))
    case .label: Color(nsColor: .labelColor)
    case .clear: .clear
    }
  }

  /// Resolve a raw colour string (hex or `{theme(name)}` template) to a SwiftUI Color.
  func resolvedColor(_ value: String) -> Color {
    Color(nsColor: NSColor(hex: styles.resolve(value)))
  }

  /// The colour `value` names, a hex colour or `{theme(name)}` template, or
  /// nil for a template the palette can't resolve.
  func color(_ value: String) -> Color? {
    let resolved = styles.resolve(value)
    return resolved.hasPrefix("{theme(") ? nil : Color(nsColor: NSColor(hex: resolved))
  }

  /// Resolve a raw colour string to its hex representation. Used by
  /// TemplateResolver's fallbackResolver to handle `{theme(name)}` patterns.
  func resolveColorString(_ value: String) -> String {
    styles.resolve(value)
  }

  // MARK: - Color Resolution

  func globalColors() -> (fg: Color, bg: Color) {
    let styles = styles
    return (
      Color(nsColor: NSColor(hex: styles.globalFg)), Color(nsColor: NSColor(hex: styles.globalBg))
    )
  }

  func globalFgNSColor() -> NSColor {
    isNative ? .labelColor : NSColor(hex: styles.globalFg)
  }

  func globalBgNSColor() -> NSColor {
    isNative ? .windowBackgroundColor : NSColor(hex: styles.globalBg)
  }

  /// The colour of the module's value. A trigger's `fg` override, a raw
  /// hex value, comes before every style.
  func textFgColor(for vm: ModuleViewModel) -> Color {
    if let override = vm.fgOverride { return Color(nsColor: NSColor(hex: override)) }
    return swiftUIColor(styles.textFg(style: vm.moduleConfig.style, dynamic: vm.dynamicStyle))
  }

  /// The module's value, each of its segments in its own colour, or the
  /// module's text colour for a segment without one. An `fg` override,
  /// and the native appearance, colour it all alike.
  func valueText(for vm: ModuleViewModel) -> AttributedString {
    valueParts(for: vm).reduce(into: AttributedString()) { $0 += $1.text }
  }

  /// The module's value as its segments, each coloured as `valueText`
  /// colours it, with whether it stays hidden until a hover reveals it.
  func valueParts(for vm: ModuleViewModel) -> [(text: AttributedString, reveal: Bool)] {
    let fg = textFgColor(for: vm)
    let styles = styles
    let segments =
      vm.segments.isEmpty ? [ValueSegment(text: vm.displayValue ?? "", fg: nil)] : vm.segments
    return segments.map { segment in
      var part = AttributedString(segment.text)
      part.foregroundColor =
        (vm.fgOverride == nil ? styles.segmentFg(segment.fg) : nil).map(swiftUIColor) ?? fg
      return (part, segment.reveal)
    }
  }

  /// The colour of the module's icon. A trigger's `fg` override comes
  /// before every style.
  func iconFgColor(for vm: ModuleViewModel) -> Color {
    if let override = vm.fgOverride { return Color(nsColor: NSColor(hex: override)) }
    return swiftUIColor(styles.iconFg(style: vm.moduleConfig.style, dynamic: vm.dynamicStyle))
  }

  /// The colour of the module's shape. A trigger's `bg` override comes
  /// before every style.
  func bgColor(for vm: ModuleViewModel) -> Color {
    if let override = vm.bgOverride { return Color(nsColor: NSColor(hex: override)) }
    return swiftUIColor(styles.bg(style: vm.moduleConfig.style, dynamic: vm.dynamicStyle))
  }

  func barBgColor() -> Color {
    swiftUIColor(styles.barBg)
  }

  /// The module's shape: a plugin's override, or the module's style's.
  func shape(for vm: ModuleViewModel) -> ModuleShape? {
    styles.shape(style: vm.moduleConfig.style, dynamic: vm.dynamicStyle)
  }

  // MARK: - Font Resolution

  /// The size the module's icon is drawn at: its font's, scaled for its glyph.
  func iconFontSize(for vm: ModuleViewModel) -> Int {
    let base = vm.moduleConfig.iconFont ?? config.iconFont ?? defaultIconFontConfig
    return Int(round(base.size * vm.iconScaleFactor))
  }

  func iconFont(for vm: ModuleViewModel) -> Font {
    let base = vm.moduleConfig.iconFont ?? config.iconFont ?? defaultIconFontConfig
    let scaledSize = iconFontSize(for: vm)
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

  /// The font of text without one of its own.
  var globalTextFont: FontConfig {
    config.textFont ?? defaultTextFontConfig
  }

  func textFont(for vm: ModuleViewModel) -> Font {
    let fontConfig = vm.moduleConfig.textFont ?? globalTextFont
    return fontConfig.swiftUIFont
  }

  // MARK: - Layout

  var iconTextSpacing: CGFloat {
    CGFloat(config.iconTextSpacing)
  }
}
