import Foundation

// MARK: - Workspace Segment Data

struct WorkspaceSegment: Equatable, Sendable {
  /// Identifies the workspace or window the segment shows, across updates.
  let id: String
  let label: String
  let isActive: Bool
  /// When the label came from a named icon (e.g. "point-filled"),
  /// this holds the font family name to render it with.
  let fontNameOverride: String?
  /// Dynamic scale factor for the icon glyph (1.0 = no adjustment).
  let scaleFactor: CGFloat
  /// Per-segment colour override from rainbow config (raw theme/hex string).
  let colorOverride: String?
  /// What clicking the segment switches to, or nil for the active workspace.
  let target: WorkspaceTarget?

  init(
    id: String, label: String, isActive: Bool, fontNameOverride: String? = nil,
    scaleFactor: CGFloat = 1.0, colorOverride: String? = nil, target: WorkspaceTarget? = nil
  ) {
    self.id = id
    self.label = label
    self.isActive = isActive
    self.fontNameOverride = fontNameOverride
    self.scaleFactor = scaleFactor
    self.colorOverride = colorOverride
    self.target = target
  }
}

/// A workspace to switch to or a window to focus, by a segment's click or
/// a scroll over the module.
enum WorkspaceTarget: Equatable, Sendable {
  /// A workspace, by the index and label its provider reported.
  case workspace(index: Int, label: String)
  /// A window of the active workspace's scroll.
  case window(id: String)
}

/// What the workspace module shows: a segment per workspace, or the
/// windows of the active workspace's scroll beside pips for its workspaces.
struct WorkspaceDisplay: Equatable, Sendable {
  var segments: [WorkspaceSegment] = []
  /// Whether `segments` are the windows of the active workspace's scroll.
  var isScroll = false
  /// The workspaces with windows, and the active one, shown beside a
  /// scroll; empty when the active workspace is the only one.
  var pips: [WorkspaceSegment] = []
  /// The active workspace's segment beside a scroll, whose width sets the
  /// narrowest a window takes, so windows are spaced like workspaces.
  var slot: WorkspaceSegment?

  /// Changes whenever the module's width might.
  var summary: String {
    ([slot].compactMap { $0 } + pips + segments)
      .map { ($0.isActive ? ">" : "") + $0.label }.joined(separator: " ")
  }

  /// The segments one page of `max` shows, the page holding the active
  /// segment, and whether segments lie before and after it. With `max`
  /// nil or no fewer than the segments, every segment shows.
  func page(max: Int?) -> (segments: [WorkspaceSegment], before: Bool, after: Bool) {
    guard let max, max > 0, segments.count > max else { return (segments, false, false) }
    let active = segments.firstIndex(where: \.isActive) ?? 0
    let start = active / max * max
    let end = min(start + max, segments.count)
    return (Array(segments[start..<end]), start > 0, end < segments.count)
  }

  /// The target of the segment `steps` along from the active one, stopping
  /// at either end; nil when that is the active segment or none is active.
  func target(steppingBy steps: Int) -> WorkspaceTarget? {
    guard let active = segments.firstIndex(where: \.isActive) else { return nil }
    let index = min(max(active + steps, 0), segments.count - 1)
    return index == active ? nil : segments[index].target
  }
}

// Memo for `shuffledRainbow`. The output is a pure function of
// `(colors, spaceCount)` so a successful lookup avoids re-shuffling
// and re-cycling on every `getValue()`.
struct RainbowKey: Hashable {
  let colors: [String]
  let spaceCount: Int
}
nonisolated(unsafe) private var rainbowCache: [RainbowKey: [String]] = [:]
private let rainbowCacheLock = NSLock()

// MARK: - Factory

struct WorkspaceConfigFactory: ModuleConfigurationFactory {
  func configuration(from yaml: Yaml, configDir: String?, theme: ThemeConfig?) throws
    -> ModuleConfiguration
  {
    return WorkspaceConfig(yaml: yaml)
  }

  func defaultConfiguration() -> ModuleConfiguration? {
    return WorkspaceConfig(yaml: nil)
  }
}

// MARK: - Overflow Config

struct OverflowConfig: Sendable {
  let enabled: Bool
  let max: Int
  let showIcon: Bool
  let iconLeft: String
  let iconRight: String
  let style: StyleConfig?

  static let disabled = OverflowConfig(
    enabled: false, max: 5, showIcon: true, iconLeft: "‹", iconRight: "›", style: nil)
}

// MARK: - Rainbow Config

struct RainbowConfig: Sendable {
  let enabled: Bool
  /// When true (default), colours are assigned in a deterministic random
  /// order that avoids adjacent repeats. When false, colours map index-wise.
  let random: Bool
  let colors: [String]

