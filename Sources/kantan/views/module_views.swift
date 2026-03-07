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
        .padding(.horizontal, CGFloat(themeProvider.globalConfig.padding))
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear { moduleFrame = geo.frame(in: .global) }
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
        return popupManager.screenPoint(from: swiftUIPoint)
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
            if viewModel.moduleConfig.type == "bluetooth" {
                let descriptors = BluetoothConfig.buildMenuDescriptors()
                popupManager.showMenu(descriptors: descriptors, moduleName: viewModel.id, anchorPoint: anchorPoint)
            }
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
    }

    private var textColor: Color {
        themeProvider.fgColor(for: viewModel)
    }

    private var iconColor: Color {
        let base = themeProvider.fgColor(for: viewModel)
        return viewModel.isActive ? base : base.opacity(0.4)
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
        return themeProvider.fgColor(for: viewModel)
    }

    private var inactiveColor: Color {
        if let wsConfig = viewModel.moduleConfig.config as? WorkspaceConfig,
           let inactiveHex = wsConfig.inactiveColour {
            return Color(nsColor: NSColor(hex: inactiveHex))
        }
        return themeProvider.fgColor(for: viewModel).opacity(0.4)
    }
}
