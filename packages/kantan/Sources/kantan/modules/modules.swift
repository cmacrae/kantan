import AppKit
import Foundation

/// Dynamic style overrides returned by modules (e.g. command JSON output).
/// Takes priority over static YAML style config when present.
struct DynamicStyleOverride: Sendable {
  let fg: String?
  let bg: String?
  let iconFg: String?
  let textFg: String?
  var shape: ShapeOverride? = nil
}

/// A plugin's override of the module's shape: another shape, or none at all.
enum ShapeOverride: Equatable, Sendable {
  case unshaped
  case shaped(ModuleShape)

  /// The override `raw` names: `none`, or a shape such as `box`.
  init?(_ raw: String) {
    if raw == "none" {
      self = .unshaped
    } else if let shape = ModuleShape(rawValue: raw) {
      self = .shaped(shape)
    } else {
      return nil
    }
  }
}

/// Style override for a module state (e.g. a power state or Focus mode).
/// Parsed from `config.style.<state>` — supports string shorthand (→ fg)
/// or expanded dict with fg/bg/icon.fg/text.fg. Colours may be
/// `{theme(name)}` templates, resolved at render time.
struct StateStyle: Equatable, Sendable {
  let fg: String?
  let bg: String?
  let iconFg: String?
  let textFg: String?

  func toDynamicStyle() -> DynamicStyleOverride {
    DynamicStyleOverride(fg: fg, bg: bg, iconFg: iconFg, textFg: textFg)
  }

  static func parse(from yaml: Yaml) -> StateStyle? {
    // Shorthand: string → fg
    if let str = yaml.string {
      return StateStyle(fg: str, bg: nil, iconFg: nil, textFg: nil)
    }
    // Expanded: dict with fg/bg/icon.fg/text.fg
    guard yaml.dictionary != nil else { return nil }
    let fg = yaml["fg"].string
    let bg = yaml["bg"].string
    let iconFg = yaml["icon"]["fg"].string
    let textFg = yaml["text"]["fg"].string
    guard fg != nil || bg != nil || iconFg != nil || textFg != nil else { return nil }
    return StateStyle(fg: fg, bg: bg, iconFg: iconFg, textFg: textFg)
  }
}

protocol ModuleConfiguration: Sendable {
  var type: String { get }
  var redrawInterval: TimeInterval { get }
  func getValue(completion: @escaping @Sendable (String) -> Void)
  func getIcon() -> String
  func getTemplateVariables() -> [String: String]
  func isActive() -> Bool
  func shouldDisplay() -> Bool
  /// Runs the module's toggle action, calling `completion` once it has
  /// finished. Must not block the calling (main) thread.
  func handleToggle(completion: @escaping @Sendable () -> Void)
  func getViewTree() -> ViewNode?
  func getDynamicStyle() -> DynamicStyleOverride?
  func getWatchCommand() -> String?
  func getBackgroundIcon() -> String?
  /// Whether the module's icon is drawn with its left edge on that of the
  /// icon behind it, rather than centred over it.
  func alignsBackgroundIconLeading() -> Bool
}

extension ModuleConfiguration {
  func getIcon() -> String { "" }
  func getTemplateVariables() -> [String: String] { [:] }
  func isActive() -> Bool { true }
  func shouldDisplay() -> Bool { true }
  func handleToggle(completion: @escaping @Sendable () -> Void) { completion() }
  func getViewTree() -> ViewNode? { nil }
  func getDynamicStyle() -> DynamicStyleOverride? { nil }
  func getWatchCommand() -> String? { nil }
  func getBackgroundIcon() -> String? { nil }
  func alignsBackgroundIconLeading() -> Bool { false }
}

/// Sentinel interval for modules that don't poll (event-driven or static).
/// Using a large value rather than 0 prevents Timer from firing continuously.
let noPoll: TimeInterval = 3600.0

// MARK: - Event-Driven Module

/// Modules that push updates via system events rather than timer-based polling.
protocol EventDrivenModule: AnyObject {
  func startObserving(onChange: @escaping @Sendable () -> Void)
  func stopObserving()
}

// MARK: - Interaction Config

