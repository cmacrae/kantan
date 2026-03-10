import Foundation
import Yaml

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
}

extension ModuleConfiguration {
    func getTemplateVariables() -> [String: String] {
        return [:]
    }
    func isActive() -> Bool {
        return true
    }
    func shouldDisplay() -> Bool {
        return true
    }
    func handleToggle() {}
    func getMenuDescriptors() -> [MenuItemDescriptor]? { return nil }
}

// MARK: - Event-Driven Module

/// Protocol for modules that push updates via system events rather than
/// relying on timer-based polling. Conforming modules create their own
/// observers (IOKit, CoreAudio, CoreWLAN, etc.) and call the provided
/// onChange callback whenever state changes.
///
/// `ModuleViewModel` checks for this conformance and skips creating a
/// polling timer when the module provides event-driven updates.
protocol EventDrivenModule: AnyObject {
    /// Start observing system events. Call `onChange` whenever the module's
    /// value, icon, or state has changed. The callback dispatches to the
    /// main actor — implementations should call it from any thread.
    func startObserving(onChange: @escaping @Sendable () -> Void)

    /// Stop observing system events and release resources.
    func stopObserving()
}

// MARK: - Interaction Config

struct InteractionConfig: Codable {
    let hover: HoverConfig?
    let click: ClickConfig?
}

struct HoverConfig: Codable {
    let type: String  // "tooltip"
    let content: String  // template string e.g. "{level}% — {state}"
}

struct ClickConfig: Codable {
    let type: String  // "popup", "menu", "dynamic-menu", "toggle", "passthrough"
    let popup: String?  // built-in popup name
    let items: [MenuItemConfig]?
}

struct MenuItemConfig: Codable {
    let label: String?
    let command: String?
    let separator: Bool?
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
    func configuration(from yaml: Yaml) throws -> ModuleConfiguration
    func defaultConfiguration() -> ModuleConfiguration?
}

extension ModuleConfigurationFactory {
    func defaultConfiguration() -> ModuleConfiguration? {
        return nil
    }
}

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
    private var lastDrawnValue: String?
    private var lastDrawnIcon: String?
    private var offset: CGFloat = 0
    private var configFactory: ModuleConfigurationFactory?

    mutating func setName(_ name: String) -> ModuleConfigBuilder {
        self.name = name
        return self
    }

    mutating func setAlignment(_ alignment: String) -> ModuleConfigBuilder {
        self.alignment = alignment
        return self
    }

    mutating func setType(_ type: String) -> ModuleConfigBuilder {
        self.type = type
        return self
    }

    mutating func setIcon(_ icon: String) -> ModuleConfigBuilder {
        self.icon = icon
        return self
    }

    mutating func setTextFont(_ textFont: FontConfig) -> ModuleConfigBuilder {
        self.textFont = textFont
        return self
    }

    mutating func setIconFont(_ iconFont: FontConfig) -> ModuleConfigBuilder {
        self.iconFont = iconFont
        return self
    }

    mutating func setStyle(_ style: StyleConfig) -> ModuleConfigBuilder {
        self.style = style
        return self
    }

    mutating func setLastDrawnValue(_ lastDrawnValue: String) -> ModuleConfigBuilder {
        self.lastDrawnValue = lastDrawnValue
        return self
    }

    mutating func setLastDrawnIcon(_ lastDrawnIcon: String) -> ModuleConfigBuilder {
        self.lastDrawnIcon = lastDrawnIcon
        return self
    }

    mutating func setOffset(_ offset: CGFloat) -> ModuleConfigBuilder {
        self.offset = offset
        return self
    }

    mutating func setInteraction(_ interaction: InteractionConfig) -> ModuleConfigBuilder {
        self.interaction = interaction
        return self
    }

    mutating func setMask(_ mask: MaskConfig) -> ModuleConfigBuilder {
        self.mask = mask
        return self
    }

    mutating func setDisplays(_ displays: DisplaysConfig) -> ModuleConfigBuilder {
        self.displays = displays
        return self
    }

    mutating func setConfigFactory(_ factory: ModuleConfigurationFactory) -> ModuleConfigBuilder {
        self.configFactory = factory
        return self
    }

    mutating func buildConfiguration(from yaml: Yaml?) throws -> ModuleConfigBuilder {
        guard let factory = self.configFactory else {
            throw BuilderError.missingConfigurationFactory
        }
        if let yaml = yaml {
            self.config = try factory.configuration(from: yaml)
        } else {
            self.config = factory.defaultConfiguration()
        }
        return self
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
    case unsupportedModuleType
}


struct ModuleConfig: Codable {
    let name: String
    let alignment: String
    let type: String
    let icon: String?
    let textFont: FontConfig?
    let iconFont: FontConfig?
    let style: StyleConfig?
    var config: ModuleConfiguration?
    var interaction: InteractionConfig?
    var mask: MaskConfig?
    var displays: DisplaysConfig?
    var lastDrawnValue: String?
    var lastDrawnIcon: String?
    var offset: CGFloat = 0
    var fgOverride: String?
    var bgOverride: String?

    private enum CodingKeys: String, CodingKey {
        case name, type, alignment, icon, textFont, iconFont, style, config, lastDrawnValue, lastDrawnIcon, interaction, mask
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

        let factories: [String: ModuleConfigurationFactory] = [
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
          "icon": IconConfigFactory()
        ]

        if let configYaml = configYaml, let factory = factories[type] {
            config = try factory.configuration(from: configYaml)
        } else {
            config = nil
        }

        // Per-module style is parsed from YAML in loadConfig, not decoded here
        style = nil

        interaction = try container.decodeIfPresent(InteractionConfig.self, forKey: .interaction)
        mask = try container.decodeIfPresent(MaskConfig.self, forKey: .mask)
        lastDrawnValue = try container.decodeIfPresent(String.self, forKey: .lastDrawnValue)
        lastDrawnIcon = try container.decodeIfPresent(String.self, forKey: .lastDrawnIcon)
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

        try container.encodeIfPresent(lastDrawnValue, forKey: .lastDrawnValue)
        try container.encodeIfPresent(lastDrawnIcon, forKey: .lastDrawnIcon)
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
