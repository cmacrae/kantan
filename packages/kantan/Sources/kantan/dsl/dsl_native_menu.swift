import AppKit
import SwiftUI

// MARK: - Build Native Menu

/// Convert a `ViewNode` tree into a native `NSMenu`.
///
/// Layout containers (vstack, hstack, zstack, scroll, group) are flattened -- their
/// children are extracted in order. NSMenu is inherently a flat list, so nesting
/// is collapsed. Unsupported node types (shapes, images, progress, gauge, badge,
/// grid, spacer) are silently skipped.
@MainActor
func buildNativeMenu(
  from rootNode: ViewNode, resolver: TemplateResolver, textColor: Color? = nil
) -> NSMenu {
  let menu = NSMenu()
  menu.autoenablesItems = false
  addItems(from: rootNode, to: menu, resolver: resolver, textColor: textColor)
  return menu
}

/// Update `menu`'s items from `rootNode`, so an open menu shows the values
/// `resolver` holds now. When the rows line up with the existing ones, each
/// existing item takes its new content in place, keeping its highlight;
/// otherwise the items are replaced.
@MainActor
func refreshNativeMenu(
  _ menu: NSMenu, from rootNode: ViewNode, resolver: TemplateResolver, textColor: Color? = nil
) {
  let fresh = buildNativeMenu(from: rootNode, resolver: resolver, textColor: textColor)
  let updates = fresh.items
  fresh.removeAllItems()

  guard updates.count == menu.items.count,
    zip(menu.items, updates).allSatisfy({ $0.isSeparatorItem == $1.isSeparatorItem })
  else {
    menu.removeAllItems()
    updates.forEach(menu.addItem)
    return
  }

  for (item, update) in zip(menu.items, updates) where !item.isSeparatorItem {
    let view = update.view
    update.view = nil
    if let shown = item.view as? NativeMenuCheckItemView,
      let fresh = view as? NativeMenuCheckItemView, shown.shows(fresh)
    {
      continue
    }
    item.view = view
    item.attributedTitle = update.attributedTitle
    item.target = update.target
    item.action = update.action
    item.representedObject = update.representedObject
    item.isEnabled = update.isEnabled
  }
}

// MARK: - HStack Composition

/// Styling metadata extracted from text/icon children when composing hstack items.
private struct HStackTextPart {
  let text: String
  let isSecondary: Bool
  let isStrikethrough: Bool
  /// When set, this part is a bundled icon glyph and must be rendered with this font
  /// instead of the system menu font.
  let iconFont: Font?

