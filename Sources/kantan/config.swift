import AppKit
import Foundation
import Yaml

struct Config: Codable {
    let global: GlobalConfig
    let modules: [ModuleConfig]
}

struct GlobalConfig: Codable {
    let height: Int
    let padding: Int
    let colour: ColourModeConfig
    let iconFont: FontConfig?
    let textFont: FontConfig?
}

struct ColourModeConfig: Codable {
    let light: ColourConfig
    let dark: ColourConfig
}

struct ColourConfig: Codable {
    let fg: String
    let bg: String
}

struct FontConfig: Codable {
    let descriptor: String

    var name: String {
        guard let firstComponent = descriptor.components(separatedBy: ":").first else {
            return "HelveticaNeue"
        }
        return firstComponent
    }

    var weight: NSFont.Weight {
        guard descriptor.components(separatedBy: ":").count > 1 else {
            return .regular
        }
        let weightString = descriptor.components(separatedBy: ":")[1]
        switch weightString.lowercased() {
        case "ultralight":
            return .ultraLight
        case "thin":
            return .thin
        case "light":
            return .light
        case "regular":
            return .regular
        case "medium":
            return .medium
        case "semibold", "demi-bold":
            return .semibold
        case "bold":
            return .bold
        case "heavy", "extrabold":
            return .heavy
        case "black":
            return .black
        default:
            return .regular
        }
    }

    var size: CGFloat {
        guard descriptor.components(separatedBy: ":").count > 2 else {
            return CGFloat(14)
        }
        return CGFloat(Double(descriptor.components(separatedBy: ":")[2]) ?? 14)
    }

    var symbolicTraits: NSFontDescriptor.SymbolicTraits {
        return weight == .bold ? .bold : []
    }
}

// NOTE: ModuleConfig & ModuleConfiguration:
//       see modules/modules.swift

// Load configuration from a YAML object
func loadConfig(from yaml: Yaml) -> Config? {
    guard let globalYaml = yaml["global"].dictionary,
          let height = globalYaml["height"]?.int,
          let padding = globalYaml["padding"]?.int,
          let colourYaml = globalYaml["colour"]?.dictionary,
          let lightColourYaml = colourYaml["light"]?.dictionary,
          let darkColourYaml = colourYaml["dark"]?.dictionary,
          let lightFg = lightColourYaml["fg"]?.string,
          let lightBg = lightColourYaml["bg"]?.string,
          let darkFg = darkColourYaml["fg"]?.string,
          let darkBg = darkColourYaml["bg"]?.string else {
        print("Failed to load global config") // NOTE: debugging
        return nil
    }

    let globalIconFontDescriptor = globalYaml["iconFont"]?.string
    let globalTextFontDescriptor = globalYaml["textFont"]?.string
    let globalIconFont = globalIconFontDescriptor.map { FontConfig(descriptor: $0) }
    let globalTextFont = globalTextFontDescriptor.map { FontConfig(descriptor: $0) }

    let globalConfig = GlobalConfig(
      height: height,
      padding: padding,
      colour: ColourModeConfig(
        light: ColourConfig(fg: lightFg, bg: lightBg),
        dark: ColourConfig(fg: darkFg, bg: darkBg)
      ),
      iconFont: globalIconFont,
      textFont: globalTextFont
    )

    guard let modulesYaml = yaml["modules"].array else {
        print("Failed to load modules config from YAML")
        return nil
    }

    var modules: [ModuleConfig] = []

    for moduleYaml in modulesYaml {
        guard let name = moduleYaml["name"].string,
              let alignment = moduleYaml["alignment"].string,
              let type = moduleYaml["type"].string else {
                print("Failed to load module config") // NOTE: debugging
                return nil
        }

        let moduleConfig: Codable?
        switch type {
        case "text":
            if moduleYaml["config"]["value"].string != nil {
                moduleConfig = try? TextConfig(yaml: moduleYaml["config"])
            } else {
                moduleConfig = nil
            }
        case "clock":
            if moduleYaml["config"]["format"].string != nil {
                moduleConfig = try? ClockConfig(yaml: moduleYaml["config"])
            } else {
                moduleConfig = nil
            }
        default:
            print("Unsupported module type")
            moduleConfig = nil
        }

        let moduleTextFont: FontConfig?
        if let textFontDescriptor = moduleYaml["textFont"].string {
            moduleTextFont = FontConfig(descriptor: textFontDescriptor)
        } else {
            moduleTextFont = nil
        }

        let icon = moduleYaml["icon"].string

        let moduleIconFont: FontConfig?
        if let iconFontDescriptor = moduleYaml["iconFont"].string {
            moduleIconFont = FontConfig(descriptor: iconFontDescriptor)
        } else {
            moduleIconFont = nil
        }

        var colour: ColourModeConfig? = nil
        if let colourYaml = moduleYaml["colour"].dictionary {
            let lightColourYaml = colourYaml["light"]?.dictionary
            let darkColourYaml = colourYaml["dark"]?.dictionary

            let lightFg = lightColourYaml?["fg"]?.string
            let lightBg = lightColourYaml?["bg"]?.string
            let darkFg = darkColourYaml?["fg"]?.string
            let darkBg = darkColourYaml?["bg"]?.string

            if lightFg != nil || lightBg != nil || darkFg != nil || darkBg != nil {
                colour = ColourModeConfig(
                  light: ColourConfig(fg: lightFg ?? globalConfig.colour.light.fg, bg: lightBg ?? globalConfig.colour.light.bg),
                  dark: ColourConfig(fg: darkFg ?? globalConfig.colour.dark.fg, bg: darkBg ?? globalConfig.colour.dark.bg)
                )
            }
        }

        let module = ModuleConfig(name: name, alignment: alignment, type: type, icon: icon, textFont: moduleTextFont, iconFont: moduleIconFont, colour: colour, config: moduleConfig)
        modules.append(module)
    }


    return Config(global: globalConfig, modules: modules)
}

// Convenience function to load data from a file
func loadFileContents(filePath: String) -> String? {
    let fileURL = URL(fileURLWithPath: filePath)
    // NOTE: Debugging
    print("Loading file from: \(fileURL.path)")

    do {
        let fileData = try String(contentsOf: fileURL, encoding: .utf8)
        return fileData
    } catch {
        print("Error loading file: \(error)")
        return nil
    }
}

// Convenience extension to convert hex strings to NSColor
extension NSColor {
    convenience init(hex: String, defaultColor: NSColor = NSColor.clear) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        let scanner = Scanner(string: hex)
        var rgbValue: UInt64 = 0

        if scanner.scanHexInt64(&rgbValue) {
            let r = CGFloat((rgbValue & 0xFF0000) >> 16) / 255.0
            let g = CGFloat((rgbValue & 0x00FF00) >> 8) / 255.0
            let b = CGFloat(rgbValue & 0x0000FF) / 255.0
            self.init(red: r, green: g, blue: b, alpha: 1)
        } else {
            self.init(red: defaultColor.redComponent, green: defaultColor.greenComponent, blue: defaultColor.blueComponent, alpha: defaultColor.alphaComponent)
        }
    }
}
