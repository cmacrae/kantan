import AppKit
import Yaml

class StatusBarController {
    var config: Config
    var statusBarWindow: NSWindow
    var statusBarView: NSView
    var statusBarWidth: CGFloat
    var moduleTimers: [ModuleTimer] = []
    var eventObserver: EventObserver
    var moduleLayout: [String: (textPosition: CGPoint, iconPosition: CGPoint, width: CGFloat, alignment: String)] = [:]

    init(config: Config, statusBarWindow: NSWindow, statusBarView: NSView, statusBarWidth: CGFloat) {
        self.config = config
        self.statusBarWindow = statusBarWindow
        self.statusBarView = statusBarView
        self.statusBarWidth = statusBarWidth
        self.eventObserver = EventObserver()

        self.applyCurrentAppearance()

        for i in 0..<self.config.modules.count {
            var moduleTimer = ModuleTimer(moduleConfig: self.config.modules[i])
            moduleTimer.timer = Timer.scheduledTimer(withTimeInterval: self.config.modules[i].config?.redrawInterval ?? 1.0, repeats: true) { [weak self] _ in
                guard let self = self else { return }
                self.updateModuleIfNeeded(self.config.modules[i]) { updatedModule in
                    DispatchQueue.main.async {
                        self.config.modules[i] = updatedModule
                    }
                }
            }
            self.moduleTimers.append(moduleTimer)
        }
    }

