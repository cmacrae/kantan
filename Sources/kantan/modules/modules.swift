import Foundation
import Yaml

protocol ModuleConfiguration: Codable {
    var type: String { get }
    var redrawInterval: TimeInterval { get }
    func getNewValue() -> String
}

protocol ModuleConfigurationFactory {
    func configuration(from yaml: Yaml) throws -> ModuleConfiguration
}

struct ModuleConfigBuilder {
    private var name: String = ""
    private var alignment: String = ""
    private var type: String = ""
    private var icon: String? = nil
    private var textFont: FontConfig? = nil
    private var iconFont: FontConfig? = nil
    private var colour: ColourModeConfig? = nil
    private var config: ModuleConfiguration?
    private var lastDrawnValue: String?
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

    mutating func setColour(_ colour: ColourModeConfig) -> ModuleConfigBuilder {
        self.colour = colour
        return self
    }

     mutating func setLastDrawnValue(_ lastDrawnValue: String) -> ModuleConfigBuilder {
        self.lastDrawnValue = lastDrawnValue
        return self
    }

     mutating func setOffset(_ offset: CGFloat) -> ModuleConfigBuilder {
        self.offset = offset
        return self
     }

    mutating func setConfigFactory(_ factory: ModuleConfigurationFactory) -> ModuleConfigBuilder {
        self.configFactory = factory
        return self
    }

    mutating func buildConfiguration(from yaml: Yaml) throws -> ModuleConfigBuilder {
        guard let factory = self.configFactory else {
            throw BuilderError.missingConfigurationFactory
        }
        self.config = try factory.configuration(from: yaml)
        return self
    }

    func build() throws -> ModuleConfig {
        guard let config = self.config else {
            throw BuilderError.missingConfiguration
        }
        return ModuleConfig(name: name, alignment: alignment, type: type, icon: icon, textFont: textFont, iconFont: iconFont, colour: colour, config: config)
    }
}

enum BuilderError: Error {
    case missingConfigurationFactory
    case missingConfiguration
    case unsupportedModuleType
}

struct ModuleTimer {
    let moduleConfig: ModuleConfig
    var timer: Timer?
}

struct ModuleConfig: Codable {
    let name: String
    let alignment: String
    let type: String
    let icon: String?
    let textFont: FontConfig?
    let iconFont: FontConfig?
    let colour: ColourModeConfig?
    var config: ModuleConfiguration?
    var lastDrawnValue: String?
    var offset: CGFloat = 0

    private enum CodingKeys: String, CodingKey {
        case name, type, alignment, icon, textFont, iconFont, colour, config, lastDrawnValue
    }

    init(name: String, alignment: String, type: String, icon: String? = nil, textFont: FontConfig? = nil, iconFont: FontConfig? = nil, colour: ColourModeConfig? = nil, config: ModuleConfiguration? = nil) {
        self.name = name
        self.alignment = alignment
        self.type = type
        self.icon = icon
        self.textFont = textFont
        self.iconFont = iconFont
        self.colour = colour
        self.config = config
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        alignment = try container.decode(String.self, forKey: .alignment)
        type = try container.decode(String.self, forKey: .type)
        icon = try container.decodeIfPresent(String.self, forKey: .icon)
        textFont = try container.decodeIfPresent(FontConfig.self, forKey: .textFont)
        iconFont = try container.decodeIfPresent(FontConfig.self, forKey: .iconFont)
        colour = try container.decodeIfPresent(ColourModeConfig.self, forKey: .colour)

        let configDict = try container.decodeIfPresent(ConfigDictionary.self, forKey: .config)?.values
        let configYaml = configDict.map(ModuleConfig.yaml(from:))

        let factories: [String: ModuleConfigurationFactory] = [
          "text": TextConfigFactory(),
          "clock": ClockConfigFactory(),
          "power": PowerConfigFactory()
        ]

        if let configYaml = configYaml, let factory = factories[type] {
            config = try factory.configuration(from: configYaml)
        } else {
            config = nil
        }

        lastDrawnValue = try container.decodeIfPresent(String.self, forKey: .lastDrawnValue)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(alignment, forKey: .alignment)
        try container.encode(type, forKey: .type)
        try container.encodeIfPresent(icon, forKey: .icon)
        try container.encodeIfPresent(textFont, forKey: .textFont)
        try container.encodeIfPresent(iconFont, forKey: .iconFont)
        try container.encodeIfPresent(colour, forKey: .colour)
        // NOTE: We're not encoding the `config` property here, as it's not directly encodable.

        try container.encodeIfPresent(lastDrawnValue, forKey: .lastDrawnValue)
    }

    static func yaml(from dictionary: [String: Any]) -> Yaml {
        var yamlDict: [Yaml: Yaml] = [:]
        for (key, value) in dictionary {
            if let stringValue = value as? String {
                yamlDict[Yaml.string(key)] = Yaml.string(stringValue)
            }
            // NOTE: add other types here when needed
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
