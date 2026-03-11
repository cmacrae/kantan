import AppKit
import Combine
import SwiftUI

// MARK: - Live Content Provider

/// Observable object that feeds live template variable updates to
/// SwiftUI popup/menu views. Connected to a ModuleViewModel via
/// Combine so content refreshes in place without closing the panel.
@MainActor
class LiveContentProvider: ObservableObject {
  @Published var templateVariables: [String: String] = [:]
  @Published var displayValue: String?
  @Published var displayIcon: String?
  @Published var descriptors: [MenuItemDescriptor] = []
  private var cancellables = Set<AnyCancellable>()

  let isStatic: Bool

  init(viewModel: ModuleViewModel, descriptorBuilder: (() -> [MenuItemDescriptor])? = nil) {
    self.isStatic = false
    self.templateVariables = viewModel.templateVariables
    self.displayValue = viewModel.displayValue
    self.displayIcon = viewModel.displayIcon

    viewModel.$templateVariables
      .receive(on: RunLoop.main)
      .sink { [weak self] vars in
        self?.templateVariables = vars
        if let builder = descriptorBuilder {
          self?.descriptors = builder()
        }
      }
      .store(in: &cancellables)

    viewModel.$displayValue
      .receive(on: RunLoop.main)
      .sink { [weak self] val in self?.displayValue = val }
      .store(in: &cancellables)

    viewModel.$displayIcon
      .receive(on: RunLoop.main)
      .sink { [weak self] icon in self?.displayIcon = icon }
      .store(in: &cancellables)
  }

  /// Creates a static (non-updating) provider for backward compatibility.
  private init(staticMarker: Bool) {
    self.isStatic = true
  }

  static func `static`() -> LiveContentProvider {
    LiveContentProvider(staticMarker: true)
  }

  func resolveTemplate(_ template: String) -> String {
    var result = template
    if let value = displayValue {
      result = result.replacingOccurrences(of: "{value}", with: value)
    }
    if let icon = displayIcon {
      result = result.replacingOccurrences(of: "{icon}", with: icon)
    }
    for (key, val) in templateVariables {
      result = result.replacingOccurrences(of: "{\(key)}", with: val)
    }
    return result
  }
}

// MARK: - Menu Item Descriptor

struct MenuItemDescriptor {
  let label: String?
  let iconGlyph: String?
  let isSeparator: Bool
  let isHeader: Bool
  let isToggle: Bool
  let isToggleOn: Bool
  let isCheck: Bool
  let isChecked: Bool
  let action: (() -> Void)?
  let toggleAction: ((@escaping () -> Void) -> Void)?

  init(
    label: String? = nil,
    iconGlyph: String? = nil,
    isSeparator: Bool = false,
    isHeader: Bool = false,
    isToggle: Bool = false,
    isToggleOn: Bool = false,
    isCheck: Bool = false,
    isChecked: Bool = false,
    action: (() -> Void)? = nil,
    toggleAction: ((@escaping () -> Void) -> Void)? = nil
  ) {
    self.label = label
    self.iconGlyph = iconGlyph
    self.isSeparator = isSeparator
    self.isHeader = isHeader
    self.isToggle = isToggle
    self.isToggleOn = isToggleOn
    self.isCheck = isCheck
    self.isChecked = isChecked
    self.action = action
    self.toggleAction = toggleAction
  }

  static func item(_ label: String, action: @escaping () -> Void) -> MenuItemDescriptor {
    MenuItemDescriptor(label: label, action: action)
  }

  static func item(_ label: String, iconGlyph: String?, action: @escaping () -> Void)
    -> MenuItemDescriptor
  {
    MenuItemDescriptor(label: label, iconGlyph: iconGlyph, action: action)
  }

  static func header(_ label: String) -> MenuItemDescriptor {
    MenuItemDescriptor(label: label, isHeader: true)
  }

  static func separator() -> MenuItemDescriptor {
    MenuItemDescriptor(isSeparator: true)
  }

  static func toggle(_ label: String, isOn: Bool, action: @escaping (@escaping () -> Void) -> Void)
    -> MenuItemDescriptor
  {
    MenuItemDescriptor(label: label, isToggle: true, isToggleOn: isOn, toggleAction: action)
  }

