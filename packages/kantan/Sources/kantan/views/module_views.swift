import SwiftUI

// MARK: - Window Reader

/// Captures the NSWindow hosting this SwiftUI view. Used to convert
/// SwiftUI coordinates to screen coordinates on the correct display.
/// Uses viewDidMoveToWindow for reliable capture — the NSView may not
/// have a window at creation time.
struct WindowReader: NSViewRepresentable {
  @Binding var window: NSWindow?

  func makeNSView(context: Context) -> WindowReaderView {
    let view = WindowReaderView()
    view.onWindowChange = { self.window = $0 }
    return view
  }

  func updateNSView(_ nsView: WindowReaderView, context: Context) {
    nsView.onWindowChange = { self.window = $0 }
    if let win = nsView.window, self.window !== win {
      self.window = win
    }
  }
}

class WindowReaderView: NSView {
  var onWindowChange: ((NSWindow?) -> Void)?

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    onWindowChange?(window)
  }
}

// MARK: - Scroll Wheel Reader

/// A scroll wheel or trackpad scroll, reduced to what decides its steps.
struct ScrollWheelDelta: Sendable {
  /// Distance along the axis scrolled furthest; negative scrolls content
  /// up or left.
  let delta: CGFloat
  /// Whether the delta is in points (trackpad) rather than lines (wheel).
  let isPrecise: Bool
  /// Whether this is the first event of a trackpad gesture.
  let begins: Bool
  /// Whether this is momentum after the fingers lifted.
  let isMomentum: Bool
}

/// Turns scrolling into steps: one per wheel notch, or one per `distance`
/// points of trackpad scrolling, counted afresh with each gesture and
/// change of direction. Scrolling content up or left steps forward.
/// Momentum after a swipe doesn't step.
struct ScrollStepper {
  static let distance: CGFloat = 24
  private var accumulated: CGFloat = 0

  mutating func steps(for scroll: ScrollWheelDelta) -> Int {
    if scroll.begins { accumulated = 0 }
    guard !scroll.isMomentum else { return 0 }
    guard scroll.isPrecise else { return scroll.delta < 0 ? 1 : scroll.delta > 0 ? -1 : 0 }
    if accumulated * scroll.delta > 0 { accumulated = 0 }
    accumulated -= scroll.delta
    let steps = Int(accumulated / Self.distance)
    accumulated -= CGFloat(steps) * Self.distance
    return steps
  }
}

/// Calls `onStep` with the steps of each scroll over the view it backs,
/// without taking its clicks.
struct ScrollWheelReader: NSViewRepresentable {
  let onStep: (Int) -> Void

  func makeNSView(context: Context) -> ScrollWheelReaderView {
    let view = ScrollWheelReaderView()
    view.onStep = onStep
    return view
  }

  func updateNSView(_ nsView: ScrollWheelReaderView, context: Context) {
    nsView.onStep = onStep
  }
}

class ScrollWheelReaderView: NSView {
  var onStep: ((Int) -> Void)?
  private var stepper = ScrollStepper()
  nonisolated(unsafe) private var monitor: Any?

  deinit {
    if let monitor { NSEvent.removeMonitor(monitor) }
  }

  override func hitTest(_ point: NSPoint) -> NSView? { nil }

  /// Watches scrolls while in a window. The view takes no events itself,
  /// so clicks reach the views in front of it, and sees scrolls through a
  /// monitor instead.
  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    if let monitor {
      NSEvent.removeMonitor(monitor)
      self.monitor = nil
    }
    guard window != nil else { return }
    monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
      let horizontal = abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY)
      let scroll = ScrollWheelDelta(
        delta: horizontal ? event.scrollingDeltaX : event.scrollingDeltaY,
        isPrecise: event.hasPreciseScrollingDeltas, begins: event.phase == .began,
        isMomentum: !event.momentumPhase.isEmpty)
      let windowNumber = event.windowNumber
      let location = event.locationInWindow
      let handled = MainActor.assumeIsolated {
        self?.scroll(scroll, windowNumber: windowNumber, at: location) ?? false
      }
      return handled ? nil : event
    }
  }

  /// Steps for a scroll over the view, reporting whether it was.
  private func scroll(_ scroll: ScrollWheelDelta, windowNumber: Int, at location: NSPoint) -> Bool {
    guard windowNumber == window?.windowNumber, bounds.contains(convert(location, from: nil))
    else { return false }
    let steps = stepper.steps(for: scroll)
    if steps != 0 { onStep?(steps) }
    return true
  }
}

