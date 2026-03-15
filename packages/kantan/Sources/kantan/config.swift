import AppKit
import CoreText
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
  let theme: ThemeConfig?
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

  /// Whether this config requires the bundled tabler-icons fonts.
  /// True when the global icon font is unset (defaults to tabler-icons)
  /// or any font config in the hierarchy uses a bundled (non-system) source.
  var needsBundledIconFonts: Bool {
    // Global icon font unset → defaults to bundled tabler-icons
    guard let globalIconFont = iconFont else { return true }
    // Global icon font is bundled
    if globalIconFont.source == .bundled { return true }
    // Check per-module overrides: any explicit bundled icon font means we need them.
    // Modules with nil iconFont inherit the global (which is system here), so skip those.
    return modules.contains { $0.iconFont?.source == .bundled }
  }

  /// Native appearance when no theme and no explicit style colours.
  var isNativeAppearance: Bool {
    theme == nil && style.light?.fg == nil && style.dark?.fg == nil
  }
}

/// Where a font is loaded from.
enum FontSource: Codable, Sendable {
  /// System-installed font (resolved via NSFontDescriptor).
  case system
  /// Bundled font shipped in share/fonts/ alongside the kantan binary.
  case bundled
}

struct FontConfig: Codable {
  let descriptor: String
  let source: FontSource

  init(descriptor: String, source: FontSource = .bundled) {
    self.descriptor = descriptor
    self.source = source
  }

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

  /// Parses a weight string into an NSFont.Weight.
  /// Returns nil if the string is not a recognised weight name.
  private static func parseWeight(_ s: String) -> NSFont.Weight? {
    switch s.lowercased() {
    case "ultralight": return .ultraLight
    case "thin": return .thin
    case "light": return .light
    case "regular": return .regular
    case "medium": return .medium
    case "semibold", "demi-bold": return .semibold
    case "bold": return .bold
    case "heavy", "extrabold": return .heavy
    case "black": return .black
    default: return nil
    }
  }

  /// Supports "Name:Size", "Name:Weight:Size", or just "Name".
  /// When there are two components and the second is numeric, it is
  /// treated as the size (weight defaults to regular).
  var weight: NSFont.Weight {
    guard components.count > 1 else { return .regular }
    if components.count == 2 {
      // Two components: could be Name:Weight or Name:Size.
      // If the second parses as a number it is the size, not a weight.
      if Double(components[1]) != nil { return .regular }
    }
    return Self.parseWeight(components[1]) ?? .regular
  }

