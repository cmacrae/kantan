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
    func getMenuDescriptors() -> [MenuItemDescriptor]?
    func getDynamicStyle() -> DynamicStyleOverride?
}

extension ModuleConfiguration {
    func getIcon() -> String { "" }
    func getTemplateVariables() -> [String: String] { [:] }
    func isActive() -> Bool { true }
    func shouldDisplay() -> Bool { true }
    func handleToggle() {}
    func getMenuDescriptors() -> [MenuItemDescriptor]? { nil }
    func getDynamicStyle() -> DynamicStyleOverride? { nil }
}

// MARK: - Event-Driven Module

/// Modules that push updates via system events rather than timer-based
/// polling. Conforming modules create their own observers (IOKit,
/// CoreAudio, CoreWLAN, etc.) and call the provided onChange callback
/// whenever state changes.
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
    let content: String
}

struct ClickConfig: Codable {
    let type: String
    let popup: String?
    let items: [MenuItemConfig]?
    let popupConfig: PopupConfig?
}

struct PopupConfig: Codable, Sendable {
    let title: String?
    let width: Int?
    let rows: [PopupRowConfig]
}

struct PopupRowConfig: Codable, Sendable {
    let type: String
    let content: String?
    let icon: String?
    let label: String?
    let value: String?
    let command: String?
    let style: String?
}

struct MenuItemConfig: Codable {
    let label: String?
    let command: String?
    let separator: Bool?
    let icon: String?
    let header: String?
    let dynamic: Bool?
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
    "reminders": RemindersConfigFactory(),
    "workspace": WorkspaceConfigFactory(),
    "volume": VolumeConfigFactory(),
    "wifi": WiFiConfigFactory(),
    "bluetooth": BluetoothConfigFactory(),
    "caffeinate": CaffeinateConfigFactory(),
    "icon": IconConfigFactory(),
]

// MARK: - Module Config Builder

struct ModuleConfigBuilder {
    private var name: String = ""
    private var alignment: String = ""
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
    mutating func setAlignment(_ alignment: String) { self.alignment = alignment }
    mutating func setType(_ type: String) { self.type = type }
    mutating func setIcon(_ icon: String) { self.icon = icon }
    mutating func setTextFont(_ textFont: FontConfig) { self.textFont = textFont }
    mutating func setIconFont(_ iconFont: FontConfig) { self.iconFont = iconFont }
    mutating func setStyle(_ style: StyleConfig) { self.style = style }
    mutating func setInteraction(_ interaction: InteractionConfig) { self.interaction = interaction }
    mutating func setMask(_ mask: MaskConfig) { self.mask = mask }
    mutating func setDisplays(_ displays: DisplaysConfig) { self.displays = displays }
    mutating func setConfigFactory(_ factory: ModuleConfigurationFactory) { self.configFactory = factory }

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
        return ModuleConfig(name: name, alignment: alignment, type: type, icon: icon, textFont: textFont, iconFont: iconFont, style: style, config: config, interaction: interaction, mask: mask, displays: displays)
    }
}

enum BuilderError: Error {
    case missingConfigurationFactory
    case missingConfiguration
}

// MARK: - Module Config

struct ModuleConfig: Codable {
    let name: String
    let alignment: String
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
        case name, type, alignment, icon, textFont, iconFont, style, config, interaction, mask
    }

    init(name: String, alignment: String, type: String, icon: String? = nil, textFont: FontConfig? = nil, iconFont: FontConfig? = nil, style: StyleConfig? = nil, config: ModuleConfiguration? = nil, interaction: InteractionConfig? = nil, mask: MaskConfig? = nil, displays: DisplaysConfig? = nil) {
        self.name = name
        self.alignment = alignment
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
        alignment = try container.decode(String.self, forKey: .alignment)
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
        try container.encode(alignment, forKey: .alignment)
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

// MARK: - Shell Command Utility

/// Run a shell command asynchronously (fire-and-forget).
func runShellCommand(_ command: String) {
    DispatchQueue.global(qos: .userInitiated).async {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
    }
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
