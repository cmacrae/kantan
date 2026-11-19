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
  /// Variables for the commands the module's views run.
  let commandEnvironment: [String: String]
  private var cancellables = Set<AnyCancellable>()

  init(viewModel: ModuleViewModel) {
    self.commandEnvironment =
      (viewModel.moduleConfig.config as? CommandConfig)?.kantanEnvironment()
      ?? ["KANTAN_MODULE_NAME": viewModel.moduleConfig.name]
    self.templateVariables = viewModel.templateVariables
    self.displayValue = viewModel.displayValue
    self.displayIcon = viewModel.displayIcon
    self.viewTree = viewModel.viewTree
    self.data = viewModel.data

    // Everything is taken together once the module has changed, so a view
    // is never drawn from one output's tree and another's data.
    viewModel.objectWillChange
      .receive(on: DispatchQueue.main)
      .sink { [weak self, weak viewModel] _ in
        guard let self, let viewModel else { return }
        self.take(from: viewModel)
      }
      .store(in: &cancellables)
  }

  /// Takes what `viewModel` shows now, leaving alone what hasn't changed.
  private func take(from viewModel: ModuleViewModel) {
    if templateVariables != viewModel.templateVariables {
      templateVariables = viewModel.templateVariables
    }
    if displayValue != viewModel.displayValue { displayValue = viewModel.displayValue }
    if displayIcon != viewModel.displayIcon { displayIcon = viewModel.displayIcon }
    if data != viewModel.data { data = viewModel.data }
    viewTree = viewModel.viewTree
  }

  /// Fires once after each burst of changes, with the new values in place.
  var changes: AnyPublisher<Void, Never> {
    objectWillChange
      .debounce(for: .milliseconds(50), scheduler: DispatchQueue.main)
      .eraseToAnyPublisher()
  }
}

// MARK: - Live DSL View

/// Renders a module's view tree with its latest variables and data.
struct LiveDSLView: View {
  @ObservedObject var liveContent: LiveContentProvider
  /// The view tree from the module's config, used in place of the module's own.
  let configViewTree: ViewNode?
  let makeResolver: (LiveContentProvider) -> TemplateResolver
  let isNative: Bool
  let dismissHandler: () -> Void

