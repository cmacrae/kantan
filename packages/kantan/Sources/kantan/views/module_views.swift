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
  }

  var body: some View {
    Group {
      if viewModel.moduleConfig.type == "workspace" {
        WorkspaceModuleView(viewModel: viewModel)
      } else {
        StandardModuleView(viewModel: viewModel)
      }
    }
    .background(
      GeometryReader { geo in
        Color.clear
          .onAppear {
            moduleFrame = geo.frame(in: .global)
          }
          .onChange(of: geo.frame(in: .global)) { _, newValue in
            moduleFrame = newValue
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
    .onHover { hovering in
      guard hasInteraction else { return }
      if hovering {
        showTooltipIfConfigured()
      } else {
        popupManager.hideTooltip()
      }
    }
    .onTapGesture {
      handleClick()
    }
  }

  // MARK: - Interaction

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
      if let viewTree = click.viewTree ?? viewModel.viewTree {
        popupManager.showMenu(
          viewTree: viewTree, moduleName: viewModel.id, anchorPoint: anchorPoint,
          moduleMinX: moduleScreenMinX, liveContent: liveContent)
      }
    case "complete":
      toggle()
    case "popup":
      let liveContent = LiveContentProvider(viewModel: viewModel)
      if let viewTree = click.viewTree ?? viewModel.viewTree {
        popupManager.showDSLView(
          viewTree: viewTree, moduleName: viewModel.id, anchorPoint: anchorPoint,
          liveContent: liveContent)
      }
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
    var result = template
    if let value = viewModel.displayValue {
      result = result.replacingOccurrences(of: "{value}", with: value)
    }
    if let icon = viewModel.displayIcon {
      result = result.replacingOccurrences(of: "{icon}", with: icon)
    }
    for (key, val) in viewModel.templateVariables {
      result = result.replacingOccurrences(of: "{\(key)}", with: val)
    }
    return result
  }
}

// MARK: - Standard Module View

/// Renders icon + text for all non-workspace modules.
struct StandardModuleView: View {
  @ObservedObject var viewModel: ModuleViewModel
  @EnvironmentObject var themeProvider: ThemeProvider

  var body: some View {
    HStack(spacing: themeProvider.iconTextSpacing) {
      if let icon = viewModel.displayIcon, !icon.isEmpty {
        if let bgIcon = viewModel.backgroundIcon, !bgIcon.isEmpty {
          Text(bgIcon)
            .font(themeProvider.iconFont(for: viewModel))
            .foregroundStyle(iconColor.opacity(0.15))
            .overlay {
              Text(icon)
                .font(themeProvider.iconFont(for: viewModel))
                .foregroundStyle(iconColor)
            }
        } else {
          Text(icon)
            .font(themeProvider.iconFont(for: viewModel))
            .foregroundStyle(iconColor)
        }
      }
      if let value = viewModel.displayValue, !value.isEmpty {
        Text(value)
          .font(themeProvider.textFont(for: viewModel))
          .foregroundStyle(textColor)
          .lineLimit(1)
      }
    }
    .fixedSize(horizontal: true, vertical: false)
    .padding(.horizontal, moduleShape != nil ? 6 : 0)
    .padding(.vertical, modulePadding)
    .frame(maxHeight: expandsToBarHeight ? .infinity : nil)
    .background(shapeBackground)
  }

  private var textColor: Color {
    themeProvider.textFgColor(for: viewModel)
  }

  private var iconColor: Color {
    let base = themeProvider.iconFgColor(for: viewModel)
    return viewModel.isActive ? base : base.opacity(0.4)
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
struct WorkspaceModuleView: View {
  @ObservedObject var viewModel: ModuleViewModel
  @EnvironmentObject var themeProvider: ThemeProvider
  /// Pairs each workspace's segment with its pip.
  @Namespace private var workspaces

  private static let pipDiameter: CGFloat = 4
  private static let pipSpacing: CGFloat = 2
  /// Share of the bar's height the pips may fill before they shrink.
  private static let pipColumnHeight: CGFloat = 0.6

  private var wsConfig: WorkspaceConfig? {
    viewModel.moduleConfig.config as? WorkspaceConfig
  }

  var body: some View {
    let wsConfig = self.wsConfig
    let display = wsConfig?.display ?? WorkspaceDisplay()
    let window = windowedSegments(display.segments, config: wsConfig)
    let animates = viewModel.contentAnimation != nil

    HStack(spacing: 6) {
      if !display.pips.isEmpty {
        pipColumn(display.pips, animates: animates)
      }
      if window.overflowBefore {
        overflowIndicatorView(icon: wsConfig?.overflow.iconLeft ?? "‹", config: wsConfig)
      }
      ForEach(window.segments, id: \.id) { segment in
        segmentLabel(segment, slot: display.slot)
          .matchedGeometryEffect(id: segment.id, in: workspaces, properties: .position)
          .transition(Self.transition(forScroll: display.isScroll, animates: animates))
      }
      if window.overflowAfter {
        overflowIndicatorView(icon: wsConfig?.overflow.iconRight ?? "›", config: wsConfig)
      }
    }
  }

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
  /// many.
  private func pipColumn(_ pips: [WorkspaceSegment], animates: Bool) -> some View {
    let count = CGFloat(pips.count)
    let natural = count * Self.pipDiameter + (count - 1) * Self.pipSpacing
    let available = CGFloat(themeProvider.config.height) * Self.pipColumnHeight
    let scale = min(1, available / natural)
    return VStack(spacing: Self.pipSpacing * scale) {
      ForEach(pips, id: \.id) { pip in
        Circle()
          .fill(segmentColor(pip))
          .frame(width: Self.pipDiameter * scale, height: Self.pipDiameter * scale)
          .matchedGeometryEffect(id: pip.id, in: workspaces, properties: .position)
          .transition(animates ? Self.workspaceTransition : .identity)
      }
    }
  }

  // MARK: - Windowing

  private struct WindowResult {
    let segments: [WorkspaceSegment]
    let overflowBefore: Bool
    let overflowAfter: Bool
  }

  private func windowedSegments(_ all: [WorkspaceSegment], config: WorkspaceConfig?) -> WindowResult
  {
    guard let of = config?.overflow, of.enabled, of.max > 0, all.count > of.max else {
      return WindowResult(segments: all, overflowBefore: false, overflowAfter: false)
    }

    let activeIndex = all.firstIndex(where: { $0.isActive }) ?? 0

    // Page-based: spaces are divided into fixed pages of `max` size.
    // The active space determines which page is displayed.
    let page = activeIndex / of.max
    let windowStart = page * of.max
    let windowEnd = min(windowStart + of.max, all.count)
    let slice = Array(all[windowStart..<windowEnd])

    let overflowBefore = windowStart > 0
    let overflowAfter = windowEnd < all.count

    return WindowResult(
      segments: slice, overflowBefore: overflowBefore, overflowAfter: overflowAfter)
  }

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
      if let fg = mode?.fg {
        return Color(nsColor: NSColor(hex: fg))
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
