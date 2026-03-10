import AppKit
import Foundation
import SwiftUI
import Yaml

// MARK: - Style Types

enum ModuleShape: String, Codable, Sendable {
    case pill, box, underline, overline
}

struct ElementStyle: Codable, Sendable {
    let fg: String?
}

struct StyleModeConfig: Codable, Sendable {
    let fg: String?
    let bg: String?
    let text: ElementStyle?
    let icon: ElementStyle?
    let shape: ModuleShape?
}

struct StyleConfig: Codable, Sendable {
    let light: StyleModeConfig?
    let dark: StyleModeConfig?
}

// MARK: - Displays

enum DisplaysConfig: Sendable {
    case main
    case all
    case named([String])
}

// MARK: - Gaps

struct GapsConfig: Sendable {
    let top: CGFloat
    let bottom: CGFloat
    let left: CGFloat
    let right: CGFloat

    static let `default` = GapsConfig(top: 0, bottom: 0, left: 0, right: 0)
}

// MARK: - Autohide

struct AutohideConfig: Codable, Sendable {
    let enabled: Bool
    let delay: Double

    static let `default` = AutohideConfig(enabled: true, delay: 0.0)
}

// MARK: - Config

struct Config {
    let appearance: AppearanceStyle
    let style: StyleConfig
    let height: Int
    let padding: Int
    let iconTextSpacing: Int
    let iconFont: FontConfig?
    let textFont: FontConfig?
    let cornerRadius: CGFloat
    let blur: Int
    let gaps: GapsConfig
    let autohide: AutohideConfig
    let displays: DisplaysConfig
    var modules: [ModuleConfig]
}

/// Controls whether tooltips, menus, and popups use the native system
/// appearance ("native") or the kantan-themed appearance ("theme").
enum AppearanceStyle: String, Codable, Sendable {
    case native
    case theme
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

    /// Converts this FontConfig to a SwiftUI Font, preserving exact
    /// NSFontDescriptor behavior (critical for custom icon fonts).
    var swiftUIFont: Font {
        let descriptor = NSFontDescriptor(name: name, size: size)
            .withSymbolicTraits(symbolicTraits)
        let nsFont = NSFont(descriptor: descriptor, size: size)
                     ?? NSFont.systemFont(ofSize: size)
        return Font(nsFont)
    }
}

// NOTE: ModuleConfig & ModuleConfiguration:
//       see modules/modules.swift

// MARK: - Style Parsing Helpers

func parseStyleModeConfig(from yaml: Yaml) -> StyleModeConfig? {
    guard let dict = yaml.dictionary else { return nil }

    let fg = dict["fg"]?.string
    let bg = dict["bg"]?.string

    var text: ElementStyle? = nil
    if let textDict = dict["text"]?.dictionary {
        text = ElementStyle(fg: textDict["fg"]?.string)
    }

    var icon: ElementStyle? = nil
    if let iconDict = dict["icon"]?.dictionary {
        icon = ElementStyle(fg: iconDict["fg"]?.string)
    }

    var shape: ModuleShape? = nil
    if let shapeStr = dict["shape"]?.string {
        shape = ModuleShape(rawValue: shapeStr)
    }

    // Return nil only if everything is nil
    if fg == nil && bg == nil && text == nil && icon == nil && shape == nil {
        return nil
    }

    return StyleModeConfig(fg: fg, bg: bg, text: text, icon: icon, shape: shape)
}

func parseStyleConfig(from yaml: Yaml) -> StyleConfig? {
    guard let dict = yaml.dictionary else { return nil }

    let light = dict["light"].flatMap { parseStyleModeConfig(from: $0) }
    let dark = dict["dark"].flatMap { parseStyleModeConfig(from: $0) }

    if light == nil && dark == nil { return nil }

    return StyleConfig(light: light, dark: dark)
}

// MARK: - Load Configuration

