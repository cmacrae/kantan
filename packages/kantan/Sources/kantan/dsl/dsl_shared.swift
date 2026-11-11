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
  /// Placeholders within a substituted value are resolved in turn, up to
  /// `maxResolveDepth` levels. A value that resolves to its own placeholder,
  /// such as an unknown `{theme(name)}`, is kept as written.
  func resolve(_ template: String) -> String {
    resolve(template, depth: 0)
  }

  /// How many levels of placeholders within substituted values are resolved.
  static let maxResolveDepth = 8

  private func resolve(_ template: String, depth: Int) -> String {
    var result = ""
    var rest = template[...]
    while let open = rest.firstIndex(of: "{"),
      let close = rest[rest.index(after: open)...].firstIndex(of: "}")
    {
      result += rest[..<open]
      let placeholder = rest[open...close]
      let key = String(rest[rest.index(after: open)..<close])
      let value = lookupValue(for: key) ?? ""
      result +=
        value == placeholder || depth >= Self.maxResolveDepth
        ? value : resolve(value, depth: depth + 1)
      rest = rest[rest.index(after: close)...]
    }
    return result + rest
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