  static let disabled = RainbowConfig(enabled: false, random: true, colors: [])
}

// MARK: - Scrolling Config

/// Shows the windows of the active workspace's scrolling layout in place
/// of the workspaces, for providers that report one (Rift).
struct ScrollingConfig: Sendable {
  let enabled: Bool
  /// Icon for windows of apps without an entry in `icons`.
  let icon: String
  /// Lowercased app name or bundle identifier → icon.
  let icons: [String: String]
  /// Whether pips beside the scroll show the other workspaces with windows.
  let showsWorkspaces: Bool
  /// Palette windows take a colour from by app, or empty for them to take
  /// their workspace's colour.
  let rainbow: [String]

  static let defaultIcon = "rectangle-vertical-filled"
  static let disabled = ScrollingConfig(
    enabled: false, icon: defaultIcon, icons: [:], showsWorkspaces: true)

  init(
    enabled: Bool, icon: String, icons: [String: String], showsWorkspaces: Bool,
    rainbow: [String] = []
  ) {
    self.enabled = enabled
    self.icon = icon
    self.icons = Dictionary(icons.map { ($0.key.lowercased(), $0.value) }) { first, _ in first }
    self.showsWorkspaces = showsWorkspaces
    self.rainbow = rainbow
  }

  /// A window's rainbow colour, the same for every window of its app, so
  /// it follows the window as the scroll changes.
  func color(for window: ScrollWindow) -> String? {
    guard !rainbow.isEmpty else { return nil }
    let app = (window.bundleIdentifier ?? window.app).lowercased()
    // FNV-1a, which unlike `hashValue` is the same in every run.
    let hash = app.utf8.reduce(UInt64(14_695_981_039_346_656_037)) {
      ($0 ^ UInt64($1)) &* 1_099_511_628_211
    }
    return rainbow[Int(hash % UInt64(rainbow.count))]
  }

  /// The icon for a window: its app's entry by bundle identifier, then by
  /// name, ignoring case, then `icon`.
  func icon(for window: ScrollWindow) -> String {
    [window.bundleIdentifier, window.app].lazy.compactMap { $0 }
      .compactMap { icons[$0.lowercased()] }.first ?? icon
  }
}

// MARK: - Providers

/// A workspace as reported by a provider. `index` positions it for
/// `config.icons` and rainbow colours.
struct Workspace: Equatable, Sendable {
  let index: Int
  let label: String
  let isActive: Bool
  var hasWindows = false
  /// The windows of a scrolling layout in strip order, or nil for any
  /// other layout.
  var scroll: [ScrollWindow]?

  /// Marks the scroll's window `id` as selected, when the scroll holds it.
  mutating func selectWindow(_ id: String) {
    guard let scroll, scroll.contains(where: { $0.id == id }) else { return }
    self.scroll = scroll.map {
      ScrollWindow(
        id: $0.id, app: $0.app, bundleIdentifier: $0.bundleIdentifier, isSelected: $0.id == id)
    }
  }
}

/// A window in a scrolling layout.
struct ScrollWindow: Equatable, Sendable {
  let id: String
  let app: String
  let bundleIdentifier: String?
  let isSelected: Bool
}

/// A source of workspaces for the workspace module, selected by `config.type`.
protocol WorkspaceProvider: Sendable {
  /// The current workspaces in display order. Called off the main thread.
  func workspaces() -> [Workspace]
  /// Whether `activate` can switch workspaces and focus windows.
  var canActivate: Bool { get }
  /// Switches to the workspace or focuses the window `target` names. The
  /// change reaches the module the way the provider's other changes do.
  /// Called off the main thread.
  func activate(_ target: WorkspaceTarget)
  /// Begins calling `onChange` when workspaces change. Providers refreshed
  /// through EventObserver or `kantan trigger` don't observe anything.
  func startObserving(onChange: @escaping @Sendable () -> Void)
  func stopObserving()
}

extension WorkspaceProvider {
  var canActivate: Bool { false }
  func activate(_ target: WorkspaceTarget) {}
  func startObserving(onChange: @escaping @Sendable () -> Void) {}
  func stopObserving() {}
}

// MARK: - Configuration

/// Workspace module. No provider requires polling: native spaces refresh
/// via EventObserver, aerospace via `kantan trigger` and Rift via its own
/// event subscription.
final class WorkspaceConfig: ModuleConfiguration, EventDrivenModule {
  var type: String { "workspace" }

  let provider: any WorkspaceProvider
  let icons: [String]
  let overflow: OverflowConfig
  let rainbow: RainbowConfig
  let scrolling: ScrollingConfig
  /// Module-level icon (from top-level `icon:` key), used as fallback
  /// when `config.icons` doesn't cover a space.
  nonisolated(unsafe) var moduleIcon: String?

