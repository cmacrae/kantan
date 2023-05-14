import AppKit
import Yaml

class StatusBarController {
    var config: Config
    var statusBarWindow: NSWindow
    var statusBarView: NSView
    var statusBarWidth: CGFloat
    var clockUpdateTimer: Timer?
    var lastDrawnClockValue: String?
    var eventObserver: EventObserver


    init(config: Config, statusBarWindow: NSWindow, statusBarView: NSView, statusBarWidth: CGFloat) {
        self.config = config
        self.statusBarWindow = statusBarWindow
        self.statusBarView = statusBarView
        self.statusBarWidth = statusBarWidth
        self.eventObserver = EventObserver()

        self.applyCurrentAppearance()

    }

    func startClockUpdateTimer() {
        let timer = Timer(timeInterval: 1, target: self,
                          selector: #selector(updateClockIfNeeded),
                          userInfo: nil, repeats: true)
        RunLoop.current.add(timer, forMode: .common)
    }

    @objc func updateClockIfNeeded() {
        if let clockModule = self.config.modules.first(where: { $0.type == "clock" }),
           let clockConfig = clockModule.config as? ClockConfig {
            let newClockValue = getClockText(format: clockConfig.format)
            if newClockValue != lastDrawnClockValue {
                lastDrawnClockValue = newClockValue
                self.drawModules(type: "clock")
            }
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
        let currentBgColour = currentColourConfig(moduleColour: nil, globalColour: self.config.global.colour).bg

        // Update the bar background color
        let barBgColor = NSColor(hex: currentBgColour)
        self.statusBarView.layer?.backgroundColor = barBgColor.cgColor
    }

    func redrawBar() {
        // Remove all subviews from the statusBarView
        self.statusBarView.subviews.forEach { $0.removeFromSuperview() }
        self.applyCurrentAppearance()
        self.drawModules()
    }

    func drawModules(type: String? = nil) {
        let padding: CGFloat = CGFloat(self.config.global.padding)
        let iconTextSpacing: CGFloat = 2

        var leftOffset: CGFloat = padding
        var rightOffset: CGFloat = padding
        var centerOffset: CGFloat = 0
        var totalWidth: CGFloat = 0


        for module in self.config.modules {
            // If a type has been specified, only operate on that
            if let targetType = type, targetType != module.type {
                continue
            }

            let currentColour = currentColourConfig(moduleColour: module.colour, globalColour: self.config.global.colour)
            let fgColor = NSColor(hex: currentColour.fg)
            let bgColor = NSColor(hex: currentColour.bg)

            let iconField = NSTextField(labelWithAttributedString: NSAttributedString())
            let textField = NSTextField(labelWithAttributedString: NSAttributedString())

            var icon: String?
            var textContent: String?

            icon = module.icon
            // Determine the text content based on the module type
            switch module.type {

            case "text":
                if let textConfig = module.config as? TextConfig {
                    textContent = textConfig.value
                }

            case "clock":
                if let clockConfig = module.config as? ClockConfig {
                    textContent = getClockText(format: clockConfig.format)
                }

                self.startClockUpdateTimer()

            case "power":
                if let powerConfig = module.config as? PowerConfig {
                    let batteryLevel = getBatteryLevel()
                    let charging = isCharging()

                    if charging {
                        icon = powerConfig.charging.icon
                        textContent = powerConfig.showLevel ? "\(batteryLevel)%" : ""
                    } else {
                        let index = min(batteryLevel / 25, powerConfig.battery.icons.count - 1)
                        icon = powerConfig.battery.icons[index]
                        textContent = powerConfig.showLevel ? "\(batteryLevel)%" : ""
                    }
                }

            default:
                print("Unsupported module type")
                continue
            }

            if let icon = icon {
                let iconFontConfig = module.iconFont ?? self.config.global.iconFont!
                let fontName = iconFontConfig.name
                let fontSize = iconFontConfig.size
                let fontSymbolicTraits = iconFontConfig.symbolicTraits

                let fontDescriptor = NSFontDescriptor(name: fontName, size: fontSize).withSymbolicTraits(fontSymbolicTraits)
                let font = NSFont(descriptor: fontDescriptor, size: fontSize) ?? NSFont.systemFont(ofSize: fontSize)
                let iconText = NSAttributedString(string: icon, attributes: [.font: font, .foregroundColor: fgColor, .backgroundColor: bgColor])

                iconField.attributedStringValue = iconText
                iconField.sizeToFit()

                totalWidth += iconField.frame.width
                self.statusBarView.addSubview(iconField)
            }

            if let textContent = textContent {
                let textFontConfig = module.textFont ?? self.config.global.textFont!
                let fontName = textFontConfig.name
                let fontSize = textFontConfig.size
                let fontSymbolicTraits = textFontConfig.symbolicTraits

                let fontDescriptor = NSFontDescriptor(name: fontName, size: fontSize).withSymbolicTraits(fontSymbolicTraits)
                let font = NSFont(descriptor: fontDescriptor, size: fontSize) ?? NSFont.systemFont(ofSize: fontSize)
                let text = NSAttributedString(string: textContent, attributes: [.font: font, .foregroundColor: fgColor, .backgroundColor: bgColor])

                textField.attributedStringValue = text
                textField.sizeToFit()

                totalWidth += (module.icon != nil ? iconTextSpacing : 0) + textField.frame.width
                self.statusBarView.addSubview(textField)
            }

            switch module.alignment {
            case "left":
                if let _ = icon {
                    iconField.frame.origin = CGPoint(x: leftOffset, y: (self.statusBarView.frame.height - iconField.frame.height) / 2)
                    leftOffset += iconField.frame.width
                }

                if let _ = textContent {
                    if let _ = module.icon {
                        leftOffset += iconTextSpacing
                    }
                    textField.frame.origin = CGPoint(x: leftOffset, y: (self.statusBarView.frame.height - textField.frame.height) / 2)
                    leftOffset += textField.frame.width + padding
                }
            case "right":
                if let _ = textContent {
                    textField.frame.origin = CGPoint(x: self.statusBarWidth - rightOffset - textField.frame.width, y: (self.statusBarView.frame.height - textField.frame.height) / 2)
                    rightOffset += textField.frame.width
                }

                if let _ = icon {
                    if let _ = textContent {
                        rightOffset += iconTextSpacing
                    }
                    iconField.frame.origin = CGPoint(x: self.statusBarWidth - rightOffset - iconField.frame.width, y: (self.statusBarView.frame.height - iconField.frame.height) / 2)
                    rightOffset += iconField.frame.width + padding
                }
            case "centre":
                let startingCenterOffset = (self.statusBarWidth - totalWidth) / 2

                if let _ = icon {
                    iconField.frame.origin = CGPoint(x: startingCenterOffset + centerOffset, y: (self.statusBarView.frame.height - iconField.frame.height) / 2)
                    centerOffset += iconField.frame.width
                }

                if let _ = textContent {
                    if let _ = module.icon {
                        centerOffset += iconTextSpacing
                    }
                    textField.frame.origin = CGPoint(x: startingCenterOffset + centerOffset, y: (self.statusBarView.frame.height - textField.frame.height) / 2)
                }
            default:
                print("Invalid alignment")
                return
            }
        }
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

        statusBarController?.drawModules()
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
        statusBarController?.clockUpdateTimer?.invalidate()
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
