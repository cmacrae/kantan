import AppKit
import SwiftUI

// MARK: - Menu Rows

/// A piece of a menu row's label or detail.
enum NativeMenuPart: Equatable {
  case text(String, secondary: Bool, strikethrough: Bool)
  /// An icon by name, `size` points tall, or the menu font's size.
  case icon(name: String, size: Double?)
}

/// A row of the native menu a view makes.
enum NativeMenuRow: Equatable {
  /// An hstack: a label, a right-aligned detail, the colour of an indicator
  /// bar before them, and the command a click runs.
  case row(label: [NativeMenuPart], detail: [NativeMenuPart], indicator: String?, command: String?)
  /// An action, disabled without a command.
  case action(label: String, icon: String?, command: String?)
  case check(label: String, checked: Bool, command: String?, uncheckedCommand: String?)
  case toggle(label: String, on: Bool, command: String?)
  case header(String)
  case divider
  case text(String, bold: Bool, secondary: Bool, strikethrough: Bool)
}

/// The rows of the native menu `node` makes, with their placeholders and
/// commands resolved.
///
/// A menu is a flat list, so layout containers (vstack, zstack, scroll,
/// group, grid) flatten into their children, and an hstack with no
/// interactive child becomes one row. Nodes a menu has no row for (shapes,
/// images, progress, gauge, badge, spacer, a lone icon) are left out.
func nativeMenuRows(from node: ViewNode, resolver: TemplateResolver) -> [NativeMenuRow] {
  switch node {
  case .vstack(_, _, let children, _),
    .zstack(_, let children, _),
    .scroll(_, let children, _),
    .group(let children, _),
    .grid(_, _, let children, _):
    return children.flatMap { nativeMenuRows(from: $0, resolver: resolver) }

  case .hstack(_, _, let children, let command, _):
    if children.contains(where: isInteractiveNode) {
      return children.flatMap { nativeMenuRows(from: $0, resolver: resolver) }
    }
    return hstackRow(children: children, command: command, resolver: resolver).map { [$0] } ?? []

  case .action(let label, let icon, let command, _):
    let iconName = icon.map { resolver.resolve($0) }
    return [
      .action(
        label: resolver.resolve(label ?? ""),
        icon: iconName?.isEmpty == false ? iconName : nil,
        command: command.map { resolver.resolveCommand($0) })
    ]

  case .check(let label, let checked, let command, let uncheckedCommand, _):
    return [
      .check(
        label: resolver.resolve(label ?? ""),
        checked: checked.map { resolver.resolveBool($0) } ?? false,
        command: command.map { resolver.resolveCommand($0) },
        uncheckedCommand: uncheckedCommand.map { resolver.resolveCommand($0) })
    ]

  case .toggle(let label, let on, let command, _):
    return [
      .toggle(
        label: resolver.resolve(label ?? ""),
        on: on.map { resolver.resolveBool($0) } ?? false,
        command: command.map { resolver.resolveCommand($0) })
    ]

  case .header(let content, _):
    return [.header(resolver.resolve(content))]

  case .divider:
    return [.divider]

  case .text(let content, _, let weight, let style, _, _, let strikethrough, _):
    return [
      .text(
        resolver.resolve(content),
        bold: weight == .bold || weight == .semibold || weight == .heavy || weight == .black,
        secondary: style == .secondary, strikethrough: strikethrough == true)
    ]

  case .foreach(let items, let child, _):
    return (resolver.data[items] ?? []).flatMap {
      nativeMenuRows(from: child, resolver: resolver.scoped(with: $0))
    }

  case .if(let condition, let thenNode, let elseNode, _):
    if dslEvaluateTruthy(condition, resolver: resolver) {
      return nativeMenuRows(from: thenNode, resolver: resolver)
    }
    return elseNode.map { nativeMenuRows(from: $0, resolver: resolver) } ?? []

  case .spacer, .icon, .image, .rect, .circle, .capsule, .button, .progress, .gauge, .badge:
    return []
  }
}

