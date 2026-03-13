import AppKit
import Foundation
import Yaml

/// Dynamic style overrides returned by modules (e.g. command JSON output).
/// Takes priority over static YAML style config when present.
struct DynamicStyleOverride: Sendable {
  let fg: String?
  let bg: String?
  let iconFg: String?
  let textFg: String?
}

protocol ModuleConfiguration: Codable, Sendable {
  var type: String { get }
  var redrawInterval: TimeInterval { get }
  func getValue(completion: @escaping @Sendable (String) -> Void)
  func getIcon() -> String
  func getTemplateVariables() -> [String: String]
  func isActive() -> Bool
  func shouldDisplay() -> Bool
  func handleToggle()
  func getViewTree() -> ViewNode?
  func getDynamicStyle() -> DynamicStyleOverride?
  func getWatchCommand() -> String?
  func getBackgroundIcon() -> String?
}

extension ModuleConfiguration {
  func getIcon() -> String { "" }
  func getTemplateVariables() -> [String: String] { [:] }
  func isActive() -> Bool { true }
  func shouldDisplay() -> Bool { true }
  func handleToggle() {}
  func getViewTree() -> ViewNode? { nil }
  func getDynamicStyle() -> DynamicStyleOverride? { nil }
  func getWatchCommand() -> String? { nil }
  func getBackgroundIcon() -> String? { nil }
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

struct InteractionConfig: Codable {
  let hover: HoverConfig?
  let click: ClickConfig?
}

struct HoverConfig: Codable {
  let type: String
  let content: String?
  let viewTree: ViewNode?

  private enum CodingKeys: String, CodingKey {
    case type, content
  }

  init(type: String, content: String? = nil, viewTree: ViewNode? = nil) {
    self.type = type
    self.content = content
    self.viewTree = viewTree
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.type = try container.decode(String.self, forKey: .type)
    self.content = try container.decodeIfPresent(String.self, forKey: .content)
    self.viewTree = nil
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(type, forKey: .type)
    try container.encodeIfPresent(content, forKey: .content)
  }
}

struct ClickConfig: Codable {
  let type: String
  let viewTree: ViewNode?

  private enum CodingKeys: String, CodingKey {
    case type
  }

  init(type: String, viewTree: ViewNode? = nil) {
    self.type = type
    self.viewTree = viewTree
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.type = try container.decode(String.self, forKey: .type)
    self.viewTree = nil
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(type, forKey: .type)
  }
}

struct MaskConfig: Codable {
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
/// Can be a single value ("left", "right", "notchleft", "notchright")
/// or an or-wise pair ("right|notchright", "left|notchleft").
struct PlacementSpec: Equatable, Sendable {
  let raw: String

  /// Resolve the effective placement for a given screen.
  /// Returns nil if the module should be hidden on this screen.
  func resolve(hasNotch: Bool) -> String? {
    let parts = raw.split(separator: "|").map(String.init)
    if parts.count == 2 {
      let notchPart = parts.first { $0 == "notchleft" || $0 == "notchright" }
      let normalPart = parts.first { $0 == "left" || $0 == "right" }
      if hasNotch {
        return notchPart ?? normalPart
      } else {
        return normalPart
      }
    }
    // Single value
    if raw == "notchleft" || raw == "notchright" {
      return hasNotch ? raw : nil
    }
    return raw
  }

  /// Whether this spec belongs to the right side for mergeModules ordering.
  var isRightSide: Bool {
    raw.contains("right")
  }
}

extension PlacementSpec: Codable {
  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    self.raw = try container.decode(String.self)
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(raw)
  }
}

protocol ModuleConfigurationFactory {
  func configuration(from yaml: Yaml, configDir: String?) throws -> ModuleConfiguration
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
  mutating func setConfigFactory(_ factory: ModuleConfigurationFactory) {
    self.configFactory = factory
  }

