import Foundation

// MARK: - Workspace Segment Data

struct WorkspaceSegment: Sendable {
  let label: String
  let isActive: Bool
  /// When the label came from a named icon (e.g. "point-filled"),
  /// this holds the font family name to render it with.
  let fontNameOverride: String?
  /// Dynamic scale factor for the icon glyph (1.0 = no adjustment).
  let scaleFactor: CGFloat
  /// Per-segment colour override from rainbow config (raw theme/hex string).
  let colorOverride: String?

  init(
    label: String, isActive: Bool, fontNameOverride: String? = nil, scaleFactor: CGFloat = 1.0,
    colorOverride: String? = nil
  ) {
    self.label = label
    self.isActive = isActive
    self.fontNameOverride = fontNameOverride
    self.scaleFactor = scaleFactor
    self.colorOverride = colorOverride
  }
}

// Module-level cache for structured workspace data.
// The drawing pipeline reads this to render per-space indicators.
nonisolated(unsafe) private var cachedSegments: [WorkspaceSegment] = []
private let segmentsLock = NSLock()

// Memo for `shuffledRainbow`. The output is a pure function of
// `(colors, spaceCount)` so a successful lookup avoids re-shuffling
// and re-cycling on every `getValue()`.
struct RainbowKey: Hashable {
  let colors: [String]
  let spaceCount: Int
}
nonisolated(unsafe) private var rainbowCache: [RainbowKey: [String]] = [:]
private let rainbowCacheLock = NSLock()

func getWorkspaceSegments() -> [WorkspaceSegment] {
  segmentsLock.lock()
  defer { segmentsLock.unlock() }
  return cachedSegments
}

private func setWorkspaceSegments(_ segments: [WorkspaceSegment]) {
  segmentsLock.lock()
  defer { segmentsLock.unlock() }
  cachedSegments = segments
}

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

// MARK: - Providers

/// A workspace as reported by a provider. `index` positions it for
/// `config.icons` and rainbow colours.
struct Workspace: Equatable, Sendable {
  let index: Int
  let label: String
  let isActive: Bool
}

/// A source of workspaces for the workspace module, selected by `config.type`.
protocol WorkspaceProvider: Sendable {
  /// The current workspaces in display order. Called off the main thread.
  func workspaces() -> [Workspace]
  /// Begins calling `onChange` when workspaces change. Providers refreshed
  /// through EventObserver or `kantan trigger` don't observe anything.
  func startObserving(onChange: @escaping @Sendable () -> Void)
  func stopObserving()
}

extension WorkspaceProvider {
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
  /// Module-level icon (from top-level `icon:` key), used as fallback
  /// when `config.icons` doesn't cover a space.
  nonisolated(unsafe) var moduleIcon: String?

  var redrawInterval: TimeInterval { noPoll }

  init(yaml: Yaml?) {
    self.provider = Self.provider(named: yaml?["type"].string)
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
  }

  func encode(to encoder: Encoder) throws {}

  static func provider(named type: String?) -> any WorkspaceProvider {
    switch type {
    case "aerospace": AerospaceWorkspaces()
    case "rift": RiftWorkspaces()
    default: NativeWorkspaces()
    }
  }

  // MARK: - EventDrivenModule

  func startObserving(onChange: @escaping @Sendable () -> Void) {
    provider.startObserving(onChange: onChange)
  }

  func stopObserving() {
    provider.stopObserving()
  }

  func getValue(completion: @escaping @Sendable (String) -> Void) {
    let provider = self.provider
    let iconList = self.icons
    let modIcon = self.moduleIcon
    let rb = self.rainbow

    DispatchQueue.global(qos: .userInitiated).async {
      let spaces = provider.workspaces()

      // Pre-compute rainbow colour assignments if enabled.
      let rainbowColors: [String]?
      if rb.enabled, !rb.colors.isEmpty {
        rainbowColors =
          rb.random
          ? Self.shuffledRainbow(rb.colors, spaceCount: spaces.count)
          : rb.colors
      } else {
        rainbowColors = nil
      }

      let segments = spaces.map { space -> WorkspaceSegment in
        let rawIcon: String
        if space.index < iconList.count {
          rawIcon = iconList[space.index]
        } else if let mi = modIcon, !mi.isEmpty {
          rawIcon = mi
        } else {
          rawIcon = space.label
        }
        let resolved = resolveIconName(rawIcon)
        let colorOvr = rainbowColors.map { $0[space.index % $0.count] }
        return WorkspaceSegment(
          label: resolved.glyph, isActive: space.isActive,
          fontNameOverride: resolved.fontNameOverride,
          scaleFactor: resolved.scaleFactor,
          colorOverride: colorOvr)
      }

      setWorkspaceSegments(segments)

      // Return a value string that changes when workspace state changes,
      // so the drawing pipeline detects the update and redraws.
      let value = segments.map { ($0.isActive ? ">" : "") + $0.label }
        .joined(separator: " ")
      completion(value)
    }
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
