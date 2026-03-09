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
    @Published var shouldDisplay: Bool = true
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
                self.shouldDisplay = config.shouldDisplay()
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

    /// Pause all timers and event observers. Called on system sleep.
    func pause() {
        if let eventModule = moduleConfig.config as? EventDrivenModule {
            eventModule.stopObserving()
        }
        timer?.invalidate()
        timer = nil
    }

    /// Resume timers and event observers. Called on system wake.
    func resume() {
        if let eventModule = moduleConfig.config as? EventDrivenModule {
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
        update()
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

// MARK: - Module Group

/// A contiguous group of modules sharing the same passthrough status.
/// Each group gets its own NSPanel in the multi-panel architecture.
struct ModuleGroup: Identifiable {
    let id: String
    let modules: [ModuleViewModel]
    let isPassthrough: Bool
    let alignment: String
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
            onSleep: { [weak self] in
                self?.pauseAll()
            },
            onWake: { [weak self] in
                self?.resumeAll()
            },
            onEvent: { [weak self] module, action, userInfo in
                self?.handleEvent(module: module, action: action, userInfo: userInfo)
            }
        )
    }

    var allModules: [ModuleViewModel] {
        leftModules + rightModules
    }

    var leftGroups: [ModuleGroup] { buildGroups(from: leftModules, alignment: "left") }
    var rightGroups: [ModuleGroup] { buildGroups(from: rightModules, alignment: "right") }

    private func isModulePassthrough(_ vm: ModuleViewModel) -> Bool {
        vm.moduleConfig.mask != nil || vm.moduleConfig.interaction?.click?.type == "passthrough"
    }

    private func buildGroups(from modules: [ModuleViewModel], alignment: String) -> [ModuleGroup] {
        guard !modules.isEmpty else { return [] }
        var groups: [ModuleGroup] = []
        var current: [ModuleViewModel] = []
        var currentPassthrough = false

        for vm in modules {
            let isMasked = vm.moduleConfig.mask != nil
            let pt = isModulePassthrough(vm)

            if isMasked {
                // Flush any accumulated non-masked modules
                if !current.isEmpty {
                    groups.append(ModuleGroup(
                        id: "\(alignment)-\(groups.count)",
                        modules: current,
                        isPassthrough: currentPassthrough,
                        alignment: alignment
                    ))
                    current = []
                }
                // Masked module gets its own group
                groups.append(ModuleGroup(
                    id: "\(alignment)-\(groups.count)",
                    modules: [vm],
                    isPassthrough: true,
                    alignment: alignment
                ))
            } else {
                if current.isEmpty {
                    currentPassthrough = pt
                    current.append(vm)
                } else if pt == currentPassthrough {
                    current.append(vm)
                } else {
                    groups.append(ModuleGroup(
                        id: "\(alignment)-\(groups.count)",
                        modules: current,
                        isPassthrough: currentPassthrough,
                        alignment: alignment
                    ))
                    current = [vm]
                    currentPassthrough = pt
                }
            }
        }

        if !current.isEmpty {
            groups.append(ModuleGroup(
                id: "\(alignment)-\(groups.count)",
                modules: current,
                isPassthrough: currentPassthrough,
                alignment: alignment
            ))
        }

        return groups
    }

    func refreshAll() {
        for vm in allModules {
            vm.update()
        }
    }

    func pauseAll() {
        for vm in allModules {
            vm.pause()
        }
    }

    func resumeAll() {
        for vm in allModules {
            vm.resume()
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
    let config: Config
    private var appearanceObservation: NSKeyValueObservation?

    var isNative: Bool {
        config.appearance == .native
    }

    init(config: Config) {
        self.config = config
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

    // MARK: - Style Resolution Helpers

    private func resolveGlobalStyleMode() -> StyleModeConfig {
        if isDarkMode {
            return config.style.dark!
        } else {
            return config.style.light!
        }
    }

    private func resolveModuleStyleMode(_ style: StyleConfig?) -> StyleModeConfig? {
        guard let style = style else { return nil }
        return isDarkMode ? style.dark : style.light
    }

    // MARK: - Color Resolution

    func globalColors() -> (fg: Color, bg: Color) {
        let mode = resolveGlobalStyleMode()
        return (Color(nsColor: NSColor(hex: mode.fg!)), Color(nsColor: NSColor(hex: mode.bg!)))
    }

    func textFgColor(for vm: ModuleViewModel) -> Color {
        if let override = vm.fgOverride {
            return Color(nsColor: NSColor(hex: override))
        }
        if isNative { return Color(nsColor: .labelColor) }

        let moduleMode = resolveModuleStyleMode(vm.moduleConfig.style)
        let globalMode = resolveGlobalStyleMode()

        // Resolution: module.text.fg -> module.fg -> global.text.fg -> global.fg
        if let fg = moduleMode?.text?.fg { return Color(nsColor: NSColor(hex: fg)) }
        if let fg = moduleMode?.fg { return Color(nsColor: NSColor(hex: fg)) }
        if let fg = globalMode.text?.fg { return Color(nsColor: NSColor(hex: fg)) }
        return Color(nsColor: NSColor(hex: globalMode.fg!))
    }

    func iconFgColor(for vm: ModuleViewModel) -> Color {
        if let override = vm.fgOverride {
            return Color(nsColor: NSColor(hex: override))
        }
        if isNative { return Color(nsColor: .labelColor) }

        let moduleMode = resolveModuleStyleMode(vm.moduleConfig.style)
        let globalMode = resolveGlobalStyleMode()

        // Resolution: module.icon.fg -> module.fg -> global.icon.fg -> global.fg
        if let fg = moduleMode?.icon?.fg { return Color(nsColor: NSColor(hex: fg)) }
        if let fg = moduleMode?.fg { return Color(nsColor: NSColor(hex: fg)) }
        if let fg = globalMode.icon?.fg { return Color(nsColor: NSColor(hex: fg)) }
        return Color(nsColor: NSColor(hex: globalMode.fg!))
    }

    func bgColor(for vm: ModuleViewModel) -> Color {
        if let override = vm.bgOverride {
            return Color(nsColor: NSColor(hex: override))
        }
        if isNative { return .clear }

        let moduleMode = resolveModuleStyleMode(vm.moduleConfig.style)
        let globalMode = resolveGlobalStyleMode()

        // Resolution: module.bg -> global.bg
        if let bg = moduleMode?.bg { return Color(nsColor: NSColor(hex: bg)) }
        return Color(nsColor: NSColor(hex: globalMode.bg!))
    }

    func barBgColor() -> Color {
        if isNative { return .clear }
        let mode = resolveGlobalStyleMode()
        return Color(nsColor: NSColor(hex: mode.bg!))
    }

    func shape(for vm: ModuleViewModel) -> ModuleShape? {
        let moduleMode = resolveModuleStyleMode(vm.moduleConfig.style)
        return moduleMode?.shape
    }

    // MARK: - Font Resolution

    func iconFont(for vm: ModuleViewModel) -> Font {
        let fontConfig = vm.moduleConfig.iconFont ?? config.iconFont!
        return fontConfig.swiftUIFont
    }

    func textFont(for vm: ModuleViewModel) -> Font {
        let fontConfig = vm.moduleConfig.textFont ?? config.textFont!
        return fontConfig.swiftUIFont
    }

    // MARK: - Layout

    func iconTextSpacing() -> CGFloat {
        CGFloat(config.iconTextSpacing)
    }
}