// MARK: - Passthrough Hover

/// Whether the pointer is over a view, from where it is, whether the view
/// is shown, and whether a button was just pressed, which ends a hover.
struct PointerHover {
  private(set) var isHovering = false

  /// The new hover state, or nil when it hasn't changed. A view that isn't
  /// shown is never hovered.
  mutating func pointer(at point: NSPoint, in frame: NSRect, shown: Bool = true, pressed: Bool)
    -> Bool?
  {
    let hovering = shown && !pressed && frame.contains(point)
    guard hovering != isHovering else { return nil }
    isHovering = hovering
    return hovering
  }
}

/// Calls `onHover` as the pointer enters and leaves the view it backs, for
/// views in panels that ignore the mouse, where SwiftUI's hover never fires.
struct PassthroughHoverReader: NSViewRepresentable {
  let onHover: (Bool) -> Void

  func makeNSView(context: Context) -> PassthroughHoverReaderView {
    let view = PassthroughHoverReaderView()
    view.onHover = onHover
    return view
  }

  func updateNSView(_ nsView: PassthroughHoverReaderView, context: Context) {
    nsView.onHover = onHover
  }
}

class PassthroughHoverReaderView: NSView {
  var onHover: ((Bool) -> Void)?
  private var hover = PointerHover()
  nonisolated(unsafe) private var monitors: [Any] = []

  deinit {
    monitors.forEach(NSEvent.removeMonitor)
  }

  override func hitTest(_ point: NSPoint) -> NSView? { nil }

  /// Watches the pointer while in a window, through monitors that see the
  /// mouse moves and presses the panel itself ignores.
  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    monitors.forEach(NSEvent.removeMonitor)
    monitors = []
    guard window != nil else {
      if hover.isHovering { onHover?(false) }
      hover = PointerHover()
      return
    }
    let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDown, .rightMouseDown]
    let handle: (NSEvent) -> Void = { [weak self] event in
      let pressed = event.type != .mouseMoved
      MainActor.assumeIsolated { self?.pointerMoved(pressed: pressed) }
    }
    monitors = [
      NSEvent.addGlobalMonitorForEvents(matching: mask, handler: handle),
      NSEvent.addLocalMonitorForEvents(matching: mask) { event in
        handle(event)
        return event
      },
    ].compactMap { $0 }
  }

  /// Whether `window` is on screen and not faded out. A panel kantan hides,
  /// such as a masked module's while its menu bar item is gone, keeps its
  /// last frame.
  static func isShown(_ window: NSWindow) -> Bool {
    window.isVisible && window.alphaValue > 0
  }

  private func pointerMoved(pressed: Bool) {
    guard let window else { return }
    let frame = window.convertToScreen(convert(bounds, to: nil))
    if let hovering = hover.pointer(
      at: NSEvent.mouseLocation, in: frame, shown: Self.isShown(window), pressed: pressed)
    {
      onHover?(hovering)
    }
  }
}

// MARK: - Module Container View

/// Wraps each module's visual content with interaction handling
/// (hover for tooltips, click for popups/menus).
struct ModuleContainerView: View {
  @ObservedObject var viewModel: ModuleViewModel
  @EnvironmentObject var themeProvider: ThemeProvider
  let popupManager: PopupManager
  @State private var moduleFrame: CGRect = .zero
  @State private var hostWindow: NSWindow?

  var hasInteraction: Bool {
    viewModel.moduleConfig.interaction != nil
      || WorkspaceModuleView.activates(viewModel.moduleConfig)
  }

