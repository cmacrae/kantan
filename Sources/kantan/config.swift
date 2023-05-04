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
    let colour: ColourConfig
}

struct ColourConfig: Codable {
    let fg: String
    let bg: String
}

struct ModuleConfig: Codable {
    let name: String
    let alignment: String
    let text: String?
    let icon: String?
    let colour: ColourConfig?
}

// Load configuration from a YAML object
func loadConfig(from yaml: Yaml) -> Config? {
    guard let globalYaml = yaml["global"].dictionary,
          let height = globalYaml["height"]?.int,
          let padding = globalYaml["padding"]?.int,
          let colourYaml = globalYaml["colour"]?.dictionary,
          let fg = colourYaml["fg"]?.string,
          let bg = colourYaml["bg"]?.string else {
            print("Failed to load global config from YAML") // NOTE: debugging
            return nil
    }


    let globalConfig = GlobalConfig(height: height, padding: padding, colour: ColourConfig(fg: fg, bg: bg))

    guard let modulesYaml = yaml["modules"].array else {
        print("Failed to load modules config from YAML")
        return nil
    }

    var modules: [ModuleConfig] = []

    for moduleYaml in modulesYaml {
        guard let name = moduleYaml["name"].string,
              let alignment = moduleYaml["alignment"].string else {
            print("Uh oh! Failed to load module config from YAML") // NOTE: debugging
            return nil
        }


        let icon = moduleYaml["icon"].string
        let text = moduleYaml["text"].string

        let colour: ColourConfig?
        if let fg = moduleYaml["colour"].string {
            colour = ColourConfig(fg: fg, bg: globalConfig.colour.bg)
        } else {
            colour = nil
        }

        let module = ModuleConfig(name: name, alignment: alignment, text: text, icon: icon, colour: colour)
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
    convenience init(hex: String) {
        let hexString: String = hex.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        let scanner = Scanner(string: hexString)

        if hexString.hasPrefix("#") {
            scanner.currentIndex = hexString.index(after: hexString.startIndex)
        }

        var color: UInt64 = 0
        scanner.scanHexInt64(&color)

        let mask = 0x000000FF
        let r = CGFloat(Int(color >> 16) & mask) / 255.0
        let g = CGFloat(Int(color >> 8) & mask) / 255.0
        let b = CGFloat(Int(color) & mask) / 255.0

        self.init(red: r, green: g, blue: b, alpha: 1)
    }
}
