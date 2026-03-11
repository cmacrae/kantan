import AppKit
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
  func resolve(_ template: String) -> String {
    var result = template
    // Find all {key} patterns and replace them
    while let openRange = result.range(of: "{") {
      guard let closeRange = result[openRange.upperBound...].range(of: "}") else {
        break
      }
      let key = String(result[openRange.upperBound..<closeRange.lowerBound])
      let replacement = lookupValue(for: key) ?? ""
      result.replaceSubrange(openRange.lowerBound..<closeRange.upperBound, with: replacement)
    }
    return result
  }

  /// Resolve a template string to a boolean value.
  ///
  /// Returns `true` if the resolved string is "true", "1", "yes", or a non-empty
  /// string that isn't "false", "0", or "no".
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
    // Walk scope stack top-down (innermost first)
    for scope in scopeStack.reversed() {
      if let value = scope[key] {
        return value
      }
    }
    // Fall back to top-level variables
    return variables[key]
  }
}

// MARK: - Build Native Menu

/// Convert a `ViewNode` tree into a native `NSMenu`.
///
/// Layout containers (vstack, hstack, zstack, scroll, group) are flattened -- their
/// children are extracted in order. NSMenu is inherently a flat list, so nesting
/// is collapsed. Unsupported node types (shapes, images, progress, gauge, badge,
/// grid, spacer) are silently skipped.
@MainActor
func buildNativeMenu(from rootNode: ViewNode, resolver: TemplateResolver) -> NSMenu {
  let menu = NSMenu()
  menu.autoenablesItems = false
  addItems(from: rootNode, to: menu, resolver: resolver)
  return menu
}

// MARK: - HStack Composition

/// Styling metadata extracted from text/icon children when composing hstack items.
private struct HStackTextPart {
  let text: String
  let isSecondary: Bool
  let isStrikethrough: Bool
}

/// Collect the visible text content from an hstack's children into a single
/// NSMenuItem. The pattern `icon + text + spacer + text` becomes a menu item
/// with a bold label on the left and right-aligned secondary detail on the right.
///
/// Children are split at the first `spacer` node:
/// - Before spacer: label text (bold unless all children are secondary/strikethrough)
/// - After spacer: secondary detail text (right-aligned)
///
/// Text styling (secondary, strikethrough) is propagated from the child nodes
/// so past events etc. render correctly in native menus.
@MainActor
private func addHStackItem(
  children: [ViewNode], command: String? = nil, to menu: NSMenu, resolver: TemplateResolver
) {
  // Separate children at the first spacer, preserving style metadata
  var labelParts: [HStackTextPart] = []
  var detailParts: [HStackTextPart] = []
  var hitSpacer = false
  var indicatorColor: String?

  for child in children {
    switch child {
    case .spacer:
      hitSpacer = true
    case .text(let content, _, _, let style, _, _, let strikethrough, _):
      let resolved = resolver.resolve(content)
      let part = HStackTextPart(
        text: resolved,
        isSecondary: style == .secondary,
        isStrikethrough: strikethrough == true)
      if hitSpacer {
        detailParts.append(part)
      } else {
        labelParts.append(part)
      }
    case .icon(let name, _, _, _, _):
      let resolved = resolver.resolve(name)
      if !resolved.isEmpty {
        let part = HStackTextPart(text: resolved, isSecondary: false, isStrikethrough: false)
        if hitSpacer {
          detailParts.append(part)
        } else {
          labelParts.append(part)
        }
      }
    case .rect(_, _, let color, _, _, _, _):
      // Extract color from rect nodes (e.g. calendar color indicators)
      if let color = color, indicatorColor == nil {
        let resolved = resolver.resolve(color)
        if !resolved.isEmpty {
          indicatorColor = resolved
        }
      }
    case .progress:
      // Skip progress bars in native menus — not representable
      break
    default:
      // Recursively extract text and style from nested layout nodes
      let extracted = extractStyledParts(from: child, resolver: resolver)
      if hitSpacer {
        detailParts.append(contentsOf: extracted)
      } else {
        labelParts.append(contentsOf: extracted)
      }
    }
  }

  let label = labelParts.map(\.text).joined(separator: " ")
  let detail = detailParts.map(\.text).joined(separator: " ")

  guard !label.isEmpty || !detail.isEmpty else { return }

  // Determine overall row styling from children
  let allParts = labelParts + detailParts
  let isSecondary = !allParts.isEmpty && allParts.allSatisfy(\.isSecondary)
  let isStrikethrough = !allParts.isEmpty && allParts.allSatisfy(\.isStrikethrough)

  let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")

  // Use a custom NSHostingView so macOS doesn't apply disabled muting.
  let rowView: NSView
  if !detail.isEmpty {
    let view = NativeMenuRowView(
      label: label, detail: detail, isSecondary: isSecondary, isStrikethrough: isStrikethrough,
      indicatorColor: indicatorColor)
    let hosting = NSHostingView(rootView: view)
    hosting.frame = NSRect(x: 0, y: 0, width: 280, height: 22)
    rowView = hosting
  } else {
    let view = NativeMenuLabelView(
      label: label, isSecondary: isSecondary, isStrikethrough: isStrikethrough,
      indicatorColor: indicatorColor)
    let hosting = NSHostingView(rootView: view)
    hosting.frame = NSRect(x: 0, y: 0, width: 280, height: 22)
    rowView = hosting
  }
  item.view = rowView
  if let command = command {
    let resolvedCommand = resolver.resolve(command)
    let target = NativeMenuTarget {
      runCommand(resolvedCommand)
    }
    item.target = target
    item.action = #selector(NativeMenuTarget.menuAction(_:))
    item.representedObject = target
  }
  menu.addItem(item)
}

