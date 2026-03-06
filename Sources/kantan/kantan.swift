import AppKit
import Yaml

@MainActor
class StatusBarController {
    var config: Config
    var statusBarWindow: NSWindow
    var statusBarView: NSView
    var statusBarWidth: CGFloat
    var moduleTimers: [ModuleTimer] = []
    var eventObserver: EventObserver?
    var moduleLayout: [String: (textPosition: CGPoint, iconPosition: CGPoint, width: CGFloat, alignment: String)] = [:]
    var moduleSubviews: [String: [NSView]] = [:]

    init(config: Config, statusBarWindow: NSWindow, statusBarView: NSView, statusBarWidth: CGFloat) {
        self.config = config
        self.statusBarWindow = statusBarWindow
        self.statusBarView = statusBarView
        self.statusBarWidth = statusBarWidth

        self.applyCurrentAppearance()

        self.eventObserver = EventObserver(onRefresh: { [weak self] in
            self?.refreshAllModules()
        })

        for i in 0..<self.config.modules.count {
            var moduleTimer = ModuleTimer(moduleConfig: self.config.modules[i])
            moduleTimer.timer = Timer.scheduledTimer(withTimeInterval: self.config.modules[i].config?.redrawInterval ?? 1.0, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self = self else { return }
                    self.updateModule(at: i)
                }
            }
            self.moduleTimers.append(moduleTimer)
        }
    }

    func updateModule(at index: Int) {
        let module = config.modules[index]
        guard let moduleConfig = module.config else { return }

        let icon = moduleConfig.getIcon()
        let newIcon = icon.isEmpty ? module.icon : icon

        moduleConfig.getValue { [weak self] newValue in
            DispatchQueue.main.async {
                guard let self = self else { return }
                var mod = self.config.modules[index]
                if newValue != mod.lastDrawnValue || newIcon != mod.lastDrawnIcon {
                    mod.lastDrawnValue = newValue
                    mod.lastDrawnIcon = newIcon
                    self.config.modules[index] = mod
                    self.redrawAllModules()
                }
            }
        }
    }

    /// Redraws all modules from scratch to ensure correct positioning.
    private func redrawAllModules() {
        statusBarView.subviews.forEach { $0.removeFromSuperview() }
        moduleLayout.removeAll()
        moduleSubviews.removeAll()
        applyCurrentAppearance()
        for module in config.modules {
            drawModule(module)
        }
    }

    func currentColourConfig(moduleColour: ColourModeConfig?, globalColour: ColourModeConfig) -> ColourConfig {
        let appearance = NSApp.effectiveAppearance
        if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
            return moduleColour?.dark ?? globalColour.dark
        } else {
            return moduleColour?.light ?? globalColour.light
        }
    }

    func applyCurrentAppearance() {
        let currentBgColour = self.currentColourConfig(moduleColour: nil, globalColour: self.config.global.colour).bg
        let barBgColor = NSColor(hex: currentBgColour)
        self.statusBarView.layer?.backgroundColor = barBgColor.cgColor
    }

    func redrawBar() {
        redrawAllModules()
    }

    func refreshAllModules() {
        for i in 0..<config.modules.count {
            updateModule(at: i)
        }
    }

    func buildIconAttributedString(icon: String, fgColor: NSColor, bgColor: NSColor, module: ModuleConfig) -> NSAttributedString {
        let iconFontConfig = module.iconFont ?? self.config.global.iconFont!
        let fontName = iconFontConfig.name
        let fontSize = iconFontConfig.size
        let fontSymbolicTraits = iconFontConfig.symbolicTraits
        let fontDescriptor = NSFontDescriptor(name: fontName, size: fontSize).withSymbolicTraits(fontSymbolicTraits)
        let font = NSFont(descriptor: fontDescriptor, size: fontSize) ?? NSFont.systemFont(ofSize: fontSize)
        return NSAttributedString(string: icon, attributes: [.font: font, .foregroundColor: fgColor, .backgroundColor: bgColor])
    }

    func buildTextAttributedString(text: String, fgColor: NSColor, bgColor: NSColor, module: ModuleConfig) -> NSAttributedString {
        let textFontConfig = module.textFont ?? self.config.global.textFont!
        let fontName = textFontConfig.name
        let fontSize = textFontConfig.size
        let fontSymbolicTraits = textFontConfig.symbolicTraits
        let fontDescriptor = NSFontDescriptor(name: fontName, size: fontSize).withSymbolicTraits(fontSymbolicTraits)
        let font = NSFont(descriptor: fontDescriptor, size: fontSize) ?? NSFont.systemFont(ofSize: fontSize)
        return NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: fgColor, .backgroundColor: bgColor])
    }

    func drawModule(_ module: ModuleConfig) {
        // Remove previous subviews for this module
        moduleSubviews[module.name]?.forEach { $0.removeFromSuperview() }
        moduleSubviews[module.name] = nil
        moduleLayout.removeValue(forKey: module.name)

        let iconTextSpacing: CGFloat = 2
        let textContent: String? = module.lastDrawnValue
        let icon: String? = module.lastDrawnIcon ?? module.icon

        let currentColour = self.currentColourConfig(moduleColour: module.colour, globalColour: self.config.global.colour)
        let fgColor = NSColor(hex: currentColour.fg)
        let bgColor = NSColor(hex: currentColour.bg)

        let iconField = NSTextField(labelWithAttributedString: NSAttributedString())
        let textField = NSTextField(labelWithAttributedString: NSAttributedString())
        var totalWidth: CGFloat = 0

        if let icon = icon {
            iconField.attributedStringValue = self.buildIconAttributedString(icon: icon, fgColor: fgColor, bgColor: bgColor, module: module)
            iconField.sizeToFit()
            totalWidth += iconField.frame.width
        }

        if let textValue = textContent {
            textField.attributedStringValue = self.buildTextAttributedString(text: textValue, fgColor: fgColor, bgColor: bgColor, module: module)
            textField.sizeToFit()
            totalWidth += (icon != nil ? iconTextSpacing : 0) + textField.frame.width
        }

        let layout = self.positionModule(module: module, iconField: iconField, textField: textField, totalWidth: totalWidth)
        self.moduleLayout[module.name] = layout

        if icon != nil {
            iconField.frame.origin = layout.iconPosition
        }

        if textContent != nil {
            textField.frame.origin = layout.textPosition
        }

        self.statusBarView.addSubview(iconField)
        self.statusBarView.addSubview(textField)
        self.moduleSubviews[module.name] = [iconField, textField]
    }

    func positionModule(module: ModuleConfig, iconField: NSTextField, textField: NSTextField, totalWidth: CGFloat) -> (textPosition: CGPoint, iconPosition: CGPoint, width: CGFloat, alignment: String) {
        let padding: CGFloat = CGFloat(self.config.global.padding)
        let iconTextSpacing: CGFloat = 2

        var leftOffset: CGFloat = padding
        var rightOffset: CGFloat = self.statusBarWidth - padding
        var iconPosition = CGPoint.zero
        var textPosition = CGPoint.zero
        var occupiedWidth: CGFloat = 0

        let icon: String? = module.lastDrawnIcon ?? module.icon

        if let layout = self.moduleLayout[module.name] {
            return layout
        }

        switch module.alignment {
        case "left":
            let totalPreviousWidth = self.moduleLayout.values
                .filter { $0.alignment == "left" }
                .reduce(CGFloat(0)) { $0 + $1.width }

            leftOffset += totalPreviousWidth
            let startOffset = leftOffset

            if let _ = icon {
                iconPosition = CGPoint(x: leftOffset, y: (self.statusBarView.frame.height - iconField.frame.height) / 2)
                leftOffset += iconField.frame.width
            }

            if module.config != nil {
                if let _ = icon {
                    leftOffset += iconTextSpacing
                }
                textPosition = CGPoint(x: leftOffset, y: (self.statusBarView.frame.height - textField.frame.height) / 2)
                leftOffset += textField.frame.width + padding
            }

            occupiedWidth = leftOffset - startOffset

        case "right":
            let totalPreviousWidth = self.moduleLayout.values
                .filter { $0.alignment == "right" }
                .reduce(CGFloat(0)) { $0 + $1.width }

            rightOffset -= totalPreviousWidth
            let startOffset = rightOffset

            if module.config != nil {
                textPosition = CGPoint(x: rightOffset - textField.frame.width, y: (self.statusBarView.frame.height - textField.frame.height) / 2)
                rightOffset -= textField.frame.width
            }

            if let _ = icon {
                if module.config != nil {
                    rightOffset -= iconTextSpacing
                }
                iconPosition = CGPoint(x: rightOffset - iconField.frame.width, y: (self.statusBarView.frame.height - iconField.frame.height) / 2)
                rightOffset -= iconField.frame.width + padding
            }

            occupiedWidth = startOffset - rightOffset

        default:
            print("Invalid alignment")
            return (CGPoint.zero, CGPoint.zero, totalWidth, module.alignment)
        }

        self.moduleLayout[module.name] = (textPosition, iconPosition, occupiedWidth, module.alignment)

        return (textPosition, iconPosition, occupiedWidth, module.alignment)
    }
}


@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var statusBarView: NSView!
    var config: Config?
    var statusBarController: StatusBarController?
    var appearanceObservation: NSKeyValueObservation?

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        NSApp.setActivationPolicy(.accessory)

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

        window = NSWindow(contentRect: statusBarRect, styleMask: [.borderless], backing: .buffered, defer: false)

        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)))
        window.collectionBehavior = .canJoinAllSpaces
        window.isOpaque = false
        window.hasShadow = false
        window.backgroundColor = NSColor.clear
        window.ignoresMouseEvents = true

        statusBarView = NSView(frame: statusBarRect)
        statusBarView.wantsLayer = true
        window.contentView = statusBarView
        window.makeKeyAndOrderFront(nil)

        statusBarController = StatusBarController(config: config,
                                                  statusBarWindow: window,
                                                  statusBarView: statusBarView,
                                                  statusBarWidth: statusBarWidth)

        for i in 0..<config.modules.count {
            statusBarController?.updateModule(at: i)
        }

        appearanceObservation = NSApp.observe(\.effectiveAppearance) { [weak self] _, _ in
            MainActor.assumeIsolated {
                self?.statusBarController?.redrawBar()
            }
        }
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        appearanceObservation?.invalidate()
    }
}

@main
struct Kantan {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }
}