func loadConfig(from yaml: Yaml) -> Config? {
    // Top-level keys (flattened — no "global" wrapper)
    guard let height = yaml["height"].int,
          let padding = yaml["padding"].int else {
        print("Failed to load config: missing height or padding")
        return nil
    }

    guard let styleYaml = yaml["style"].dictionary,
          let lightYaml = styleYaml["light"],
          let darkYaml = styleYaml["dark"],
          let lightMode = parseStyleModeConfig(from: lightYaml),
          let darkMode = parseStyleModeConfig(from: darkYaml),
          lightMode.fg != nil, lightMode.bg != nil,
          darkMode.fg != nil, darkMode.bg != nil else {
        print("Failed to load config: style.light and style.dark must have fg and bg")
        return nil
    }

    let style = StyleConfig(light: lightMode, dark: darkMode)

    let iconTextSpacing = yaml["iconTextSpacing"].int ?? 5

    let iconFont = yaml["iconFont"].string.map { FontConfig(descriptor: $0) }
    let textFont = yaml["textFont"].string.map { FontConfig(descriptor: $0) }

    let cornerRadius: CGFloat
    if let cr = yaml["cornerRadius"].double {
        cornerRadius = max(0, CGFloat(cr))
    } else if let cr = yaml["cornerRadius"].int {
        cornerRadius = max(0, CGFloat(cr))
    } else {
        cornerRadius = 0
    }

    let blur: Int
    if let b = yaml["blur"].int {
        blur = max(0, min(6, b))
    } else {
        blur = 0
    }

    let gaps: GapsConfig
    if let gapsYaml = yaml["gaps"].dictionary {
        let top = gapsYaml["top"]?.int.map { max(0, CGFloat($0)) } ?? 0
        let bottom = gapsYaml["bottom"]?.int.map { max(0, CGFloat($0)) } ?? 0
        let left = gapsYaml["left"]?.int.map { max(0, CGFloat($0)) } ?? 0
        let right = gapsYaml["right"]?.int.map { max(0, CGFloat($0)) } ?? 0
        gaps = GapsConfig(top: top, bottom: bottom, left: left, right: right)
    } else {
        gaps = .default
    }

    let appearanceStr = yaml["appearance"].string ?? "theme"
    let appearance = AppearanceStyle(rawValue: appearanceStr) ?? .theme

    let displays: DisplaysConfig
    if let displaysStr = yaml["displays"].string {
        switch displaysStr.lowercased() {
        case "all":
            displays = .all
        default:
            displays = .main
        }
    } else if let displaysArray = yaml["displays"].array {
        let names = displaysArray.compactMap { $0.string }
        displays = names.isEmpty ? .main : .named(names)
    } else {
        displays = .main
    }

    let autohide: AutohideConfig
    if let autohideYaml = yaml["autohide"].dictionary {
        let enable = autohideYaml["enabled"]?.bool ?? true
        let delay: Double
        if let d = autohideYaml["delay"]?.double {
            delay = max(0.0, min(5.0, d))
        } else if let d = autohideYaml["delay"]?.int {
            delay = max(0.0, min(5.0, Double(d)))
        } else {
            delay = AutohideConfig.default.delay
        }
        autohide = AutohideConfig(enabled: enable, delay: delay)
    } else {
        autohide = AutohideConfig.default
    }

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
    let caffeinateConfigFactory = CaffeinateConfigFactory()
    let iconConfigFactory = IconConfigFactory()

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

        // Parse per-module style
        if let moduleStyle = parseStyleConfig(from: moduleYaml["style"]) {
            builder = builder.setStyle(moduleStyle)
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

        // Parse mask config (index or name, mutually exclusive)
        if let maskYaml = moduleYaml["mask"].dictionary {
            if let index = maskYaml["index"]?.int {
                builder = builder.setMask(MaskConfig(index: index))
            } else if let name = maskYaml["name"]?.string {
                builder = builder.setMask(MaskConfig(name: name))
            }

            // Default to passthrough if no explicit click type was set
            if moduleYaml["interaction"]["click"]["type"].string == nil {
                // Preserve any existing hover config
                var hover: HoverConfig? = nil
                if let hoverYaml = moduleYaml["interaction"]["hover"].dictionary {
                    let hoverType = hoverYaml["type"]?.string ?? "tooltip"
                    let hoverContent = hoverYaml["content"]?.string ?? "{value}"
                    hover = HoverConfig(type: hoverType, content: hoverContent)
                }
                let click = ClickConfig(type: "passthrough", popup: nil, items: nil)
                builder = builder.setInteraction(InteractionConfig(hover: hover, click: click))
            }
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
        case "caffeinate":
            builder = builder.setConfigFactory(caffeinateConfigFactory)
        case "icon":
            builder = builder.setConfigFactory(iconConfigFactory)
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

    return Config(
        appearance: appearance,
        style: style,
        height: height,
        padding: padding,
        iconTextSpacing: iconTextSpacing,
        iconFont: iconFont,
        textFont: textFont,
        cornerRadius: cornerRadius,
        blur: blur,
        gaps: gaps,
        autohide: autohide,
        displays: displays,
        modules: modules
    )
}

// Convenience function to load data from a file
func loadFileContents(filePath: String) -> String? {
    let fileURL = URL(fileURLWithPath: filePath)
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