  mutating func buildConfiguration(from yaml: Yaml?, configDir: String? = nil) throws {
    guard let factory = self.configFactory else {
      throw BuilderError.missingConfigurationFactory
    }
    if let yaml = yaml {
      self.config = try factory.configuration(from: yaml, configDir: configDir)
    } else {
      self.config = factory.defaultConfiguration()
    }
  }

  func build() throws -> ModuleConfig {
    guard let config = self.config else {
      throw BuilderError.missingConfiguration
    }
    return ModuleConfig(
      name: name, placement: placement, type: type, icon: icon, textFont: textFont,
      iconFont: iconFont, style: style, config: config, interaction: interaction, mask: mask,
      displays: displays)
  }
}

enum BuilderError: Error {
  case missingConfigurationFactory
  case missingConfiguration
}

// MARK: - Module Config

struct ModuleConfig: Codable {
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

  var isPassthrough: Bool {
    mask != nil || interaction?.click?.type == "passthrough"
  }

  private enum CodingKeys: String, CodingKey {
    case name, type, placement, icon, textFont, iconFont, style, config, interaction, mask
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

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    name = try container.decode(String.self, forKey: .name)
    placement = try container.decode(PlacementSpec.self, forKey: .placement)
    type = try container.decode(String.self, forKey: .type)
    icon = try container.decodeIfPresent(String.self, forKey: .icon)
    textFont = try container.decodeIfPresent(FontConfig.self, forKey: .textFont)
    iconFont = try container.decodeIfPresent(FontConfig.self, forKey: .iconFont)

    let configDict = try container.decodeIfPresent(ConfigDictionary.self, forKey: .config)?.values
    let configYaml = configDict.map(ModuleConfig.yaml(from:))

    if let configYaml = configYaml, let factory = moduleFactories[type] {
      config = try factory.configuration(from: configYaml, configDir: nil)
    } else {
      config = nil
    }

    style = nil
    interaction = try container.decodeIfPresent(InteractionConfig.self, forKey: .interaction)
    mask = try container.decodeIfPresent(MaskConfig.self, forKey: .mask)
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(name, forKey: .name)
    try container.encode(placement.raw, forKey: .placement)
    try container.encode(type, forKey: .type)
    try container.encodeIfPresent(icon, forKey: .icon)
    try container.encodeIfPresent(textFont, forKey: .textFont)
    try container.encodeIfPresent(iconFont, forKey: .iconFont)
    try container.encodeIfPresent(mask, forKey: .mask)
  }

  static func yaml(from dictionary: [String: Any]) -> Yaml {
    var yamlDict: [Yaml: Yaml] = [:]
    for (key, value) in dictionary {
      if let stringValue = value as? String {
        yamlDict[Yaml.string(key)] = Yaml.string(stringValue)
      }
    }
    return Yaml.dictionary(yamlDict)
  }
}

struct ConfigDictionary: Decodable {
  var values: [String: Any] = [:]

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if let decodedDictionary = try? container.decode([String: String].self) {
      for (key, value) in decodedDictionary {
        values[key] = value
      }
    }
  }
}

// MARK: - Command Utility

/// Run a command asynchronously (fire-and-forget).
/// If the command matches a URL scheme (e.g. "calshow:123", "https://..."),
/// it is opened via NSWorkspace. Otherwise it is executed as a shell command.
func runCommand(_ command: String) {
  let trimmed = command.trimmingCharacters(in: .whitespaces)
  // Detect URL scheme: starts with letters followed by ":"
  if let colonRange = trimmed.range(of: ":"),
    trimmed[trimmed.startIndex..<colonRange.lowerBound].allSatisfy({ $0.isLetter }),
    !trimmed.contains(" "),
    let url = URL(string: trimmed)
  {
    DispatchQueue.main.async {
      NSWorkspace.shared.open(url)
    }
    return
  }
  DispatchQueue.global(qos: .userInitiated).async {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/sh")
    process.arguments = ["-c", command]
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