  private let displayLock = NSLock()
  nonisolated(unsafe) private var currentDisplay = WorkspaceDisplay()
  /// The last `getValue` started, so a slower earlier one finishing after
  /// it doesn't replace what it read.
  nonisolated(unsafe) private var latestRead: UInt64 = 0

  var redrawInterval: TimeInterval { noPoll }

  /// What the module shows, as of the last `getValue`.
  var display: WorkspaceDisplay {
    displayLock.withLock { currentDisplay }
  }

  /// `provider` replaces the one `type` selects.
  init(yaml: Yaml?, provider: (any WorkspaceProvider)? = nil) {
    self.scrolling = Self.parseScrolling(
      yaml?["scrolling"], palette: yaml?["rainbow"]["colors"].array?.compactMap(\.string) ?? [])
    self.provider =
      provider ?? Self.provider(named: yaml?["type"].string, scrolling: scrolling.enabled)
    self.icons = yaml?["icons"].array?.compactMap { $0.string } ?? []

    if let rbYaml = yaml?["rainbow"].dictionary {
      let enabled = rbYaml["enabled"]?.bool ?? false
      let random = rbYaml["random"]?.bool ?? true
      let colors = rbYaml["colors"]?.array?.compactMap { $0.string } ?? []
      self.rainbow = RainbowConfig(enabled: enabled, random: random, colors: colors)
    } else {
      self.rainbow = .disabled
    }

    if let ofYaml = yaml?["overflow"].dictionary {
      let enabled = ofYaml["enabled"]?.bool ?? false
      let max = ofYaml["max"]?.int ?? 5
      let style = ofYaml["style"].flatMap { parseStyleConfig(from: $0) }

      // icon: false disables indicator, icon: "str" sets both,
      // icon: {left: ..., right: ...} sets individually
      let showIcon: Bool
      let iconLeft: String
      let iconRight: String
      if let iconBool = ofYaml["icon"]?.bool, iconBool == false {
        showIcon = false
        iconLeft = ""
        iconRight = ""
      } else if let iconStr = ofYaml["icon"]?.string {
        showIcon = true
        iconLeft = iconStr
        iconRight = iconStr
      } else if let iconDict = ofYaml["icon"]?.dictionary {
        showIcon = true
        iconLeft = iconDict["left"]?.string ?? "‹"
        iconRight = iconDict["right"]?.string ?? "›"
      } else {
        showIcon = true
        iconLeft = "‹"
        iconRight = "›"
      }

      self.overflow = OverflowConfig(
        enabled: enabled, max: max, showIcon: showIcon, iconLeft: iconLeft, iconRight: iconRight,
        style: style)
    } else {
      self.overflow = .disabled
    }
  }

  init(from decoder: Decoder) throws {
    self.provider = NativeWorkspaces()
    self.icons = []
    self.overflow = .disabled
    self.rainbow = .disabled
    self.scrolling = .disabled
  }

  func encode(to encoder: Encoder) throws {}

  static func provider(named type: String?, scrolling: Bool = false) -> any WorkspaceProvider {
    switch type {
    case "aerospace": AerospaceWorkspaces()
    case "rift": RiftWorkspaces(scrolling: scrolling)
    default: NativeWorkspaces()
    }
  }

  /// `palette` is the module's rainbow colours, which a scroll's rainbow
  /// uses unless it lists its own.
  static func parseScrolling(_ yaml: Yaml?, palette: [String] = []) -> ScrollingConfig {
    guard let scrolling = yaml?.dictionary else { return .disabled }
    let rainbow = scrolling["rainbow"]?.dictionary
    let rainbowColors = rainbow?["colors"]?.array?.compactMap(\.string) ?? palette
    var icons: [String: String] = [:]
    for (key, value) in scrolling["icons"]?.dictionary ?? [:] {
      if let app = key.string, let icon = value.string {
        icons[app] = icon
      }
    }
    return ScrollingConfig(
      enabled: scrolling["enabled"]?.bool ?? false,
      icon: scrolling["icon"]?.string ?? ScrollingConfig.defaultIcon,
      icons: icons,
      showsWorkspaces: scrolling["workspaces"]?.bool ?? true,
      rainbow: rainbow?["enabled"]?.bool == true ? rainbowColors : [])
  }

  // MARK: - EventDrivenModule

  func startObserving(onChange: @escaping @Sendable () -> Void) {
    provider.startObserving(onChange: onChange)
  }

  func stopObserving() {
    provider.stopObserving()
  }

  /// Switches to or focuses `target` off the main thread.
  func activate(_ target: WorkspaceTarget) {
    let provider = self.provider
    DispatchQueue.global(qos: .userInitiated).async {
      provider.activate(target)
    }
  }