struct InteractionConfig {
  let hover: HoverConfig?
  let click: ClickConfig?
}

/// A part of a module that a `reveal` hover can keep hidden until the
/// pointer is over the module.
enum RevealPart: String, Sendable {
  case icon
  case text
}

struct HoverConfig {
  let type: String
  let content: String?
  let viewTree: ViewNode?
  /// The parts a `reveal` hover hides until the pointer is over the module,
  /// or nil for those the module's output marks, and its text when it
  /// marks none.
  let reveal: Set<RevealPart>?
  /// Whether what a hover reveals stays while the module's menu or popup
  /// is open.
  let persist: Bool

  init(
    type: String, content: String? = nil, viewTree: ViewNode? = nil,
    reveal: Set<RevealPart>? = nil, persist: Bool = false
  ) {
    self.type = type
    self.content = content
    self.viewTree = viewTree
    self.reveal = reveal
    self.persist = persist
  }
}

extension HoverConfig {
  /// Whether a `reveal` hover keeps `part` hidden until the pointer is over
  /// the module: a part `reveal` lists, or without a list, one the module's
  /// output marks. An output that says nothing of what a hover reveals,
  /// with no `reveal` of its own (`outputRevealsIcon` is nil) and no
  /// segment marked, has its text hidden.
  func hides(_ part: RevealPart, outputRevealsIcon: Bool?, segments: [ValueSegment]) -> Bool {
    guard type == "reveal" else { return false }
    if let reveal { return reveal.contains(part) }
    switch part {
    case .icon: return outputRevealsIcon == true
    case .text: return outputRevealsIcon == nil && !segments.contains(where: \.reveal)
    }
  }
}

/// The side of a module its icon is on, its text taking the other.
enum IconPosition: String, Sendable {
  case left
  case right
}

/// The part of a module that sits on the bar's centre on a screen without
/// a notch.
enum ModuleAnchor: String, Sendable {
  case icon
}

/// How a module enters and leaves the bar as it shows and hides.
enum ModuleTransition: String, Sendable {
  /// Slides to and from the edge its group is anchored to: the notch
  /// beside it, or the screen's edge.
  case slide
  /// Appears and disappears at once.
  case none
}

/// Makes a module beside the notch give way to the others on its side:
/// while one of them shows, the module waits behind the notch.
struct TuckConfig: Equatable, Sendable {
  /// How long a module arriving stays out before it slides behind the
  /// notch, when `peek` isn't set.
  static let defaultPeek: TimeInterval = 5

  /// The seconds the module stays out when it arrives while another shows,
  /// or 0 to go behind the notch at once.
  var peek: TimeInterval = TuckConfig.defaultPeek
}

struct ClickConfig {
  let type: String
  let viewTree: ViewNode?

  init(type: String, viewTree: ViewNode? = nil) {
    self.type = type
    self.viewTree = viewTree
  }
}

struct MaskConfig {
  let index: Int?
  let name: String?

  init(index: Int) {
    self.index = index
    self.name = nil
  }

  init(name: String) {
    self.index = nil
    self.name = name
  }
}

// MARK: - Placement Spec

/// Represents a placement specification from config.
/// Can be a single value ("left", "right", "notchleft", "notchright",
/// "center") or an or-wise pair of a placement beside the notch and one for
/// a screen without a notch ("right|notchright", "notchleft|center").
struct PlacementSpec: Equatable, Sendable {
  let raw: String

  /// Resolve the effective placement for a given screen.
  /// Returns nil if the module should be hidden on this screen.
  ///
  /// A screen without a notch has the placements beside one too: they meet
  /// at the bar's centre, around the modules at "center", and hold the
  /// modules whose pair names "center" for such a screen.
  func resolve(hasNotch: Bool) -> String? {
    let parts = raw.split(separator: "|").map(String.init)
    if parts.count == 2 {
      let notchPart = parts.first { $0 == "notchleft" || $0 == "notchright" }
      let normalPart = parts.first { $0 == "left" || $0 == "right" || $0 == "center" }
      if hasNotch {
        return notchPart ?? (normalPart == "center" ? nil : normalPart)
      } else {
        return normalPart == "center" ? notchPart ?? normalPart : normalPart
      }
    }
    // Single value
    if raw == "notchleft" || raw == "notchright" {
      return hasNotch ? raw : nil
    }
    if raw == "center" {
      return hasNotch ? nil : raw
    }
    return raw
  }

