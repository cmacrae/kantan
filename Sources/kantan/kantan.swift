import AppKit
import Combine
import SwiftUI
import Yaml

// MARK: - Display Instance

/// Encapsulates all per-display state: panels, autohide tracking, and
/// repositioning. One instance is created for each screen kantan runs on.
@MainActor
class DisplayInstance {
    let screenName: String
    var bgPanel: NSPanel!
    var groupPanels: [(panel: NSPanel, hostingView: NSHostingView<ModuleGroupView>, group: ModuleGroup)] = []
    var bgColorCancellable: AnyCancellable?

    // Autohide state (independent per display)
    var isMenuBarShowing: Bool = false
    var isHoveringTopEdge: Bool = false
    var enteredFromAbove: Bool = false
    nonisolated(unsafe) var autohideDelayTimer: Timer?

    private let barHeight: CGFloat
    private let config: Config
    private weak var bar: BarViewModel?
    private weak var theme: ThemeProvider?

    init(screenName: String, barHeight: CGFloat, config: Config) {
        self.screenName = screenName
        self.barHeight = barHeight
        self.config = config
    }

    /// Find the current NSScreen matching this instance's screenName.
    func resolveScreen() -> NSScreen? {
        for screen in NSScreen.screens {
            if screen.localizedName == screenName {
                return screen
            }
        }
        return nil
    }

