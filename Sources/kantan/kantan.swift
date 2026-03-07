import AppKit
import SwiftUI
import Yaml

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var barViewModel: BarViewModel?
    var themeProvider: ThemeProvider?

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

        guard let focusedScreen = NSScreen.deepest else {
            print("Unable to get focused screen")
            return
        }

        let screenSize = focusedScreen.frame.size
        let statusBarWidth = screenSize.width

        let statusBarRect = NSRect(x: 0, y: screenSize.height - CGFloat(config.global.height), width: statusBarWidth, height: CGFloat(config.global.height))

        // Use NSPanel with .nonactivatingPanel so the bar is interactive
        // (hover/click) without ever stealing focus from tiling WMs
        window = NSPanel(contentRect: statusBarRect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)

        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)))
        window.collectionBehavior = .canJoinAllSpaces
        window.isOpaque = false
        window.hasShadow = false
        window.backgroundColor = NSColor.clear
        window.ignoresMouseEvents = false

        let theme = ThemeProvider(globalConfig: config.global)
        let bar = BarViewModel(config: config)

        // Update popup manager with theme colors and appearance
        let globalColour = theme.isDarkMode ? config.global.colour.dark : config.global.colour.light
        bar.popupManager.fgColor = NSColor(hex: globalColour.fg)
        bar.popupManager.bgColor = NSColor(hex: globalColour.bg)
        bar.popupManager.appearance = config.global.appearance
        bar.popupManager.barWindow = window

        let rootView = KantanBarView(barViewModel: bar, themeProvider: theme)
        let hostingView = NSHostingView(rootView: rootView)
        hostingView.frame = NSRect(origin: .zero, size: statusBarRect.size)

        if config.global.appearance == .native {
            let effectView = NSVisualEffectView(frame: NSRect(origin: .zero, size: statusBarRect.size))
            effectView.material = .headerView
            effectView.state = .active
            effectView.blendingMode = .behindWindow
            effectView.autoresizingMask = [.width, .height]

            hostingView.autoresizingMask = [.width, .height]
            effectView.addSubview(hostingView)
            window.contentView = effectView
        } else {
            window.contentView = hostingView
        }
        window.orderFrontRegardless()

        self.barViewModel = bar
        self.themeProvider = theme
    }

    func applicationWillTerminate(_ aNotification: Notification) {
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