  init(text: String, isSecondary: Bool, isStrikethrough: Bool, iconFont: Font? = nil) {
    self.text = text
    self.isSecondary = isSecondary
    self.isStrikethrough = isStrikethrough
    self.iconFont = iconFont
  }
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
  children: [ViewNode], command: String? = nil, to menu: NSMenu, resolver: TemplateResolver,
  textColor: Color? = nil
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
    case .icon(let name, let size, _, _, _):
      let templateResolved = resolver.resolve(name)
      if !templateResolved.isEmpty {
        let part: HStackTextPart
        if iconFontsAvailable {
          let resolved = resolveIconName(templateResolved)
          if let fontOverride = resolved.fontNameOverride {
            let fontSize = size ?? Double(NSFont.menuFont(ofSize: 0).pointSize)
            let scaledSize = dslScaledFontSize(fontSize, scale: resolved.scaleFactor)
            let font = FontConfig(
              descriptor: "\(fontOverride):\(scaledSize)", source: .bundled
            ).swiftUIFont
            part = HStackTextPart(
              text: resolved.glyph, isSecondary: false, isStrikethrough: false, iconFont: font)
          } else {
            part = HStackTextPart(
              text: resolved.glyph, isSecondary: false, isStrikethrough: false)
          }
        } else {
          part = HStackTextPart(
            text: templateResolved, isSecondary: false, isStrikethrough: false)
        }
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

  guard !labelParts.isEmpty || !detailParts.isEmpty else { return }

  let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")

  // Use a custom NSHostingView so macOS doesn't apply disabled muting.
  let rowView: NSView
  if !detailParts.isEmpty {
    let view = NativeMenuRowView(
      labelParts: labelParts, detailParts: detailParts, indicatorColor: indicatorColor,
      textColor: textColor)
    let hosting = NSHostingView(rootView: view)
    hosting.frame = NSRect(x: 0, y: 0, width: 280, height: 22)
    rowView = hosting
  } else {
    let view = NativeMenuLabelView(
      parts: labelParts, indicatorColor: indicatorColor, textColor: textColor)
    let hosting = NSHostingView(rootView: view)
    hosting.frame = NSRect(x: 0, y: 0, width: 280, height: 22)
    rowView = hosting
  }
  item.view = rowView
  if let command = command {
    let resolvedCommand = resolver.resolveCommand(command)
    let target = NativeMenuTarget {
      runCommand(resolvedCommand, environment: resolver.commandEnvironment)
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
  case .icon(let name, let size, _, _, _):
    let templateResolved = resolver.resolve(name)
    guard !templateResolved.isEmpty else { return [] }
    if iconFontsAvailable {
      let resolved = resolveIconName(templateResolved)
      if let fontOverride = resolved.fontNameOverride {
        let fontSize = size ?? Double(NSFont.menuFont(ofSize: 0).pointSize)
        let scaledSize = dslScaledFontSize(fontSize, scale: resolved.scaleFactor)
        let font = FontConfig(
          descriptor: "\(fontOverride):\(scaledSize)", source: .bundled
        ).swiftUIFont
        return [
          HStackTextPart(
            text: resolved.glyph, isSecondary: false, isStrikethrough: false, iconFont: font)
        ]
      }
      return [HStackTextPart(text: resolved.glyph, isSecondary: false, isStrikethrough: false)]
    }
    return [HStackTextPart(text: templateResolved, isSecondary: false, isStrikethrough: false)]
  case .vstack(_, _, let children, _),
    .hstack(_, _, let children, _, _),
    .group(let children, _):
    return children.flatMap { extractStyledParts(from: $0, resolver: resolver) }
  default:
    return []
  }
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
private func addItems(
  from node: ViewNode, to menu: NSMenu, resolver: TemplateResolver, textColor: Color? = nil
) {
  switch node {
  // MARK: Layout nodes -- flatten children (except hstack)

  case .vstack(_, _, let children, _),
    .zstack(_, let children, _),
    .scroll(_, let children, _),
    .group(let children, _),
    .grid(_, _, let children, _):
    for child in children {
      addItems(from: child, to: menu, resolver: resolver, textColor: textColor)
    }

  // MARK: HStack -- compose into a single menu item

  case .hstack(_, _, let children, let command, _):
    // Check if hstack contains any interactive nodes — if so, flatten normally
    if children.contains(where: { isInteractiveNode($0) }) {
      for child in children {
        addItems(from: child, to: menu, resolver: resolver, textColor: textColor)
      }
    } else {
      addHStackItem(
        children: children, command: command, to: menu, resolver: resolver, textColor: textColor)
    }

  // MARK: Action

  case .action(let label, let iconGlyph, let command, _, _):
    let resolvedLabel = resolver.resolve(label ?? "")
    let menuFontSize = NSFont.menuFont(ofSize: 0).pointSize
    let title = NSMutableAttributedString()
    if let glyph = iconGlyph {
      let templateResolved = resolver.resolve(glyph)
      if !templateResolved.isEmpty {
        if iconFontsAvailable {
          let resolved = resolveIconName(templateResolved)
          if let fontOverride = resolved.fontNameOverride {
            let scaledSize = CGFloat(round(Double(menuFontSize) * resolved.scaleFactor))
            let fc = FontConfig(descriptor: "\(fontOverride):\(Int(scaledSize))", source: .bundled)
            let nsFont =
              NSFont(name: fc.name, size: scaledSize) ?? NSFont.menuFont(ofSize: menuFontSize)
            title.append(
              NSAttributedString(string: resolved.glyph, attributes: [.font: nsFont]))
          } else {
            title.append(NSAttributedString(string: resolved.glyph))
          }
        } else {
          title.append(NSAttributedString(string: templateResolved))
        }
        title.append(NSAttributedString(string: " "))
      }
    }
    title.append(NSAttributedString(string: resolvedLabel))

    // Apply theme foreground color when set.
    if let textColor = textColor {
      let nsColor = NSColor(textColor)
      title.addAttribute(
        .foregroundColor, value: nsColor,
        range: NSRange(location: 0, length: title.length))
    }

    let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    item.attributedTitle = title
    if let command = command {
      let resolvedCommand = resolver.resolveCommand(command)
      let target = NativeMenuTarget {
        runCommand(resolvedCommand, environment: resolver.commandEnvironment)
      }
      item.target = target
      item.action = #selector(NativeMenuTarget.menuAction(_:))
      item.representedObject = target
    } else {
      item.isEnabled = false
    }
    menu.addItem(item)

  // MARK: Check

  case .check(let label, let checked, let command, let uncheckedCommand, _):
    let resolvedLabel = resolver.resolve(label ?? "")
    let isChecked = checked.map { resolver.resolveBool($0) } ?? false
    let resolvedCommand = command.map { resolver.resolveCommand($0) }
    let resolvedUncheckedCommand = uncheckedCommand.map { resolver.resolveCommand($0) }

    let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")

    // Use a custom NSView so clicking doesn't dismiss the menu.
    // This allows the user to check/uncheck multiple items without
    // the menu closing after each interaction.
    let checkView = NativeMenuCheckItemView(
      label: resolvedLabel, isChecked: isChecked, command: resolvedCommand,
      uncheckedCommand: resolvedUncheckedCommand, environment: resolver.commandEnvironment,
      textColor: textColor)
    item.view = checkView
    menu.addItem(item)

  // MARK: Toggle

  case .toggle(let label, let on, let command, _):
    let resolvedLabel = resolver.resolve(label ?? "")
    let isOn = on.map { resolver.resolveBool($0) } ?? false

    let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")

    // Resolved now, while any foreach item is still in scope.
    let resolvedCommand = command.map { resolver.resolveCommand($0) }
    let environment = resolver.commandEnvironment
    let toggleView = NativeMenuToggleView(label: resolvedLabel, isOn: isOn, textColor: textColor) {
      if let resolvedCommand {
        runCommand(resolvedCommand, environment: environment)
      }
    }
    let hostingView = NSHostingView(rootView: toggleView)
    hostingView.frame = NSRect(x: 0, y: 0, width: 220, height: 28)
    item.view = hostingView
    menu.addItem(item)

  // MARK: Header

  case .header(let content, _):
    let resolvedContent = resolver.resolve(content)
    let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    let view = NativeMenuHeaderView(content: resolvedContent, textColor: textColor ?? .primary)
    let hosting = NSHostingView(rootView: view)
    hosting.frame = NSRect(x: 0, y: 0, width: 280, height: 22)
    item.view = hosting
    menu.addItem(item)

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
      isStrikethrough: strikethrough == true, textColor: textColor)
    let hosting = NSHostingView(rootView: view)
    hosting.frame = NSRect(x: 0, y: 0, width: 280, height: 22)
    item.view = hosting
    menu.addItem(item)

  // MARK: Foreach

  case .foreach(let items, let child, _):
    guard let dataArray = resolver.data[items] else { break }
    for element in dataArray {
      resolver.pushScope(element)
      defer { resolver.popScope() }
      addItems(from: child, to: menu, resolver: resolver, textColor: textColor)
    }

  // MARK: If

  case .if(let condition, let thenNode, let elseNode, _):
    if dslEvaluateTruthy(condition, resolver: resolver) {
      addItems(from: thenNode, to: menu, resolver: resolver, textColor: textColor)
    } else if let elseNode = elseNode {
      addItems(from: elseNode, to: menu, resolver: resolver, textColor: textColor)
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

/// Header row for native NSMenu, matching the themed view's header style.
struct NativeMenuHeaderView: View {
  let content: String
  var textColor: Color = .primary

  var body: some View {
    Text(content)
      .font(.system(size: 12, weight: .bold))
      .foregroundStyle(textColor)
      .frame(maxWidth: .infinity, alignment: .leading)
      .frame(height: 22)
      .padding(.horizontal, 14)
  }
}

/// Renders a sequence of `HStackTextPart` values, using each part's `iconFont`
/// when present and falling back to the system menu font otherwise.
private struct NativeMenuPartsView: View {
  let parts: [HStackTextPart]
  let secondaryOverride: Bool
  var textColor: Color?

  init(parts: [HStackTextPart], secondaryOverride: Bool = false, textColor: Color? = nil) {
    self.parts = parts
    self.secondaryOverride = secondaryOverride
    self.textColor = textColor
  }

  private var primaryColor: Color { textColor ?? .primary }
  private var secondaryColor: Color { textColor?.opacity(0.5) ?? Color.secondary }

  var body: some View {
    let menuFont = Font.system(size: NSFont.menuFont(ofSize: 0).pointSize)
    ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
      let isSecondary = secondaryOverride || part.isSecondary
      Text(part.text)
        .font(part.iconFont ?? menuFont)
        .strikethrough(part.isStrikethrough)
        .foregroundStyle(isSecondary ? secondaryColor : primaryColor)
    }
  }
}

/// A key/value row for native NSMenu: label parts on the left, detail parts
/// right-aligned. Rendered via NSHostingView to bypass NSMenu's disabled muting.
/// Each part carries its own font so bundled icon glyphs render correctly.
private struct NativeMenuRowView: View {
  let labelParts: [HStackTextPart]
  let detailParts: [HStackTextPart]
  var indicatorColor: String?
  var textColor: Color?

  var body: some View {
    HStack(spacing: 0) {
      if let hex = indicatorColor, let color = dslColorFromHex(hex) {
        RoundedRectangle(cornerRadius: 1.5)
          .fill(color)
          .frame(width: 3, height: 16)
          .padding(.trailing, 8)
      }
      HStack(spacing: 4) {
        NativeMenuPartsView(parts: labelParts, textColor: textColor)
      }
      Spacer(minLength: 16)
      HStack(spacing: 4) {
        NativeMenuPartsView(parts: detailParts, secondaryOverride: true, textColor: textColor)
      }
    }
    .padding(.horizontal, 14)
    .frame(maxWidth: .infinity, minHeight: 22)
  }
}

/// A label-only row for native NSMenu.
/// Each part carries its own font so bundled icon glyphs render correctly.
private struct NativeMenuLabelView: View {
  let parts: [HStackTextPart]
  var indicatorColor: String?
  var textColor: Color?

  var body: some View {
    HStack(spacing: 4) {
      if let hex = indicatorColor, let color = dslColorFromHex(hex) {
        RoundedRectangle(cornerRadius: 1.5)
          .fill(color)
          .frame(width: 3, height: 16)
          .padding(.trailing, 4)
      }
      NativeMenuPartsView(parts: parts, textColor: textColor)
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
  var textColor: Color?

  private var primaryColor: Color { textColor ?? .primary }
  private var secondaryColor: Color { textColor?.opacity(0.5) ?? Color.secondary }

  var body: some View {
    HStack {
      Text(content)
        .font(
          .system(
            size: NSFont.menuFont(ofSize: 0).pointSize,
            weight: isBold ? .bold : .regular)
        )
        .strikethrough(isStrikethrough)
        .foregroundStyle(isSecondary ? secondaryColor : primaryColor)
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
  /// The checked value the item was built with.
  private let reported: Bool
  private let label: String
  private let checkedCommand: String?
  private let uncheckedCommand: String?
  private let environment: [String: String]
  private let textColor: Color?
  private var hostingView: NSHostingView<NativeMenuCheckContent>?

  init(
    label: String, isChecked: Bool, command: String?, uncheckedCommand: String?,
    environment: [String: String] = [:], textColor: Color? = nil
  ) {
    self.isChecked = isChecked
    self.reported = isChecked
    self.label = label
    self.checkedCommand = command
    self.uncheckedCommand = uncheckedCommand
    self.environment = environment
    self.textColor = textColor
    super.init(frame: NSRect(x: 0, y: 0, width: 280, height: 26))
    let content = NativeMenuCheckContent(label: label, isChecked: isChecked, textColor: textColor)
    let hosting = NSHostingView(rootView: content)
    hosting.frame = bounds
    hosting.autoresizingMask = [.width, .height]
    addSubview(hosting)
    self.hostingView = hosting
  }

  required init?(coder: NSCoder) { fatalError() }

  /// Whether `other` was built from the same item and checked value, so this
  /// view, and any click on it, still stands for it.
  func shows(_ other: NativeMenuCheckItemView) -> Bool {
    label == other.label && checkedCommand == other.checkedCommand
      && uncheckedCommand == other.uncheckedCommand && reported == other.reported
  }

  override func mouseUp(with event: NSEvent) {
    // Pick the right command BEFORE toggling the visual state:
    // If currently unchecked, we're checking it → use checkedCommand
    // If currently checked, we're unchecking it → use uncheckedCommand (falling back to checkedCommand)
    let command = isChecked ? (uncheckedCommand ?? checkedCommand) : checkedCommand
    isChecked.toggle()
    if let hosting = hostingView {
      hosting.rootView = NativeMenuCheckContent(
        label: label, isChecked: isChecked, textColor: textColor)
    }
    if let command = command, !command.isEmpty {
      runCommand(command, environment: environment)
    }
  }
}

/// Pure rendering content for a check item — no interaction handling.
struct NativeMenuCheckContent: View {
  let label: String
  let isChecked: Bool
  var textColor: Color?

  private var primaryColor: Color { textColor ?? .primary }
  private var secondaryColor: Color { textColor?.opacity(0.4) ?? Color.secondary }

  var body: some View {
    HStack(spacing: 8) {
      Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
        .foregroundStyle(isChecked ? secondaryColor : primaryColor)
        .imageScale(.medium)
      Text(label)
        .font(.system(size: NSFont.menuFont(ofSize: 0).pointSize))
        .strikethrough(isChecked)
        .foregroundStyle(isChecked ? secondaryColor : primaryColor)
      Spacer()
    }
    .padding(.horizontal, 14)
    .frame(maxWidth: .infinity, minHeight: 26)
  }
}