  /// A checkable item with a circle/checkmark indicator (like Reminders.app).
  /// The action takes a completion callback for menu rebuilding.
  static func check(
    _ label: String, isChecked: Bool, action: @escaping (@escaping () -> Void) -> Void
  ) -> MenuItemDescriptor {
    MenuItemDescriptor(label: label, isCheck: true, isChecked: isChecked, toggleAction: action)
  }
}

// MARK: - Popup Panel

/// Uses `windowDidResignKey` for natural click-outside dismiss.
class PopupPanel: NSPanel, NSWindowDelegate {
  var onResignKey: (() -> Void)?

  override var canBecomeKey: Bool { true }

  override init(
    contentRect: NSRect,
    styleMask style: NSWindow.StyleMask,
    backing bufferingType: NSWindow.BackingStoreType,
    defer flag: Bool
  ) {
    super.init(contentRect: contentRect, styleMask: style, backing: bufferingType, defer: flag)
    self.delegate = self
  }

  func windowDidResignKey(_ notification: Notification) {
    onResignKey?()
  }
}

// MARK: - Native Menu Target

class NativeMenuTarget: NSObject {
  let handler: () -> Void
  init(handler: @escaping () -> Void) {
    self.handler = handler
  }
  @objc func menuAction(_ sender: Any?) {
    handler()
  }
}

// MARK: - Popup Manager

/// Centralised manager for all tooltips, menus, and popups.
/// Always uses native macOS controls (NSVisualEffectView, system colors)
/// as the foundation. In "theme" mode, colors are tinted on top of the
/// native materials to maintain a native feel while respecting user config.
@MainActor
class PopupManager {
  private var activePanel: NSPanel?
  private var activePopupId: String?
  private var activeLiveContent: LiveContentProvider?
  private var tooltipPanel: NSPanel?
  private var tooltipLabel: NSTextField?
  private var tooltipRefreshTimer: Timer?
  private var tooltipRefreshProvider: (() -> String)?
  weak var themeProvider: ThemeProvider?
  var appearance: AppearanceStyle = .theme

  /// Whether we're in native appearance mode (use system colors throughout).
  var isNative: Bool { appearance == .native }

  var effectiveFgColor: NSColor {
    themeProvider?.globalFgNSColor() ?? .labelColor
  }

  var effectiveBgColor: NSColor {
    themeProvider?.globalBgNSColor() ?? .windowBackgroundColor
  }

  var isPopupActive: Bool {
    activePanel != nil
  }

  // MARK: - Coordinate Conversion

  /// Convert a point from SwiftUI .global coordinate space (window-local,
  /// Y-down from top-left) to macOS screen coordinates (Y-up from bottom-left).
  /// Uses the provided window for coordinate conversion. Each display has
  /// its own panels, so the caller must supply the correct window.
  func screenPoint(from swiftUIPoint: NSPoint, in window: NSWindow?) -> NSPoint {
    guard let window = window else { return swiftUIPoint }
    let panelFrame = window.frame
    return NSPoint(
      x: panelFrame.origin.x + swiftUIPoint.x,
      y: panelFrame.origin.y + panelFrame.height - swiftUIPoint.y
    )
  }

  // MARK: - Screen Clamping

  /// Clamp a rect to the visible area of the screen that contains the
  /// rect's origin. Falls back to the main screen if no match.
  private func clampToScreen(_ rect: NSRect) -> NSRect {
    let screen =
      NSScreen.screens.first(where: { $0.frame.contains(rect.origin) })?.visibleFrame
      ?? NSScreen.main?.visibleFrame
    guard let screen = screen else { return rect }
    var clamped = rect
    if clamped.maxX > screen.maxX {
      clamped.origin.x = screen.maxX - clamped.width
    }
    if clamped.origin.x < screen.minX {
      clamped.origin.x = screen.minX
    }
    if clamped.origin.y < screen.minY {
      clamped.origin.y = screen.minY
    }
    if clamped.maxY > screen.maxY {
      clamped.origin.y = screen.maxY - clamped.height
    }
    return clamped
  }

  // MARK: - Tooltip