/// An hstack's children as one row: the pattern `icon + text + spacer +
/// text` becomes a label on the left with a secondary detail on the right.
/// The children split at the first `spacer`, and the first coloured `rect`
/// gives the indicator. Nil when no child has anything to show.
private func hstackRow(children: [ViewNode], command: String?, resolver: TemplateResolver)
  -> NativeMenuRow?
{
  var label: [NativeMenuPart] = []
  var detail: [NativeMenuPart] = []
  var hitSpacer = false
  var indicator: String?

  func add(_ parts: [NativeMenuPart]) {
    if hitSpacer {
      detail += parts
    } else {
      label += parts
    }
  }

  for child in children {
    switch child {
    case .spacer:
      hitSpacer = true
    case .text(let content, _, _, let style, _, _, let strikethrough, _):
      add([
        .text(
          resolver.resolve(content), secondary: style == .secondary,
          strikethrough: strikethrough == true)
      ])
    case .icon(let name, let size, _, _, _):
      let resolved = resolver.resolve(name)
      if !resolved.isEmpty {
        add([.icon(name: resolved, size: size)])
      }
    case .rect(_, _, let color, _, _, _, _):
      if let color, indicator == nil {
        let resolved = resolver.resolve(color)
        if !resolved.isEmpty {
          indicator = resolved
        }
      }
    case .progress:
      break
    default:
      add(nestedParts(of: child, resolver: resolver))
    }
  }

  guard !label.isEmpty || !detail.isEmpty else { return nil }
  return .row(
    label: label, detail: detail, indicator: indicator,
    command: command.map { resolver.resolveCommand($0) })
}

/// The text and icon parts nested within `node`, leaving out empty ones.
private func nestedParts(of node: ViewNode, resolver: TemplateResolver) -> [NativeMenuPart] {
  switch node {
  case .text(let content, _, _, let style, _, _, let strikethrough, _):
    let resolved = resolver.resolve(content)
    guard !resolved.isEmpty else { return [] }
    return [.text(resolved, secondary: style == .secondary, strikethrough: strikethrough == true)]
  case .icon(let name, let size, _, _, _):
    let resolved = resolver.resolve(name)
    return resolved.isEmpty ? [] : [.icon(name: resolved, size: size)]
  case .vstack(_, _, let children, _),
    .hstack(_, _, let children, _, _),
    .group(let children, _):
    return children.flatMap { nestedParts(of: $0, resolver: resolver) }
  default:
    return []
  }
}

/// Whether the node is an interactive type that gets a menu item of its own.
private func isInteractiveNode(_ node: ViewNode) -> Bool {
  switch node {
  case .action, .check, .toggle, .button:
    return true
  default:
    return false
  }
}

// MARK: - Build Native Menu

/// Convert a `ViewNode` tree into a native `NSMenu` of its rows.
@MainActor
func buildNativeMenu(
  from rootNode: ViewNode, resolver: TemplateResolver, textColor: Color? = nil
) -> NSMenu {
  let menu = NativeMenu()
  for row in nativeMenuRows(from: rootNode, resolver: resolver) {
    menu.addItem(
      menuItem(for: row, environment: resolver.commandEnvironment, textColor: textColor))
  }
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
    (view as? NativeMenuItemView)?.isHighlighted = item.isHighlighted
    item.attributedTitle = update.attributedTitle
    item.target = update.target
    item.action = update.action
    item.representedObject = update.representedObject
    item.isEnabled = update.isEnabled
  }
}

/// A menu whose items drawn by a view of their own are told when they are
/// highlighted, as macOS highlights only the items it draws itself.
private final class NativeMenu: NSMenu, NSMenuDelegate {
  init() {
    super.init(title: "")
    autoenablesItems = false
    delegate = self
  }

  required init(coder: NSCoder) { fatalError() }

  func menu(_ menu: NSMenu, willHighlight item: NSMenuItem?) {
    for each in items {
      (each.view as? NativeMenuItemView)?.isHighlighted = each === item
    }
  }

  func menuDidClose(_ menu: NSMenu) {
    for each in items {
      (each.view as? NativeMenuItemView)?.isHighlighted = false
    }
  }
}

/// The view of a menu item a click acts on. It draws the system's highlight
/// behind its content while its item is highlighted, and takes the clicks
/// anywhere within it.
class NativeMenuItemView: NSView {
  /// How far the highlight sits in from the menu's sides, and how round
  /// its corners are, as macOS draws it for its own items.
  private static let highlightInset: CGFloat = 5
  private static let highlightRadius: CGFloat = 4

