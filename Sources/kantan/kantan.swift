import AppKit
import Yaml

class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var statusBarView: NSView!
    var config: Config?
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Make sure we're not focusable
        NSApp.setActivationPolicy(.accessory)

        if let fileData = loadFileContents(filePath: "config.yaml") {
            do {
                let yaml = try Yaml.load(fileData)
                config = loadConfig(from: yaml)
                if let config = config {
                    print("Loaded config: \(config)") // NOTE: debugging
                    // Work with the config object here
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
        
        // let statusBarColor = NSColor(hex: config.global.colour.bg)
        // TODO: Make this dynamic
        let appearance = getCurrentAppearance()
        var statusBarColor: NSColor!
        if case appearance = "light" {
            statusBarColor = NSColor(hex: config.global.colour.light.bg)
        } else {
            statusBarColor = NSColor(hex: config.global.colour.dark.bg)
        }


        statusBarView = NSView(frame: statusBarRect)
        statusBarView.wantsLayer = true
        statusBarView.layer?.backgroundColor = statusBarColor.cgColor
        window.contentView = statusBarView
        

        drawModules(config: config, barWidth: statusBarWidth)
        
        window.makeKeyAndOrderFront(nil)
    }

    func drawModules(config: Config, barWidth: CGFloat) {
        let padding: CGFloat = CGFloat(config.global.padding)
        let iconTextSpacing: CGFloat = 2

        var leftOffset: CGFloat = padding
        var rightOffset: CGFloat = padding
        var centerOffset: CGFloat = 0
        var totalWidth: CGFloat = 0


        for module in config.modules {
            let currentColour = currentColourConfig(moduleColour: module.colour, globalColour: config.global.colour)
            let fgColor = NSColor(hex: currentColour.fg)
            let bgColor = NSColor(hex: currentColour.bg)

            let iconField = NSTextField(labelWithAttributedString: NSAttributedString())
            let textField = NSTextField(labelWithAttributedString: NSAttributedString())

            var textContent: String?

            // Determine the text content based on the module type
            switch module.type {
            case "text":
                if let textConfig = module.config as? TextConfig {
                    textContent = textConfig.value
                }
            case "clock":
                if let clockConfig = module.config as? ClockConfig {
                    textContent = getClockText(format: clockConfig.format) // Replace this with your clock module implementation
                }
            default:
                print("Unsupported module type")
                continue
            }

            if let icon = module.icon {
                let iconFontConfig = module.iconFont ?? config.global.iconFont!
                let fontName = iconFontConfig.name
                let fontSize = iconFontConfig.size
                let fontSymbolicTraits = iconFontConfig.symbolicTraits

                let fontDescriptor = NSFontDescriptor(name: fontName, size: fontSize).withSymbolicTraits(fontSymbolicTraits)
                let font = NSFont(descriptor: fontDescriptor, size: fontSize) ?? NSFont.systemFont(ofSize: fontSize)
                let iconText = NSAttributedString(string: icon, attributes: [.font: font, .foregroundColor: fgColor, .backgroundColor: bgColor])

                iconField.attributedStringValue = iconText
                iconField.sizeToFit()

                totalWidth += iconField.frame.width
                statusBarView.addSubview(iconField)
            }

            if let textContent = textContent {
                let textFontConfig = module.textFont ?? config.global.textFont!
                let fontName = textFontConfig.name
                let fontSize = textFontConfig.size
                let fontSymbolicTraits = textFontConfig.symbolicTraits

                let fontDescriptor = NSFontDescriptor(name: fontName, size: fontSize).withSymbolicTraits(fontSymbolicTraits)
                let font = NSFont(descriptor: fontDescriptor, size: fontSize) ?? NSFont.systemFont(ofSize: fontSize)
                let text = NSAttributedString(string: textContent, attributes: [.font: font, .foregroundColor: fgColor, .backgroundColor: bgColor])

                textField.attributedStringValue = text
                textField.sizeToFit()

                totalWidth += (module.icon != nil ? iconTextSpacing : 0) + textField.frame.width
                statusBarView.addSubview(textField)
            }

            switch module.alignment {
            case "left":
                if let _ = module.icon {
                    iconField.frame.origin = CGPoint(x: leftOffset, y: (statusBarView.frame.height - iconField.frame.height) / 2)
                    leftOffset += iconField.frame.width
                }

                if let _ = textContent {
                    if let _ = module.icon {
                        leftOffset += iconTextSpacing
                    }
                    textField.frame.origin = CGPoint(x: leftOffset, y: (statusBarView.frame.height - textField.frame.height) / 2)
                    leftOffset += textField.frame.width + padding
                }
            case "right":
                if let _ = textContent {
                    textField.frame.origin = CGPoint(x: barWidth - rightOffset - textField.frame.width, y: (statusBarView.frame.height - textField.frame.height) / 2)
                    rightOffset += textField.frame.width
                }

                if let _ = module.icon {
                    if let _ = textContent {
                        rightOffset += iconTextSpacing
                    }
                    iconField.frame.origin = CGPoint(x: barWidth - rightOffset - iconField.frame.width, y: (statusBarView.frame.height - iconField.frame.height) / 2)
                    rightOffset += iconField.frame.width + padding
                }
            case "centre":
                let startingCenterOffset = (barWidth - totalWidth) / 2

                if let _ = module.icon {
                    iconField.frame.origin = CGPoint(x: startingCenterOffset + centerOffset, y: (statusBarView.frame.height - iconField.frame.height) / 2)
                    centerOffset += iconField.frame.width
                }

                if let _ = textContent {
                    if let _ = module.icon {
                        centerOffset += iconTextSpacing
                    }
                    textField.frame.origin = CGPoint(x: startingCenterOffset + centerOffset, y: (statusBarView.frame.height - textField.frame.height) / 2)
                }
            default:
                print("Invalid alignment")
                return
            }
        }
    }

    func getCurrentAppearance() -> String {
        let appearance = NSApp.effectiveAppearance
        if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
            return "dark"
        } else {
            return "light"
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

    override init() {
        super.init()
        NSApp.addObserver(self, forKeyPath: #keyPath(NSApplication.effectiveAppearance), options: [.new], context: nil)
    }

    deinit {
        NSApp.removeObserver(self, forKeyPath: #keyPath(NSApplication.effectiveAppearance))
    }
    
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        if keyPath == #keyPath(NSApplication.effectiveAppearance) {
            redrawBar()
        }
    }
    
    func redrawBar() {
        // Remove all subviews from the statusBarView
        statusBarView.subviews.forEach { $0.removeFromSuperview() }

        // Update the bar background color based on the current appearance
        let appearance = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) ?? .aqua
        let barBgColor = appearance == .aqua ? NSColor(hex: config!.global.colour.light.bg) : NSColor(hex: config!.global.colour.dark.bg)
        statusBarView.layer?.backgroundColor = barBgColor.cgColor

        // Call the drawModules function
        drawModules(config: config!, barWidth: statusBarView.frame.width)
    }

    
    func applicationWillTerminate(_ aNotification: Notification) {
        // Insert code here to tear down your application
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