  func showTooltip(
    text: String, anchorPoint: NSPoint, refreshProvider: (() -> String)? = nil
  ) {
    guard !isPopupActive else { return }
    hideTooltip()

    let label = NSTextField(labelWithString: text)
    label.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
    label.textColor = isNative ? .labelColor : effectiveFgColor
    label.backgroundColor = .clear
    label.isBezeled = false
    label.isEditable = false
    label.sizeToFit()

    let padding: CGFloat = 8
    let panelWidth = label.frame.width + padding * 2
    let panelHeight = label.frame.height + padding * 2

    var panelRect = NSRect(
      x: anchorPoint.x - panelWidth / 2,
      y: anchorPoint.y - panelHeight - 4,
      width: panelWidth,
      height: panelHeight
    )
    panelRect = clampToScreen(panelRect)

    let panel = makeNonActivatingPanel(rect: panelRect)
    panel.ignoresMouseEvents = true

    let effect = NSVisualEffectView(frame: NSRect(origin: .zero, size: panelRect.size))
    effect.material = isNative ? .toolTip : .menu
    effect.state = .active
    effect.blendingMode = .behindWindow
    effect.wantsLayer = true
    effect.layer?.cornerRadius = 6
    effect.layer?.masksToBounds = true

    if !isNative {
      let tint = NSView(frame: NSRect(origin: .zero, size: panelRect.size))
      tint.wantsLayer = true
      tint.layer?.backgroundColor = effectiveBgColor.withAlphaComponent(0.85).cgColor
      tint.autoresizingMask = [.width, .height]
      effect.addSubview(tint)
    }

    label.frame.origin = NSPoint(x: padding, y: padding)
    effect.addSubview(label)

    panel.contentView = effect
    panel.orderFrontRegardless()
    tooltipPanel = panel
    tooltipLabel = label
    tooltipRefreshProvider = refreshProvider

    if refreshProvider != nil {
      let t = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
        MainActor.assumeIsolated {
          self?.refreshTooltipContent()
        }
      }
      RunLoop.main.add(t, forMode: .common)
      tooltipRefreshTimer = t
    }
  }

  private func refreshTooltipContent() {
    guard let label = tooltipLabel, let provider = tooltipRefreshProvider else { return }
    let newText = provider()
    guard newText != label.stringValue else { return }
    label.stringValue = newText
    label.sizeToFit()

    // Resize panel to fit new content without repositioning
    let padding: CGFloat = 8
    if let panel = tooltipPanel, let effect = panel.contentView {
      let newWidth = label.frame.width + padding * 2
      let newHeight = label.frame.height + padding * 2
      var frame = panel.frame
      let oldMidX = frame.midX
      frame.size.width = newWidth
      frame.size.height = newHeight
      frame.origin.x = oldMidX - newWidth / 2
      effect.frame.size = NSSize(width: newWidth, height: newHeight)
      panel.setFrame(frame, display: true)
    }
  }

  func hideTooltip() {
    tooltipRefreshTimer?.invalidate()
    tooltipRefreshTimer = nil
    tooltipRefreshProvider = nil
    tooltipLabel = nil
    tooltipPanel?.orderOut(nil)
    tooltipPanel = nil
  }

  // MARK: - Menu

  func showMenu(
    descriptors: [MenuItemDescriptor], moduleName: String, anchorPoint: NSPoint,
    moduleMinX: CGFloat? = nil, rebuilder: (() -> Void)? = nil,
    liveContent: LiveContentProvider? = nil
  ) {
    guard !descriptors.isEmpty else { return }

    let menuId = "\(moduleName):menu"

    if dismissIfActive(menuId) { return }

    if isNative, liveContent == nil {
      // Native NSMenu left-aligns at the anchor point. Use the
      // module's left edge X so the menu appears directly below
      // the module, matching native macOS menu bar behaviour.
      // Menus with live content always use the themed path so
      // SwiftUI can observe and re-render updates in place.
      var nativeAnchor = anchorPoint
      if let minX = moduleMinX {
        nativeAnchor.x = minX
      }
      showNativeMenu(descriptors: descriptors, anchorPoint: nativeAnchor, rebuilder: rebuilder)
    } else {
      showThemedMenu(
        descriptors: descriptors, moduleName: moduleName, anchorPoint: anchorPoint,
        rebuilder: rebuilder, liveContent: liveContent)
    }
  }

  // MARK: - Native NSMenu

  /// Build and display an actual NSMenu. This gives us the real macOS
  /// menu appearance — correct material, shadow, corner radius, and
  /// item rendering, identical to system menu bar dropdown menus.
  /// `popUp()` is synchronous: it blocks until the menu is dismissed.
  private func showNativeMenu(
    descriptors: [MenuItemDescriptor], anchorPoint: NSPoint, rebuilder: (() -> Void)? = nil
  ) {
    let menu = NSMenu()
    menu.autoenablesItems = false

    for descriptor in descriptors {
      if descriptor.isSeparator {
        menu.addItem(.separator())
      } else if descriptor.isHeader {
        if #available(macOS 14, *) {
          menu.addItem(.sectionHeader(title: descriptor.label ?? ""))
        } else {
          let item = NSMenuItem(title: descriptor.label ?? "", action: nil, keyEquivalent: "")
          item.isEnabled = false
          item.attributedTitle = NSAttributedString(
            string: (descriptor.label ?? "").uppercased(),
            attributes: [
              .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
              .foregroundColor: NSColor.secondaryLabelColor,
            ]
          )
          menu.addItem(item)
        }
      } else if descriptor.isCheck {
        let item = NSMenuItem(
          title: descriptor.label ?? "",
          action: #selector(NativeMenuTarget.menuAction(_:)),
          keyEquivalent: "")
        let size = NSFont.menuFont(ofSize: 0).pointSize
        let config = NSImage.SymbolConfiguration(pointSize: size, weight: .regular)
        if descriptor.isChecked {
          item.image = NSImage(
            systemSymbolName: "checkmark.circle.fill", accessibilityDescription: "completed")?
            .withSymbolConfiguration(config)
          item.attributedTitle = NSAttributedString(
            string: descriptor.label ?? "",
            attributes: [
              .strikethroughStyle: NSUnderlineStyle.single.rawValue,
              .foregroundColor: NSColor.secondaryLabelColor,
            ]
          )
        } else {
          item.image = NSImage(systemSymbolName: "circle", accessibilityDescription: "incomplete")?
            .withSymbolConfiguration(config)
        }
        let target = NativeMenuTarget {
          descriptor.toggleAction? { [rebuilder] in
            rebuilder?()
          }
        }
        item.target = target
        item.representedObject = target
        menu.addItem(item)
      } else if descriptor.isToggle {
        let item = NSMenuItem()
        let toggleView = NativeMenuToggleView(
          label: descriptor.label ?? "",
          isOn: descriptor.isToggleOn,
          action: {
            menu.cancelTracking()
            descriptor.toggleAction? { [rebuilder] in
              rebuilder?()
            }
          }
        )
        let hosting = NSHostingView(rootView: toggleView)
        hosting.frame = NSRect(x: 0, y: 0, width: 220, height: 28)
        item.view = hosting
        menu.addItem(item)
      } else {
        let title: String
        if let glyph = descriptor.iconGlyph, !glyph.isEmpty {
          title = "\(glyph)  \(descriptor.label ?? "")"
        } else {
          title = descriptor.label ?? ""
        }
        let item = NSMenuItem(
          title: title,
          action: #selector(NativeMenuTarget.menuAction(_:)),
          keyEquivalent: "")
        let target = NativeMenuTarget {
          descriptor.action?()
        }
        item.target = target
        item.representedObject = target
        menu.addItem(item)
      }
    }

    menu.popUp(positioning: nil, at: anchorPoint, in: nil)
  }

  // MARK: - Themed Menu (PopupPanel + SwiftUI)

  private func showThemedMenu(
    descriptors: [MenuItemDescriptor], moduleName: String, anchorPoint: NSPoint,
    rebuilder: (() -> Void)? = nil, liveContent: LiveContentProvider? = nil
  ) {
    let resolvedFg: Color = isNative ? .primary : Color(nsColor: effectiveFgColor)
    let menuView = SwiftUIThemedMenuView(
      descriptors: descriptors,
      isNative: isNative,
      resolvedFg: resolvedFg,
      dismissHandler: { [weak self] in self?.dismissPopup() },
      rebuilder: rebuilder,
      liveContent: liveContent
    )

    let hostingView = NSHostingView(rootView: menuView)
    let fittingSize = hostingView.fittingSize
    let panelWidth = max(fittingSize.width, 160)
    let panelHeight = max(fittingSize.height, 20)

    let panelRect = NSRect(
      x: anchorPoint.x - panelWidth / 2,
      y: anchorPoint.y - panelHeight - 4,
      width: panelWidth,
      height: panelHeight
    )

    presentPopupPanel(
      hostingView: hostingView, panelRect: panelRect, popupId: "\(moduleName):menu",
      liveContent: liveContent)
  }

  // MARK: - Popup

  /// Returns true if the popup was already showing (and was dismissed).
  private func dismissIfActive(_ popupId: String) -> Bool {
    if popupId == activePopupId, activePanel != nil {
      dismissPopup()
      return true
    }
    dismissPopup()
    return false
  }

  func dismissPopup() {
    activePanel?.orderOut(nil)
    activePanel = nil
    activePopupId = nil
    activeLiveContent = nil
  }

  // MARK: - Panel Factories

  private func configurePanel(_ panel: NSPanel) {
    panel.level = .floating
    panel.isOpaque = false
    panel.hasShadow = true
    panel.backgroundColor = .clear
    panel.isMovable = false
    panel.collectionBehavior = [.canJoinAllSpaces, .transient]
  }

  private func makeNonActivatingPanel(rect: NSRect) -> NSPanel {
    let panel = NSPanel(
      contentRect: rect,
      styleMask: [.nonactivatingPanel],
      backing: .buffered,
      defer: false
    )
    configurePanel(panel)
    return panel
  }

  private func makePopupPanel(rect: NSRect) -> PopupPanel {
    let panel = PopupPanel(
      contentRect: rect,
      styleMask: [.nonactivatingPanel],
      backing: .buffered,
      defer: false
    )
    configurePanel(panel)
    panel.onResignKey = { [weak self] in
      self?.dismissPopup()
    }
    return panel
  }

  /// Always uses NSVisualEffectView(.menu) for the native translucent
  /// material. In theme mode, adds a semi-transparent tint overlay so
  /// the user's configured color shows through while preserving the
  /// native vibrancy effect.
  private func makePopupContainer(size: NSSize) -> NSView {
    let effect = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
    effect.material = .menu
    effect.state = .active
    effect.blendingMode = .behindWindow
    effect.wantsLayer = true
    effect.layer?.cornerRadius = 6
    effect.layer?.masksToBounds = true

    if !isNative {
      // Tint overlay: semi-transparent theme color on top of native blur
      let tint = NSView(frame: NSRect(origin: .zero, size: size))
      tint.wantsLayer = true
      tint.layer?.backgroundColor = effectiveBgColor.withAlphaComponent(0.85).cgColor
      tint.autoresizingMask = [.width, .height]
      effect.addSubview(tint)
    }

    return effect
  }

  /// Present a SwiftUI hosting view in a popup panel, clamped to screen bounds.
  /// Shared by showThemedMenu and showUserPopup to avoid duplicating the
  /// panel-creation and container-setup pattern.
  private func presentPopupPanel(
    hostingView: NSView, panelRect: NSRect, popupId: String,
    liveContent: LiveContentProvider? = nil
  ) {
    let clamped = clampToScreen(panelRect)
    let panel = makePopupPanel(rect: clamped)

    let container = makePopupContainer(size: clamped.size)
    hostingView.frame = container.bounds
    hostingView.autoresizingMask = [.width, .height]
    container.addSubview(hostingView)

    panel.contentView = container
    panel.makeKeyAndOrderFront(nil)

    activePanel = panel
    activePopupId = popupId
    activeLiveContent = liveContent
  }

  // MARK: - User-Defined Popup

  func showUserPopup(
    config: PopupConfig, moduleName: String, anchorPoint: NSPoint,
    templateResolver: @escaping (String) -> String,
    fgColor: Color, iconFont: Font?,
    liveContent: LiveContentProvider? = nil
  ) {
    let popupId = "\(moduleName):user-popup"

    if dismissIfActive(popupId) { return }

    let resolvedFg: Color = isNative ? .primary : fgColor
    let popupView = UserPopupView(
      config: config,
      templateResolver: templateResolver,
      isNative: isNative,
      resolvedFg: resolvedFg,
      iconFont: iconFont,
      dismissHandler: { [weak self] in self?.dismissPopup() },
      liveContent: liveContent
    )

    let hostingView = NSHostingView(rootView: popupView)
    let fittingSize = hostingView.fittingSize
    let panelWidth = max(fittingSize.width, CGFloat(config.width ?? 240))
    let panelHeight = max(fittingSize.height, 40)

    let panelRect = NSRect(
      x: anchorPoint.x - panelWidth / 2,
      y: anchorPoint.y - panelHeight - 4,
      width: panelWidth,
      height: panelHeight
    )

    presentPopupPanel(
      hostingView: hostingView, panelRect: panelRect, popupId: popupId,
      liveContent: liveContent)
  }
}