  private let highlight = NSVisualEffectView()

  var isHighlighted = false {
    didSet {
      guard isHighlighted != oldValue else { return }
      highlight.isHidden = !isHighlighted
      highlightChanged()
    }
  }

  /// The colour content takes while highlighted, in place of its own.
  static var highlightedTextColor: Color { Color(nsColor: .selectedMenuItemTextColor) }

  override init(frame: NSRect) {
    super.init(frame: frame)
    highlight.material = .selection
    highlight.state = .active
    highlight.isEmphasized = true
    highlight.blendingMode = .behindWindow
    highlight.wantsLayer = true
    highlight.layer?.cornerRadius = Self.highlightRadius
    highlight.layer?.masksToBounds = true
    highlight.isHidden = true
    highlight.frame = bounds.insetBy(dx: Self.highlightInset, dy: 0)
    highlight.autoresizingMask = [.width, .height]
    addSubview(highlight)
  }

  required init?(coder: NSCoder) { fatalError() }

  /// Shows `content` over the highlight, filling the view.
  func host(_ content: NSView) {
    content.frame = bounds
    content.autoresizingMask = [.width, .height]
    addSubview(content)
  }

  /// Called when the item gains or loses its highlight, to redraw content.
  func highlightChanged() {}

  override func hitTest(_ point: NSPoint) -> NSView? {
    frame.contains(point) ? self : nil
  }
}

/// A menu item's view showing a SwiftUI row that runs the item's command
/// when clicked, closing the menu as choosing any item does.
private final class NativeMenuCommandItemView: NativeMenuItemView {
  private let content: (Bool) -> AnyView
  private let hosting: NSHostingView<AnyView>

  /// `content` draws the row, highlighted or not.
  init(height: CGFloat = 22, content: @escaping (Bool) -> AnyView) {
    self.content = content
    self.hosting = NSHostingView(rootView: content(false))
    super.init(frame: NSRect(x: 0, y: 0, width: 280, height: height))
    host(hosting)
  }

  required init?(coder: NSCoder) { fatalError() }

  override func highlightChanged() {
    hosting.rootView = content(isHighlighted)
  }

  override func mouseUp(with event: NSEvent) {
    guard let item = enclosingMenuItem, let action = item.action else { return }
    item.menu?.cancelTracking()
    NSApp.sendAction(action, to: item.target, from: item)
  }
}

// MARK: - Menu Items

/// A row part ready to draw: its text, or an icon's glyph with its font.
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

  /// `part` as the menu draws it: an icon the bundled fonts have is its
  /// glyph in its font, scaled, and any other is its name as text.
  init(_ part: NativeMenuPart) {
    switch part {
    case .text(let text, let secondary, let strikethrough):
      self.init(text: text, isSecondary: secondary, isStrikethrough: strikethrough)
    case .icon(let name, let size):
      guard iconFontsAvailable else {
        self.init(text: name, isSecondary: false, isStrikethrough: false)
        return
      }
      let resolved = resolveIconName(name)
      guard let fontOverride = resolved.fontNameOverride else {
        self.init(text: resolved.glyph, isSecondary: false, isStrikethrough: false)
        return
      }
      let fontSize = size ?? Double(NSFont.menuFont(ofSize: 0).pointSize)
      let scaledSize = dslScaledFontSize(fontSize, scale: resolved.scaleFactor)
      self.init(
        text: resolved.glyph, isSecondary: false, isStrikethrough: false,
        iconFont: FontConfig(descriptor: "\(fontOverride):\(scaledSize)", source: .bundled)
          .swiftUIFont)
    }
  }
}

/// A menu item running `command` with `environment` when chosen.
@MainActor
private func setCommand(_ command: String, environment: [String: String], on item: NSMenuItem) {
  let target = NativeMenuTarget {
    runCommand(command, environment: environment)
  }
  item.target = target
  item.action = #selector(NativeMenuTarget.menuAction(_:))
  item.representedObject = target
}

/// A menu item showing `view` in place of a title, so macOS doesn't mute it
/// as it does a disabled item.
@MainActor
private func hostedItem<Content: View>(_ view: Content, width: CGFloat = 280, height: CGFloat = 22)
  -> NSMenuItem
{
  let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
  let hosting = NSHostingView(rootView: view)
  hosting.frame = NSRect(x: 0, y: 0, width: width, height: height)
  item.view = hosting
  return item
}

