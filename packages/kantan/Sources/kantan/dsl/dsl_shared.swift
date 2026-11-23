import Foundation
import SwiftUI

// MARK: - Template Resolver

/// Resolves `{key}` interpolation in template strings against a variable scope stack.
///
/// The resolver maintains a stack of scopes for `foreach` nesting. When resolving
/// a template, it walks the stack top-down (innermost scope first), then falls back
/// to the top-level `variables` map.
class TemplateResolver {
  var variables: [String: String]
  let data: [String: [[String: String]]]
  private(set) var scopeStack: [[String: String]] = []
  /// Optional fallback for resolving keys not found in variables/scopes
  /// (e.g. `theme(name)` patterns resolved via ThemeProvider).
  var fallbackResolver: ((String) -> String?)?
  /// Variables for the commands a view runs, such as the module's
  /// `KANTAN_SETTINGS`.
  var commandEnvironment: [String: String] = [:]

  init(variables: [String: String], data: [String: [[String: String]]]) {
    self.variables = variables
    self.data = data
  }

  /// Push a foreach element's key-value pairs onto the scope stack.
  func pushScope(_ element: [String: String]) {
    scopeStack.append(element)
  }

  /// A copy of this resolver, with its fallback and command environment,
  /// and `element` pushed as the innermost scope.
  func scoped(with element: [String: String]) -> TemplateResolver {
    let copy = TemplateResolver(variables: variables, data: data)
    copy.scopeStack = scopeStack + [element]
    copy.fallbackResolver = fallbackResolver
    copy.commandEnvironment = commandEnvironment
    return copy
  }

  /// Pop the most recent foreach scope.
  func popScope() {
    if !scopeStack.isEmpty {
      scopeStack.removeLast()
    }
  }

  /// Resolve `{key}` placeholders in a template string.
  ///
  /// A brace pair is a placeholder when a variable of that name exists, or
  /// when what it holds has the shape of a name (`isName`). One with a name
  /// nothing defines comes to nothing. Any other brace is text, and stays
  /// as written: `awk '{print $2}'` keeps its braces.
  ///
  /// Resolution order:
  /// 1. Innermost foreach scope (top of stack)
  /// 2. Outer foreach scopes (walking down the stack)
  /// 3. Top-level `variables` map
  ///
  /// A substituted value is used as it is, except that `{theme(name)}`
  /// templates within it resolve against the palette, so a variable can hold
  /// one. A theme template the palette can't resolve is kept as written.
  func resolve(_ template: String) -> String {
    Self.filling(template, with: placeholderValue)
  }

  /// The value of the variable `key`, with the theme templates within it
  /// resolved, or nothing when no variable has that name.
  func value(of key: String) -> String {
    guard let value = lookupValue(for: key) else { return "" }
    return Self.filling(value) { inner in
      inner.hasPrefix("theme(") && inner.hasSuffix(")") ? fallbackResolver?(inner) : nil
    }
  }

  /// What the placeholder `{key}` comes to, or nil when `{key}` isn't one.
  private func placeholderValue(_ key: String) -> String? {
    lookupValue(for: key) != nil || Self.isName(key) ? value(of: key) : nil
  }

  /// Whether `key` has the shape of a variable's name: a letter or `_`,
  /// then letters, digits, `_`, `.` and `-`, all of them ASCII.
  static func isName(_ key: String) -> Bool {
    let letter = { (scalar: Unicode.Scalar) in
      ("a"..."z").contains(scalar) || ("A"..."Z").contains(scalar) || scalar == "_"
    }
    guard let first = key.unicodeScalars.first, letter(first) else { return false }
    return key.unicodeScalars.allSatisfy {
      letter($0) || ("0"..."9").contains($0) || $0 == "." || $0 == "-"
    }
  }

  /// What the `{` at `open` holds when the next brace after it is a `}`,
  /// with where that pair ends. Braces are read by scalar, as the shell
  /// reads them: one with a combining mark after it is still a brace.
  private static func bracePair(
    in scalars: String.UnicodeScalarView, at open: String.UnicodeScalarView.Index
  ) -> (key: String, end: String.UnicodeScalarView.Index)? {
    let start = scalars.index(after: open)
    var index = start
    while index < scalars.endIndex {
      if scalars[index] == "}" {
        return (String(scalars[start..<index]), scalars.index(after: index))
      }
      if scalars[index] == "{" { return nil }
      index = scalars.index(after: index)
    }
    return nil
  }

  /// `template` with each brace pair `fill` gives a value for replaced by
  /// that value. A brace it gives none for is left where it is, and what
  /// follows it is read on.
  private static func filling(_ template: String, with fill: (String) -> String?) -> String {
    let scalars = template.unicodeScalars
    var result = String.UnicodeScalarView()
    var index = scalars.startIndex
    while index < scalars.endIndex {
      if scalars[index] == "{", let pair = bracePair(in: scalars, at: index),
        let value = fill(pair.key)
      {
        result.append(contentsOf: value.unicodeScalars)
        index = pair.end
        continue
      }
      result.append(scalars[index])
      index = scalars.index(after: index)
    }
    return String(result)
  }