// MARK: - User-Defined Popup View

struct UserPopupView: View {
  let config: PopupConfig
  let templateResolver: (String) -> String
  let isNative: Bool
  let resolvedFg: Color
  let iconFont: Font?
  let dismissHandler: () -> Void
  @ObservedObject var liveContent: LiveContentProvider

  /// Initializer that accepts an optional LiveContentProvider, creating
  /// a dummy static one if nil (for backward compatibility).
  init(
    config: PopupConfig, templateResolver: @escaping (String) -> String,
    isNative: Bool, resolvedFg: Color, iconFont: Font?,
    dismissHandler: @escaping () -> Void, liveContent: LiveContentProvider? = nil
  ) {
    self.config = config
    self.templateResolver = templateResolver
    self.isNative = isNative
    self.resolvedFg = resolvedFg
    self.iconFont = iconFont
    self.dismissHandler = dismissHandler
    self.liveContent = liveContent ?? LiveContentProvider.static()
  }

  private func resolve(_ template: String) -> String {
    if liveContent.isStatic {
      return templateResolver(template)
    }
    return liveContent.resolveTemplate(template)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      if let title = config.title {
        Text(resolve(title))
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(resolvedFg)
          .padding(.horizontal, 16)
          .frame(height: 32, alignment: .leading)
        Divider()
          .padding(.horizontal, 8)
      }

      ForEach(Array(config.rows.enumerated()), id: \.offset) { _, row in
        popupRow(row)
      }
    }
    .padding(.vertical, 8)
    .frame(minWidth: CGFloat(config.width ?? 240))
  }

  @ViewBuilder
  private func popupRow(_ row: PopupRowConfig) -> some View {
    switch row.type {
    case "header":
      Text(resolve(row.content ?? row.label ?? ""))
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(resolvedFg.opacity(0.5))
        .padding(.horizontal, 16)
        .frame(height: 22, alignment: .leading)

    case "text":
      HStack(spacing: 8) {
        if let icon = row.icon {
          Text(resolve(icon))
            .font(iconFont ?? .system(size: 13))
            .foregroundStyle(rowFgColor(row))
        }
        if let label = row.label {
          Text(resolve(label))
            .font(.system(size: 13))
            .foregroundStyle(rowFgColor(row))
        }
        Spacer()
        if let value = row.value {
          Text(resolve(value))
            .font(.system(size: 13))
            .foregroundStyle(rowFgColor(row))
        }
      }
      .padding(.horizontal, 16)
      .frame(height: 28)

    case "separator":
      Divider()
        .padding(.horizontal, 8)
        .padding(.vertical, 4)

    case "action":
      PopupActionRow(
        label: resolve(row.label ?? ""),
        icon: row.icon.map { resolve($0) },
        iconFont: iconFont,
        isNative: isNative,
        resolvedFg: resolvedFg,
        command: row.command,
        dismissHandler: dismissHandler
      )

    default:
      EmptyView()
    }
  }

  private func rowFgColor(_ row: PopupRowConfig) -> Color {
    row.style == "secondary" ? resolvedFg.opacity(0.5) : resolvedFg
  }
}

struct PopupActionRow: View {
  let label: String
  let icon: String?
  let iconFont: Font?
  let isNative: Bool
  let resolvedFg: Color
  let command: String?
  let dismissHandler: () -> Void

  var body: some View {
    HoverableRowView(
      label: label,
      icon: icon,
      iconFont: iconFont,
      iconWidth: nil,
      isNative: isNative,
      resolvedFg: resolvedFg,
      action: {
        dismissHandler()
        guard let command = command, !command.isEmpty else { return }
        runShellCommand(command)
      }
    )
  }
}

// MARK: - Native Menu Toggle View

/// SwiftUI Toggle embedded in a native NSMenuItem via NSHostingView.
/// Used only for `.toggle()` descriptors in native NSMenu mode.
struct NativeMenuToggleView: View {
  let label: String
  @State var isOn: Bool
  let action: () -> Void

  var body: some View {
    Toggle(label, isOn: $isOn)
      .toggleStyle(.switch)
      .controlSize(.small)
      .padding(.horizontal, 14)
      .frame(height: 28)
      .onChange(of: isOn) { _, _ in action() }
  }
}
