import AppKit
import Foundation
import Yaml

struct Config: Codable {
    let global: GlobalConfig
    var modules: [ModuleConfig]
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
    let textConfigFactory = TextConfigFactory()
    let clockConfigFactory = ClockConfigFactory()
    let powerConfigFactory = PowerConfigFactory()
    let commandConfigFactory = CommandConfigFactory()
    let remindersConfigFactory = RemindersConfigFactory()
    let workspaceConfigFactory = WorkspaceConfigFactory()
    let volumeConfigFactory = VolumeConfigFactory()
    let wifiConfigFactory = WiFiConfigFactory()
    let bluetoothConfigFactory = BluetoothConfigFactory()

    for moduleYaml in modulesYaml {
        var builder = ModuleConfigBuilder()

        guard let name = moduleYaml["name"].string,
              let alignment = moduleYaml["alignment"].string,
              let type = moduleYaml["type"].string else {
            print("Failed to load module config")
            return nil
        }

        builder = builder.setName(name)
        builder = builder.setAlignment(alignment)
        builder = builder.setType(type)

        if let icon = moduleYaml["icon"].string {
            builder = builder.setIcon(icon)
        }

        if let textFontDescriptor = moduleYaml["textFont"].string {
            let moduleTextFont = FontConfig(descriptor: textFontDescriptor)
            builder = builder.setTextFont(moduleTextFont)
        }

        if let iconFontDescriptor = moduleYaml["iconFont"].string {
            let moduleIconFont = FontConfig(descriptor: iconFontDescriptor)
            builder = builder.setIconFont(moduleIconFont)
        }

        if let colourYaml = moduleYaml["colour"].dictionary {
            let lightColourYaml = colourYaml["light"]?.dictionary
            let darkColourYaml = colourYaml["dark"]?.dictionary

            let lightFg = lightColourYaml?["fg"]?.string
            let lightBg = lightColourYaml?["bg"]?.string
            let darkFg = darkColourYaml?["fg"]?.string
            let darkBg = darkColourYaml?["bg"]?.string

            if lightFg != nil || lightBg != nil || darkFg != nil || darkBg != nil {
                let colour = ColourModeConfig(
                  light: ColourConfig(fg: lightFg ?? globalConfig.colour.light.fg, bg: lightBg ?? globalConfig.colour.light.bg),
                  dark: ColourConfig(fg: darkFg ?? globalConfig.colour.dark.fg, bg: darkBg ?? globalConfig.colour.dark.bg)
                )
                builder = builder.setColour(colour)
            }
        }

        // Parse interaction config
        if let interactionYaml = moduleYaml["interaction"].dictionary {
            var hover: HoverConfig? = nil
            var click: ClickConfig? = nil

            if let hoverYaml = interactionYaml["hover"]?.dictionary {
                let hoverType = hoverYaml["type"]?.string ?? "tooltip"
                let content = hoverYaml["content"]?.string ?? "{value}"
                hover = HoverConfig(type: hoverType, content: content)
            }

            if let clickYaml = interactionYaml["click"]?.dictionary {
                let clickType = clickYaml["type"]?.string ?? "menu"
                let popup = clickYaml["popup"]?.string
                var menuItems: [MenuItemConfig]? = nil

                if let itemsYaml = clickYaml["items"]?.array {
                    menuItems = itemsYaml.compactMap { itemYaml -> MenuItemConfig? in
                        let isSeparator = itemYaml["separator"].bool ?? false
                        if isSeparator {
                            return MenuItemConfig(label: nil, command: nil, separator: true)
                        }
                        guard let label = itemYaml["label"].string else { return nil }
                        let command = itemYaml["command"].string
                        return MenuItemConfig(label: label, command: command, separator: false)
                    }
                }

                click = ClickConfig(type: clickType, popup: popup, items: menuItems)
            }

            let interaction = InteractionConfig(hover: hover, click: click)
            builder = builder.setInteraction(interaction)
        }

        switch type {
        case "text":
            builder = builder.setConfigFactory(textConfigFactory)
        case "clock":
            builder = builder.setConfigFactory(clockConfigFactory)
        case "power":
            builder = builder.setConfigFactory(powerConfigFactory)
        case "command":
            builder = builder.setConfigFactory(commandConfigFactory)
        case "reminders":
            builder = builder.setConfigFactory(remindersConfigFactory)
        case "workspace":
            builder = builder.setConfigFactory(workspaceConfigFactory)
        case "volume":
            builder = builder.setConfigFactory(volumeConfigFactory)
        case "wifi":
            builder = builder.setConfigFactory(wifiConfigFactory)
        case "bluetooth":
            builder = builder.setConfigFactory(bluetoothConfigFactory)
        default:
            print("Unsupported module type")
        }

        do {
            builder = try builder.buildConfiguration(from: moduleYaml["config"])
            let module = try builder.build()
            modules.append(module)
        } catch {
            print("Failed to build module config: \(error)")
        }
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