  var size: CGFloat {
    if components.count == 2 {
      // Two components: second may be a size (Name:Size) or a weight (Name:Weight).
      if let s = Double(components[1]) { return CGFloat(s) }
      return Self.defaultSize
    }
    guard components.count > 2 else { return Self.defaultSize }
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

// MARK: - Bundled Font Registration

/// Resolves the share/fonts/ directory relative to the kantan binary.
/// The binary lives at <prefix>/bin/kantan; fonts are at <prefix>/share/fonts/.
/// Resolves symlinks so it works with nix-built wrappers.
func bundledFontsDirectory() -> URL? {
  let execURL = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
  // <prefix>/bin/kantan -> <prefix>/share/fonts
  let prefixURL = execURL.deletingLastPathComponent().deletingLastPathComponent()
  let fontsDir = prefixURL.appendingPathComponent("share/fonts")
  guard FileManager.default.fileExists(atPath: fontsDir.path) else { return nil }
  return fontsDir
}

/// Registers all .ttf fonts found in the bundled fonts directory with CoreText.
/// Called once at startup so bundled fonts become available via NSFont/CTFont by name.
/// Guarded by `bundledFontsRegistered` to avoid redundant registration on hot-reload.
nonisolated(unsafe) private var bundledFontsRegistered = false

func registerBundledFonts() {
  guard !bundledFontsRegistered else { return }
  guard let fontsDir = bundledFontsDirectory() else {
    print("No bundled fonts directory found")
    return
  }

  let fm = FileManager.default
  guard let enumerator = fm.enumerator(at: fontsDir, includingPropertiesForKeys: nil) else {
    return
  }

  for case let fileURL as URL in enumerator where fileURL.pathExtension == "ttf" {
    var errorRef: Unmanaged<CFError>?
    let success = CTFontManagerRegisterFontsForURL(
      fileURL as CFURL, .process, &errorRef)
    if !success {
      let error = errorRef?.takeRetainedValue()
      print(
        "Failed to register font \(fileURL.lastPathComponent): \(error.map { "\($0)" } ?? "unknown error")"
      )
    }
  }

  bundledFontsRegistered = true
}

/// Parses a font descriptor string, extracting the source prefix if present.
/// Format: "system:FontName:Weight:Size" or "FontName:Weight:Size" (bundled by default).
func parseFontDescriptor(_ raw: String) -> FontConfig {
  if raw.hasPrefix("system:") {
    let rest = String(raw.dropFirst("system:".count))
    return FontConfig(descriptor: rest, source: .system)
  }
  return FontConfig(descriptor: raw, source: .bundled)
}

// MARK: - Icon Resolution

/// A resolved icon: either a named icon from a bundled font (with font info)
/// or a literal glyph string.
struct ResolvedIcon {
  /// The character(s) to render.
  let glyph: String
  /// If non-nil, override the module's icon font family name (e.g. "tabler-icons-filled").
  /// The size is inherited from the module's configured icon font.
  let fontNameOverride: String?
  /// Multiplier to apply to the configured font size so that the glyph's
  /// visual height fills a consistent proportion of the em square.
  /// 1.0 means no adjustment (glyph already fills the target area).
  let scaleFactor: CGFloat
}

private let outlineFontFamily = "tabler-icons"
private let filledFontFamily = "tabler-icons-filled"
private let filledSuffix = "-filled"

/// Maps icon glyph names (e.g. "bell") to their resolved Unicode scalar,
/// font family, and dynamic scale factor. Built once at startup from the
/// bundled font cmap tables.
/// Outline icons are keyed by their glyph name; filled icons are keyed
/// with a "-filled" suffix (e.g. "bell-filled").
nonisolated(unsafe) private var iconNameMap:
  [String: (scalar: Unicode.Scalar, font: String, scaleFactor: CGFloat)] = [:]
nonisolated(unsafe) private var _iconFontsInitialized = false

/// Whether the bundled icon fonts have been registered and the icon name map
/// has been built. When false, `resolveIconName()` will pass names through as-is
/// (no font override, no glyph mapping).
var iconFontsAvailable: Bool { _iconFontsInitialized }

/// Builds the icon name lookup table from the bundled icon fonts' cmap tables.
/// Registers bundled fonts first if not already done. Guarded to run at most once.
///
/// For each glyph, measures its bounding box to compute a scale factor that
/// normalises visual height across glyphs with different proportions within
/// the em square. The target is for each glyph's visual height to fill
/// ~85% of the em square; glyphs already at or above that get scaleFactor 1.0.
func initIconFonts() {
  guard !_iconFontsInitialized else { return }
  registerBundledFonts()
  _iconFontsInitialized = true

  // Reference size used for bounding box measurement. The actual value
  // doesn't matter because we compute ratios, but a reasonable size
  // avoids floating-point noise.
  let refSize: CGFloat = 100

  // Target: glyph visual height should be this fraction of the em square.
  let targetRatio: CGFloat = 0.85

  // Cap the scale factor to avoid blowing up extremely tiny decorative glyphs.
  let maxScale: CGFloat = 1.6

  func buildMap(fontFamily: String, suffix: String) {
    let ctFont = CTFontCreateWithName(fontFamily as CFString, refSize, nil)
    let glyphCount = CTFontGetGlyphCount(ctFont)
    guard glyphCount > 0 else { return }

    // Build a reverse map: glyphID → codepoint, from the font's character set.
    var glyphToScalar: [CGGlyph: Unicode.Scalar] = [:]
    if let charset = CTFontCopyCharacterSet(ctFont) as? CharacterSet {
      for plane: UInt8 in 0...16 {
        guard charset.hasMember(inPlane: plane) else { continue }
        let base = UInt32(plane) << 16
        for cp in base...(base + 0xFFFF) {
          guard let scalar = Unicode.Scalar(cp), charset.contains(scalar) else { continue }
          let utf16 = Array(String(scalar).utf16)
          var glyphs = [CGGlyph](repeating: 0, count: utf16.count)
          if CTFontGetGlyphsForCharacters(ctFont, utf16, &glyphs, utf16.count) {
            glyphToScalar[glyphs[0]] = scalar
          }
        }
      }
    }

    let targetHeight = refSize * targetRatio

    // Map each glyph's PostScript name to its codepoint and scale factor.
    for glyphID in 0..<CGGlyph(glyphCount) {
      guard let nameRef = CTFontCopyNameForGlyph(ctFont, glyphID),
        let scalar = glyphToScalar[glyphID]
      else { continue }
      let name = nameRef as String
      guard !name.isEmpty, name != ".notdef", name != ".null" else { continue }

      // Measure the glyph's tight bounding box at the reference size.
      var glyph = glyphID
      var bounds = CGRect.zero
      CTFontGetBoundingRectsForGlyphs(ctFont, .default, &glyph, &bounds, 1)

      var scale: CGFloat = 1.0
      if bounds.height > 0 {
        let ratio = targetHeight / bounds.height
        // Only scale up glyphs that are smaller than the target.
        // Glyphs already at or above the target keep scale 1.0.
        if ratio > 1.0 {
          scale = min(ratio, maxScale)
        }
      }

      iconNameMap[name + suffix] = (scalar: scalar, font: fontFamily, scaleFactor: scale)
    }
  }

  buildMap(fontFamily: outlineFontFamily, suffix: "")
  buildMap(fontFamily: filledFontFamily, suffix: filledSuffix)
}

/// Resolves an icon string by looking up its name in the bundled icon fonts.
///
/// Convention:
/// - "bell" → outline icon (glyph name "bell" in tabler-icons font)
/// - "bell-filled" → filled icon (glyph name "bell" in tabler-icons-filled font)
///
/// If the name doesn't match any bundled icon glyph, the raw string is
/// returned as-is (allowing literal Unicode characters to pass through).
func resolveIconName(_ raw: String) -> ResolvedIcon {
  if let entry = iconNameMap[raw] {
    return ResolvedIcon(
      glyph: String(entry.scalar),
      fontNameOverride: entry.font,
      scaleFactor: entry.scaleFactor
    )
  }
  return ResolvedIcon(glyph: raw, fontNameOverride: nil, scaleFactor: 1.0)
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

  // Check for nested light/dark blocks (existing format)
  let light = dict["light"].flatMap { parseStyleModeConfig(from: $0) }
  let dark = dict["dark"].flatMap { parseStyleModeConfig(from: $0) }

  if light != nil || dark != nil {
    return StyleConfig(light: light, dark: dark)
  }

  // Check for flat style block (same values for both modes).
  // Useful with theme templates: style: { fg: "{theme(text)}" }
  let flat = parseStyleModeConfig(from: yaml)
  if flat != nil {
    return StyleConfig(light: flat, dark: flat)
  }

  return nil
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

  // Parse theme (optional)
  var theme: ThemeConfig?
  let themeYaml = yaml["theme"]
  if themeYaml.string != nil || themeYaml.dictionary != nil {
    theme = loadThemeConfig(from: themeYaml, configDir: configDir)
    if theme == nil {
      print("Failed to load theme")
      return nil
    }
  }

  // Parse style — optional when theme is set, required otherwise.
  // Supports both nested (light/dark blocks) and flat (same values for both modes).
  let style: StyleConfig
  if let parsedStyle = parseStyleConfig(from: yaml["style"]) {
    style = parsedStyle
  } else if theme != nil {
    // No explicit style — synthesise from theme palette defaults
    let light = StyleModeConfig(
      fg: theme!.lightPalette.fg, bg: theme!.lightPalette.bg,
      text: nil, icon: nil, shape: nil)
    let dark = StyleModeConfig(
      fg: theme!.darkPalette.fg, bg: theme!.darkPalette.bg,
      text: nil, icon: nil, shape: nil)
    style = StyleConfig(light: light, dark: dark)
  } else if yaml["style"].dictionary != nil {
    // style: was present but couldn't parse — missing fg/bg
    print("Failed to load config: style.light and style.dark must have fg and bg")
    return nil
  } else {
    // No theme, no style — native appearance
    style = StyleConfig(light: nil, dark: nil)
  }

  // When no theme is set and style has values, validate completeness
  if theme == nil && (style.light != nil || style.dark != nil) {
    guard let light = style.light, let dark = style.dark,
      light.fg != nil, light.bg != nil,
      dark.fg != nil, dark.bg != nil
    else {
      print("Failed to load config: style without theme requires light and dark with fg and bg")
      return nil
    }
  }

  let iconTextSpacing = yaml["iconTextSpacing"].int ?? 5

  let fontsYaml = yaml["fonts"]
  let iconFont = fontsYaml["icon"].string.map { parseFontDescriptor($0) }
  let textFont = fontsYaml["text"].string.map { parseFontDescriptor($0) }

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
      if let module = parseModuleConfig(from: moduleYaml, configDir: configDir, theme: theme) {
        modules.append(module)
      }
    }
  }

