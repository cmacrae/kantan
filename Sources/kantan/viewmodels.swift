import AppKit
import SwiftUI

// MARK: - Module View Model

/// Bridges the imperative ModuleConfiguration protocol to SwiftUI's
/// reactive model. Wraps getValue(completion:) in a timer and publishes
/// state changes that SwiftUI views observe.
@MainActor
class ModuleViewModel: ObservableObject, Identifiable {
    let id: String
    let moduleConfig: ModuleConfig

    @Published var displayValue: String?
    @Published var displayIcon: String?
    @Published var isActive: Bool = true
    @Published var templateVariables: [String: String] = [:]

    // CLI trigger overrides
    @Published var fgOverride: String?
    @Published var bgOverride: String?

    nonisolated(unsafe) private var timer: Timer?
    nonisolated(unsafe) private var durationTimer: Timer?

    init(moduleConfig: ModuleConfig) {
        self.id = moduleConfig.name
        self.moduleConfig = moduleConfig
        self.displayIcon = moduleConfig.icon

        // Event-driven modules push their own updates; polling modules
        // use a repeating timer.
        if let eventModule = moduleConfig.config as? EventDrivenModule {
            update()
            eventModule.startObserving { [weak self] in
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        self?.update()
                    }
                }
            }
        } else {
            startPolling()
        }
    }

    deinit {
        (moduleConfig.config as? EventDrivenModule)?.stopObserving()
        timer?.invalidate()
        durationTimer?.invalidate()
    }

    func update() {
        guard durationTimer == nil else { return }
        guard let config = moduleConfig.config else { return }

        let icon = config.getIcon()
        let newIcon = icon.isEmpty ? moduleConfig.icon : icon

        config.getValue { [weak self] newValue in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.displayValue = newValue
                self.displayIcon = newIcon
                self.isActive = config.isActive()
                self.templateVariables = config.getTemplateVariables()
            }
        }
    }

    /// Apply a timed override from CLI trigger, resetting after duration.
    func scheduleDurationReset(_ duration: Double) {
        durationTimer?.invalidate()
        durationTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self = self else { return }
                self.durationTimer = nil
                self.fgOverride = nil
                self.bgOverride = nil
                self.update()
            }
        }
    }

    private func startPolling() {
        update()
        let interval = moduleConfig.config?.redrawInterval ?? 1.0
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.update()
            }
        }
    }
}

// MARK: - Bar View Model

/// Central coordinator that replaces StatusBarController.
/// Owns all ModuleViewModels and wires the EventObserver for CLI triggers.
@MainActor
class BarViewModel: ObservableObject {
    @Published var leftModules: [ModuleViewModel] = []
    @Published var rightModules: [ModuleViewModel] = []
    let config: Config
    let popupManager = PopupManager()
    var eventObserver: EventObserver?

    init(config: Config) {
        self.config = config

        for moduleConfig in config.modules {
            let vm = ModuleViewModel(moduleConfig: moduleConfig)
            if moduleConfig.alignment == "right" {
                rightModules.append(vm)
            } else {
                leftModules.append(vm)
            }
        }

        eventObserver = EventObserver(
            onRefresh: { [weak self] in
                self?.refreshAll()
            },
            onEvent: { [weak self] module, action, userInfo in
                self?.handleEvent(module: module, action: action, userInfo: userInfo)
            }
        )
    }

    var allModules: [ModuleViewModel] {
        leftModules + rightModules
    }

    func refreshAll() {
        for vm in allModules {
            vm.update()
        }
    }

    func handleEvent(module moduleName: String, action: String, userInfo: [String: String]) {
        let targets: [ModuleViewModel]
        if moduleName == "*" {
            targets = allModules
        } else {
            targets = allModules.filter { $0.id == moduleName }
        }

        guard !targets.isEmpty else { return }

        for vm in targets {
            switch action {
            case "refresh":
                vm.update()

            case "set":
                if let value = userInfo["value"] {
                    vm.displayValue = value.isEmpty ? nil : value
                }
                if let icon = userInfo["icon"] {
                    vm.displayIcon = icon.isEmpty ? nil : icon
                }
                if let fg = userInfo["fg"] {
                    vm.fgOverride = fg.isEmpty ? nil : fg
                }
                if let bg = userInfo["bg"] {
                    vm.bgOverride = bg.isEmpty ? nil : bg
                }
                if let durationStr = userInfo["duration"],
                   let duration = Double(durationStr), duration > 0 {
                    vm.scheduleDurationReset(duration)
                }

            default:
                break
            }
        }
    }
}

// MARK: - Theme Provider

/// Provides resolved colors and fonts to SwiftUI views based on the
/// current system appearance (light/dark) and user config.
@MainActor
class ThemeProvider: ObservableObject {
    @Published var isDarkMode: Bool = true
    let globalConfig: GlobalConfig
    private var appearanceObservation: NSKeyValueObservation?

    var isNative: Bool {
        globalConfig.appearance == .native
    }

    init(globalConfig: GlobalConfig) {
        self.globalConfig = globalConfig
        self.isDarkMode = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        observeAppearance()
    }

    private func observeAppearance() {
        appearanceObservation = NSApp.observe(\.effectiveAppearance) { [weak self] _, _ in
            MainActor.assumeIsolated {
                guard let self = self else { return }
                self.isDarkMode = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            }
        }
    }

    // MARK: - Color Resolution

    func globalColors() -> (fg: Color, bg: Color) {
        let config = isDarkMode ? globalConfig.colour.dark : globalConfig.colour.light
        return (Color(nsColor: NSColor(hex: config.fg)), Color(nsColor: NSColor(hex: config.bg)))
    }

    func fgColor(for vm: ModuleViewModel) -> Color {
        if let override = vm.fgOverride {
            return Color(nsColor: NSColor(hex: override))
        }
        if isNative { return Color(nsColor: .labelColor) }
        let config = resolveColourConfig(moduleColour: vm.moduleConfig.colour)
        return Color(nsColor: NSColor(hex: config.fg))
    }

    func bgColor(for vm: ModuleViewModel) -> Color {
        if let override = vm.bgOverride {
            return Color(nsColor: NSColor(hex: override))
        }
        if isNative { return .clear }
        let config = resolveColourConfig(moduleColour: vm.moduleConfig.colour)
        return Color(nsColor: NSColor(hex: config.bg))
    }

    func barBgColor() -> Color {
        if isNative { return .clear }
        let config = isDarkMode ? globalConfig.colour.dark : globalConfig.colour.light
        return Color(nsColor: NSColor(hex: config.bg))
    }

    private func resolveColourConfig(moduleColour: ColourModeConfig?) -> ColourConfig {
        if isDarkMode {
            return moduleColour?.dark ?? globalConfig.colour.dark
        } else {
            return moduleColour?.light ?? globalConfig.colour.light
        }
    }

    // MARK: - Font Resolution

    func iconFont(for vm: ModuleViewModel) -> Font {
        let config = vm.moduleConfig.iconFont ?? globalConfig.iconFont!
        return config.swiftUIFont
    }

    func textFont(for vm: ModuleViewModel) -> Font {
        let config = vm.moduleConfig.textFont ?? globalConfig.textFont!
        return config.swiftUIFont
    }
}
