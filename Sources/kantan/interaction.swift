import AppKit
import SwiftUI

// MARK: - Menu Item Descriptor

/// A universal descriptor for menu items, used by both native NSMenu and
/// themed menu panels. Modules provide these; PopupManager renders them
/// according to the active appearance style.
struct MenuItemDescriptor {
    let label: String?
    let icon: NSView?
    let isSeparator: Bool
    let isHeader: Bool
    let action: (() -> Void)?

    static func item(_ label: String, action: @escaping () -> Void) -> MenuItemDescriptor {
        MenuItemDescriptor(label: label, icon: nil, isSeparator: false, isHeader: false, action: action)
    }

    static func item(_ label: String, icon: NSView, action: @escaping () -> Void) -> MenuItemDescriptor {
        MenuItemDescriptor(label: label, icon: icon, isSeparator: false, isHeader: false, action: action)
    }

    static func header(_ label: String) -> MenuItemDescriptor {
        MenuItemDescriptor(label: label, icon: nil, isSeparator: false, isHeader: true, action: nil)
    }

    static func separator() -> MenuItemDescriptor {
        MenuItemDescriptor(label: nil, icon: nil, isSeparator: true, isHeader: false, action: nil)
    }
}

// MARK: - Popup Panel

/// An NSPanel subclass that can become key without activating the app.
/// Uses `windowDidResignKey` for natural click-outside dismiss, following
/// the standard macOS floating panel pattern (like Spotlight, palette windows).
class PopupPanel: NSPanel, NSWindowDelegate {
    var onResignKey: (() -> Void)?

    override var canBecomeKey: Bool { true }

    override init(
        contentRect: NSRect,
        styleMask style: NSWindow.StyleMask,
        backing bufferingType: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        super.init(contentRect: contentRect, styleMask: style, backing: bufferingType, defer: flag)
        self.delegate = self
    }

    func windowDidResignKey(_ notification: Notification) {
        onResignKey?()
    }
}

// MARK: - Popup Manager

/// Centralised manager for all tooltips, menus, and popups.
/// Renders using either native system controls or kantan-themed panels,
/// controlled by the `appearance` property.
@MainActor
class PopupManager {
    private var activePanel: NSPanel?
    private var activePopupId: String?
    private var tooltipPanel: NSPanel?
    var fgColor: NSColor = .labelColor
    var bgColor: NSColor = .windowBackgroundColor
    var appearance: AppearanceStyle = .theme
    weak var barWindow: NSWindow?

    var effectiveFgColor: NSColor {
        appearance == .native ? .labelColor : fgColor
    }

    var effectiveBgColor: NSColor {
        appearance == .native ? .windowBackgroundColor : bgColor
    }

    var isPopupActive: Bool {
        return activePanel != nil
    }

    // MARK: - Coordinate Conversion

    /// Convert a point from SwiftUI .global coordinate space (window-local,
    /// Y-down from top-left) to macOS screen coordinates (Y-up from bottom-left).
    func screenPoint(from swiftUIPoint: NSPoint) -> NSPoint {
        guard let windowFrame = barWindow?.frame else { return swiftUIPoint }
        return NSPoint(
            x: windowFrame.origin.x + swiftUIPoint.x,
            y: windowFrame.origin.y + windowFrame.height - swiftUIPoint.y
        )
    }

    // MARK: - Screen Clamping

    private func clampToScreen(_ rect: NSRect) -> NSRect {
        guard let screen = NSScreen.main?.visibleFrame else { return rect }
        var clamped = rect
        if clamped.maxX > screen.maxX {
            clamped.origin.x = screen.maxX - clamped.width
        }
        if clamped.origin.x < screen.minX {
            clamped.origin.x = screen.minX
        }
        if clamped.origin.y < screen.minY {
            clamped.origin.y = screen.minY
        }
        if clamped.maxY > screen.maxY {
            clamped.origin.y = screen.maxY - clamped.height
        }
        return clamped
    }

    // MARK: - Tooltip

    func showTooltip(text: String, anchorPoint: NSPoint) {
        guard !isPopupActive else { return }
        hideTooltip()

        switch appearance {
        case .native:
            showNativeTooltip(text: text, anchorPoint: anchorPoint)
        case .theme:
            showThemedTooltip(text: text, anchorPoint: anchorPoint)
        }
    }

    private func showNativeTooltip(text: String, anchorPoint: NSPoint) {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: 11)
        label.textColor = .labelColor
        label.backgroundColor = .clear
        label.isBezeled = false
        label.isEditable = false
        label.sizeToFit()