/// Recursively extract styled text parts from a node (for composing hstack items).
private func extractStyledParts(from node: ViewNode, resolver: TemplateResolver)
  -> [HStackTextPart]
{
  switch node {
  case .text(let content, _, _, let style, _, _, let strikethrough, _):
    let resolved = resolver.resolve(content)
    guard !resolved.isEmpty else { return [] }
    return [
      HStackTextPart(
        text: resolved, isSecondary: style == .secondary, isStrikethrough: strikethrough == true)
    ]
  case .icon(let name, _, _, _, _):
    let resolved = resolver.resolve(name)
    guard !resolved.isEmpty else { return [] }
    return [HStackTextPart(text: resolved, isSecondary: false, isStrikethrough: false)]
  case .vstack(_, _, _, let children, _),
    .hstack(_, _, _, let children, _, _),
    .group(let children, _):
    return children.flatMap { extractStyledParts(from: $0, resolver: resolver) }
  default:
    return []
  }
}

// MARK: - Condition Evaluation

/// Evaluate a condition string as a variable lookup, matching the SwiftUI
/// renderer's `evaluateCondition`. Wraps the condition in braces so it gets
/// resolved as a variable reference, then checks for truthiness.
private func evaluateCondition(_ condition: String, resolver: TemplateResolver) -> Bool {
  let conditionValue = resolver.resolve("{\(condition)}")
  // If the variable wasn't found, resolve() returns the braces stripped
  // (empty replacement). Check for unresolved patterns.
  if conditionValue.contains("{") && conditionValue.contains("}") {
    return false
  }
  let lowered = conditionValue.lowercased()
  return !lowered.isEmpty && lowered != "0" && lowered != "false" && lowered != "no"
}

// MARK: - Node Classification

/// Returns true if the node is an interactive type that should be its own NSMenuItem.
private func isInteractiveNode(_ node: ViewNode) -> Bool {
  switch node {
  case .action, .check, .toggle, .button:
    return true
  default:
    return false
  }
}

// MARK: - Recursive Item Builder