  /// Whether this spec belongs to the right side for mergeModules ordering.
  var isRightSide: Bool {
    raw.contains("right")
  }
}

protocol ModuleConfigurationFactory {
  func configuration(from yaml: Yaml, configDir: String?, theme: ThemeConfig?) throws
    -> ModuleConfiguration
  func defaultConfiguration() -> ModuleConfiguration?
}

extension ModuleConfigurationFactory {
  func defaultConfiguration() -> ModuleConfiguration? { nil }
}

/// Registry of module type names to their configuration factories.
/// Immutable after initialization; concurrency-safe by construction.
nonisolated(unsafe) let moduleFactories: [String: ModuleConfigurationFactory] = [
  "text": TextConfigFactory(),
  "clock": ClockConfigFactory(),
  "power": PowerConfigFactory(),
  "command": CommandConfigFactory(),
  "workspace": WorkspaceConfigFactory(),
  "volume": VolumeConfigFactory(),
  "wifi": WiFiConfigFactory(),
  "bluetooth": BluetoothConfigFactory(),
  "icon": IconConfigFactory(),
  "drawer": DrawerConfigFactory(),
  "focus": FocusConfigFactory(),
  "waveform": WaveformConfigFactory(),
]

// MARK: - Module Config Builder

struct ModuleConfigBuilder {
  private var name: String = ""
  private var placement: PlacementSpec = PlacementSpec(raw: "")
  private var type: String = ""
  private var icon: String? = nil
  private var textFont: FontConfig? = nil
  private var iconFont: FontConfig? = nil
  private var style: StyleConfig? = nil
  private var config: ModuleConfiguration?
  private var interaction: InteractionConfig? = nil
  private var mask: MaskConfig? = nil
  private var displays: DisplaysConfig? = nil
  private var transition: ModuleTransition? = nil
  private var tuck: TuckConfig? = nil
  private var iconPosition: IconPosition? = nil
  private var anchor: ModuleAnchor? = nil
  private var configFactory: ModuleConfigurationFactory?

  mutating func setName(_ name: String) { self.name = name }
  mutating func setPlacement(_ placement: String) { self.placement = PlacementSpec(raw: placement) }
  mutating func setType(_ type: String) { self.type = type }
  mutating func setIcon(_ icon: String) { self.icon = icon }
  mutating func setTextFont(_ textFont: FontConfig) { self.textFont = textFont }
  mutating func setIconFont(_ iconFont: FontConfig) { self.iconFont = iconFont }
  mutating func setStyle(_ style: StyleConfig) { self.style = style }
  mutating func setInteraction(_ interaction: InteractionConfig) { self.interaction = interaction }
  mutating func setMask(_ mask: MaskConfig) { self.mask = mask }
  mutating func setDisplays(_ displays: DisplaysConfig) { self.displays = displays }
  mutating func setTransition(_ transition: ModuleTransition) { self.transition = transition }
  mutating func setTuck(_ tuck: TuckConfig) { self.tuck = tuck }
  mutating func setIconPosition(_ position: IconPosition) { self.iconPosition = position }
  mutating func setAnchor(_ anchor: ModuleAnchor) { self.anchor = anchor }
  mutating func setConfigFactory(_ factory: ModuleConfigurationFactory) {
    self.configFactory = factory
  }

  mutating func buildConfiguration(
    from yaml: Yaml?, configDir: String? = nil, theme: ThemeConfig? = nil
  ) throws {
    guard let factory = self.configFactory else {
      throw BuilderError.missingConfigurationFactory
    }
    if let yaml = yaml {
      self.config = try factory.configuration(from: yaml, configDir: configDir, theme: theme)
    } else {
      self.config = factory.defaultConfiguration()
    }
    // Inject the module-level icon into workspace configs so it can serve
    // as the default indicator icon when config.icons doesn't cover a space.
    if let ws = self.config as? WorkspaceConfig {
      ws.moduleIcon = self.icon
    }
    // Commands give the plugins they run their module's name.
    if var command = self.config as? CommandConfig {
      command.moduleName = name
      self.config = command
    }
  }

