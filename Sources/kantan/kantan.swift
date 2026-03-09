import AppKit
import Combine
import SwiftUI
import Yaml

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    var bgPanel: NSPanel!
    var groupPanels: [(panel: NSPanel, hostingView: NSHostingView<ModuleGroupView>, group: ModuleGroup)] = []
    var barViewModel: BarViewModel?
    var themeProvider: ThemeProvider?
    var barHeight: CGFloat = 0
    var autohideConfig: AutohideConfig = .default
    var isMenuBarShowing: Bool = false
    var isHoveringTopEdge: Bool = false
    nonisolated(unsafe) var menuBarMonitor: Any?
    nonisolated(unsafe) var repositionTimer: Timer?
    nonisolated(unsafe) var autohideDelayTimer: Timer?
    var bgColorCancellable: AnyCancellable?
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

        barHeight = CGFloat(config.height)
        autohideConfig = config.autohide

        guard let screen = NSScreen.screens.first else {
            print("Unable to get screen")
            return
        }

        let statusBarY = screen.frame.origin.y + screen.frame.height - barHeight
        let statusWindowLevel = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)))

        // MARK: Background Panel — full-width, ignoresMouseEvents
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

        let theme = ThemeProvider(config: config)

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

            // Reactively update bar background when light/dark mode changes
            bgColorCancellable = theme.$isDarkMode.sink { [weak self] isDark in
                guard let self = self, let view = self.bgPanel.contentView else { return }
                let mode = isDark ? config.style.dark! : config.style.light!
                view.layer?.backgroundColor = NSColor(hex: mode.bg!).cgColor
            }
        }

        bgPanel.orderFrontRegardless()

        // MARK: Module Group Panels
        let bar = BarViewModel(config: config)

        bar.popupManager.themeProvider = theme
        bar.popupManager.appearance = config.appearance

        let moduleGroupLevel = NSWindow.Level(rawValue: statusWindowLevel.rawValue + 1)
        // Right groups are reversed so the last group (rightmost in config)
        // gets positioned at the far right edge of the screen
        let allGroups = bar.leftGroups + bar.rightGroups.reversed()

        // Detect native menu bar items for masked module positioning
        let nativeItems = MenuBarItemDetector.detectItems()

        // First pass: determine space occupied by masked modules
        var leftX = screen.frame.origin.x
        var rightX = screen.frame.origin.x + screen.frame.width

        for group in allGroups {
            guard group.modules.count == 1,
                  let mask = group.modules[0].moduleConfig.mask,
                  let nativeItem = MenuBarItemDetector.resolveItem(for: mask, from: nativeItems) else { continue }
            if group.alignment == "right" {
                rightX = min(rightX, CGFloat(nativeItem.cgRect.origin.x))
            } else {
                leftX = max(leftX, CGFloat(nativeItem.cgRect.origin.x + nativeItem.cgRect.width))
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
                // Masked module: position at native item coordinates
                let nativeRect = MenuBarItemDetector.appKitRect(from: nativeItem.cgRect, screenHeight: screen.frame.height)
                panelRect = NSRect(x: nativeRect.origin.x, y: statusBarY, width: nativeRect.width, height: barHeight)
            } else {
                // Non-masked: sequential positioning
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

            // Register each module in the group with the popup manager
            for vm in group.modules {
                bar.popupManager.modulePanels[vm.id] = panel
            }

            groupPanels.append((panel: panel, hostingView: hostingView, group: group))
        }

        self.barViewModel = bar
        self.themeProvider = theme

        // Reposition panels when module visibility changes (e.g. reminders
        // hiding when empty). Debounce to coalesce rapid changes.
        for vm in bar.allModules {
            vm.$shouldDisplay
                .removeDuplicates()
                .debounce(for: .milliseconds(50), scheduler: RunLoop.main)
                .sink { [weak self] _ in
                    self?.repositionAllPanels()
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

    @objc func screenDidChange(_ notification: Notification) {
        repositionAllPanels()
        restartRepositionTimer()
    }

    func restartRepositionTimer() {
        repositionTimer?.invalidate()
        var repositionCount = 0
        repositionTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.repositionAllPanels()
                repositionCount += 1
                if repositionCount >= 20 {
                    self?.repositionTimer?.invalidate()
                    self?.repositionTimer = nil
                }
            }
        }
    }

    func repositionAllPanels() {
        guard let screen = NSScreen.screens.first else { return }
        let statusBarY = screen.frame.origin.y + screen.frame.height - barHeight

        // Background panel — full width
        let bgFrame = NSRect(
            x: screen.frame.origin.x,
            y: statusBarY,
            width: screen.frame.width,
            height: barHeight
        )
        bgPanel.setFrame(bgFrame, display: true)

        // Re-detect native items for current positions
        let nativeItems = MenuBarItemDetector.detectItems()

        // First pass: position masked panels and compute the space they occupy
        // so non-masked panels don't overlap with them
        var leftX = screen.frame.origin.x
        var rightX = screen.frame.origin.x + screen.frame.width

        for entry in groupPanels {
            guard entry.group.modules.count == 1,
                  let mask = entry.group.modules[0].moduleConfig.mask else { continue }

            guard let nativeItem = MenuBarItemDetector.resolveItem(for: mask, from: nativeItems) else {
                // Mask resolution failed — hide panel to avoid stale positioning
                entry.panel.orderOut(nil)
                continue
            }

            let nativeRect = MenuBarItemDetector.appKitRect(from: nativeItem.cgRect, screenHeight: screen.frame.height)
            let panelFrame = NSRect(x: nativeRect.origin.x, y: statusBarY, width: nativeRect.width, height: barHeight)
            entry.panel.setFrame(panelFrame, display: true)
            if !entry.panel.isVisible {
                entry.panel.orderFrontRegardless()
            }

            // Shrink the available space for sequential panels
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
        guard let screen = NSScreen.screens.first else { return }
        let mouseY = NSEvent.mouseLocation.y
        let mouseX = NSEvent.mouseLocation.x
        let screenTop = screen.frame.maxY
        let menuBarRegion = screen.frame.maxY - screen.visibleFrame.maxY

        // Only trigger when the mouse is within this screen's horizontal bounds
        let inScreenX = mouseX >= screen.frame.minX && mouseX <= screen.frame.maxX
        let atTopEdge = mouseY >= screenTop - 4 && inScreenX

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
            if isMenuBarShowing && mouseY < screenTop - menuBarRegion {
                isMenuBarShowing = false
                slideIn()
            }
        }
    }

    // MARK: - Slide Animation

    private var allPanels: [NSPanel] {
        [bgPanel] + groupPanels.map { $0.panel }
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
                MainActor.assumeIsolated {
                    for panel in panels {
                        panel.orderOut(nil)
                    }
                }
            }
        })
    }

    func slideIn() {
        // Reposition panels to their correct locations before showing
        repositionAllPanels()

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

    func applicationWillTerminate(_ aNotification: Notification) {
        stopMenuBarMonitoring()
        repositionTimer?.invalidate()
        autohideDelayTimer?.invalidate()
        bgColorCancellable?.cancel()
        visibilityCancellables.removeAll()
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
