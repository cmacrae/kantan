import Foundation

/// A colour a style resolves to: one a config or plugin wrote, or one the
/// system supplies for the native appearance.
enum StyleColor: Equatable, Sendable {
  /// A colour as written, once any theme template in it is resolved:
  /// `RRGGBB` or `RRGGBBAA` hex. Anything else draws as no colour.
  case value(String)
  /// The system's text colour.
  case label
  /// No colour.
  case clear
}

/// Resolves the bar's and each module's colours and shape for one
/// appearance of a config.
struct StyleResolver {
  let config: Config
  let isDark: Bool

  var isNative: Bool { config.isNativeAppearance }

  /// The theme's palette for the appearance.
  var palette: ThemePalette? {
    guard let theme = config.theme else { return nil }
    return isDark ? theme.darkPalette : theme.lightPalette
  }

  /// `value` with a `{theme(name)}` template resolved against the palette,
  /// or as written when it isn't one or there's no palette.
  func resolve(_ value: String) -> String {
    guard let palette else { return value }
    return resolveThemeTemplate(value, palette: palette)
  }

  /// Whether `value` is a `{theme(...)}` template with no palette to
  /// resolve it, as in the native appearance.
  func isUnresolvableTemplate(_ value: String) -> Bool {
    palette == nil && value.hasPrefix("{theme(") && value.hasSuffix(")}")
  }

  /// The bar's style for the appearance, or the other appearance's when it
  /// has none.
  var globalMode: StyleModeConfig {
    let style = config.style
    return (isDark ? style.dark ?? style.light : style.light ?? style.dark) ?? Self.defaultMode
  }

  private static let defaultMode = StyleModeConfig(
    fg: "FFFFFF", bg: "000000", text: nil, icon: nil, shape: nil)

  /// A module's style for the appearance.
  func moduleMode(_ style: StyleConfig?) -> StyleModeConfig? {
    isDark ? style?.dark : style?.light
  }

  /// The bar's configured text colour, whatever the appearance.
  var globalFg: String { resolve(globalMode.fg ?? "FFFFFF") }

  /// The bar's configured background colour, whatever the appearance.
  var globalBg: String { resolve(globalMode.bg ?? "000000") }

  /// The bar's text colour: the system's when native.
  var barFg: StyleColor { isNative ? .label : .value(globalFg) }

  /// The bar's background colour: none when native.
  var barBg: StyleColor { isNative ? .clear : .value(globalBg) }

  /// An element's colour: the plugin's for the element, then the plugin's
  /// `fg`, the module's for the element, the module's `fg`, and the bar's.
  /// A plugin's theme template that no palette resolves is passed over.
  private func elementFg(
    style: StyleConfig?, dynamic: DynamicStyleOverride?,
    dynamicFg: KeyPath<DynamicStyleOverride, String?>,
    elementFg: KeyPath<StyleModeConfig, ElementStyle?>
  ) -> StyleColor {
    let dynamicCandidates: [String?] = [dynamic?[keyPath: dynamicFg], dynamic?.fg]
    if let fg = dynamicCandidates.compactMap({ $0 }).first(where: { !isUnresolvableTemplate($0) }) {
      return .value(resolve(fg))
    }
    if isNative { return .label }

    let mode = moduleMode(style)
    let staticCandidates: [String?] = [
      mode?[keyPath: elementFg]?.fg,
      mode?.fg,
      globalMode[keyPath: elementFg]?.fg,
      globalMode.fg,
    ]
    return .value(resolve(staticCandidates.compactMap({ $0 }).first ?? "FFFFFF"))
  }

  /// The colour of a module's icon.
  func iconFg(style: StyleConfig?, dynamic: DynamicStyleOverride?) -> StyleColor {
    elementFg(style: style, dynamic: dynamic, dynamicFg: \.iconFg, elementFg: \.icon)
  }

  /// The colour of a module's value.
  func textFg(style: StyleConfig?, dynamic: DynamicStyleOverride?) -> StyleColor {
    elementFg(style: style, dynamic: dynamic, dynamicFg: \.textFg, elementFg: \.text)
  }

  /// A value segment's own colour, or nil for it to take the value's. The
  /// native appearance colours every segment alike.
  func segmentFg(_ fg: String?) -> StyleColor? {
    guard let fg, !isNative, !isUnresolvableTemplate(fg) else { return nil }
    return .value(resolve(fg))
  }

  /// A module's shape: a plugin's override, or the module's style's.
  func shape(style: StyleConfig?, dynamic: DynamicStyleOverride?) -> ModuleShape? {
    switch dynamic?.shape {
    case .unshaped: return nil
    case .shaped(let shape): return shape
    case nil: return moduleMode(style)?.shape
    }
  }

  /// The colour of a module's shape: the plugin's, the module's, the
  /// palette's shape colour so the shape shows against the bar, then the
  /// bar's background.
  func bg(style: StyleConfig?, dynamic: DynamicStyleOverride?) -> StyleColor {
    if let bg = dynamic?.bg, !bg.isEmpty, !isUnresolvableTemplate(bg) {
      return .value(resolve(bg))
    }
    if isNative { return .clear }
    if let bg = moduleMode(style)?.bg { return .value(resolve(bg)) }
    if shape(style: style, dynamic: dynamic) != nil, let shapeBg = palette?.shape {
      return .value(shapeBg)
    }
    return .value(globalBg)
  }
}

/// `template` as a plain tooltip shows it: `{value}`, `{icon}` and each
/// variable filled in, and any other placeholder left as written.
func plainTooltipText(
  _ template: String, value: String?, icon: String?, variables: [String: String]
) -> String {
  var result = template
  if let value {
    result = result.replacingOccurrences(of: "{value}", with: value)
  }
  if let icon {
    result = result.replacingOccurrences(of: "{icon}", with: icon)
  }
  for (key, val) in variables {
    result = result.replacingOccurrences(of: "{\(key)}", with: val)
  }
  return result
}