  /// Resolve a view command's placeholders, each value quoted for where its
  /// placeholder sits: bare, inside single quotes, or inside double quotes.
  /// There, no value can change what the command does. A `$` straight
  /// before a bare or double-quoted placeholder is dropped, as it would
  /// have the shell expand the value. `$'…'` quotes and command
  /// substitutions aren't tracked. An empty bare value leaves nothing, as
  /// it always has. In a URL command values are percent-encoded. A command
  /// that is a single placeholder is a command the plugin built, and runs
  /// as the value, exactly as written. Braces that aren't placeholders are
  /// the command's own, and stay as written.
  func resolveCommand(_ template: String) -> String {
    let trimmed = template.trimmingCharacters(in: .whitespaces)
    let scalars = trimmed.unicodeScalars
    if scalars.first == "{", let pair = Self.bracePair(in: scalars, at: scalars.startIndex),
      pair.end == scalars.endIndex, lookupValue(for: pair.key) != nil || Self.isName(pair.key)
    {
      return lookupValue(for: pair.key) ?? ""
    }
    if isURLCommand(trimmed) {
      return substitute(template) {
        $1.addingPercentEncoding(withAllowedCharacters: Self.urlValueAllowed) ?? ""
      }
    }
    return substitute(template) { quote, value in
      switch quote {
      case "'": shellSingleQuoteEscaped(value)
      case "\"":
        // By scalar: a quote with a combining mark after it is one
        // character to Swift, and still a quote to the shell.
        String(
          value.unicodeScalars.reduce(into: String.UnicodeScalarView()) { escaped, scalar in
            if "\\\"$`".unicodeScalars.contains(scalar) { escaped.append("\\") }
            escaped.append(scalar)
          })
      default: value.isEmpty ? "" : "'" + shellSingleQuoteEscaped(value) + "'"
      }
    }
  }