    /// Create all panels for the given screen.
    func createPanels(for screen: NSScreen, bar: BarViewModel, theme: ThemeProvider) {
        self.bar = bar
        self.theme = theme

        let statusBarY = screen.frame.origin.y + screen.frame.height - barHeight
        let statusWindowLevel = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)))

        // Background panel — full-width, ignoresMouseEvents
        let bgRect = NSRect(
            x: screen.frame.origin.x,
            y: statusBarY,
            width: screen.frame.width,
            height: barHeight
        )

        bgPanel = NSPanel(contentRect: bgRect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        bgPanel.level = statusWindowLevel
        bgPanel.collectionBehavior = .canJoinAllSpaces
        bgPanel.isOpaque = false
        bgPanel.hasShadow = false
        bgPanel.backgroundColor = NSColor.clear
        bgPanel.ignoresMouseEvents = true

        if config.appearance == .native {
            let effectView = NSVisualEffectView(frame: NSRect(origin: .zero, size: bgRect.size))
            effectView.material = .headerView
            effectView.state = .active
            effectView.blendingMode = .behindWindow
            effectView.autoresizingMask = [.width, .height]
            bgPanel.contentView = effectView
        } else {
            let bgView = NSView(frame: NSRect(origin: .zero, size: bgRect.size))
            bgView.wantsLayer = true
            let globalStyle = theme.isDarkMode ? config.style.dark! : config.style.light!
            bgView.layer?.backgroundColor = NSColor(hex: globalStyle.bg!).cgColor
            bgView.autoresizingMask = [.width, .height]
            bgPanel.contentView = bgView

            bgColorCancellable = theme.$isDarkMode.sink { [weak self] isDark in
                guard let self = self, let view = self.bgPanel.contentView else { return }
                let mode = isDark ? config.style.dark! : config.style.light!
                view.layer?.backgroundColor = NSColor(hex: mode.bg!).cgColor
            }
        }

        bgPanel.orderFrontRegardless()

        // Module group panels
        let moduleGroupLevel = NSWindow.Level(rawValue: statusWindowLevel.rawValue + 1)
        let allGroups = bar.leftGroups + bar.rightGroups.reversed()

        let nativeItems = MenuBarItemDetector.detectItems(for: screen)

        // First pass: determine space occupied by masked modules
        var leftX = screen.frame.origin.x
        var rightX = screen.frame.origin.x + screen.frame.width

        for group in allGroups {
            guard group.modules.count == 1,
                  let mask = group.modules[0].moduleConfig.mask,
                  let nativeItem = MenuBarItemDetector.resolveItem(for: mask, from: nativeItems) else { continue }
            let nativeRect = MenuBarItemDetector.appKitRect(from: nativeItem.cgRect, on: screen)
            if group.alignment == "right" {
                rightX = min(rightX, nativeRect.origin.x)
            } else {
                leftX = max(leftX, nativeRect.origin.x + nativeRect.width)
            }
        }

        // Second pass: create panels for all groups
        for group in allGroups {
            let groupView = ModuleGroupView(
                modules: group.modules,
                popupManager: bar.popupManager,
                themeProvider: theme
            )
            let hostingView = NSHostingView(rootView: groupView)

            let panelRect: NSRect
            if group.modules.count == 1,
               let mask = group.modules[0].moduleConfig.mask,
               let nativeItem = MenuBarItemDetector.resolveItem(for: mask, from: nativeItems) {
                let nativeRect = MenuBarItemDetector.appKitRect(from: nativeItem.cgRect, on: screen)
                panelRect = NSRect(x: nativeRect.origin.x, y: statusBarY, width: nativeRect.width, height: barHeight)
            } else {
                let fittingWidth = hostingView.fittingSize.width
                let panelX: CGFloat
                if group.alignment == "left" {
                    panelX = leftX
                    leftX += fittingWidth
                } else {
                    rightX -= fittingWidth
                    panelX = rightX
                }
                panelRect = NSRect(x: panelX, y: statusBarY, width: fittingWidth, height: barHeight)
            }

            let panel = NSPanel(contentRect: panelRect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.level = moduleGroupLevel
            panel.collectionBehavior = .canJoinAllSpaces
            panel.isOpaque = false
            panel.hasShadow = false
            panel.backgroundColor = NSColor.clear
            panel.ignoresMouseEvents = group.isPassthrough

            hostingView.frame = NSRect(origin: .zero, size: panelRect.size)
            hostingView.autoresizingMask = [.width, .height]
            panel.contentView = hostingView
            panel.orderFrontRegardless()

            for vm in group.modules {
                bar.popupManager.modulePanels[vm.id] = panel
            }

            groupPanels.append((panel: panel, hostingView: hostingView, group: group))
        }
    }

    /// Reposition all panels to match the current screen geometry and
    /// native menu bar item positions.
    func repositionPanels() {
        guard let screen = resolveScreen() else { return }
        let statusBarY = screen.frame.origin.y + screen.frame.height - barHeight

        // Background panel — full width
        let bgFrame = NSRect(
            x: screen.frame.origin.x,
            y: statusBarY,
            width: screen.frame.width,
            height: barHeight
        )
        bgPanel.setFrame(bgFrame, display: true)

        // Re-detect native items for current positions on this screen
        let nativeItems = MenuBarItemDetector.detectItems(for: screen)

        // First pass: position masked panels
        var leftX = screen.frame.origin.x
        var rightX = screen.frame.origin.x + screen.frame.width

        for entry in groupPanels {
            guard entry.group.modules.count == 1,
                  let mask = entry.group.modules[0].moduleConfig.mask else { continue }

            guard let nativeItem = MenuBarItemDetector.resolveItem(for: mask, from: nativeItems) else {
                entry.panel.orderOut(nil)
                continue
            }

            let nativeRect = MenuBarItemDetector.appKitRect(from: nativeItem.cgRect, on: screen)
            let panelFrame = NSRect(x: nativeRect.origin.x, y: statusBarY, width: nativeRect.width, height: barHeight)
            entry.panel.setFrame(panelFrame, display: true)
            if !entry.panel.isVisible {
                entry.panel.orderFrontRegardless()
            }

            if entry.group.alignment == "right" {
                rightX = min(rightX, nativeRect.origin.x)
            } else {
                leftX = max(leftX, nativeRect.origin.x + nativeRect.width)
            }
        }

        // Second pass: position non-masked panels sequentially
        for entry in groupPanels {
            if entry.group.modules.count == 1 && entry.group.modules[0].moduleConfig.mask != nil {
                continue
            }

            let fittingWidth = entry.hostingView.fittingSize.width

            let panelX: CGFloat
            if entry.group.alignment == "left" {
                panelX = leftX
                leftX += fittingWidth
            } else {
                rightX -= fittingWidth
                panelX = rightX
            }

            let panelFrame = NSRect(x: panelX, y: statusBarY, width: fittingWidth, height: barHeight)
            entry.panel.setFrame(panelFrame, display: true)
        }
    }

    // MARK: - Autohide

    /// Check whether the mouse is in this display's trigger zone and
    /// update autohide state accordingly. Called from the global mouse
    /// monitor for each display instance.
    func checkMenuBar(mouseLocation: NSPoint, autohideConfig: AutohideConfig) {
        guard let screen = resolveScreen() else { return }
        let mouseX = mouseLocation.x
        let mouseY = mouseLocation.y
        let screenTop = screen.frame.maxY
        let menuBarRegion = screen.frame.maxY - screen.visibleFrame.maxY

        let onScreen = mouseX >= screen.frame.minX && mouseX <= screen.frame.maxX
                    && mouseY >= screen.frame.minY && mouseY < screenTop
        let inTriggerZone = onScreen && mouseY >= screenTop - 4

        if !onScreen {
            enteredFromAbove = true
        } else if enteredFromAbove && !inTriggerZone {
            enteredFromAbove = false
        }

        let atTopEdge = inTriggerZone && !enteredFromAbove

        if !isMenuBarShowing && atTopEdge {
            if !isHoveringTopEdge {
                isHoveringTopEdge = true
                if autohideConfig.delay <= 0 {
                    isMenuBarShowing = true
                    slideOut()
                } else {
                    autohideDelayTimer?.invalidate()
                    autohideDelayTimer = Timer.scheduledTimer(withTimeInterval: autohideConfig.delay, repeats: false) { [weak self] _ in
                        MainActor.assumeIsolated {
                            guard let self = self, self.isHoveringTopEdge else { return }
                            self.isMenuBarShowing = true
                            self.slideOut()
                        }
                    }
                }
            }
        } else if !atTopEdge {
            if isHoveringTopEdge {
                isHoveringTopEdge = false
                autohideDelayTimer?.invalidate()
                autohideDelayTimer = nil
            }
            if isMenuBarShowing && (!onScreen || mouseY < screenTop - menuBarRegion) {
                isMenuBarShowing = false
                slideIn()
            }
        }
    }

    // MARK: - Slide Animation

    var allPanels: [NSPanel] {
        [bgPanel].compactMap { $0 } + groupPanels.map { $0.panel }
    }

    func slideOut() {
        let panels = allPanels
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            for panel in panels {
                panel.animator().alphaValue = 0
            }
        }, completionHandler: {
            DispatchQueue.main.async {
                MainActor.assumeIsolated { [weak self] in
                    guard let self = self, self.isMenuBarShowing else { return }
                    for panel in panels {
                        panel.orderOut(nil)
                    }
                }
            }
        })
    }

    func slideIn() {
        repositionPanels()

        for panel in allPanels {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            for panel in self.allPanels {
                panel.animator().alphaValue = 1
            }
        }
    }

    /// Remove all panels from screen and release resources.
    func teardown() {
        autohideDelayTimer?.invalidate()
        autohideDelayTimer = nil
        bgColorCancellable?.cancel()
        bgColorCancellable = nil
        for panel in allPanels {
            panel.orderOut(nil)
        }
        groupPanels.removeAll()
        bgPanel = nil
    }
}