/// Recursively walk the ViewNode tree and append NSMenuItems to the menu.
@MainActor
private func addItems(from node: ViewNode, to menu: NSMenu, resolver: TemplateResolver) {
  switch node {
  // MARK: Layout nodes -- flatten children (except hstack)

  case .vstack(_, _, _, let children, _),
    .zstack(_, let children, _),
    .scroll(_, let children, _),
    .group(let children, _),
    .grid(_, _, let children, _):
    for child in children {
      addItems(from: child, to: menu, resolver: resolver)
    }

  // MARK: HStack -- compose into a single menu item

  case .hstack(_, _, _, let children, let command, _):
    // Check if hstack contains any interactive nodes — if so, flatten normally
    if children.contains(where: { isInteractiveNode($0) }) {
      for child in children {
        addItems(from: child, to: menu, resolver: resolver)
      }
    } else {
      addHStackItem(children: children, command: command, to: menu, resolver: resolver)
    }

  // MARK: Action

  case .action(let label, let iconGlyph, let command, _, _):
    let resolvedLabel = resolver.resolve(label ?? "")
    var title = resolvedLabel
    if let glyph = iconGlyph {
      let resolvedGlyph = resolver.resolve(glyph)
      if !resolvedGlyph.isEmpty {
        title = "\(resolvedGlyph) \(resolvedLabel)"
      }
    }
    let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
    if let command = command {
      let resolvedCommand = resolver.resolve(command)
      let target = NativeMenuTarget {
        runCommand(resolvedCommand)
      }
      item.target = target
      item.action = #selector(NativeMenuTarget.menuAction(_:))
      item.representedObject = target
    } else {
      item.isEnabled = false
    }
    menu.addItem(item)

  // MARK: Check

  case .check(let label, let checked, let command, _):
    let resolvedLabel = resolver.resolve(label ?? "")
    let isChecked = checked.map { resolver.resolveBool($0) } ?? false
    let resolvedCommand = command.map { resolver.resolve($0) }

    let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")

    // Use a custom NSView so clicking doesn't dismiss the menu.
    // This allows the user to check/uncheck multiple items without
    // the menu closing after each interaction.
    let checkView = NativeMenuCheckItemView(
      label: resolvedLabel, isChecked: isChecked, command: resolvedCommand)
    item.view = checkView
    menu.addItem(item)

  // MARK: Toggle

  case .toggle(let label, let on, let command, _):
    let resolvedLabel = resolver.resolve(label ?? "")
    let isOn = on.map { resolver.resolveBool($0) } ?? false

    let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")

    let toggleView = NativeMenuToggleView(label: resolvedLabel, isOn: isOn) {
      if let command = command {
        let resolvedCommand = resolver.resolve(command)
        runCommand(resolvedCommand)
      }
    }
    let hostingView = NSHostingView(rootView: toggleView)
    hostingView.frame = NSRect(x: 0, y: 0, width: 220, height: 28)
    item.view = hostingView
    menu.addItem(item)

  // MARK: Header

  case .header(let content, _):
    let resolvedContent = resolver.resolve(content)
    if #available(macOS 14.0, *) {
      let item = NSMenuItem.sectionHeader(title: resolvedContent)
      menu.addItem(item)
    } else {
      // Fallback: disabled item with uppercase, 11pt semibold, secondary color
      let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
        .foregroundColor: NSColor.secondaryLabelColor,
      ]
      let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
      item.attributedTitle = NSAttributedString(
        string: resolvedContent.uppercased(), attributes: attributes)
      item.isEnabled = false
      menu.addItem(item)
    }

  // MARK: Divider

  case .divider:
    menu.addItem(NSMenuItem.separator())

  // MARK: Text (read-only display)

  case .text(let content, _, let weight, let style, _, _, let strikethrough, _):
    let resolvedContent = resolver.resolve(content)
    let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")

    let isSecondary = style == .secondary
    let isBold = weight == .bold || weight == .semibold || weight == .heavy || weight == .black
    let view = NativeMenuTextView(
      content: resolvedContent, isBold: isBold, isSecondary: isSecondary,
      isStrikethrough: strikethrough == true)
    let hosting = NSHostingView(rootView: view)
    hosting.frame = NSRect(x: 0, y: 0, width: 280, height: 22)
    item.view = hosting
    menu.addItem(item)

  // MARK: Foreach

  case .foreach(let items, let child, _):
    guard let dataArray = resolver.data[items] else { break }
    for element in dataArray {
      resolver.pushScope(element)
      addItems(from: child, to: menu, resolver: resolver)
      resolver.popScope()
    }

  // MARK: If

  case .if(let condition, let thenNode, let elseNode, _):
    if evaluateCondition(condition, resolver: resolver) {
      addItems(from: thenNode, to: menu, resolver: resolver)
    } else if let elseNode = elseNode {
      addItems(from: elseNode, to: menu, resolver: resolver)
    }

  // MARK: Unsupported nodes -- silently skip

  case .spacer:
    break
  case .icon:
    break
  case .image:
    break
  case .rect:
    break
  case .circle:
    break
  case .capsule:
    break
  case .button:
    break
  case .progress:
    break
  case .gauge:
    break
  case .badge:
    break
  }
}

// MARK: - Native Menu Custom Views

/// Parse a hex color string (e.g. "#FF5733") into a SwiftUI Color.
private func nativeMenuColorFromHex(_ hex: String) -> Color? {
  let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
  guard cleaned.count == 6, let rgbValue = UInt64(cleaned, radix: 16) else { return nil }
  let r = Double((rgbValue & 0xFF0000) >> 16) / 255.0
  let g = Double((rgbValue & 0x00FF00) >> 8) / 255.0
  let b = Double(rgbValue & 0x0000FF) / 255.0
  return Color(red: r, green: g, blue: b)
}

/// A key/value row for native NSMenu: bold label on the left, secondary detail
/// right-aligned. Rendered via NSHostingView to bypass NSMenu's disabled muting.
/// Supports secondary (muted) and strikethrough styling for past events etc.
struct NativeMenuRowView: View {
  let label: String
  let detail: String
  var isSecondary: Bool = false
  var isStrikethrough: Bool = false
  var indicatorColor: String?