  /// Characters a value keeps unencoded in a URL command: the ones a URL
  /// gives no meaning, so a value can't add a host, a port or a path
  /// segment.
  private static let urlValueAllowed = CharacterSet(
    charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

  /// Replaces each placeholder in a command with `encode(quote, value)`,
  /// `quote` being the shell quote character the placeholder sits within,
  /// or nil. A `$` that would expand a bare or double-quoted placeholder's
  /// value is left out. The command is read by scalar, as the shell reads
  /// it.
  private func substitute(
    _ template: String, encode: (Unicode.Scalar?, String) -> String
  ) -> String {
    let scalars = template.unicodeScalars
    var result = String.UnicodeScalarView()
    var quote: Unicode.Scalar?
    // Whether the last scalar is a `$` the shell would expand with what
    // follows: not escaped, and not the second of a `$$`.
    var expands = false
    var index = scalars.startIndex
    while index < scalars.endIndex {
      let scalar = scalars[index]
      if scalar == "{", let pair = Self.bracePair(in: scalars, at: index),
        let value = placeholderValue(pair.key)
      {
        if expands, quote != "'" { result.removeLast() }
        expands = false
        result.append(contentsOf: encode(quote, value).unicodeScalars)
        index = pair.end
        continue
      }
      result.append(scalar)
      expands = scalar == "$" && !expands
      let next = scalars.index(after: index)
      if scalar == "\\", quote != "'", next < scalars.endIndex {
        result.append(scalars[next])
        index = next
      } else if scalar == "'" || scalar == "\"" {
        quote = quote == nil ? scalar : (quote == scalar ? nil : quote)
      }
      index = scalars.index(after: index)
    }
    return String(result)
  }

  /// Resolve a template string to a boolean value.
  ///
  /// Returns `true` if the resolved string is "true", "1", "yes", or a non-empty
  /// string that isn't "false", "0", or "no".
  ///
  /// Canonical forms produced by `dslCanonicalBool(_:)` ("true"/"false") and
  /// `dslCanonicalNumber(_:)` (decimal digits, no trailing ".0" for integer
  /// values) always round-trip correctly through this function.
  func resolveBool(_ template: String) -> Bool {
    let resolved = resolve(template).lowercased().trimmingCharacters(in: .whitespaces)
    switch resolved {
    case "true", "1", "yes":
      return true
    case "false", "0", "no", "":
      return false
    default:
      return !resolved.isEmpty
    }
  }

  private func lookupValue(for key: String) -> String? {
    for scope in scopeStack.reversed() {
      if let value = scope[key] {
        return value
      }
    }
    if let value = variables[key] { return value }
    return fallbackResolver?(key)
  }
}

// MARK: - Sizes

/// The width of a progress ring's stroke when it gives none, in points.
let dslRingStrokeWidth = 4.0

/// The least width and height of a `plain` button's click area, in points.
let dslPlainButtonSize: CGFloat = 24

/// How many columns a grid with `columns` has: 2 by default, and at least 1.
func dslGridColumnCount(_ columns: Int?) -> Int {
  max(1, columns ?? 2)
}

/// The furthest from zero, in points, a view's size, spacing or padding
/// goes.
let dslMaxLength: Double = 10_000

/// `value` as a length a view can lay out: no further than `dslMaxLength`
/// from zero, and none when it isn't a finite number.
func dslLength(_ value: Double?) -> CGFloat? {
  guard let value, value.isFinite else { return nil }
  return CGFloat(min(max(value, -dslMaxLength), dslMaxLength))
}

/// The point size of an icon `size` points tall scaled by `scale`, rounded,
/// between 1 and 1000.
func dslScaledFontSize(_ size: Double, scale: Double) -> Int {
  let scaled = size * scale
  guard scaled.isFinite else { return 13 }
  return Int(round(min(max(scaled, 1), 1000)))
}

// MARK: - File Images

/// Images read from files on this Mac, by path and modification date.
nonisolated(unsafe) private let dslFileImages: NSCache<NSString, NSImage> = {
  let cache = NSCache<NSString, NSImage>()
  cache.countLimit = 32
  return cache
}()

/// The image in the regular file at `url`, or the one a symlink there leads
/// to, read again only once the file has changed. Anything but a regular
/// file, such as a pipe, is no image.
func dslFileImage(at url: URL) -> NSImage? {
  let url = url.resolvingSymlinksInPath()
  guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
    attributes[.type] as? FileAttributeType == .typeRegular,
    let modified = attributes[.modificationDate] as? Date
  else { return nil }
  let key = "\(modified.timeIntervalSinceReferenceDate) \(url.path)" as NSString
  if let image = dslFileImages.object(forKey: key) { return image }
  guard let image = NSImage(contentsOf: url) else { return nil }
  dslFileImages.setObject(image, forKey: key)
  return image
}

// MARK: - Gauge Range

/// The range a gauge spans: `min` (default 0) to `max` (default 1), in
/// whichever order they come, with a bound that isn't finite taking its
/// default.
func dslGaugeRange(min: Double?, max: Double?) -> ClosedRange<Double> {
  let lower = min.flatMap { $0.isFinite ? $0 : nil } ?? 0
  let upper = max.flatMap { $0.isFinite ? $0 : nil } ?? 1
  return Swift.min(lower, upper)...Swift.max(lower, upper)
}

// MARK: - Color Parsing

/// Parse a hex color string (with or without leading `#`) into a SwiftUI `Color`.
///
/// Accepts 6-char `RRGGBB` or 8-char `RRGGBBAA`. Returns nil for any other length
/// or for non-hex content.
func dslColorFromHex(_ hex: String) -> Color? {
  let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
  guard let value = UInt64(cleaned, radix: 16) else { return nil }
  switch cleaned.count {
  case 6:
    let r = Double((value & 0xFF0000) >> 16) / 255.0
    let g = Double((value & 0x00FF00) >> 8) / 255.0
    let b = Double(value & 0x0000FF) / 255.0
    return Color(red: r, green: g, blue: b)
  case 8:
    let r = Double((value & 0xFF00_0000) >> 24) / 255.0
    let g = Double((value & 0x00FF_0000) >> 16) / 255.0
    let b = Double((value & 0x0000_FF00) >> 8) / 255.0
    let a = Double(value & 0x0000_00FF) / 255.0
    return Color(red: r, green: g, blue: b, opacity: a)
  default:
    return nil
  }
}

// MARK: - Canonical String Normalisation

/// Canonical string form for a boolean carried through the type-erased DSL
/// pipeline (e.g. JSON/YAML `checked:`, `on:`, `condition:` operands).
///
/// Always returns `"true"` or `"false"` — the tokens `TemplateResolver`
/// recognises in `resolveBool` and `dslEvaluateTruthy`. Pin this contract so
/// every entry point that erases a boolean to a string produces the same shape.
func dslCanonicalBool(_ value: Bool) -> String {
  value ? "true" : "false"
}

/// Canonical string form for a numeric value carried through the DSL pipeline
/// (e.g. JSON/YAML `progress.value:`, `gauge.value:`).
///
/// Integer-valued doubles render without a trailing `".0"`; everything else
/// uses Swift's default `Double` description. The result is always parseable
/// by `Double.init(_:)`, which is how downstream renderers consume it.
func dslCanonicalNumber(_ value: Double) -> String {
  guard value.isFinite else { return String(value) }
  if value == value.rounded(), let int = Int(exactly: value) {
    return String(int)
  }
  return String(value)
}

// MARK: - Condition Evaluation

/// Evaluate a template-style condition as a truthy boolean.
///
/// Wraps the condition in `{…}`, resolves it through the resolver, then applies
/// the standard truthy rules (non-empty, not `0`/`false`/`no`). Unknown variables
/// resolve to the empty string and therefore read as falsy.
func dslEvaluateTruthy(_ condition: String, resolver: TemplateResolver) -> Bool {
  let resolved = resolver.value(of: condition).lowercased()
  return !resolved.isEmpty && resolved != "0" && resolved != "false" && resolved != "no"
}
