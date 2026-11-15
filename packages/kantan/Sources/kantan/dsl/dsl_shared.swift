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
  /// Resolution order:
  /// 1. Innermost foreach scope (top of stack)
  /// 2. Outer foreach scopes (walking down the stack)
  /// 3. Top-level `variables` map
  ///
  /// A substituted value is used as it is, except that `{theme(name)}`
  /// templates within it resolve against the palette, so a variable can hold
  /// one. A theme template the palette can't resolve is kept as written.
  func resolve(_ template: String) -> String {
    replacePlaceholders(in: template) { key, _ in
      replacePlaceholders(in: lookupValue(for: key) ?? "") { inner, placeholder in
        inner.hasPrefix("theme(") && inner.hasSuffix(")")
          ? fallbackResolver?(inner) ?? placeholder : placeholder
      }
    }
  }

  /// `template` with each `{key}` placeholder replaced by
  /// `replacement(key, placeholder)`.
  private func replacePlaceholders(
    in template: String, with replacement: (String, String) -> String
  ) -> String {
    var result = ""
    var rest = template[...]
    while let open = rest.firstIndex(of: "{"),
      let close = rest[rest.index(after: open)...].firstIndex(of: "}")
    {
      result += rest[..<open]
      result += replacement(
        String(rest[rest.index(after: open)..<close]), String(rest[open...close]))
      rest = rest[rest.index(after: close)...]
    }
    return result + rest
  }

  /// Resolve a view command's placeholders, each value quoted for where its
  /// placeholder sits: bare, inside single quotes, or inside double quotes.
  /// There, no value can change what the command does. `$'…'` quotes and
  /// command substitutions aren't tracked. An empty bare value leaves
  /// nothing, as it always has. In a URL command
  /// values are percent-encoded. A command that is a single placeholder
  /// is a command the plugin built, and runs as the value, exactly as
  /// written.
  func resolveCommand(_ template: String) -> String {
    let trimmed = template.trimmingCharacters(in: .whitespaces)
    if trimmed.hasPrefix("{"), trimmed.hasSuffix("}"),
      trimmed.dropFirst().firstIndex(where: { $0 == "{" || $0 == "}" })
        == trimmed.index(before: trimmed.endIndex)
    {
      return lookupValue(for: String(trimmed.dropFirst().dropLast())) ?? ""
    }
    if isURLCommand(trimmed) {
      return substitute(template) {
        $1.addingPercentEncoding(withAllowedCharacters: Self.urlValueAllowed) ?? ""
      }
    }
    return substitute(template) { quote, value in
      switch quote {
      case "'": value.replacingOccurrences(of: "'", with: #"'\''"#)
      case "\"":
        value.reduce(into: "") { escaped, char in
          if "\\\"$`".contains(char) { escaped.append("\\") }
          escaped.append(char)
        }
      default: value.isEmpty ? "" : "'" + value.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
      }
    }
  }

  /// Characters a value may keep unencoded in a URL command.
  private static let urlValueAllowed = CharacterSet.urlQueryAllowed.subtracting(
    CharacterSet(charactersIn: "&=+#?"))

  /// Replaces each placeholder in a command with `encode(quote, value)`,
  /// `quote` being the shell quote character the placeholder sits within,
  /// or nil.
  private func substitute(
    _ template: String, encode: (Character?, String) -> String
  ) -> String {
    var result = ""
    var quote: Character?
    var index = template.startIndex
    while index < template.endIndex {
      let char = template[index]
      if char == "{", let close = template[index...].firstIndex(of: "}") {
        result += encode(quote, resolve(String(template[index...close])))
        index = template.index(after: close)
        continue
      }
      result.append(char)
      if char == "\\", quote != "'", template.index(after: index) < template.endIndex {
        index = template.index(after: index)
        result.append(template[index])
      } else if char == "'" || char == "\"" {
        quote = quote == nil ? char : (quote == char ? nil : quote)
      }
      index = template.index(after: index)
    }
    return result
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

/// How many columns a grid with `columns` has: 2 by default, and at least 1.
func dslGridColumnCount(_ columns: Int?) -> Int {
  max(1, columns ?? 2)
}

/// The point size of an icon `size` points tall scaled by `scale`, rounded,
/// between 1 and 1000.
func dslScaledFontSize(_ size: Double, scale: Double) -> Int {
  let scaled = size * scale
  guard scaled.isFinite else { return 13 }
  return Int(round(min(max(scaled, 1), 1000)))
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
  let resolved = resolver.resolve("{\(condition)}").lowercased()
  return !resolved.isEmpty && resolved != "0" && resolved != "false" && resolved != "no"
}
