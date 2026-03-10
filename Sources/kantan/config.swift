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

    private static let defaultSize: CGFloat = 14

    /// Components of the descriptor string, parsed once and cached.
    private var components: [String] {
        descriptor.components(separatedBy: ":")
    }

    var name: String {
        guard let firstComponent = components.first else {
            return "HelveticaNeue"
        }
        return firstComponent
    }

    var weight: NSFont.Weight {
        guard components.count > 1 else {
            return .regular
        }
        let weightString = components[1]
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
        guard components.count > 2 else {
            return Self.defaultSize
        }
        return Double(components[2]).map { CGFloat($0) } ?? Self.defaultSize
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

// MARK: - Config Parsing Helpers

/// Parse a displays config value from YAML, falling back to a default.
func parseDisplaysConfig(from yaml: Yaml?, default defaultValue: DisplaysConfig = .main) -> DisplaysConfig {
    guard let yaml = yaml else { return defaultValue }
    if let displaysStr = yaml.string {
        switch displaysStr.lowercased() {
        case "all":
            return .all
        default:
            return .main
        }
    } else if let displaysArray = yaml.array {
        let names = displaysArray.compactMap { $0.string }
        return names.isEmpty ? defaultValue : .named(names)
    }
    return defaultValue
}

/// Clamp a YAML int value to a non-negative CGFloat, returning 0 if nil.
func clampedCGFloat(_ yaml: Yaml?) -> CGFloat {
    guard let value = yaml?.int else { return 0 }
    return max(0, CGFloat(value))
}

// MARK: - Load Configuration

func loadConfig(from yaml: Yaml, configDir: String? = nil) -> Config? {
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
        gaps = GapsConfig(
            top: clampedCGFloat(gapsYaml["top"]),
            bottom: clampedCGFloat(gapsYaml["bottom"]),
            left: clampedCGFloat(gapsYaml["left"]),
            right: clampedCGFloat(gapsYaml["right"])
        )
    } else {
        gaps = .default
    }

    let appearanceStr = yaml["appearance"].string ?? "theme"
    let appearance = AppearanceStyle(rawValue: appearanceStr) ?? .theme

    let displays = parseDisplaysConfig(from: yaml["displays"])

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


    var modules: [ModuleConfig] = []
    if let modulesYaml = yaml["modules"].array {
        for moduleYaml in modulesYaml {
            if let module = parseModuleConfig(from: moduleYaml, configDir: configDir) {
                modules.append(module)
            }
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

// MARK: - Module Parsing

/// Parse a single module definition from YAML into a ModuleConfig.
/// Used both for inline modules in config.yaml and standalone files in modules.d.
/// `configDir` is the directory containing the config/module file, used to
/// resolve relative paths (e.g. command scripts).
func parseModuleConfig(from moduleYaml: Yaml, configDir: String? = nil) -> ModuleConfig? {
    var builder = ModuleConfigBuilder()

    guard let name = moduleYaml["name"].string,
          let alignment = moduleYaml["alignment"].string,
          let type = moduleYaml["type"].string else {
        print("Failed to load module config: missing name, alignment, or type")
        return nil
    }

    builder.setName(name)
    builder.setAlignment(alignment)
    builder.setType(type)

    if let icon = moduleYaml["icon"].string {
        builder.setIcon(fixYamlUnicodeEscapes(icon))
    }

    if let textFontDescriptor = moduleYaml["textFont"].string {
        let moduleTextFont = FontConfig(descriptor: textFontDescriptor)
        builder.setTextFont(moduleTextFont)
    }

    if let iconFontDescriptor = moduleYaml["iconFont"].string {
        let moduleIconFont = FontConfig(descriptor: iconFontDescriptor)
        builder.setIconFont(moduleIconFont)
    }

    // Parse per-module style
    if let moduleStyle = parseStyleConfig(from: moduleYaml["style"]) {
        builder.setStyle(moduleStyle)
    }

    // Parse interaction config
    if let interactionYaml = moduleYaml["interaction"].dictionary {
        var hover: HoverConfig? = nil
        var click: ClickConfig? = nil

        if let hoverYaml = interactionYaml["hover"]?.dictionary {
            let hoverType = hoverYaml["type"]?.string ?? "tooltip"
            let content = fixYamlUnicodeEscapes(hoverYaml["content"]?.string ?? "{value}")
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
                        return MenuItemConfig(label: nil, command: nil, separator: true, icon: nil, header: nil, dynamic: nil)
                    }
                    if let header = itemYaml["header"].string {
                        return MenuItemConfig(label: nil, command: nil, separator: nil, icon: nil, header: fixYamlUnicodeEscapes(header), dynamic: nil)
                    }
                    if itemYaml["dynamic"].bool == true {
                        return MenuItemConfig(label: nil, command: nil, separator: nil, icon: nil, header: nil, dynamic: true)
                    }
                    guard let label = itemYaml["label"].string else { return nil }
                    let command = itemYaml["command"].string
                    let icon = itemYaml["icon"].string.map(fixYamlUnicodeEscapes)
                    return MenuItemConfig(label: fixYamlUnicodeEscapes(label), command: command, separator: false, icon: icon, header: nil, dynamic: nil)
                }
            }

            // Parse popup config (object form for user-defined popups)
            var popupConfig: PopupConfig? = nil
            if let popupYaml = clickYaml["popup"]?.dictionary {
                let title = popupYaml["title"]?.string.map(fixYamlUnicodeEscapes)
                let width = popupYaml["width"]?.int
                var rows: [PopupRowConfig] = []
                if let rowsYaml = popupYaml["rows"]?.array {
                    rows = rowsYaml.compactMap { rowYaml -> PopupRowConfig? in
                        guard let rowType = rowYaml["type"].string else { return nil }
                        return PopupRowConfig(
                            type: rowType,
                            content: rowYaml["content"].string.map(fixYamlUnicodeEscapes),
                            icon: rowYaml["icon"].string.map(fixYamlUnicodeEscapes),
                            label: rowYaml["label"].string.map(fixYamlUnicodeEscapes),
                            value: rowYaml["value"].string.map(fixYamlUnicodeEscapes),
                            command: rowYaml["command"].string,
                            style: rowYaml["style"].string
                        )
                    }
                }
                popupConfig = PopupConfig(title: title, width: width, rows: rows)
            }

            click = ClickConfig(type: clickType, popup: popup, items: menuItems, popupConfig: popupConfig)
        }

        let interaction = InteractionConfig(hover: hover, click: click)
        builder.setInteraction(interaction)
    }

    // Parse mask config (index or name, mutually exclusive)
    if let maskYaml = moduleYaml["mask"].dictionary {
        if let index = maskYaml["index"]?.int {
            builder.setMask(MaskConfig(index: index))
        } else if let name = maskYaml["name"]?.string {
            builder.setMask(MaskConfig(name: name))
        }

        // Default to passthrough if no explicit click type was set
        if moduleYaml["interaction"]["click"]["type"].string == nil {
            // Preserve any existing hover config
            var hover: HoverConfig? = nil
            if let hoverYaml = moduleYaml["interaction"]["hover"].dictionary {
                let hoverType = hoverYaml["type"]?.string ?? "tooltip"
                let hoverContent = fixYamlUnicodeEscapes(hoverYaml["content"]?.string ?? "{value}")
                hover = HoverConfig(type: hoverType, content: hoverContent)
            }
            let click = ClickConfig(type: "passthrough", popup: nil, items: nil, popupConfig: nil)
            builder.setInteraction(InteractionConfig(hover: hover, click: click))
        }
    }

    // Parse per-module displays config
    let moduleDisplays = parseDisplaysConfig(from: moduleYaml["displays"])
    if case .main = moduleDisplays {
        // Only set if not the default (.main), to avoid overriding unset state
        if moduleYaml["displays"].string != nil || moduleYaml["displays"].array != nil {
            builder.setDisplays(moduleDisplays)
        }
    } else {
        builder.setDisplays(moduleDisplays)
    }

    guard let factory = moduleFactories[type] else {
        print("Unsupported module type: \(type)")
        return nil
    }

    builder.setConfigFactory(factory)

    do {
        try builder.buildConfiguration(from: moduleYaml["config"], configDir: configDir)
        return try builder.build()
    } catch {
        print("Failed to build module config: \(error)")
        return nil
    }
}