  return Config(
    theme: theme,
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

/// Default module-level icons (tabler-icons) applied when the user
/// doesn't specify an `icon:` field. Only modules that need a
/// default display icon are listed here.
private let defaultModuleIcons: [String: String] = [
  "focus": "brain"
]

/// `configDir` resolves relative paths (e.g. command scripts).
func parseModuleConfig(from moduleYaml: Yaml, configDir: String? = nil, theme: ThemeConfig? = nil)
  -> ModuleConfig?
{
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
  } else if let defaultIcon = defaultModuleIcons[type] {
    builder.setIcon(defaultIcon)
  }

  let moduleFontsYaml = moduleYaml["fonts"]
  if let textFontDescriptor = moduleFontsYaml["text"].string {
    builder.setTextFont(parseFontDescriptor(textFontDescriptor))
  }

  if let iconFontDescriptor = moduleFontsYaml["icon"].string {
    builder.setIconFont(parseFontDescriptor(iconFontDescriptor))
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
    try builder.buildConfiguration(from: moduleYaml["config"], configDir: configDir, theme: theme)
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
func loadModulesFromDirectory(path: String, theme: ThemeConfig? = nil) -> [ModuleConfig] {
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
      if let module = parseModuleConfig(from: yaml, configDir: path, theme: theme) {
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