  var body: some View {
    Group {
      if viewModel.moduleConfig.type == "workspace" {
        WorkspaceModuleView(viewModel: viewModel)
      } else if viewModel.moduleConfig.type == "waveform" {
        WaveformModuleView(viewModel: viewModel)
      } else {
        StandardModuleView(viewModel: viewModel)
      }
    }
    .background(
      GeometryReader { geo in
        Color.clear
          .onAppear {
            moduleFrame = geo.frame(in: .global)
            ModuleWidths.shared.set(moduleFrame.width, for: viewModel.id)
          }
          .onChange(of: geo.frame(in: .global)) { _, newValue in
            moduleFrame = newValue
            ModuleWidths.shared.set(newValue.width, for: viewModel.id)
          }
      }
    )
    .background(WindowReader(window: $hostWindow))
    // Drawer icon: expand hit target without affecting layout.
    // Positive padding expands contentShape, negative padding collapses layout back.
    .padding(.horizontal, viewModel.moduleConfig.type == "drawer" ? 6 : 0)
    .contentShape(Rectangle())
    .padding(.horizontal, viewModel.moduleConfig.type == "drawer" ? -6 : 0)
    .allowsHitTesting(hasInteraction)
    .onHover(perform: hoverChanged)
    .background {
      if viewModel.moduleConfig.isPassthrough, hasTooltip || viewModel.revealsOnHover {
        PassthroughHoverReader(onHover: hoverChanged)
      }
    }
    .onTapGesture {
      handleClick()
    }
    .onReceive(popupManager.openModule) { open in
      let isOpen = open == viewModel.id
      guard viewModel.isPopupOpen != isOpen else { return }
      withAnimation(viewModel.revealAnimation) { viewModel.isPopupOpen = isOpen }
    }
  }

  // MARK: - Interaction

  /// Whether the module shows a tooltip on hover.
  private var hasTooltip: Bool {
    viewModel.moduleConfig.interaction?.hover?.type == "tooltip"
  }

  private func hoverChanged(_ hovering: Bool) {
    guard hasInteraction else { return }
    if viewModel.revealsOnHover {
      withAnimation(viewModel.revealAnimation) { viewModel.isHovered = hovering }
    }
    if hovering {
      showTooltipIfConfigured()
    } else {
      popupManager.hideTooltip()
    }
  }

  private var anchorPoint: NSPoint {
    let swiftUIPoint = NSPoint(x: moduleFrame.midX, y: moduleFrame.maxY)
    return popupManager.screenPoint(from: swiftUIPoint, in: hostWindow)
  }

  /// Module's left edge in screen coordinates, for native NSMenu
  /// left-aligned positioning.
  private var moduleScreenMinX: CGFloat {
    let swiftUIPoint = NSPoint(x: moduleFrame.minX, y: moduleFrame.maxY)
    return popupManager.screenPoint(from: swiftUIPoint, in: hostWindow).x
  }

  private func showTooltipIfConfigured() {
    guard let hover = viewModel.moduleConfig.interaction?.hover,
      hover.type == "tooltip"
    else { return }
    guard !popupManager.isPopupActive else { return }

    // Rich DSL tooltip (from hover.view or module's viewTree)
    if let viewTree = hover.viewTree {
      let liveContent = LiveContentProvider(viewModel: viewModel)
      popupManager.showDSLTooltip(
        viewTree: viewTree, anchorPoint: anchorPoint, liveContent: liveContent)
      return
    }

    // Plain text tooltip
    let template = hover.content ?? "{value}"
    let resolved = resolveTemplate(template)
    popupManager.showTooltip(
      text: resolved, anchorPoint: anchorPoint,
      refreshProvider: { [weak viewModel] in
        guard let viewModel else { return resolved }
        return self.resolveTemplateWith(template, viewModel: viewModel)
      }
    )
  }

  private func handleClick() {
    popupManager.hideTooltip()
    guard let click = viewModel.moduleConfig.interaction?.click else { return }

    switch click.type {
    case "menu":
      let liveContent = LiveContentProvider(viewModel: viewModel)
      // Priority: click.viewTree (YAML-defined) > module's live viewTree (plugin JSON)
      popupManager.showMenu(
        configViewTree: click.viewTree, moduleName: viewModel.id, anchorPoint: anchorPoint,
        moduleMinX: moduleScreenMinX, liveContent: liveContent)
    case "complete":
      toggle()
    case "popup":
      let liveContent = LiveContentProvider(viewModel: viewModel)
      popupManager.showDSLView(
        configViewTree: click.viewTree, moduleName: viewModel.id, anchorPoint: anchorPoint,
        liveContent: liveContent)
    case "drawer":
      viewModel.toggleAction?()
    case "toggle":
      toggle()
    default:
      break
    }
  }