// MARK: - Config Path Resolution

/// Resolve the config file path using the priority chain:
/// 1. Explicit path (from --config flag)
/// 2. config.yaml in CWD
/// 3. $XDG_CONFIG_HOME/kantan/config.yaml (default ~/.config/kantan/config.yaml)
func resolveConfigPath(explicit: String?) -> String? {
    let fm = FileManager.default

    if let explicit = explicit {
        let url = URL(fileURLWithPath: explicit).standardizedFileURL
        if fm.fileExists(atPath: url.path) {
            return url.path
        }
        print("Config file not found: \(explicit)")
        return nil
    }

    let cwdPath = URL(fileURLWithPath: "config.yaml").standardizedFileURL.path
    if fm.fileExists(atPath: cwdPath) {
        return cwdPath
    }

    let xdgBase: String
    if let xdg = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"] {
        xdgBase = xdg
    } else {
        xdgBase = ("~/.config" as NSString).expandingTildeInPath
    }
    let xdgPath = URL(fileURLWithPath: xdgBase)
        .appendingPathComponent("kantan/config.yaml").standardizedFileURL.path
    if fm.fileExists(atPath: xdgPath) {
        return xdgPath
    }

    print("No config file found (tried CWD and \(xdgPath))")
    return nil
}

/// Resolve the modules.d directory path.
/// 1. Explicit path (from --modules-dir flag)
/// 2. modules.d/ sibling to the resolved config file
func resolveModulesDir(explicit: String?, configPath: String) -> String {
    if let explicit = explicit {
        return URL(fileURLWithPath: explicit).standardizedFileURL.path
    }
    let configDir = URL(fileURLWithPath: configPath).deletingLastPathComponent()
    return configDir.appendingPathComponent("modules.d").standardizedFileURL.path
}