  var body: some View {
    HStack(spacing: 0) {
      if let hex = indicatorColor, let color = nativeMenuColorFromHex(hex) {
        RoundedRectangle(cornerRadius: 1.5)
          .fill(color)
          .frame(width: 3, height: 16)
          .padding(.trailing, 8)
      }
      Text(label)
        .font(
          .system(
            size: NSFont.menuFont(ofSize: 0).pointSize,
            weight: isSecondary ? .regular : .bold)
        )
        .strikethrough(isStrikethrough)
        .foregroundStyle(isSecondary ? .secondary : .primary)
      Spacer(minLength: 16)
      Text(detail)
        .font(.system(size: NSFont.menuFont(ofSize: 0).pointSize))
        .strikethrough(isStrikethrough)
        .foregroundStyle(.secondary)
    }
    .padding(.horizontal, 14)
    .frame(maxWidth: .infinity, minHeight: 22)
  }
}

/// A label-only row for native NSMenu. Bold primary text.
/// Supports secondary (muted) and strikethrough styling.
struct NativeMenuLabelView: View {
  let label: String
  var isSecondary: Bool = false
  var isStrikethrough: Bool = false
  var indicatorColor: String?

  var body: some View {
    HStack {
      if let hex = indicatorColor, let color = nativeMenuColorFromHex(hex) {
        RoundedRectangle(cornerRadius: 1.5)
          .fill(color)
          .frame(width: 3, height: 16)
          .padding(.trailing, 8)
      }
      Text(label)
        .font(
          .system(
            size: NSFont.menuFont(ofSize: 0).pointSize,
            weight: isSecondary ? .regular : .bold)
        )
        .strikethrough(isStrikethrough)
        .foregroundStyle(isSecondary ? .secondary : .primary)
      Spacer()
    }
    .padding(.horizontal, 14)
    .frame(maxWidth: .infinity, minHeight: 22)
  }
}

/// A standalone text item for native NSMenu. Supports bold/secondary/strikethrough styling.
struct NativeMenuTextView: View {
  let content: String
  let isBold: Bool
  let isSecondary: Bool
  var isStrikethrough: Bool = false

  var body: some View {
    HStack {
      Text(content)
        .font(
          .system(
            size: NSFont.menuFont(ofSize: 0).pointSize,
            weight: isBold ? .bold : .regular)
        )
        .strikethrough(isStrikethrough)
        .foregroundStyle(isSecondary ? .secondary : .primary)
      Spacer()
    }
    .padding(.horizontal, 14)
    .frame(maxWidth: .infinity, minHeight: 22)
  }
}

/// A check item for native NSMenu. Uses a custom NSView so clicking doesn't
/// dismiss the menu, allowing multiple items to be checked/unchecked.
/// Handles mouseUp at the AppKit level (SwiftUI gesture recognizers don't
/// reliably receive events inside NSMenuItem custom views).
class NativeMenuCheckItemView: NSView {
  private var isChecked: Bool
  private let command: String?
  private var hostingView: NSHostingView<NativeMenuCheckContent>?

  init(label: String, isChecked: Bool, command: String?) {
    self.isChecked = isChecked
    self.command = command
    super.init(frame: NSRect(x: 0, y: 0, width: 280, height: 26))
    let content = NativeMenuCheckContent(label: label, isChecked: isChecked)
    let hosting = NSHostingView(rootView: content)
    hosting.frame = bounds
    hosting.autoresizingMask = [.width, .height]
    addSubview(hosting)
    self.hostingView = hosting
  }

  required init?(coder: NSCoder) { fatalError() }

  override func mouseUp(with event: NSEvent) {
    isChecked.toggle()
    if let hosting = hostingView {
      hosting.rootView = NativeMenuCheckContent(
        label: hosting.rootView.label, isChecked: isChecked)
    }
    if let command = command, !command.isEmpty {
      runCommand(command)
    }
  }
}

/// Pure rendering content for a check item — no interaction handling.
struct NativeMenuCheckContent: View {
  let label: String
  let isChecked: Bool

  var body: some View {
    HStack(spacing: 8) {
      Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
        .foregroundStyle(isChecked ? .secondary : .primary)
        .imageScale(.medium)
      Text(label)
        .font(.system(size: NSFont.menuFont(ofSize: 0).pointSize))
        .strikethrough(isChecked)
        .foregroundStyle(isChecked ? .secondary : .primary)
      Spacer()
    }
    .padding(.horizontal, 14)
    .frame(maxWidth: .infinity, minHeight: 26)
  }
}
