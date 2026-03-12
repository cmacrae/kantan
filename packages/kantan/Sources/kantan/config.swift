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

  /// Components of the descriptor string.
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
    let nsFont =
      NSFont(descriptor: descriptor, size: size)
      ?? NSFont.systemFont(ofSize: size)
    return Font(nsFont)
  }
}

// MARK: - Style Parsing Helpers

func parseStyleModeConfig(from yaml: Yaml) -> StyleModeConfig? {
  guard let dict = yaml.dictionary else { return nil }

  let fg = dict["fg"]?.string
  let bg = dict["bg"]?.string

  var text: ElementStyle?
  if let textDict = dict["text"]?.dictionary {
    text = ElementStyle(fg: textDict["fg"]?.string)
  }

  var icon: ElementStyle?
  if let iconDict = dict["icon"]?.dictionary {
    icon = ElementStyle(fg: iconDict["fg"]?.string)
  }

  var shape: ModuleShape?
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
func parseDisplaysConfig(from yaml: Yaml?, default defaultValue: DisplaysConfig = .main)
  -> DisplaysConfig
{
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

/// Parse a YAML value as CGFloat, accepting both int and double forms.
/// Clamps to [min, max] range. Returns `fallback` if nil.
func yamlCGFloat(
  _ yaml: Yaml?, min minVal: CGFloat = 0, max maxVal: CGFloat = .greatestFiniteMagnitude,
  fallback: CGFloat = 0
) -> CGFloat {
  if let d = yaml?.double {
    return Swift.max(minVal, Swift.min(maxVal, CGFloat(d)))
  } else if let i = yaml?.int {
    return Swift.max(minVal, Swift.min(maxVal, CGFloat(i)))
  }
  return fallback
}

private func parseHoverConfig(from yaml: Yaml?) -> HoverConfig? {
  guard let hoverYaml = yaml?.dictionary else { return nil }
  let hoverType = hoverYaml["type"]?.string ?? "tooltip"
  let content = hoverYaml["content"]?.string.map(fixYamlUnicodeEscapes)
  let viewTree = hoverYaml["view"].flatMap { parseViewNodeFromYaml($0) }
  return HoverConfig(type: hoverType, content: content, viewTree: viewTree)
}

private func parseClickConfig(from clickYaml: [Yaml: Yaml]) -> ClickConfig {
  let clickType = clickYaml["type"]?.string ?? "menu"
  let viewTree = clickYaml["view"].flatMap { parseViewNodeFromYaml($0) }
  return ClickConfig(type: clickType, viewTree: viewTree)
}

// MARK: - YAML to ViewNode Parsing

/// Parse a YAML node into a ViewNode tree.
/// This allows users to define view trees directly in YAML config files.
private func parseViewNodeFromYaml(_ yaml: Yaml) -> ViewNode? {
  guard let dict = yaml.dictionary else { return nil }
  guard let typeStr = dict["type"]?.string else { return nil }

  let common = parseCommonNodeProperties(from: dict)

  switch typeStr {
  case "vstack":
    let spacing = yamlDouble(dict["spacing"])
    let nodePadding = yamlPadding(dict["padding"])
    let alignment = dict["alignment"]?.string.flatMap { ViewAlignment(rawValue: $0) }
    let children = dict["children"]?.array?.compactMap { parseViewNodeFromYaml($0) } ?? []
    return .vstack(
      spacing: spacing, padding: nodePadding, alignment: alignment, children: children,
      common: common)

  case "hstack":
    let spacing = yamlDouble(dict["spacing"])
    let nodePadding = yamlPadding(dict["padding"])
    let alignment = dict["alignment"]?.string.flatMap { ViewAlignment(rawValue: $0) }
    let children = dict["children"]?.array?.compactMap { parseViewNodeFromYaml($0) } ?? []
    let command = dict["command"]?.string
    return .hstack(
      spacing: spacing, padding: nodePadding, alignment: alignment, children: children,
      command: command, common: common)

  case "zstack":
    let alignment = dict["alignment"]?.string.flatMap { ViewAlignment(rawValue: $0) }
    let children = dict["children"]?.array?.compactMap { parseViewNodeFromYaml($0) } ?? []
    return .zstack(alignment: alignment, children: children, common: common)

  case "scroll":
    let axis = dict["axis"]?.string.flatMap { ScrollAxis(rawValue: $0) } ?? .vertical
    let children = dict["children"]?.array?.compactMap { parseViewNodeFromYaml($0) } ?? []
    return .scroll(axis: axis, children: children, common: common)

  case "spacer":
    let minLength = yamlDouble(dict["minLength"])
    return .spacer(minLength: minLength, common: common)

  case "group":
    let children = dict["children"]?.array?.compactMap { parseViewNodeFromYaml($0) } ?? []
    return .group(children: children, common: common)

  case "text":
    let content = fixYamlUnicodeEscapes(dict["content"]?.string ?? "")
    let size = yamlDouble(dict["size"])
    let weight = dict["weight"]?.string.flatMap { TextWeight(rawValue: $0) }
    let style = dict["style"]?.string.flatMap { TextStyle(rawValue: $0) }
    let color = dict["color"]?.string
    let align = dict["align"]?.string.flatMap { DSLTextAlignment(rawValue: $0) }
    let strikethrough = dict["strikethrough"]?.bool
    return .text(
      content: content, size: size, weight: weight, style: style, color: color, align: align,
      strikethrough: strikethrough, common: common)

  case "icon":
    let name = fixYamlUnicodeEscapes(dict["name"]?.string ?? "")
    let size = yamlDouble(dict["size"])
    let color = dict["color"]?.string
    let style = dict["style"]?.string.flatMap { IconStyle(rawValue: $0) }
    return .icon(name: name, size: size, color: color, style: style, common: common)

  case "image":
    let url = dict["url"]?.string ?? ""
    let width = yamlDouble(dict["width"])
    let height = yamlDouble(dict["height"])
    let cornerRadius = yamlDouble(dict["cornerRadius"])
    return .image(
      url: url, width: width, height: height, cornerRadius: cornerRadius, common: common)

  case "divider":
    return .divider(common: common)

  case "header":
    let content = fixYamlUnicodeEscapes(dict["content"]?.string ?? "")
    return .header(content: content, common: common)

  case "rect":
    let width = yamlDouble(dict["width"])
    let height = yamlDouble(dict["height"])
    let color = dict["color"]?.string
    let cornerRadius = yamlDouble(dict["cornerRadius"])
    let strokeColor = dict["strokeColor"]?.string
    let strokeWidth = yamlDouble(dict["strokeWidth"])
    return .rect(
      width: width, height: height, color: color, cornerRadius: cornerRadius,
      strokeColor: strokeColor, strokeWidth: strokeWidth, common: common)

  case "circle":
    let size = yamlDouble(dict["size"])
    let color = dict["color"]?.string
    let strokeColor = dict["strokeColor"]?.string
    let strokeWidth = yamlDouble(dict["strokeWidth"])
    return .circle(
      size: size, color: color, strokeColor: strokeColor, strokeWidth: strokeWidth, common: common)

  case "capsule":
    let width = yamlDouble(dict["width"])
    let height = yamlDouble(dict["height"])
    let color = dict["color"]?.string
    return .capsule(width: width, height: height, color: color, common: common)

  case "action":
    let label = fixYamlUnicodeEscapes(dict["label"]?.string ?? "")
    let icon = dict["icon"]?.string.map(fixYamlUnicodeEscapes)
    let command = dict["command"]?.string
    let iconFont = dict["iconFont"]?.string
    return .action(
      label: label, icon: icon, command: command, iconFont: iconFont, common: common)

  case "check":
    let label = fixYamlUnicodeEscapes(dict["label"]?.string ?? "")
    let checked = dict["checked"]?.string ?? dict["checked"]?.bool.map { "\($0)" } ?? "false"
    let command = dict["command"]?.string
    let uncheckedCommand = dict["uncheckedCommand"]?.string
    return .check(
      label: label, checked: checked, command: command,
      uncheckedCommand: uncheckedCommand, common: common)

  case "toggle":
    let label = fixYamlUnicodeEscapes(dict["label"]?.string ?? "")
    let on = dict["on"]?.string ?? dict["on"]?.bool.map { "\($0)" } ?? "false"
    let command = dict["command"]?.string
    return .toggle(label: label, on: on, command: command, common: common)

  case "button":
    let label = fixYamlUnicodeEscapes(dict["label"]?.string ?? "")
    let icon = dict["icon"]?.string.map(fixYamlUnicodeEscapes)
    let command = dict["command"]?.string
    let style = dict["style"]?.string.flatMap { DSLButtonStyle(rawValue: $0) }
    return .button(label: label, icon: icon, command: command, style: style, common: common)

  case "foreach":
    let items = dict["items"]?.string ?? ""
    guard let child = dict["child"].flatMap({ parseViewNodeFromYaml($0) }) else { return nil }
    return .foreach(items: items, child: child, common: common)

  case "if":
    let condition = dict["condition"]?.string ?? ""
    guard let thenNode = dict["then"].flatMap({ parseViewNodeFromYaml($0) }) else { return nil }
    let elseNode = dict["else"].flatMap { parseViewNodeFromYaml($0) }
    return .if(condition: condition, then: thenNode, else: elseNode, common: common)

  case "progress":
    let value =
      dict["value"]?.string ?? dict["value"]?.double.map { "\($0)" }
      ?? dict["value"]?.int.map { "\($0)" } ?? "0"
    let color = dict["color"]?.string
    let trackColor = dict["trackColor"]?.string
    let style = dict["style"]?.string.flatMap { ProgressStyle(rawValue: $0) }
    return .progress(
      value: value, color: color, trackColor: trackColor, style: style, common: common)

  case "gauge":
    let value =
      dict["value"]?.string ?? dict["value"]?.double.map { "\($0)" }
      ?? dict["value"]?.int.map { "\($0)" } ?? "0"
    let min = yamlDouble(dict["min"])
    let max = yamlDouble(dict["max"])
    let label = dict["label"]?.string
    let color = dict["color"]?.string
    return .gauge(value: value, min: min, max: max, label: label, color: color, common: common)

  case "badge":
    let content = fixYamlUnicodeEscapes(dict["content"]?.string ?? "")
    let color = dict["color"]?.string
    let textColor = dict["textColor"]?.string
    return .badge(content: content, color: color, textColor: textColor, common: common)

  case "grid":
    let columns = dict["columns"]?.int ?? 2
    let spacing = yamlDouble(dict["spacing"])
    let children = dict["children"]?.array?.compactMap { parseViewNodeFromYaml($0) } ?? []
    return .grid(columns: columns, spacing: spacing, children: children, common: common)

  default:
    return nil
  }
}

/// Extract a Double from a Yaml value (int or double).
private func yamlDouble(_ yaml: Yaml?) -> Double? {
  if let d = yaml?.double { return d }
  if let i = yaml?.int { return Double(i) }
  return nil
}

/// Parse a Padding value from Yaml (uniform number or [t, l, b, r] array).
private func yamlPadding(_ yaml: Yaml?) -> Padding? {
  if let d = yaml?.double { return .uniform(d) }
  if let i = yaml?.int { return .uniform(Double(i)) }
  if let arr = yaml?.array, arr.count == 4 {
    let values = arr.map { yamlDouble($0) ?? 0.0 }
    return .edges(top: values[0], leading: values[1], bottom: values[2], trailing: values[3])
  }
  return nil
}

/// Parse common node properties from a YAML dictionary.
private func parseCommonNodeProperties(from dict: [Yaml: Yaml]) -> CommonNodeProperties {
  let padding = yamlPadding(dict["padding"])

  var frame: FrameProperties?
  if let frameDict = dict["frame"]?.dictionary {
    frame = FrameProperties(
      w: yamlDouble(frameDict["w"]),
      h: yamlDouble(frameDict["h"]),
      maxW: yamlDouble(frameDict["maxW"]),
      maxH: yamlDouble(frameDict["maxH"]),
      minW: yamlDouble(frameDict["minW"]),
      minH: yamlDouble(frameDict["minH"])
    )
  }

  return CommonNodeProperties(
    padding: padding,
    frame: frame,
    opacity: yamlDouble(dict["opacity"]),
    background: dict["background"]?.string,
    cornerRadius: yamlDouble(dict["cornerRadius"]),
    visible: dict["visible"]?.string
  )
}

// MARK: - Load Configuration

func loadConfig(from yaml: Yaml, configDir: String? = nil) -> Config? {
  // Top-level keys (flattened — no "global" wrapper)
  guard let height = yaml["height"].int,
    let padding = yaml["padding"].int
  else {
    print("Failed to load config: missing height or padding")
    return nil
  }

  guard let styleYaml = yaml["style"].dictionary,
    let lightYaml = styleYaml["light"],
    let darkYaml = styleYaml["dark"],
    let lightMode = parseStyleModeConfig(from: lightYaml),
    let darkMode = parseStyleModeConfig(from: darkYaml),
    lightMode.fg != nil, lightMode.bg != nil,
    darkMode.fg != nil, darkMode.bg != nil
  else {
    print("Failed to load config: style.light and style.dark must have fg and bg")
    return nil
  }

  let style = StyleConfig(light: lightMode, dark: darkMode)

  let iconTextSpacing = yaml["iconTextSpacing"].int ?? 5

  let iconFont = yaml["iconFont"].string.map { FontConfig(descriptor: $0) }
  let textFont = yaml["textFont"].string.map { FontConfig(descriptor: $0) }

  let cornerRadius = yamlCGFloat(yaml["cornerRadius"])

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
    let delay = Double(
      yamlCGFloat(autohideYaml["delay"], max: 5, fallback: CGFloat(AutohideConfig.default.delay)))
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

/// `configDir` resolves relative paths (e.g. command scripts).
func parseModuleConfig(from moduleYaml: Yaml, configDir: String? = nil) -> ModuleConfig? {
  var builder = ModuleConfigBuilder()

  guard let name = moduleYaml["name"].string,
    let placement = moduleYaml["placement"].string,
    let type = moduleYaml["type"].string
  else {
    print("Failed to load module config: missing name, placement, or type")
    return nil
  }

  builder.setName(name)
  builder.setPlacement(placement)
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

  if let moduleStyle = parseStyleConfig(from: moduleYaml["style"]) {
    builder.setStyle(moduleStyle)
  }

  if let interactionYaml = moduleYaml["interaction"].dictionary {
    let hover = parseHoverConfig(from: interactionYaml["hover"])
    var click: ClickConfig?
    if let clickYaml = interactionYaml["click"]?.dictionary {
      click = parseClickConfig(from: clickYaml)
    }
    builder.setInteraction(InteractionConfig(hover: hover, click: click))
  }

  if let maskYaml = moduleYaml["mask"].dictionary {
    if let index = maskYaml["index"]?.int {
      builder.setMask(MaskConfig(index: index))
    } else if let name = maskYaml["name"]?.string {
      builder.setMask(MaskConfig(name: name))
    }

    if moduleYaml["interaction"]["click"]["type"].string == nil {
      let hover = parseHoverConfig(from: moduleYaml["interaction"]["hover"])
      let click = ClickConfig(type: "passthrough")
      builder.setInteraction(InteractionConfig(hover: hover, click: click))
    }
  }

  // Drawer modules automatically get a click interaction
  if type == "drawer" && moduleYaml["interaction"]["click"]["type"].string == nil {
    builder.setInteraction(
      InteractionConfig(
        hover: nil,
        click: ClickConfig(type: "drawer")
      ))
  }

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

  let yamlFiles =
    entries
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
  let extraRight = extra.filter { $0.placement.isRightSide }
  let extraLeft = extra.filter { !$0.placement.isRightSide }
  let baseRight = base.filter { $0.placement.isRightSide }
  let baseLeft = base.filter { !$0.placement.isRightSide }
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
      let scalar = Unicode.Scalar(codepoint)
    {
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
    print("Error loading file \(filePath): \(error)")
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
      let rgb = defaultColor.usingColorSpace(.deviceRGB) ?? NSColor.clear
      self.init(
        red: rgb.redComponent, green: rgb.greenComponent, blue: rgb.blueComponent,
        alpha: rgb.alphaComponent)
    }
  }
}