    func updateModuleIfNeeded(_ module: ModuleConfig, completion: @escaping (ModuleConfig) -> Void) {
        var mutableModule = module
        guard let config = mutableModule.config else { 
            completion(mutableModule)
            return
        }

        config.getValue() { newValue in 
            let icon = config.getIcon()
            let newIcon = icon.isEmpty ? mutableModule.icon : icon

            if newValue != mutableModule.lastDrawnValue || newIcon != mutableModule.lastDrawnIcon {
                mutableModule.lastDrawnValue = newValue
                mutableModule.lastDrawnIcon = newIcon
                self.drawModule(mutableModule)
            }
            completion(mutableModule)
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
        // Get the current color configuration for the background
        let currentBgColour = self.currentColourConfig(moduleColour: nil, globalColour: self.config.global.colour).bg

        // Update the bar background color
        let barBgColor = NSColor(hex: currentBgColour)
        self.statusBarView.layer?.backgroundColor = barBgColor.cgColor
    }

    func redrawBar() {
        // Remove all subviews from the statusBarView
        self.statusBarView.subviews.forEach { $0.removeFromSuperview() }
        self.applyCurrentAppearance()
        for module in config.modules {
            self.drawModule(module)
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
        DispatchQueue.global(qos: .userInitiated).async {
            let iconTextSpacing: CGFloat = 2
            var textContent: String?
            var icon: String? = module.icon

            let valReady = DispatchGroup()

            switch module.type {
            case "text":
                if let textConfig = module.config as? TextConfig {
                    valReady.enter()
                    textConfig.getValue() { value in
                        textContent = value
                        valReady.leave()
                    }
                }
            case "clock":
                if let clockConfig = module.config as? ClockConfig {
                    valReady.enter()
                    clockConfig.getValue() { value in
                        textContent = value
                        valReady.leave()
                    }
                }
            case "power":
                if let powerConfig = module.config as? PowerConfig {
                    valReady.enter()
                    icon = powerConfig.getIcon()
                    powerConfig.getValue() { value in
                        textContent = value
                        valReady.leave()
                    }
                }
            case "command":
                if let commandConfig = module.config as? CommandConfig {
                    valReady.enter()
                    commandConfig.getValue() { value in
                        textContent = value
                        valReady.leave()
                    }
                }
            case "reminders":
                if let remindersConfig = module.config as? RemindersConfig {
                    valReady.enter()
                    remindersConfig.getValue() { value in
                        textContent = value
                        valReady.leave()
                    }
                }
            default:
                print("Unsupported module type")
                return
            }

            valReady.wait()

            DispatchQueue.main.async {
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

                // Position the icon and text field according to the module's alignment
                let layout = self.positionModule(module: module, iconField: iconField, textField: textField, totalWidth: totalWidth)
                self.moduleLayout[module.name] = layout

                // Set the positions
                if icon != nil {
                    iconField.frame.origin = layout.iconPosition
                }

                if textContent != nil {
                    textField.frame.origin = layout.textPosition
                }

                // Add to the view
                self.statusBarView.addSubview(iconField)
                self.statusBarView.addSubview(textField)
            }
        }
    }

    func positionModule(module: ModuleConfig, iconField: NSTextField, textField: NSTextField, totalWidth: CGFloat) -> (textPosition: CGPoint, iconPosition: CGPoint, width: CGFloat, alignment: String) {
        let padding: CGFloat = CGFloat(self.config.global.padding)
        let iconTextSpacing: CGFloat = 2

        var leftOffset: CGFloat = padding
        var rightOffset: CGFloat = self.statusBarWidth - padding
        var iconPosition = CGPoint.zero
        var textPosition = CGPoint.zero

        var icon: String? = module.config?.getIcon()
        icon = icon?.isEmpty ?? true ? module.icon : icon


        // Check if the module position is already in the moduleLayout
        if let layout = self.moduleLayout[module.name] {
            return layout
        }

        switch module.alignment {
        case "left":
            // Get the last left-aligned module's information
            let lastModuleInfo = self.moduleLayout.values.filter { $0.alignment == "left" }.sorted(by: { $0.iconPosition.x < $1.iconPosition.x }).last

            leftOffset += lastModuleInfo?.width ?? 0

            if let _ = icon {
                iconPosition = CGPoint(x: leftOffset, y: (self.statusBarView.frame.height - iconField.frame.height) / 2)
                leftOffset += iconField.frame.width
            }

            if let _ = module.config?.getValue {
                if let _ = icon {
                    leftOffset += iconTextSpacing
                }
                textPosition = CGPoint(x: leftOffset, y: (self.statusBarView.frame.height - textField.frame.height) / 2)
                leftOffset += textField.frame.width + padding
            }

        case "right":
            // Get the last right-aligned module's information
            let lastModuleInfo = self.moduleLayout.values.filter { $0.alignment == "right" }.sorted(by: { $0.iconPosition.x > $1.iconPosition.x }).first

            rightOffset -= lastModuleInfo?.width ?? 0

            if let _ = module.config?.getValue {
                textPosition = CGPoint(x: rightOffset - textField.frame.width, y: (self.statusBarView.frame.height - textField.frame.height) / 2)
                rightOffset -= textField.frame.width
            }

            if let _ = icon {
                if let _ = module.config?.getValue {
                    rightOffset -= iconTextSpacing
                }
                iconPosition = CGPoint(x: rightOffset - iconField.frame.width, y: (self.statusBarView.frame.height - iconField.frame.height) / 2)
                rightOffset -= iconField.frame.width + padding
            }

        default:
            print("Invalid alignment")
            return (CGPoint.zero, CGPoint.zero, totalWidth, module.alignment)
        }

        // Store the current module's position information in moduleLayout
        self.moduleLayout[module.name] = (textPosition, iconPosition, totalWidth, module.alignment)

        return (textPosition, iconPosition, totalWidth, module.alignment)
    }
}


class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var statusBarView: NSView!
    var config: Config?
    var statusBarController: StatusBarController?
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Make sure we're not focusable
        NSApp.setActivationPolicy(.accessory)

        if let fileData = loadFileContents(filePath: "config.yaml") {
            do {
                let yaml = try Yaml.load(fileData)
                config = loadConfig(from: yaml)
                if let config = config {
                    print("Loaded config: \(config)") // NOTE: debugging
                } else {
                    print("Failed to load config from YAML data") // NOTE: debugging
                }
            } catch {
                print(error)
            }
        } else {
            print("Failed to load file contents") // NOTE: debugging
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
        // let screenSize = NSScreen.main!.frame.size

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

        for module in config.modules {
            statusBarController?.drawModule(module)
        }
    }

    override init() {
        super.init()
        NSApp.addObserver(self, forKeyPath: #keyPath(NSApplication.effectiveAppearance), options: [.new], context: nil)
    }

    deinit {
        NSApp.removeObserver(self, forKeyPath: #keyPath(NSApplication.effectiveAppearance))
    }
    
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        if keyPath == #keyPath(NSApplication.effectiveAppearance) {
            statusBarController?.redrawBar()
        }
    }
    
    func applicationWillTerminate(_ aNotification: Notification) {
        // statusBarController?.clockUpdateTimer?.invalidate()
    }
}

@main
public struct Kantan {
    public init() {}

    public static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }
}