  func build() throws -> ModuleConfig {
    guard let config = self.config else {
      throw BuilderError.missingConfiguration
    }
    var module = ModuleConfig(
      name: name, placement: placement, type: type, icon: icon, textFont: textFont,
      iconFont: iconFont, style: style, config: config, interaction: interaction, mask: mask,
      displays: displays)
    module.transition = transition
    module.tuck = tuck
    module.iconPosition = iconPosition
    module.anchor = anchor
    return module
  }
}

enum BuilderError: Error {
  case missingConfigurationFactory
  case missingConfiguration
}

// MARK: - Module Config

struct ModuleConfig {
  let name: String
  let placement: PlacementSpec
  let type: String
  let icon: String?
  let textFont: FontConfig?
  let iconFont: FontConfig?
  let style: StyleConfig?
  let config: ModuleConfiguration?
  let interaction: InteractionConfig?
  let mask: MaskConfig?
  var displays: DisplaysConfig?
  /// How the module enters and leaves the bar, or nil to slide beside the
  /// notch and appear at once elsewhere.
  var transition: ModuleTransition?

  /// How the module gives way to the others on its side of the notch, or
  /// nil for a module that keeps its place.
  var tuck: TuckConfig?

  /// The side of the module its icon is on, or nil for the left, and the
  /// right for a module that reveals on hover left of the notch.
  var iconPosition: IconPosition?

  /// The part of the module the bar's centre passes through on a screen
  /// without a notch, for a module whose placement there is around it.
  var anchor: ModuleAnchor?

  /// Whether the icon comes after the text at `placement`, one of those
  /// a module resolves to. Left of the notch, a module that reveals on
  /// hover keeps its icon beside the notch as the rest slides out.
  func iconTrails(at placement: String) -> Bool {
    let revealsBesideNotch = interaction?.hover?.type == "reveal" && placement == "notchleft"
    return (iconPosition ?? (revealsBesideNotch ? .right : .left)) == .right
  }

  /// Whether the module takes part in sharing its side of the notch: every
  /// module but a drawer's and one over a menu bar item.
  var sharesNotch: Bool {
    mask == nil && type != "drawer"
  }

  /// Whether the module slides in and out as it shows and hides at
  /// `placement`, one of those a module resolves to.
  func slides(at placement: String) -> Bool {
    (transition ?? (placement.hasPrefix("notch") ? .slide : ModuleTransition.none)) == .slide
  }

  /// Whether the module slides in and out at any placement it may take.
  var slidesSomewhere: Bool {
    placement.raw.split(separator: "|").contains { slides(at: String($0)) }
  }

  /// Whether clicks pass through to whatever is beneath the module. A masked
  /// module passes them through unless its config sets a click type.
  var isPassthrough: Bool {
    interaction?.click?.type == "passthrough"
  }

  init(
    name: String, placement: PlacementSpec, type: String, icon: String? = nil,
    textFont: FontConfig? = nil,
    iconFont: FontConfig? = nil, style: StyleConfig? = nil, config: ModuleConfiguration? = nil,
    interaction: InteractionConfig? = nil, mask: MaskConfig? = nil, displays: DisplaysConfig? = nil
  ) {
    self.name = name
    self.placement = placement
    self.type = type
    self.icon = icon
    self.textFont = textFont
    self.iconFont = iconFont
    self.style = style
    self.config = config
    self.interaction = interaction
    self.mask = mask
    self.displays = displays
  }
}

// MARK: - Command Utility

/// Whether `command` is opened as a URL rather than run: a scheme (a
/// letter, then letters, digits, `+`, `-` or `.`) followed by `:`, and no
/// spaces.
func isURLCommand(_ command: String) -> Bool {
  guard let colon = command.firstIndex(of: ":"), colon > command.startIndex else { return false }
  let scheme = command[..<colon]
  return scheme.first!.isASCII && scheme.first!.isLetter
    && scheme.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "+-.".contains($0)) }
    && !command.contains(" ")
}