  /// Runs the module's toggle action, refreshing the module once it exits.
  private func toggle() {
    let viewModel = self.viewModel
    guard let config = viewModel.moduleConfig.config else { return }
    config.handleToggle {
      DispatchQueue.main.async {
        MainActor.assumeIsolated { viewModel.update() }
      }
    }
  }

  // MARK: - Template Resolution

  private func resolveTemplate(_ template: String) -> String {
    resolveTemplateWith(template, viewModel: viewModel)
  }

  private func resolveTemplateWith(_ template: String, viewModel: ModuleViewModel) -> String {
    plainTooltipText(
      template, value: viewModel.displayValue, icon: viewModel.displayIcon,
      variables: viewModel.templateVariables)
  }
}

// MARK: - Standard Module View

/// Renders icon + text for all non-workspace modules.
struct StandardModuleView: View {
  @ObservedObject var viewModel: ModuleViewModel
  @EnvironmentObject var themeProvider: ThemeProvider

  @Environment(\.groupPlacement) private var groupPlacement
  @Environment(\.anchorsCenter) private var anchorsCenter

  /// Whether the text comes before the icon.
  private var textLeads: Bool {
    viewModel.moduleConfig.iconTrails(at: groupPlacement)
  }

  /// The edge revealed parts slide out from: the icon's side of the
  /// module, so the text unfolds from the icon.
  private var revealEdge: Edge {
    textLeads ? .trailing : .leading
  }

  private var hasIcon: Bool {
    !(viewModel.displayIcon ?? "").isEmpty
  }

  /// Whether the icon is in place: always, or once a hover reveals it.
  private var showsIcon: Bool {
    hasIcon && (!viewModel.hidesUntilRevealed(.icon) || viewModel.isRevealed)
  }

  /// The value's segments, each with whether it waits for a hover.
  private var valueParts: [(text: AttributedString, reveal: Bool)] {
    guard !(viewModel.displayValue ?? "").isEmpty else { return [] }
    let hidesText = viewModel.hidesUntilRevealed(.text)
    return themeProvider.valueParts(for: viewModel).map { ($0.text, hidesText || $0.reveal) }
  }

  var body: some View {
    if viewModel.revealsOnHover {
      let parts = valueParts
      let showsText = parts.contains { !$0.reveal || viewModel.isRevealed }
      HStack(spacing: 0) {
        if textLeads { revealingText(parts) }
        if textLeads, showsIcon, showsText { iconTextGap }
        ZStack {
          if showsIcon {
            iconView.transition(.move(edge: revealEdge).combined(with: .opacity))
          }
        }
        .clipped()
        if !textLeads, showsIcon, showsText { iconTextGap }
        if !textLeads { revealingText(parts) }
      }
      .modifier(ModuleChrome(viewModel: viewModel))
    } else {
      HStack(spacing: themeProvider.iconTextSpacing) {
        if hasIcon, !textLeads { iconView }
        if let value = viewModel.displayValue, !value.isEmpty {
          Text(themeProvider.valueText(for: viewModel))
            .font(themeProvider.textFont(for: viewModel))
            .lineLimit(1)
        }
        if hasIcon, textLeads { iconView }
      }
      .modifier(ModuleChrome(viewModel: viewModel))
    }
  }

  private var iconTextGap: some View {
    Color.clear.frame(width: themeProvider.iconTextSpacing, height: 1)
  }

  /// The module's icon, telling its group where it is when it anchors the
  /// bar's centre.
  private var iconView: some View {
    iconGlyph.background {
      if anchorsCenter {
        GeometryReader { geo in
          Color.clear.preference(
            key: AnchorIconKey.self, value: geo.frame(in: .named(AnchorIconKey.space)).midX)
        }
      }
    }
  }

