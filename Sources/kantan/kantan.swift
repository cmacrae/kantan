import AppKit
import Yaml

class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var statusBarView: NSView!
    var config: Config?
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        if let fileData = loadFileContents(filePath: "config.yaml") {
            do {
                let yaml = try Yaml.load(fileData)
                config = loadConfig(from: yaml)
                // Work with the config object here
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
        
        let statusBarColor = NSColor(hex: config.global.colour.bg)

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

        for module in config.modules {
            let fgColor = (module.colour?.fg).flatMap { NSColor(hex: String($0)) } ?? NSColor(hex: config.global.colour.fg)
            let bgColor = (module.colour?.bg).flatMap { NSColor(hex: String($0)) } ?? NSColor(hex: config.global.colour.bg)



            if let icon = module.icon {
                let iconText = NSTextField(labelWithString: icon)
                iconText.sizeToFit()

                switch module.alignment {
                case "left":
                    iconText.frame.origin = CGPoint(x: leftOffset, y: (statusBarView.frame.height - iconText.frame.height) / 2)
                    leftOffset += iconText.frame.width + (module.text != nil ? iconTextSpacing : padding)
                case "right":
                    iconText.frame.origin = CGPoint(x: barWidth - rightOffset - iconText.frame.width, y: (statusBarView.frame.height - iconText.frame.height) / 2)
                    rightOffset += iconText.frame.width + (module.text != nil ? iconTextSpacing : padding)
                case "centre":
                    iconText.frame.origin = CGPoint(x: (barWidth - iconText.frame.width) / 2 + centerOffset, y: (statusBarView.frame.height - iconText.frame.height) / 2)
                    centerOffset += iconText.frame.width + (module.text != nil ? iconTextSpacing : 0)
                default:
                    print("Invalid alignment")
                    return
                }

                iconText.textColor = fgColor
                iconText.backgroundColor = bgColor
                statusBarView.addSubview(iconText)
            }

            if let textContent = module.text {
                let text = NSTextField(labelWithString: textContent)
                text.sizeToFit()

                switch module.alignment {
                case "left":
                    text.frame.origin = CGPoint(x: leftOffset, y: (statusBarView.frame.height - text.frame.height) / 2)
                    leftOffset += text.frame.width + padding
                case "right":
                    text.frame.origin = CGPoint(x: barWidth - rightOffset - text.frame.width, y: (statusBarView.frame.height - text.frame.height) / 2)
                    rightOffset += text.frame.width + padding
                case "centre":
                    text.frame.origin = CGPoint(x: (barWidth - text.frame.width) / 2 + centerOffset, y: (statusBarView.frame.height - text.frame.height) / 2)
                    centerOffset += text.frame.width
                default:
                    print("Invalid alignment")
                    return
                }

                text.textColor = fgColor
                text.backgroundColor = bgColor
                statusBarView.addSubview(text)
            }
        }
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