  var body: some View {
    if let tree = configViewTree ?? liveContent.viewTree {
      DSLRendererView(
        node: tree, resolver: makeResolver(liveContent), isNative: isNative,
        dismissHandler: dismissHandler, depth: 0)
    }
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
  /// The name of the module whose menu or popup is open, if one is.
  let openModule = CurrentValueSubject<String?, Never>(nil)
  /// Watches for the pointer leaving a popup a click has left open.
  private var pointerLeaveTimer: Timer?
  static let pointerLeaveDelay: TimeInterval = 0.4
  static let pointerLeaveMargin: CGFloat = 8
  private var tooltipPanel: NSPanel?
  private var tooltipLabel: NSTextField?
  private var tooltipRefreshTimer: Timer?
  private var tooltipRefreshProvider: (() -> String)?
  private var tooltipClickMonitor: Any?
  weak var themeProvider: ThemeProvider?
  var isNativeAppearance: Bool = false

  /// Whether we're in native appearance mode (use system colors throughout).
  var isNative: Bool { isNativeAppearance }

  var effectiveFgColor: NSColor {
    themeProvider?.globalFgNSColor() ?? .labelColor
  }

  /// The theme's resolved fg color for use as the default text color in DSL views.
  var defaultTextColor: Color {
    if isNative { return .primary }
    return Color(nsColor: effectiveFgColor)
  }

  /// A resolver for a module's view: its variables, data, `{value}`,
  /// `{icon}` and theme colours, and the environment its commands run with.
  func makeResolver(for liveContent: LiveContentProvider) -> TemplateResolver {
    let resolver = TemplateResolver(
      variables: liveContent.templateVariables, data: liveContent.data)
    configureThemeResolution(resolver)
    if let value = liveContent.displayValue {
      resolver.variables["value"] = value
    }
    if let icon = liveContent.displayIcon {
      resolver.variables["icon"] = icon
    }
    resolver.commandEnvironment = liveContent.commandEnvironment
    return resolver
  }

  /// Configure a TemplateResolver to resolve `{theme(name)}` patterns via ThemeProvider.
  func configureThemeResolution(_ resolver: TemplateResolver) {
    resolver.fallbackResolver = { [weak self] key in
      guard key.hasPrefix("theme("), key.hasSuffix(")") else { return nil }
      return self?.themeProvider?.resolveColorString("{\(key)}")
    }
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
  /// rect's top centre, just below what it's anchored to. Falls back to the
  /// main screen if no match.
  private func clampToScreen(_ rect: NSRect) -> NSRect {
    Self.clamp(
      rect, screens: NSScreen.screens.map { ($0.frame, $0.visibleFrame) },
      fallback: NSScreen.main?.visibleFrame)
  }

  /// `rect` moved into the visible frame of the first of `screens` whose
  /// frame contains its top centre, or into `fallback`.
  static func clamp(
    _ rect: NSRect, screens: [(frame: NSRect, visible: NSRect)], fallback: NSRect?
  ) -> NSRect {
    let anchor = NSPoint(x: rect.midX, y: rect.maxY)
    let screen = screens.first(where: { $0.frame.contains(anchor) })?.visible ?? fallback
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

    let effect = makeEffectView(
      size: panelRect.size, material: isNative ? .toolTip : .menu)

    label.frame.origin = NSPoint(x: padding, y: padding)
    effect.addSubview(label)

    panel.contentView = effect
    panel.orderFrontRegardless()
    tooltipPanel = panel
    tooltipLabel = label
    hideTooltipOnClickElsewhere()
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

    let resolver = makeResolver(for: liveContent)

    let themeFg = defaultTextColor
    let dslView = DSLRendererView(
      node: viewTree, resolver: resolver, isNative: isNative,
      dismissHandler: {}, depth: 0
    )
    .environment(\.defaultTextColor, themeFg)
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
    hideTooltipOnClickElsewhere()
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

  /// Hides the tooltip on the next click that goes to another app. A click
  /// on a masked module is one: it passes through to the menu bar item
  /// underneath and opens that item's menu.
  func hideTooltipOnClickElsewhere() {
    guard tooltipClickMonitor == nil else { return }
    tooltipClickMonitor = NSEvent.addGlobalMonitorForEvents(
      matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
    ) { [weak self] _ in
      DispatchQueue.main.async {
        MainActor.assumeIsolated {
          self?.hideTooltip()
        }
      }
    }
  }

  var isWatchingClicksForTooltip: Bool {
    tooltipClickMonitor != nil
  }

  func hideTooltip() {
    if let monitor = tooltipClickMonitor {
      NSEvent.removeMonitor(monitor)
      tooltipClickMonitor = nil
    }
    tooltipRefreshTimer?.invalidate()
    tooltipRefreshTimer = nil
    tooltipRefreshProvider = nil
    tooltipLabel = nil
    tooltipPanel?.orderOut(nil)
    tooltipPanel = nil
  }

  // MARK: - Menu (DSL)

  /// Show a menu from a ViewNode tree. Always uses native NSMenu for
  /// consistent appearance; theme colors are threaded through when active.
  /// The menu's items are rebuilt as the module's content changes, using
  /// `configViewTree` when given and the module's own view tree otherwise.
  func showMenu(
    configViewTree: ViewNode?, moduleName: String, anchorPoint: NSPoint,
    moduleMinX: CGFloat? = nil, liveContent: LiveContentProvider
  ) {
    let menuId = "\(moduleName):menu"

    if dismissIfActive(menuId) { return }

    guard let viewTree = configViewTree ?? liveContent.viewTree else { return }

    var nativeAnchor = anchorPoint
    if let minX = moduleMinX {
      nativeAnchor.x = minX
    }
    let textColor: Color? = isNative ? nil : Color(nsColor: effectiveFgColor)
    let menu = buildNativeMenu(
      from: viewTree, resolver: makeResolver(for: liveContent), textColor: textColor)
    let refresh = liveContent.changes.sink { [weak self, weak menu, weak liveContent] in
      guard let self, let menu, let liveContent,
        let tree = configViewTree ?? liveContent.viewTree
      else { return }
      refreshNativeMenu(
        menu, from: tree, resolver: self.makeResolver(for: liveContent), textColor: textColor)
    }
    openModule.send(moduleName)
    withExtendedLifetime(refresh) {
      _ = menu.popUp(positioning: nil, at: nativeAnchor, in: nil)
    }
    openModule.send(nil)
  }

  // MARK: - DSL View (PopupPanel + SwiftUI)

  /// Show a DSL ViewNode tree in a themed popup panel. The panel's content
  /// and size follow the module's content as it changes, using
  /// `configViewTree` when given and the module's own view tree otherwise.
  func showDSLView(
    configViewTree: ViewNode?, moduleName: String, anchorPoint: NSPoint,
    popupId: String? = nil, liveContent: LiveContentProvider
  ) {
    let effectiveId = popupId ?? "\(moduleName):dsl"

    if dismissIfActive(effectiveId) { return }

    guard configViewTree ?? liveContent.viewTree != nil else { return }

    let themeFg = defaultTextColor
    let dslView = LiveDSLView(
      liveContent: liveContent, configViewTree: configViewTree,
      makeResolver: { [weak self] in
        self?.makeResolver(for: $0) ?? TemplateResolver(variables: [:], data: [:])
      },
      isNative: isNative,
      dismissHandler: { [weak self] in self?.dismissPopup() }
    )
    .environment(\.defaultTextColor, themeFg)
    .environment(\.dismissWhenPointerLeaves) { [weak self] in self?.dismissWhenPointerLeaves() }
    .padding(.vertical, 8)
    // The content is laid out at the height it wants, whatever the panel's,
    // and the panel takes that height as the content is laid out, so the
    // two change together.
    .fixedSize(horizontal: false, vertical: true)
    .onGeometryChange(for: CGSize.self, of: { $0.size }) { [weak self] size in
      self?.resizePopup(effectiveId, toFit: size)
    }
    // The content hangs from the panel's top, so nothing above a change
    // moves.
    .frame(maxHeight: .infinity, alignment: .top)

    let hostingView = NSHostingView(rootView: dslView)

    presentPopupPanel(
      hostingView: hostingView,
      panelRect: popupRect(fitting: hostingView.fittingSize, anchorPoint: anchorPoint),
      popupId: effectiveId, liveContent: liveContent)
    openModule.send(moduleName)
  }

  /// Sizes the popup `popupId` to fit content of `size`, keeping its top
  /// edge, and its centre along it, where they are.
  private func resizePopup(_ popupId: String, toFit size: CGSize) {
    guard activePopupId == popupId, let panel = activePanel else { return }
    let anchor = NSPoint(x: panel.frame.midX, y: panel.frame.maxY + 4)
    let frame = clampToScreen(popupRect(fitting: size, anchorPoint: anchor))
    if frame != panel.frame { panel.setFrame(frame, display: true) }
  }

  /// A frame for a popup whose content is of `size`, centred below
  /// `anchorPoint`.
  private func popupRect(fitting size: CGSize, anchorPoint: NSPoint) -> NSRect {
    let panelWidth = max(size.width.rounded(.up), 160)
    let panelHeight = max(size.height.rounded(.up), 20)
    return NSRect(
      x: anchorPoint.x - panelWidth / 2,
      y: anchorPoint.y - panelHeight - 4,
      width: panelWidth,
      height: panelHeight
    )
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

  /// Closes the popup once the pointer has been away from it for
  /// `pointerLeaveDelay`, for a popup a click has left open. The pointer
  /// counts as on the popup within `pointerLeaveMargin` of it.
  func dismissWhenPointerLeaves() {
    guard pointerLeaveTimer == nil, activePanel != nil else { return }
    var away: Date?
    let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated {
        guard let self, let panel = self.activePanel else { return }
        let margin = -Self.pointerLeaveMargin
        if panel.frame.insetBy(dx: margin, dy: margin).contains(NSEvent.mouseLocation) {
          away = nil
        } else if let since = away {
          if Date().timeIntervalSince(since) >= Self.pointerLeaveDelay { self.dismissPopup() }
        } else {
          away = Date()
        }
      }
    }
    RunLoop.main.add(timer, forMode: .common)
    pointerLeaveTimer = timer
  }

  func dismissPopup() {
    pointerLeaveTimer?.invalidate()
    pointerLeaveTimer = nil
    if openModule.value != nil { openModule.send(nil) }
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

  /// Builds an NSVisualEffectView with a rounded layer-backed corner.
  /// In theme mode, adds a semi-transparent tint overlay so the user's
  /// configured colour shows through while preserving native vibrancy.
  func makeEffectView(size: NSSize, material: NSVisualEffectView.Material) -> NSVisualEffectView {
    let effect = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
    effect.material = material
    effect.state = .active
    effect.blendingMode = .behindWindow
    effect.wantsLayer = true
    effect.layer?.cornerRadius = 6
    effect.layer?.masksToBounds = true

    if !isNative {
      let tint = NSView(frame: NSRect(origin: .zero, size: size))
      tint.wantsLayer = true
      tint.layer?.backgroundColor = effectiveBgColor.withAlphaComponent(0.85).cgColor
      tint.autoresizingMask = [.width, .height]
      effect.addSubview(tint)
    }

    return effect
  }

  /// Always uses NSVisualEffectView(.menu) for the native translucent
  /// material. In theme mode, adds a semi-transparent tint overlay so
  /// the user's configured color shows through while preserving the
  /// native vibrancy effect.
  func makePopupContainer(size: NSSize) -> NSView {
    makeEffectView(size: size, material: .menu)
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
/// Used for toggle nodes in NSMenu menus.
struct NativeMenuToggleView: View {
  let label: String
  @State var isOn: Bool
  var textColor: Color?
  let action: () -> Void

  private var fgColor: Color { textColor ?? .primary }

  var body: some View {
    Toggle(label, isOn: $isOn)
      .toggleStyle(.switch)
      .controlSize(.small)
      .foregroundStyle(fgColor)
      .padding(.horizontal, 14)
      .frame(height: 28)
      .onChange(of: isOn) { _, _ in action() }
  }
}
