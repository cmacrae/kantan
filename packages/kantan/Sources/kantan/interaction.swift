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
  @Published var viewTree: ViewNode?
  @Published var data: [String: [[String: String]]] = [:]
  private var cancellables = Set<AnyCancellable>()

  let isStatic: Bool

  init(viewModel: ModuleViewModel) {
    self.isStatic = false
    self.templateVariables = viewModel.templateVariables
    self.displayValue = viewModel.displayValue
    self.displayIcon = viewModel.displayIcon
    self.viewTree = viewModel.viewTree
    self.data = viewModel.data

    viewModel.$templateVariables
      .receive(on: RunLoop.main)
      .sink { [weak self] vars in
        self?.templateVariables = vars
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

    viewModel.$viewTree
      .receive(on: RunLoop.main)
      .sink { [weak self] tree in self?.viewTree = tree }
      .store(in: &cancellables)

    viewModel.$data
      .receive(on: RunLoop.main)
      .sink { [weak self] d in self?.data = d }
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

  /// Show a DSL view tree as a tooltip (for rich hover content).
  func showDSLTooltip(
    viewTree: ViewNode, anchorPoint: NSPoint, liveContent: LiveContentProvider
  ) {
    guard !isPopupActive else { return }
    hideTooltip()

    let resolver = TemplateResolver(
      variables: liveContent.templateVariables,
      data: liveContent.data
    )
    if let value = liveContent.displayValue {
      resolver.variables["value"] = value
    }
    if let icon = liveContent.displayIcon {
      resolver.variables["icon"] = icon
    }

    let dslView = DSLRendererView(
      node: viewTree, resolver: resolver, isNative: isNative,
      dismissHandler: {}, depth: 0
    )
    .padding(8)

    let hostingView = NSHostingView(rootView: dslView)
    let fittingSize = hostingView.fittingSize
    let panelWidth = max(fittingSize.width, 40)
    let panelHeight = max(fittingSize.height, 20)

    var panelRect = NSRect(
      x: anchorPoint.x - panelWidth / 2,
      y: anchorPoint.y - panelHeight - 4,
      width: panelWidth,
      height: panelHeight
    )
    panelRect = clampToScreen(panelRect)

    let panel = makeNonActivatingPanel(rect: panelRect)
    panel.ignoresMouseEvents = true

    let container = makePopupContainer(size: panelRect.size)
    hostingView.frame = container.bounds
    hostingView.autoresizingMask = [.width, .height]
    container.addSubview(hostingView)

    panel.contentView = container
    panel.orderFrontRegardless()
    tooltipPanel = panel
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

  // MARK: - Menu (DSL)

  /// Show a menu from a ViewNode tree. Dispatches to native NSMenu or
  /// themed SwiftUI panel based on appearance mode.
  func showMenu(
    viewTree: ViewNode, moduleName: String, anchorPoint: NSPoint,
    moduleMinX: CGFloat? = nil, liveContent: LiveContentProvider
  ) {
    let menuId = "\(moduleName):menu"

    if dismissIfActive(menuId) { return }

    let resolver = TemplateResolver(
      variables: liveContent.templateVariables,
      data: liveContent.data
    )
    if let value = liveContent.displayValue {
      resolver.variables["value"] = value
    }
    if let icon = liveContent.displayIcon {
      resolver.variables["icon"] = icon
    }

    if isNative {
      var nativeAnchor = anchorPoint
      if let minX = moduleMinX {
        nativeAnchor.x = minX
      }
      let menu = buildNativeMenu(from: viewTree, resolver: resolver)
      menu.popUp(positioning: nil, at: nativeAnchor, in: nil)
    } else {
      showDSLView(
        viewTree: viewTree, moduleName: moduleName, anchorPoint: anchorPoint,
        popupId: menuId, liveContent: liveContent, resolver: resolver)
    }
  }

  // MARK: - DSL View (PopupPanel + SwiftUI)

  /// Show a DSL ViewNode tree in a themed popup panel.
  func showDSLView(
    viewTree: ViewNode, moduleName: String, anchorPoint: NSPoint,
    popupId: String? = nil, liveContent: LiveContentProvider,
    resolver: TemplateResolver? = nil
  ) {
    let effectiveId = popupId ?? "\(moduleName):dsl"

    if dismissIfActive(effectiveId) { return }

    let effectiveResolver =
      resolver
      ?? {
        let r = TemplateResolver(
          variables: liveContent.templateVariables,
          data: liveContent.data
        )
        if let value = liveContent.displayValue {
          r.variables["value"] = value
        }
        if let icon = liveContent.displayIcon {
          r.variables["icon"] = icon
        }
        return r
      }()

    let dslView = DSLRendererView(
      node: viewTree, resolver: effectiveResolver, isNative: isNative,
      dismissHandler: { [weak self] in self?.dismissPopup() }, depth: 0
    )
    .padding(.vertical, 8)

    let hostingView = NSHostingView(rootView: dslView)
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
      hostingView: hostingView, panelRect: panelRect, popupId: effectiveId,
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
  func makePopupContainer(size: NSSize) -> NSView {
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
}

// MARK: - Native Menu Toggle View

/// SwiftUI Toggle embedded in a native NSMenuItem via NSHostingView.
/// Used only for toggle nodes in native NSMenu mode.
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