/// `value` for inside a shell's single quotes: each `'` closes them, adds
/// an escaped quote and opens them again. The match is literal, as a quote
/// with a combining mark after it is still a quote to the shell.
func shellSingleQuoteEscaped(_ value: String) -> String {
  value.replacingOccurrences(of: "'", with: #"'\''"#, options: .literal)
}

/// Run a command asynchronously (fire-and-forget).
/// If the command matches a URL scheme (e.g. "calshow:123", "https://..."),
/// it is opened via NSWorkspace. Otherwise it is executed as a shell command,
/// with `environment` added to kantan's own.
func runCommand(_ command: String, environment: [String: String] = [:]) {
  let trimmed = command.trimmingCharacters(in: .whitespaces)
  if isURLCommand(trimmed), let url = URL(string: trimmed) {
    DispatchQueue.main.async {
      NSWorkspace.shared.open(url)
    }
    return
  }
  DispatchQueue.global(qos: .userInitiated).async {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/sh")
    process.arguments = ["-c", command]
    process.environment = ProcessInfo.processInfo.environment.merging(environment) { $1 }
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try? process.run()
  }
}

/// Compute an icon array index from a 0–100 level value.
/// Clamps to valid array bounds.
func iconForLevel(_ level: Int, icons: [String]) -> String {
  guard !icons.isEmpty else { return "" }
  let step = max(1, 100 / icons.count)
  let index = min(level / step, icons.count - 1)
  return icons[index]
}

/// How long a window manager's CLI has to answer before it's terminated.
let windowManagerCLITimeout: TimeInterval = 5

/// Run a command synchronously and return its stdout.
/// Returns nil on launch failure or non-zero exit.
func runCommandSync(path: String, arguments: [String], timeout: TimeInterval? = nil) -> Data? {
  let process = Process()
  process.executableURL = URL(fileURLWithPath: path)
  process.arguments = arguments

  let stdoutPipe = Pipe()
  process.standardOutput = stdoutPipe
  process.standardError = FileHandle.nullDevice

  do {
    try process.run()
  } catch {
    return nil
  }

  var timeoutWorkItem: DispatchWorkItem?
  if let timeout = timeout {
    let item = DispatchWorkItem {
      if process.isRunning { process.terminate() }
    }
    DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: item)
    timeoutWorkItem = item
  }

  let data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
  process.waitUntilExit()
  timeoutWorkItem?.cancel()

  guard process.terminationStatus == 0 else { return nil }
  return data
}

/// Splits output arriving in chunks into lines, holding back what follows
/// the last newline until the rest of its line arrives.
struct LineBuffer {
  private var partial = Data()

  /// Appends `output` and takes the lines it completes, without newlines.
  mutating func append(_ output: Data) -> [Data] {
    partial.append(output)
    var lines: [Data] = []
    while let newline = partial.firstIndex(of: UInt8(ascii: "\n")) {
      lines.append(partial[..<newline])
      partial = partial[partial.index(after: newline)...]
    }
    return lines
  }
}

/// Runs a long-lived command that writes a line per event, calling `onEvent`
/// whenever output arrives. The command is resolved at each launch (`nil`
/// while it is unavailable); when it exits or can't be resolved, launching is
/// retried with exponential backoff, and `onEvent` fires after each relaunch
/// so consumers resynchronise with whatever changed while it was down.
///
/// With `accepts`, only the lines it accepts are events. With `coalescing`,
/// events arriving within that interval of the first call `onEvent` once,
/// at the end of it.
final class EventStreamProcess: @unchecked Sendable {
  private let command: @Sendable () -> [String]?
  private let coalescing: TimeInterval
  private let accepts: (@Sendable (Data) -> Bool)?
  private let onEvent: @Sendable () -> Void
  private let lock = NSLock()
  private var process: Process?
  /// Write end of the command's stdin; closing it (explicitly or by kantan
  /// exiting) makes `tetherScript` kill the command.
  private var tether: FileHandle?
  private var stopped = true
  private var failures = 0
  /// The command's output, split into lines while `accepts` reads them.
  private var lines = LineBuffer()
  /// Whether an event is waiting out `coalescing`.
  private var eventPending = false