        let padding: CGFloat = 8
        let panelWidth = label.frame.width + padding * 2
        let panelHeight = label.frame.height + padding * 2

        var panelRect = NSRect(
            x: anchorPoint.x - panelWidth / 2,
            y: anchorPoint.y - panelHeight - 4,
            width: panelWidth,
            height: panelHeight
        )
        panelRect = clampToScreen(panelRect)

        let panel = makeNonActivatingPanel(rect: panelRect)
        panel.ignoresMouseEvents = true

        let effect = NSVisualEffectView(frame: NSRect(origin: .zero, size: panelRect.size))
        effect.material = .toolTip
        effect.state = .active
        effect.blendingMode = .behindWindow
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 6
        effect.layer?.masksToBounds = true

        label.frame.origin = NSPoint(x: padding, y: padding)
        effect.addSubview(label)

        panel.contentView = effect
        panel.orderFrontRegardless()
        tooltipPanel = panel
    }

    private func showThemedTooltip(text: String, anchorPoint: NSPoint) {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: 11)
        label.textColor = fgColor
        label.backgroundColor = .clear
        label.isBezeled = false
        label.isEditable = false
        label.sizeToFit()

        let padding: CGFloat = 8
        let panelWidth = label.frame.width + padding * 2
        let panelHeight = label.frame.height + padding * 2

        var panelRect = NSRect(
            x: anchorPoint.x - panelWidth / 2,
            y: anchorPoint.y - panelHeight - 4,
            width: panelWidth,
            height: panelHeight
        )
        panelRect = clampToScreen(panelRect)

        let panel = makeNonActivatingPanel(rect: panelRect)
        panel.ignoresMouseEvents = true

        let container = NSView(frame: NSRect(origin: .zero, size: panelRect.size))
        container.wantsLayer = true
        container.layer?.cornerRadius = 6
        container.layer?.masksToBounds = true
        container.layer?.backgroundColor = bgColor.cgColor

        label.frame.origin = NSPoint(x: padding, y: padding)
        container.addSubview(label)

        panel.contentView = container
        panel.orderFrontRegardless()
        tooltipPanel = panel
    }

    func hideTooltip() {
        tooltipPanel?.orderOut(nil)
        tooltipPanel = nil
    }

    // MARK: - Menu

    func showMenu(descriptors: [MenuItemDescriptor], moduleName: String, anchorPoint: NSPoint, positioningView: NSView? = nil) {
        guard !descriptors.isEmpty else { return }

        switch appearance {
        case .native:
            showNativeMenu(descriptors: descriptors, anchorPoint: anchorPoint)
        case .theme:
            showThemedMenu(descriptors: descriptors, moduleName: moduleName, anchorPoint: anchorPoint)
        }
    }

    private func showNativeMenu(descriptors: [MenuItemDescriptor], anchorPoint: NSPoint) {
        let menu = NSMenu()
        let actionTarget = NativeMenuActionTarget()
        objc_setAssociatedObject(menu, "actionTarget", actionTarget, .OBJC_ASSOCIATION_RETAIN)

        for descriptor in descriptors {
            if descriptor.isSeparator {
                menu.addItem(NSMenuItem.separator())
            } else if descriptor.isHeader {
                let item = NSMenuItem(title: descriptor.label ?? "", action: nil, keyEquivalent: "")
                item.isEnabled = false
                menu.addItem(item)
            } else if let label = descriptor.label {
                let item = NSMenuItem(title: label, action: #selector(NativeMenuActionTarget.menuItemClicked(_:)), keyEquivalent: "")
                item.target = actionTarget
                item.representedObject = descriptor.action
                menu.addItem(item)
            }
        }

        menu.popUp(positioning: nil, at: anchorPoint, in: nil)
    }

    private func showThemedMenu(descriptors: [MenuItemDescriptor], moduleName: String, anchorPoint: NSPoint) {
        let menuId = "\(moduleName):menu"

        if menuId == activePopupId, activePanel != nil {
            dismissPopup()
            return
        }

        dismissPopup()

        let fg = Color(nsColor: fgColor)
        let bg = Color(nsColor: bgColor)

        let menuView = SwiftUIThemedMenuView(descriptors: descriptors, fgColor: fg, bgColor: bg) { [weak self] in
            self?.dismissPopup()
        }

        let hostingView = NSHostingView(rootView: menuView)
        let fittingSize = hostingView.fittingSize
        let panelWidth = max(fittingSize.width, 160)
        let panelHeight = max(fittingSize.height, 20)

        var panelRect = NSRect(
            x: anchorPoint.x - panelWidth / 2,
            y: anchorPoint.y - panelHeight - 4,
            width: panelWidth,
            height: panelHeight
        )
        panelRect = clampToScreen(panelRect)

        let panel = makePopupPanel(rect: panelRect)

        let container = makePopupContainer(size: panelRect.size)
        hostingView.frame = container.bounds
        hostingView.autoresizingMask = [.width, .height]
        container.addSubview(hostingView)

        panel.contentView = container
        panel.makeKeyAndOrderFront(nil)

        activePanel = panel
        activePopupId = menuId
    }

    // MARK: - Popup

    func togglePopup(name: String, moduleName: String, anchorPoint: NSPoint, positioningView: NSView? = nil) {
        let popupId = "\(moduleName):\(name)"

        if popupId == activePopupId, activePanel != nil {
            dismissPopup()
            return
        }

        dismissPopup()

        let fg = Color(nsColor: effectiveFgColor)
        let bg = Color(nsColor: effectiveBgColor)

        guard let popupView = createSwiftUIPopup(name: name, fgColor: fg, bgColor: bg) else { return }

        let hostingView = NSHostingView(rootView: popupView)
        let fittingSize = hostingView.fittingSize
        let panelWidth = max(fittingSize.width, 200)
        let panelHeight = max(fittingSize.height, 100)

        var panelRect = NSRect(
            x: anchorPoint.x - panelWidth / 2,
            y: anchorPoint.y - panelHeight - 4,
            width: panelWidth,
            height: panelHeight
        )
        panelRect = clampToScreen(panelRect)

        let panel = makePopupPanel(rect: panelRect)

        let container = makePopupContainer(size: panelRect.size)
        hostingView.frame = container.bounds
        hostingView.autoresizingMask = [.width, .height]
        container.addSubview(hostingView)

        panel.contentView = container
        panel.makeKeyAndOrderFront(nil)

        activePanel = panel
        activePopupId = popupId
    }

    func dismissPopup() {
        activePanel?.orderOut(nil)
        activePanel = nil
        activePopupId = nil
    }

    // MARK: - Panel Factories

    private func makeNonActivatingPanel(rect: NSRect) -> NSPanel {
        let panel = NSPanel(
            contentRect: rect,
            styleMask: [.nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.hasShadow = true
        panel.backgroundColor = .clear
        panel.isMovable = false
        panel.collectionBehavior = [.canJoinAllSpaces, .transient]
        return panel
    }

    private func makePopupPanel(rect: NSRect) -> PopupPanel {
        let panel = PopupPanel(
            contentRect: rect,
            styleMask: [.nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.hasShadow = true
        panel.backgroundColor = .clear
        panel.isMovable = false
        panel.collectionBehavior = [.canJoinAllSpaces, .transient]
        panel.onResignKey = { [weak self] in
            self?.dismissPopup()
        }
        return panel
    }

    private func makePopupContainer(size: NSSize) -> NSView {
        switch appearance {
        case .native:
            let effect = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
            effect.material = .menu
            effect.state = .active
            effect.blendingMode = .behindWindow
            effect.wantsLayer = true
            effect.layer?.cornerRadius = 10
            effect.layer?.masksToBounds = true
            return effect
        case .theme:
            let container = NSView(frame: NSRect(origin: .zero, size: size))
            container.wantsLayer = true
            container.layer?.cornerRadius = 10
            container.layer?.masksToBounds = true
            container.layer?.backgroundColor = bgColor.cgColor
            return container
        }
    }

    // MARK: - SwiftUI Popup Content

    private func createSwiftUIPopup(name: String, fgColor: Color, bgColor: Color) -> AnyView? {
        switch name {
        case "battery-detail":
            return AnyView(BatteryPopupView(fgColor: fgColor, bgColor: bgColor))
        case "volume-detail":
            return AnyView(VolumePopupView(fgColor: fgColor, bgColor: bgColor))
        case "wifi-detail":
            return AnyView(WiFiPopupView(fgColor: fgColor, bgColor: bgColor))
        case "calendar":
            return AnyView(CalendarPopupView(fgColor: fgColor, bgColor: bgColor))
        default:
            return nil
        }
    }
}

// MARK: - Native Menu Action Target

class NativeMenuActionTarget: NSObject {
    @objc func menuItemClicked(_ sender: NSMenuItem) {
        guard let action = sender.representedObject as? (() -> Void) else { return }
        action()
    }
}
