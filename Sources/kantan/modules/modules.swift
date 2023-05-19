import Foundation
import Yaml

protocol ModuleConfiguration: Codable {
    var type: String { get }
    var redrawInterval: TimeInterval { get }
    func getNewValue() -> String
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

        switch type {
        case "text":
            config = configYaml.flatMap { try? TextConfig(yaml: $0) }
        case "clock":
            config = configYaml.flatMap { try? ClockConfig(yaml: $0) }
        default:
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
