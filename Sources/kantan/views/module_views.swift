import SwiftUI

// MARK: - Module Container View

/// Wraps each module's visual content with interaction handling
/// (hover for tooltips, click for popups/menus).
struct ModuleContainerView: View {
    @ObservedObject var viewModel: ModuleViewModel
    @EnvironmentObject var themeProvider: ThemeProvider
    let popupManager: PopupManager
    @State private var moduleFrame: CGRect = .zero

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

    // MARK: - Interaction

    private var anchorPoint: NSPoint {
        let swiftUIPoint = NSPoint(x: moduleFrame.midX, y: moduleFrame.maxY)
        return popupManager.screenPoint(from: swiftUIPoint, forModule: viewModel.id)
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
            let descriptors = descriptorsFromClickConfig(click)
            popupManager.showMenu(descriptors: descriptors, moduleName: viewModel.id, anchorPoint: anchorPoint)
        case "dynamic-menu":
            break
        case "popup":
            guard let popupName = click.popup else { return }
            popupManager.togglePopup(name: popupName, moduleName: viewModel.id, anchorPoint: anchorPoint)
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
    private func descriptorsFromClickConfig(_ config: ClickConfig) -> [MenuItemDescriptor] {
        guard let items = config.items else { return [] }
        return items.map { item in
            if item.separator == true {
                return .separator()
            }
            guard let label = item.label else { return .separator() }
            let command = item.command
            return .item(label) {
                guard let command = command, !command.isEmpty else { return }
                DispatchQueue.global(qos: .userInitiated).async {
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: "/bin/sh")
                    process.arguments = ["-c", command]
                    process.standardOutput = Pipe()
                    process.standardError = Pipe()
                    try? process.run()
                }
            }
        }
    }
}

// MARK: - Standard Module View

/// Renders icon + text for all non-workspace modules.
struct StandardModuleView: View {
    @ObservedObject var viewModel: ModuleViewModel
    @EnvironmentObject var themeProvider: ThemeProvider

    var body: some View {
        HStack(spacing: 2) {
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
struct WorkspaceModuleView: View {
    @ObservedObject var viewModel: ModuleViewModel
    @EnvironmentObject var themeProvider: ThemeProvider

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                Text(segment.label)
                    .font(themeProvider.textFont(for: viewModel))
                    .foregroundStyle(segment.isActive ? activeColor : inactiveColor)
            }
        }
    }

    private var segments: [WorkspaceSegment] {
        getWorkspaceSegments()
    }

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