  /// Runs `"$@"` in the background and kills it once stdin reaches EOF, so
  /// the command never outlives kantan however kantan exits. The shell exits
  /// when the command does, taking the stdin watcher with it.
  static let tetherScript = """
    exec 3<&0
    "$@" </dev/null 3<&- &
    command=$!
    { read -r _ <&3; kill "$command" 2>/dev/null; } &
    watcher=$!
    trap 'kill "$watcher" 2>/dev/null' EXIT
    wait "$command"
    """

  init(
    command: @escaping @Sendable () -> [String]?,
    coalescing: TimeInterval = 0,
    accepts: (@Sendable (Data) -> Bool)? = nil,
    onEvent: @escaping @Sendable () -> Void
  ) {
    self.command = command
    self.coalescing = coalescing
    self.accepts = accepts
    self.onEvent = onEvent
  }

  deinit {
    stop()
  }

  /// Delay before the relaunch following `failures` consecutive exits
  /// without output: 1s doubling to a 16s cap.
  static func restartDelay(afterFailures failures: Int) -> TimeInterval {
    TimeInterval(1 << min(max(failures - 1, 0), 4))
  }

  func start() {
    lock.lock()
    defer { lock.unlock() }
    guard stopped else { return }
    stopped = false
    failures = 0
    launchLocked()
  }

  func stop() {
    lock.lock()
    stopped = true
    process = nil
    let tether = self.tether
    self.tether = nil
    lock.unlock()
    try? tether?.close()
  }

  private func launchLocked() {
    guard let command = command(), !command.isEmpty else {
      scheduleRelaunchLocked()
      return
    }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/sh")
    process.arguments = ["-c", Self.tetherScript, "sh"] + command
    let stdin = Pipe()
    let stdout = Pipe()
    process.standardInput = stdin
    process.standardOutput = stdout
    process.standardError = FileHandle.nullDevice
    lines = LineBuffer()

    stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
      let output = handle.availableData
      guard !output.isEmpty else {
        handle.readabilityHandler = nil
        return
      }
      self?.received(output)
    }
    process.terminationHandler = { [weak self] exited in
      self?.exited(exited)
    }

    do {
      try process.run()
      self.process = process
      self.tether = stdin.fileHandleForWriting
    } catch {
      stdout.fileHandleForReading.readabilityHandler = nil
      scheduleRelaunchLocked()
    }
  }

  private func received(_ output: Data) {
    lock.lock()
    guard !stopped else {
      lock.unlock()
      return
    }
    failures = 0
    let complete = accepts == nil ? [] : lines.append(output)
    lock.unlock()
    if let accepts, !complete.contains(where: accepts) { return }
    deliver()
  }

  private func deliver() {
    guard coalescing > 0 else { return onEvent() }
    lock.lock()
    let alreadyPending = eventPending
    eventPending = true
    lock.unlock()
    guard !alreadyPending else { return }
    DispatchQueue.global().asyncAfter(deadline: .now() + coalescing) { [weak self] in
      guard let self else { return }
      lock.lock()
      eventPending = false
      let live = !stopped
      lock.unlock()
      if live { onEvent() }
    }
  }

  private func exited(_ exited: Process) {
    lock.lock()
    defer { lock.unlock() }
    guard !stopped, process === exited else { return }
    process = nil
    try? tether?.close()
    tether = nil
    scheduleRelaunchLocked()
  }

  private func scheduleRelaunchLocked() {
    failures += 1
    let delay = Self.restartDelay(afterFailures: failures)
    DispatchQueue.global().asyncAfter(deadline: .now() + delay) { [weak self] in
      self?.relaunch()
    }
  }

  private func relaunch() {
    lock.lock()
    guard !stopped, process == nil else {
      lock.unlock()
      return
    }
    launchLocked()
    let launched = process != nil
    lock.unlock()
    if launched { onEvent() }
  }
}