// MARK: - modules.d Loading

/// Load individual module YAML files from a directory.
/// Files are sorted alphabetically (numeric prefix controls order).
/// Non-existent directory is silently ignored.
func loadModulesFromDirectory(path: String) -> [ModuleConfig] {
    let fm = FileManager.default
    guard fm.fileExists(atPath: path) else { return [] }

    guard let entries = try? fm.contentsOfDirectory(atPath: path) else {
        print("Failed to read modules directory: \(path)")
        return []
    }

    let yamlFiles = entries
        .filter { $0.hasSuffix(".yaml") || $0.hasSuffix(".yml") }
        .sorted()

    var modules: [ModuleConfig] = []
    for filename in yamlFiles {
        let filePath = URL(fileURLWithPath: path)
            .appendingPathComponent(filename).path
        guard let fileData = loadFileContents(filePath: filePath) else {
            print("modules.d: failed to read \(filename)")
            continue
        }
        do {
            let yaml = try Yaml.load(fileData)
            if let module = parseModuleConfig(from: yaml, configDir: path) {
                modules.append(module)
            } else {
                print("modules.d: failed to parse module from \(filename)")
            }
        } catch {
            print("modules.d: YAML error in \(filename) — \(error)")
        }
    }
    return modules
}

/// Merge modules.d modules into the base config modules list with correct
/// visual ordering. Config.yaml modules occupy the screen edges; modules.d
/// modules are placed inward (toward center), ordered by filename prefix.
///
/// Right-aligned: modules.d entries are prepended so they appear to the
/// LEFT of config.yaml right modules (closer to center) after the
/// right-group reversal in the positioning pass.
///
/// Left-aligned: modules.d entries are appended so they appear to the
/// RIGHT of config.yaml left modules (closer to center).
func mergeModules(base: [ModuleConfig], extra: [ModuleConfig]) -> [ModuleConfig] {
    let extraRight = extra.filter { $0.alignment == "right" }
    let extraLeft = extra.filter { $0.alignment != "right" }
    let baseRight = base.filter { $0.alignment == "right" }
    let baseLeft = base.filter { $0.alignment != "right" }
    // modules.d numbering follows the same convention as config.yaml line
    // order: lower number = earlier in visual flow (left to right).
    // Right-aligned modules.d entries are prepended so they appear to the
    // left of config.yaml right modules (closer to center).
    return baseLeft + extraLeft + extraRight + baseRight
}

/// Fix YamlSwift bug: `String(describing: UnicodeScalar(n))` produces
/// `Optional("\u{XXXX}")` instead of the actual character for `\uXXXX`
/// escapes in double-quoted YAML strings. This unwraps the Optional
/// wrapper and converts `\u{XXXX}` escape literals into real characters.
func fixYamlUnicodeEscapes(_ s: String) -> String {
    var result = s

    // Step 1: Strip Optional("...") wrappers
    if result.contains("Optional(\"") {
        while let range = result.range(of: "Optional(\"") {
            let afterOpen = range.upperBound
            guard let closeQuote = result[afterOpen...].firstIndex(of: "\"") else { break }
            let nextIndex = result.index(after: closeQuote)
            guard nextIndex < result.endIndex, result[nextIndex] == ")" else { break }
            let content = String(result[afterOpen..<closeQuote])
            let fullRange = range.lowerBound..<result.index(after: nextIndex)
            result.replaceSubrange(fullRange, with: content)
        }
    }

    // Step 2: Convert literal \u{XXXX} sequences into actual unicode characters
    while let range = result.range(of: "\\u{") {
        guard let closeBrace = result[range.upperBound...].firstIndex(of: "}") else { break }
        let hexStr = String(result[range.upperBound..<closeBrace])
        let fullRange = range.lowerBound..<result.index(after: closeBrace)
        if let codepoint = UInt32(hexStr, radix: 16),
           let scalar = Unicode.Scalar(codepoint) {
            result.replaceSubrange(fullRange, with: String(scalar))
        } else {
            break
        }
    }

    return result
}

func loadFileContents(filePath: String) -> String? {
    let fileURL = URL(fileURLWithPath: filePath)

    do {
        let fileData = try String(contentsOf: fileURL, encoding: .utf8)
        return fileData
    } catch {
        print("Error loading file: \(error)")
        return nil
    }
}

extension NSColor {
    convenience init(hex: String, defaultColor: NSColor = NSColor.clear) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)

        if let rgbValue = UInt64(hex, radix: 16) {
            let r = CGFloat((rgbValue & 0xFF0000) >> 16) / 255.0
            let g = CGFloat((rgbValue & 0x00FF00) >> 8) / 255.0
            let b = CGFloat(rgbValue & 0x0000FF) / 255.0
            self.init(red: r, green: g, blue: b, alpha: 1)
        } else {
            self.init(red: defaultColor.redComponent, green: defaultColor.greenComponent, blue: defaultColor.blueComponent, alpha: defaultColor.alphaComponent)
        }
    }
}
