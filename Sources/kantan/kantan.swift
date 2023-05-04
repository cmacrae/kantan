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
        
        // print("Screen height: \(screenSize.height)") // NOTE: debugging
        // print("Config height: \(config.global.height)") // NOTE: debugging

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
        
        let leftText = "Left"
        let centerText = "Center"
        let rightText = "Right"
        let padding: CGFloat = 10
        
        addTextToStatusBar(text: leftText, xPosition: padding)
        addTextToStatusBar(text: centerText, xPosition: (statusBarWidth / 2) - (padding / 2))
        addTextToStatusBar(text: rightText, xPosition: statusBarWidth - padding, alignment: .right)
        
        window.makeKeyAndOrderFront(nil)
    }
    
    func addTextToStatusBar(text: String, xPosition: CGFloat, alignment: NSTextAlignment = .left) {
        let textField = NSTextField(labelWithString: text)
        textField.alignment = alignment
        textField.sizeToFit()
        textField.frame.origin.x = xPosition
        textField.frame.origin.y = (statusBarView.frame.height - textField.frame.height) / 2
        statusBarView.addSubview(textField)
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