// MARK: - App Delegate

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    var displayInstances: [DisplayInstance] = []
    var barViewModel: BarViewModel?
    var themeProvider: ThemeProvider?
    var config: Config?
    var barHeight: CGFloat = 0
    var autohideConfig: AutohideConfig = .default
    nonisolated(unsafe) var menuBarMonitor: Any?
    nonisolated(unsafe) var repositionTimer: Timer?
    var visibilityCancellables: [AnyCancellable] = []

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        var config: Config?

        if let fileData = loadFileContents(filePath: "config.yaml") {
            do {
                let yaml = try Yaml.load(fileData)
                config = loadConfig(from: yaml)
            } catch {
                print(error)
            }
        } else {
            print("Failed to load file contents")
        }

        guard let config = config else {
            print("Configuration not loaded")
            return
        }

        self.config = config
        barHeight = CGFloat(config.height)
        autohideConfig = config.autohide

        let theme = ThemeProvider(config: config)
        let bar = BarViewModel(config: config)
        bar.popupManager.themeProvider = theme
        bar.popupManager.appearance = config.appearance

        self.barViewModel = bar
        self.themeProvider = theme

        // Create display instances for target screens
        let targetScreens = resolveTargetScreens(config.displays)
        for screen in targetScreens {
            let instance = DisplayInstance(screenName: screen.localizedName, barHeight: barHeight, config: config)
            instance.createPanels(for: screen, bar: bar, theme: theme)
            displayInstances.append(instance)
        }

        // Reposition panels when module visibility changes
        for vm in bar.allModules {
            vm.$shouldDisplay
                .removeDuplicates()
                .debounce(for: .milliseconds(50), scheduler: RunLoop.main)
                .sink { [weak self] _ in
                    self?.repositionAllDisplays()
                }
                .store(in: &visibilityCancellables)
        }

        restartRepositionTimer()

        NotificationCenter.default.addObserver(
            self, selector: #selector(screenDidChange),
            name: NSApplication.didChangeScreenParametersNotification, object: nil
        )

        if autohideConfig.enabled {
            startMenuBarMonitoring()
        }
    }

    // MARK: - Screen Resolution

    /// Resolve which screens to display on based on the config.
    func resolveTargetScreens(_ displays: DisplaysConfig) -> [NSScreen] {
        switch displays {
        case .main:
            if let main = NSScreen.main {
                return [main]
            }
            // Fall back to first screen if main isn't available
            if let first = NSScreen.screens.first {
                return [first]
            }
            return []
        case .all:
            return NSScreen.screens
        case .named(let names):
            return NSScreen.screens.filter { screen in
                names.contains(screen.localizedName)
            }
        }
    }

    // MARK: - Screen Change Handling

    @objc func screenDidChange(_ notification: Notification) {
        guard let config = config, let bar = barViewModel, let theme = themeProvider else { return }

        let targetScreens = resolveTargetScreens(config.displays)
        let targetNames = Set(targetScreens.map { $0.localizedName })
        let existingNames = Set(displayInstances.map { $0.screenName })

        // Remove instances for screens no longer targeted
        for instance in displayInstances where !targetNames.contains(instance.screenName) {
            instance.teardown()
        }
        displayInstances.removeAll { !targetNames.contains($0.screenName) }

        // Add instances for newly targeted screens
        for screen in targetScreens where !existingNames.contains(screen.localizedName) {
            let instance = DisplayInstance(screenName: screen.localizedName, barHeight: barHeight, config: config)
            instance.createPanels(for: screen, bar: bar, theme: theme)
            displayInstances.append(instance)
        }

        // Reposition existing instances
        repositionAllDisplays()
        restartRepositionTimer()
    }

    // MARK: - Repositioning

    func repositionAllDisplays() {
        for instance in displayInstances {
            instance.repositionPanels()
        }
    }

    func restartRepositionTimer() {
        repositionTimer?.invalidate()
        var repositionCount = 0
        repositionTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.repositionAllDisplays()
                repositionCount += 1
                if repositionCount >= 20 {
                    self?.repositionTimer?.invalidate()
                    self?.repositionTimer = nil
                }
            }
        }
    }

    // MARK: - Menu Bar Visibility Monitoring

    func startMenuBarMonitoring() {
        menuBarMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self?.checkMenuBar()
                }
            }
        }
    }

    func stopMenuBarMonitoring() {
        if let monitor = menuBarMonitor {
            NSEvent.removeMonitor(monitor)
            menuBarMonitor = nil
        }
    }

    func checkMenuBar() {
        let mouseLocation = NSEvent.mouseLocation
        for instance in displayInstances {
            instance.checkMenuBar(mouseLocation: mouseLocation, autohideConfig: autohideConfig)
        }
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        stopMenuBarMonitoring()
        repositionTimer?.invalidate()
        visibilityCancellables.removeAll()
        for instance in displayInstances {
            instance.teardown()
        }
    }
}

@main
struct Kantan {
    static func main() {
        let args = CommandLine.arguments

        // CLI trigger mode: kantan trigger <module> <action> [key=value ...]
        if args.count >= 4 && args[1] == "trigger" {
            let module = args[2]
            let action = args[3]

            var userInfo: [String: String] = [
                "module": module,
                "action": action,
            ]

            // Parse key=value pairs from remaining args
            for i in 4..<args.count {
                let parts = args[i].split(separator: "=", maxSplits: 1)
                if parts.count == 2 {
                    userInfo[String(parts[0])] = String(parts[1])
                }
            }

            DistributedNotificationCenter.default().postNotificationName(
                NSNotification.Name("com.kantan.event"),
                object: nil,
                userInfo: userInfo,
                deliverImmediately: true
            )
            return
        }

        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }
}