  /// The module's icon, over the icon drawn faintly behind it when it has one.
  @ViewBuilder
  private var iconGlyph: some View {
    if let icon = viewModel.displayIcon {
      if let bgIcon = viewModel.backgroundIcon, !bgIcon.isEmpty {
        Text(bgIcon)
          .font(themeProvider.iconFont(for: viewModel))
          .foregroundStyle(iconColor.opacity(0.15))
          .overlay {
            Text(icon)
              .font(themeProvider.iconFont(for: viewModel))
              .foregroundStyle(iconColor)
              .offset(x: viewModel.iconShift * CGFloat(themeProvider.iconFontSize(for: viewModel)))
          }
      } else {
        Text(icon)
          .font(themeProvider.iconFont(for: viewModel))
          .foregroundStyle(iconColor)
      }
    }
  }

  /// The value of a revealing module: each segment that waits for a hover
  /// slides out from the group's anchored edge once revealed, and back.
  private func revealingText(_ parts: [(text: AttributedString, reveal: Bool)]) -> some View {
    HStack(spacing: 0) {
      ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
        ZStack {
          if !part.reveal || viewModel.isRevealed {
            Text(part.text)
              .font(themeProvider.textFont(for: viewModel))
              .lineLimit(1)
              .transition(.move(edge: revealEdge).combined(with: .opacity))
          }
        }
        .clipped()
      }
    }
  }

  private var iconColor: Color {
    let base = themeProvider.iconFgColor(for: viewModel)
    return viewModel.isActive ? base : base.opacity(0.4)
  }
}

/// A standard module's size, padding and shape.
private struct ModuleChrome: ViewModifier {
  @ObservedObject var viewModel: ModuleViewModel
  @EnvironmentObject var themeProvider: ThemeProvider

  func body(content: Content) -> some View {
    content
      .fixedSize(horizontal: true, vertical: false)
      .padding(.horizontal, moduleShape != nil ? 6 : 0)
      .padding(.vertical, modulePadding)
      .frame(maxHeight: expandsToBarHeight ? .infinity : nil)
      .background(shapeBackground)
  }

  private var moduleShape: ModuleShape? {
    themeProvider.shape(for: viewModel)
  }

  private var modulePadding: CGFloat {
    guard let shape = moduleShape else { return 0 }
    switch shape {
    case .pill, .box: return 3
    case .underline, .overline: return 0
    }
  }

  private var expandsToBarHeight: Bool {
    guard let shape = moduleShape else { return false }
    switch shape {
    case .underline, .overline: return true
    case .pill, .box: return false
    }
  }

  private var moduleBgColor: Color {
    themeProvider.bgColor(for: viewModel)
  }

  @ViewBuilder
  private var shapeBackground: some View {
    if let shape = moduleShape {
      switch shape {
      case .pill:
        Capsule().fill(moduleBgColor)
      case .box:
        RoundedRectangle(cornerRadius: 4).fill(moduleBgColor)
      case .underline:
        VStack(spacing: 0) {
          Spacer(minLength: 0)
          Rectangle().fill(moduleBgColor).frame(height: 2)
        }
        .frame(maxHeight: .infinity)
      case .overline:
        VStack(spacing: 0) {
          Rectangle().fill(moduleBgColor).frame(height: 2)
          Spacer(minLength: 0)
        }
        .frame(maxHeight: .infinity)
      }
    }
  }
}

// MARK: - Workspace Module View

/// Renders N space indicators with active/inactive colouring.
/// Supports `maxSpaces` windowing: when the user has more spaces than
/// `maxSpaces`, only a sliding window of spaces is shown, with an
/// overflow indicator hinting at hidden spaces.
///
/// On a scrolling workspace with `scrolling` enabled, the segments are the
/// scroll's windows, led by a column of pips for the workspaces. Switching
/// to and from a scroll moves each workspace's segment into its pip and
/// back, while the windows slide out of the pips and fade.
///
/// When the provider can switch workspaces, clicking a segment or pip
/// switches to its workspace or focuses its window, and scrolling over the
/// module steps along the segments.
struct WorkspaceModuleView: View {
  @ObservedObject var viewModel: ModuleViewModel
  @EnvironmentObject var themeProvider: ThemeProvider
  /// Pairs each workspace's segment with its pip.
  @Namespace private var workspaces

