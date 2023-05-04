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
}

struct ColourModeConfig: Codable {
    let light: ColourConfig
    let dark: ColourConfig
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
    let colour: ColourModeConfig?
}

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
            print("Failed to load global config from YAML") // NOTE: debugging
            return nil
    }

    let globalConfig = GlobalConfig(
        height: height,
        padding: padding,
        colour: ColourModeConfig(
            light: ColourConfig(fg: lightFg, bg: lightBg),
            dark: ColourConfig(fg: darkFg, bg: darkBg)
        )
    )

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
