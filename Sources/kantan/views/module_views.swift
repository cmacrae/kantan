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
        view.onWindowChange = { [self] win in self.window = win }
        return view
    }

    func updateNSView(_ nsView: WindowReaderView, context: Context) {
        nsView.onWindowChange = { [self] win in self.window = win }
        if let win = nsView.window {
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
        if viewModel.shouldDisplay {
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
            .contentShape(hasInteraction ? Rectangle() : .rect)
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
    }

    // MARK: - Interaction

    private var anchorPoint: NSPoint {
        let swiftUIPoint = NSPoint(x: moduleFrame.midX, y: moduleFrame.maxY)
        return popupManager.screenPoint(from: swiftUIPoint, in: hostWindow)
    }

    private func showTooltipIfConfigured() {
        guard let hover = viewModel.moduleConfig.interaction?.hover,
              hover.type == "tooltip" else { return }
        guard !popupManager.isPopupActive else { return }
        let resolved = resolveTemplate(hover.content)
        popupManager.showTooltip(text: resolved, anchorPoint: anchorPoint)
    }

    private func handleClick() {
        popupManager.hideTooltip()
        guard let click = viewModel.moduleConfig.interaction?.click else { return }

        switch click.type {
        case "menu":
            if click.items != nil {
                // YAML items defined — build from config (dynamic: true entries
                // splice in getMenuDescriptors() at their position).
                showDynamicMenu(
                    builder: { self.descriptorsFromClickConfig(click) },
                    moduleName: viewModel.id,
                    anchorPoint: anchorPoint
                )
            } else if let descriptors = viewModel.moduleConfig.config?.getMenuDescriptors(), !descriptors.isEmpty {
                // No YAML items — module provides its own full menu (e.g. wifi, bluetooth).
                showDynamicMenu(
                    builder: { self.viewModel.moduleConfig.config?.getMenuDescriptors() ?? [] },
                    moduleName: viewModel.id,
                    anchorPoint: anchorPoint
                )
            } else {
                let descriptors = descriptorsFromClickConfig(click)
                popupManager.showMenu(descriptors: descriptors, moduleName: viewModel.id, anchorPoint: anchorPoint)
            }
        case "dynamic-menu":
            break
        case "complete":
            viewModel.moduleConfig.config?.handleToggle()
            viewModel.update()
        case "popup":
            if let popupConfig = click.popupConfig {
                let fg = Color(nsColor: popupManager.effectiveFgColor)
                let bg = Color(nsColor: popupManager.effectiveBgColor)
                let iconFont = themeProvider.iconFont(for: viewModel)
                popupManager.showUserPopup(
                    config: popupConfig,
                    moduleName: viewModel.id,
                    anchorPoint: anchorPoint,
                    templateResolver: { self.resolveTemplate($0) },
                    fgColor: fg,
                    bgColor: bg,
                    iconFont: iconFont
                )
            } else if let popupName = click.popup {
                popupManager.togglePopup(name: popupName, moduleName: viewModel.id, anchorPoint: anchorPoint)
            }
        case "toggle":
            viewModel.moduleConfig.config?.handleToggle()
            viewModel.update()
        default:
            break
        }
    }

    /// Show a dynamic menu with a rebuilder that re-fetches descriptors
    /// after toggle state changes (e.g. WiFi/Bluetooth power toggle).
    /// The rebuilder is self-referencing so repeated toggles work.
    private func showDynamicMenu(builder: @escaping () -> [MenuItemDescriptor], moduleName: String, anchorPoint: NSPoint) {
        let descriptors = builder()
        popupManager.showMenu(descriptors: descriptors, moduleName: moduleName, anchorPoint: anchorPoint) {
            self.showDynamicMenu(builder: builder, moduleName: moduleName, anchorPoint: anchorPoint)
        }
    }

    // MARK: - Template Resolution

    private func resolveTemplate(_ template: String) -> String {
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

    /// Convert a ClickConfig's static menu items into MenuItemDescriptors.
    /// Supports icon glyphs, headers, and `dynamic: true` placeholders that
    /// expand to the module's getMenuDescriptors() output.
    private func descriptorsFromClickConfig(_ config: ClickConfig) -> [MenuItemDescriptor] {
        guard let items = config.items else { return [] }
        var result: [MenuItemDescriptor] = []
        for item in items {
            if item.separator == true {
                result.append(.separator())
                continue
            }
            if let header = item.header {
                result.append(.header(resolveTemplate(header)))
                continue
            }
            if item.dynamic == true {
                if let dynamicDescriptors = viewModel.moduleConfig.config?.getMenuDescriptors() {
                    result.append(contentsOf: dynamicDescriptors)
                }
                continue
            }
            guard let label = item.label else { continue }
            let resolved = resolveTemplate(label)
            let command = item.command
            let iconGlyph = item.icon
            result.append(.item(resolved, iconGlyph: iconGlyph) {
                guard let command = command, !command.isEmpty else { return }
                DispatchQueue.global(qos: .userInitiated).async {
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: "/bin/sh")
                    process.arguments = ["-c", command]
                    process.standardOutput = Pipe()
                    process.standardError = Pipe()
                    try? process.run()
                }
            })
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
        HStack(spacing: themeProvider.iconTextSpacing()) {
            if let icon = viewModel.displayIcon, !icon.isEmpty {
                Text(icon)
                    .font(themeProvider.iconFont(for: viewModel))
                    .foregroundStyle(iconColor)
            }
            if let value = viewModel.displayValue, !value.isEmpty {
                Text(value)
                    .font(themeProvider.textFont(for: viewModel))
                    .foregroundStyle(textColor)
            }
        }
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
struct WorkspaceModuleView: View {
    @ObservedObject var viewModel: ModuleViewModel
    @EnvironmentObject var themeProvider: ThemeProvider

    var body: some View {
        let allSegments = getWorkspaceSegments()
        let wsConfig = viewModel.moduleConfig.config as? WorkspaceConfig
        let window = windowedSegments(allSegments, config: wsConfig)

        HStack(spacing: 6) {
            if window.overflowBefore {
                overflowIndicatorView(icon: wsConfig?.overflow.iconLeft ?? "‹", config: wsConfig)
            }
            ForEach(Array(window.segments.enumerated()), id: \.offset) { _, segment in
                Text(segment.label)
                    .font(themeProvider.textFont(for: viewModel))
                    .foregroundStyle(segment.isActive ? activeColor : inactiveColor)
            }
            if window.overflowAfter {
                overflowIndicatorView(icon: wsConfig?.overflow.iconRight ?? "›", config: wsConfig)
            }
        }
    }

    // MARK: - Windowing

    private struct WindowResult {
        let segments: [WorkspaceSegment]
        let overflowBefore: Bool
        let overflowAfter: Bool
    }

    private func windowedSegments(_ all: [WorkspaceSegment], config: WorkspaceConfig?) -> WindowResult {
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

        return WindowResult(segments: slice, overflowBefore: overflowBefore, overflowAfter: overflowAfter)
    }

    // MARK: - Overflow Indicator

    @ViewBuilder
    private func overflowIndicatorView(icon: String, config: WorkspaceConfig?) -> some View {
        if let of = config?.overflow, of.enabled, of.showIcon {
            Text(icon)
                .font(themeProvider.textFont(for: viewModel))
                .foregroundStyle(overflowColor(config: config))
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

    private var activeColor: Color {
        if let wsConfig = viewModel.moduleConfig.config as? WorkspaceConfig,
           let activeHex = wsConfig.activeColour {
            return Color(nsColor: NSColor(hex: activeHex))
        }
        return themeProvider.textFgColor(for: viewModel)
    }

    private var inactiveColor: Color {
        if let wsConfig = viewModel.moduleConfig.config as? WorkspaceConfig,
           let inactiveHex = wsConfig.inactiveColour {
            return Color(nsColor: NSColor(hex: inactiveHex))
        }
        return themeProvider.textFgColor(for: viewModel).opacity(0.4)
    }
}