  func getValue(completion: @escaping @Sendable (String) -> Void) {
    let provider = self.provider
    let read = displayLock.withLock {
      latestRead &+= 1
      return latestRead
    }

    DispatchQueue.global(qos: .userInitiated).async {
      let display = self.display(of: provider.workspaces())
      self.displayLock.withLock {
        if read == self.latestRead { self.currentDisplay = display }
      }
      // A value that changes with the display, so the module redraws and
      // its panel resizes.
      completion(display.summary)
    }
  }

  /// What to show for `spaces`: the active workspace's scroll while it has
  /// windows and scrolling is enabled, otherwise the workspaces.
  func display(of spaces: [Workspace]) -> WorkspaceDisplay {
    let rainbowColors: [String]?
    if rainbow.enabled, !rainbow.colors.isEmpty {
      rainbowColors =
        rainbow.random
        ? Self.shuffledRainbow(rainbow.colors, spaceCount: spaces.count)
        : rainbow.colors
    } else {
      rainbowColors = nil
    }
    let color = { (space: Workspace) in rainbowColors.map { $0[space.index % $0.count] } }

    let segments = spaces.map { space -> WorkspaceSegment in
      let rawIcon: String
      if space.index < icons.count {
        rawIcon = icons[space.index]
      } else if let mi = moduleIcon, !mi.isEmpty {
        rawIcon = mi
      } else {
        rawIcon = space.label
      }
      let resolved = resolveIconName(rawIcon)
      return WorkspaceSegment(
        id: "workspace-\(space.index)", label: resolved.glyph, isActive: space.isActive,
        fontNameOverride: resolved.fontNameOverride,
        scaleFactor: resolved.scaleFactor,
        colorOverride: color(space),
        target: space.isActive ? nil : .workspace(index: space.index, label: space.label))
    }

    guard scrolling.enabled, let active = spaces.first(where: \.isActive),
      let scroll = active.scroll, !scroll.isEmpty
    else {
      return WorkspaceDisplay(segments: segments)
    }

    let windows = scroll.map { window in
      let resolved = resolveIconName(scrolling.icon(for: window))
      return WorkspaceSegment(
        id: "window-\(window.id)", label: resolved.glyph, isActive: window.isSelected,
        fontNameOverride: resolved.fontNameOverride,
        scaleFactor: resolved.scaleFactor,
        colorOverride: scrolling.color(for: window) ?? color(active),
        target: .window(id: window.id))
    }
    let pips = zip(spaces, segments).filter { $0.0.hasWindows || $0.0.isActive }.map(\.1)
    return WorkspaceDisplay(
      segments: windows, isScroll: true,
      pips: scrolling.showsWorkspaces && pips.count > 1 ? pips : [],
      slot: segments.first(where: \.isActive))
  }

  // MARK: - Rainbow Helpers

  /// Returns a deterministic permutation of `colors` seeded by `spaceCount`,
  /// ensuring no two adjacent entries are the same colour. When the palette
  /// has more entries than spaces, the first `spaceCount` colours of the
  /// shuffled palette are used (all unique). When cycling is needed, a
  /// greedy swap avoids adjacent repeats.
  static func shuffledRainbow(_ colors: [String], spaceCount: Int) -> [String] {
    let key = RainbowKey(colors: colors, spaceCount: spaceCount)
    rainbowCacheLock.lock()
    if let cached = rainbowCache[key] {
      rainbowCacheLock.unlock()
      return cached
    }
    rainbowCacheLock.unlock()

    let result = computeShuffledRainbow(colors, spaceCount: spaceCount)

    rainbowCacheLock.lock()
    rainbowCache[key] = result
    rainbowCacheLock.unlock()
    return result
  }

  private static func computeShuffledRainbow(_ colors: [String], spaceCount: Int) -> [String] {
    guard colors.count > 1 else { return colors }

    // Deterministic Fisher-Yates shuffle seeded by space count.
    var shuffled = colors
    var rng: UInt64 = UInt64(spaceCount)
    for i in stride(from: shuffled.count - 1, through: 1, by: -1) {
      rng = rng &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
      let j = Int((rng >> 33) % UInt64(i + 1))
      shuffled.swapAt(i, j)
    }

    // Build the full assignment list for `spaceCount` entries.
    guard spaceCount > shuffled.count else { return shuffled }

    var result = shuffled
    while result.count < spaceCount {
      var next = result[result.count % shuffled.count]
      // Avoid adjacent repeat: pick the next distinct colour from the palette.
      if next == result.last {
        let startIdx = result.count % shuffled.count
        for offset in 1..<shuffled.count {
          let candidate = shuffled[(startIdx + offset) % shuffled.count]
          if candidate != result.last {
            next = candidate
            break
          }
        }
      }
      result.append(next)
    }
    return result
  }
}
