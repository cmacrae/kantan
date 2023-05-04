import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var statusBarView: NSView!
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        let screenSize = NSScreen.main!.frame.size
        let statusBarHeight: CGFloat = 26
        let statusBarWidth = screenSize.width
        
        let statusBarRect = NSRect(x: 0, y: screenSize.height - statusBarHeight, width: statusBarWidth, height: statusBarHeight)
        window = NSWindow(contentRect: statusBarRect, styleMask: [.borderless], backing: .buffered, defer: false)
        
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)))
        window.collectionBehavior = .canJoinAllSpaces
        window.isOpaque = false
        window.hasShadow = false
        window.backgroundColor = NSColor.clear
        window.ignoresMouseEvents = true
        
        statusBarView = NSView(frame: statusBarRect)
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