/// The menu item for `row`, its commands run with `environment`, drawn in
/// the theme's `textColor` when there is one.
@MainActor
private func menuItem(
  for row: NativeMenuRow, environment: [String: String], textColor: Color?
) -> NSMenuItem {
  switch row {
  case .row(let label, let detail, let indicator, let command):
    let labelParts = label.map(HStackTextPart.init)
    let detailParts = detail.map(HStackTextPart.init)
    let row = { (textColor: Color?) -> AnyView in
      detailParts.isEmpty
        ? AnyView(
          NativeMenuLabelView(parts: labelParts, indicatorColor: indicator, textColor: textColor))
        : AnyView(
          NativeMenuRowView(
            labelParts: labelParts, detailParts: detailParts,
            indicatorColor: indicator, textColor: textColor))
    }
    guard let command else { return hostedItem(row(textColor)) }
    // A row with a command is chosen like any item, so it highlights.
    let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    item.view = NativeMenuCommandItemView { highlighted in
      row(highlighted ? NativeMenuItemView.highlightedTextColor : textColor)
    }
    setCommand(command, environment: environment, on: item)
    return item

  case .action(let label, let icon, let command):
    let menuFontSize = NSFont.menuFont(ofSize: 0).pointSize
    let title = NSMutableAttributedString()
    if let icon {
      if iconFontsAvailable {
        let resolved = resolveIconName(icon)
        if let fontOverride = resolved.fontNameOverride {
          let scaledSize = CGFloat(round(Double(menuFontSize) * resolved.scaleFactor))
          let fc = FontConfig(descriptor: "\(fontOverride):\(Int(scaledSize))", source: .bundled)
          let nsFont =
            NSFont(name: fc.name, size: scaledSize) ?? NSFont.menuFont(ofSize: menuFontSize)
          title.append(NSAttributedString(string: resolved.glyph, attributes: [.font: nsFont]))
        } else {
          title.append(NSAttributedString(string: resolved.glyph))
        }
      } else {
        title.append(NSAttributedString(string: icon))
      }
      title.append(NSAttributedString(string: " "))
    }
    title.append(NSAttributedString(string: label))

    // Apply theme foreground color when set.
    if let textColor {
      title.addAttribute(
        .foregroundColor, value: NSColor(textColor),
        range: NSRange(location: 0, length: title.length))
    }

    let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    item.attributedTitle = title
    if let command {
      setCommand(command, environment: environment, on: item)
    } else {
      item.isEnabled = false
    }
    return item

  case .check(let label, let checked, let command, let uncheckedCommand):
    // A custom NSView, so a click doesn't dismiss the menu and several
    // items can be checked or unchecked in one visit.
    let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    item.view = NativeMenuCheckItemView(
      label: label, isChecked: checked, command: command, uncheckedCommand: uncheckedCommand,
      environment: environment, textColor: textColor)
    return item

  case .toggle(let label, let on, let command):
    return hostedItem(
      NativeMenuToggleView(label: label, isOn: on, textColor: textColor) {
        if let command {
          runCommand(command, environment: environment)
        }
      }, width: 220, height: 28)

  case .header(let content):
    return hostedItem(NativeMenuHeaderView(content: content, textColor: textColor ?? .primary))

  case .divider:
    return NSMenuItem.separator()

  case .text(let content, let bold, let secondary, let strikethrough):
    return hostedItem(
      NativeMenuTextView(
        content: content, isBold: bold, isSecondary: secondary, isStrikethrough: strikethrough,
        textColor: textColor))
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
class NativeMenuCheckItemView: NativeMenuItemView {
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
    let hosting = NSHostingView(rootView: content)
    host(hosting)
    self.hostingView = hosting
  }

  /// The check as it stands, in the highlight's text colour while highlighted.
  private var content: NativeMenuCheckContent {
    NativeMenuCheckContent(
      label: label, isChecked: isChecked,
      textColor: isHighlighted ? Self.highlightedTextColor : textColor)
  }

  override func highlightChanged() {
    hostingView?.rootView = content
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
    hostingView?.rootView = content
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