  private static let spacing: CGFloat = 6
  private static let pipDiameter: CGFloat = 4
  private static let pipSpacing: CGFloat = 2
  /// Share of the bar's height the pips may fill before they shrink.
  private static let pipColumnHeight: CGFloat = 0.6

  private var wsConfig: WorkspaceConfig? {
    viewModel.moduleConfig.config as? WorkspaceConfig
  }

  /// Whether the module's segments switch workspaces: its provider can,
  /// and the module has no click interaction of its own.
  static func activates(_ module: ModuleConfig) -> Bool {
    guard let config = module.config as? WorkspaceConfig else { return false }
    return config.provider.canActivate && module.interaction?.click == nil
  }

  var body: some View {
    let wsConfig = self.wsConfig
    let display = wsConfig?.display ?? WorkspaceDisplay()
    let overflow = wsConfig?.overflow
    let window = display.page(max: overflow?.enabled == true ? overflow?.max : nil)
    let animates = viewModel.contentAnimation != nil
    let activate = self.activate

    HStack(spacing: Self.spacing) {
      if !display.pips.isEmpty {
        pipColumn(display.pips, animates: animates, activate: activate)
      }
      if window.before {
        overflowIndicatorView(icon: wsConfig?.overflow.iconLeft ?? "‹", config: wsConfig)
      }
      ForEach(window.segments, id: \.id) { segment in
        segmentLabel(segment, slot: display.slot)
          .matchedGeometryEffect(id: segment.id, in: workspaces, properties: .position)
          .modifier(
            ActivateOnClick(target: segment.target, reach: Self.segmentReach, activate: activate)
          )
          .transition(Self.transition(forScroll: display.isScroll, animates: animates))
      }
      if window.after {
        overflowIndicatorView(icon: wsConfig?.overflow.iconRight ?? "›", config: wsConfig)
      }
    }
    .background {
      if activate != nil {
        ScrollWheelReader(onStep: step)
      }
    }
  }

  /// Switches to or focuses a target, or nil while segments don't switch.
  private var activate: ((WorkspaceTarget) -> Void)? {
    guard Self.activates(viewModel.moduleConfig), let wsConfig else { return nil }
    return { wsConfig.activate($0) }
  }

  private func step(_ steps: Int) {
    guard let wsConfig, let target = wsConfig.display.target(steppingBy: steps) else { return }
    wsConfig.activate(target)
  }

  /// How far past a segment a click reaches: halfway to its neighbours.
  private static let segmentReach = EdgeInsets(
    top: 0, leading: spacing / 2, bottom: 0, trailing: spacing / 2)

  private static let workspaceTransition = staggered(
    .scale(scale: 0.4).combined(with: .opacity))
  private static let windowTransition = staggered(.offset(x: -8).combined(with: .opacity))

  /// How segments come and go: windows slide from the pips and workspaces
  /// scale, unless changes show at once.
  private static func transition(forScroll isScroll: Bool, animates: Bool) -> AnyTransition {
    guard animates else { return .identity }
    return isScroll ? windowTransition : workspaceTransition
  }

  private static func staggered(_ transition: AnyTransition) -> AnyTransition {
    .asymmetric(
      insertion: transition.animation(ModuleAnimation.entrance),
      removal: transition.animation(ModuleAnimation.exit))
  }

  /// A segment's label, centred in a slot at least as wide as `slot`.
  private func segmentLabel(_ segment: WorkspaceSegment, slot: WorkspaceSegment?) -> some View {
    ZStack {
      if let slot {
        Text(slot.label).font(segmentFont(slot)).hidden()
      }
      Text(segment.label)
        .font(segmentFont(segment))
        .foregroundStyle(segmentColor(segment))
    }
  }

  // MARK: - Pips

  /// The workspaces top to bottom, shrinking to fit the bar when there are
  /// many. A click on a pip reaches halfway to the pips beside it, and
  /// past the first and last to the module's edges, where the module's
  /// own hit area stops it.
  private func pipColumn(
    _ pips: [WorkspaceSegment], animates: Bool, activate: ((WorkspaceTarget) -> Void)?
  ) -> some View {
    let count = CGFloat(pips.count)
    let natural = count * Self.pipDiameter + (count - 1) * Self.pipSpacing
    let height = CGFloat(themeProvider.config.height)
    let scale = min(1, height * Self.pipColumnHeight / natural)
    let between = Self.pipSpacing * scale / 2
    return VStack(spacing: Self.pipSpacing * scale) {
      ForEach(pips, id: \.id) { pip in
        Circle()
          .fill(segmentColor(pip))
          .frame(width: Self.pipDiameter * scale, height: Self.pipDiameter * scale)
          .matchedGeometryEffect(id: pip.id, in: workspaces, properties: .position)
          .modifier(
            ActivateOnClick(
              target: pip.target,
              reach: EdgeInsets(
                top: pip.id == pips.first?.id ? height : between, leading: Self.spacing / 2,
                bottom: pip.id == pips.last?.id ? height : between, trailing: Self.spacing / 2),
              activate: activate)
          )
          .transition(animates ? Self.workspaceTransition : .identity)
      }
    }
  }

  // MARK: - Windowing

  // MARK: - Overflow Indicator

  /// Returns the appropriate font for a workspace segment. If the segment's
  /// label was resolved from a named icon, uses the override font at the
  /// text font's size; otherwise falls back to the normal text font.
  private func segmentFont(_ segment: WorkspaceSegment) -> Font {
    if let override = segment.fontNameOverride {
      let base = viewModel.moduleConfig.textFont ?? themeProvider.config.textFont
      let size = base?.size ?? 14
      let scaled = Int(round(size * segment.scaleFactor))
      return FontConfig(descriptor: "\(override):\(scaled)", source: .bundled).swiftUIFont
    }
    return themeProvider.textFont(for: viewModel)
  }

  @ViewBuilder
  private func overflowIndicatorView(icon: String, config: WorkspaceConfig?) -> some View {
    if let of = config?.overflow, of.enabled, of.showIcon {
      let resolved = resolveIconName(icon)
      if let override = resolved.fontNameOverride {
        let base = viewModel.moduleConfig.textFont ?? themeProvider.config.textFont
        let size = base?.size ?? 14
        let scaled = Int(round(size * resolved.scaleFactor))
        Text(resolved.glyph)
          .font(
            FontConfig(descriptor: "\(override):\(scaled)", source: .bundled).swiftUIFont
          )
          .foregroundStyle(overflowColor(config: config))
      } else {
        Text(resolved.glyph)
          .font(themeProvider.textFont(for: viewModel))
          .foregroundStyle(overflowColor(config: config))
      }
    }
  }

  private func overflowColor(config: WorkspaceConfig?) -> Color {
    if let style = config?.overflow.style {
      let mode = themeProvider.isDarkMode ? style.dark : style.light
      if let fg = mode?.fg, let colour = themeProvider.color(fg) {
        return colour
      }
    }
    return inactiveColor
  }

  // MARK: - Colors

  private func segmentColor(_ segment: WorkspaceSegment) -> Color {
    if !themeProvider.isNative, let colorStr = segment.colorOverride {
      let base = themeProvider.resolvedColor(colorStr)
      return segment.isActive ? base : base.opacity(0.4)
    }
    return segment.isActive ? activeColor : inactiveColor
  }

  private var activeColor: Color {
    themeProvider.textFgColor(for: viewModel)
  }

  private var inactiveColor: Color {
    themeProvider.textFgColor(for: viewModel).opacity(0.4)
  }
}

/// Activates `target` on a click within `reach` of the view, without
/// changing its layout. Takes no clicks while `activate` is nil.
private struct ActivateOnClick: ViewModifier {
  let target: WorkspaceTarget?
  let reach: EdgeInsets
  let activate: ((WorkspaceTarget) -> Void)?

  @ViewBuilder
  func body(content: Content) -> some View {
    if let activate {
      content
        .padding(reach)
        .contentShape(Rectangle())
        .padding(
          EdgeInsets(
            top: -reach.top, leading: -reach.leading, bottom: -reach.bottom,
            trailing: -reach.trailing)
        )
        .onTapGesture {
          if let target { activate(target) }
        }
    } else {
      content
    }
  }
}
