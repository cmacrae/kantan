import AppKit
import IOKit.ps

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

// MARK: - Status Bar View

/// Custom NSView for the status bar that only responds to mouse events
/// on InteractiveModuleView children. All other areas pass events through
/// to the windows below, preserving tiling WM interaction.
class StatusBarContainerView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        for subview in subviews.reversed() {
            if let interactive = subview as? InteractiveModuleView {
                let localPoint = interactive.convert(point, from: self)
                if interactive.bounds.contains(localPoint) {
                    return interactive
                }
            }
        }
        return nil
    }
}

// MARK: - Interactive Module View

/// A transparent hit-test view placed over module subviews to capture
/// hover and click events. Delegates all rendering of tooltips, menus,
/// and popups to PopupManager.
class InteractiveModuleView: NSView {
    let moduleName: String
    var interaction: InteractionConfig?
    var templateVariableProvider: (() -> [String: String])?
    var currentValue: (() -> String?)?
    var currentIcon: (() -> String?)?
    /// Provides menu item descriptors for dynamic menus (e.g. bluetooth).
    var dynamicMenuProvider: (() -> [MenuItemDescriptor])?
    private var trackingArea: NSTrackingArea?
    weak var popupManager: PopupManager?

    init(frame: NSRect, moduleName: String) {
        self.moduleName = moduleName
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        guard let hover = interaction?.hover, hover.type == "tooltip" else { return }
        guard popupManager?.isPopupActive != true else { return }
        let resolved = resolveTemplate(hover.content)
        let locationInWindow = convert(NSPoint(x: bounds.midX, y: 0), to: nil)
        guard let screenPoint = window?.convertPoint(toScreen: locationInWindow) else { return }
        popupManager?.showTooltip(text: resolved, anchorPoint: screenPoint)
    }

    override func mouseExited(with event: NSEvent) {
        popupManager?.hideTooltip()
    }

    override func mouseDown(with event: NSEvent) {
        popupManager?.hideTooltip()

        guard let click = interaction?.click else { return }
        let locationInWindow = convert(NSPoint(x: bounds.midX, y: 0), to: nil)
        guard let screenPoint = window?.convertPoint(toScreen: locationInWindow) else { return }

        switch click.type {
        case "menu":
            let descriptors = Self.descriptorsFromConfig(click)
            popupManager?.showMenu(descriptors: descriptors, moduleName: moduleName, anchorPoint: screenPoint)
        case "dynamic-menu":
            guard let descriptors = dynamicMenuProvider?() else { return }
            popupManager?.showMenu(descriptors: descriptors, moduleName: moduleName, anchorPoint: screenPoint)
        case "popup":
            guard let popupName = click.popup else { return }
            popupManager?.togglePopup(name: popupName, moduleName: moduleName, anchorPoint: screenPoint)
        default:
            break
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let localPoint = convert(point, from: superview)
        if bounds.contains(localPoint) {
            return self
        }
        return nil
    }

    // MARK: - Template Resolution

    func resolveTemplate(_ template: String) -> String {
        var result = template

        if let value = currentValue?() {
            result = result.replacingOccurrences(of: "{value}", with: value)
        }
        if let icon = currentIcon?() {
            result = result.replacingOccurrences(of: "{icon}", with: icon)
        }

        if let vars = templateVariableProvider?() {
            for (key, val) in vars {
                result = result.replacingOccurrences(of: "{\(key)}", with: val)
            }
        }

        return result
    }

    /// Convert a ClickConfig's static menu items into MenuItemDescriptors.
    static func descriptorsFromConfig(_ config: ClickConfig) -> [MenuItemDescriptor] {
        guard let items = config.items else { return [] }
        return items.map { item in
            if item.separator == true {
                return .separator()
            }
            guard let label = item.label else { return .separator() }
            let command = item.command
            return .item(label) {
                guard let command = command, !command.isEmpty else { return }
                DispatchQueue.global(qos: .userInitiated).async {
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: "/bin/sh")
                    process.arguments = ["-c", command]
                    process.standardOutput = Pipe()
                    process.standardError = Pipe()
                    try? process.run()
                }
            }
        }
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
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var tooltipPanel: NSPanel?
    var fgColor: NSColor = .labelColor
    var bgColor: NSColor = .windowBackgroundColor
    var appearance: AppearanceStyle = .theme

    var isPopupActive: Bool {
        return activePanel != nil
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
        // Native tooltip: system-styled panel
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

        let container = NSView(frame: NSRect(origin: .zero, size: panelRect.size))
        container.wantsLayer = true
        container.layer?.cornerRadius = 6
        container.layer?.masksToBounds = true
        container.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        label.frame.origin = NSPoint(x: padding, y: padding)
        container.addSubview(label)

        panel.contentView = container
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

    /// Show a menu from an array of MenuItemDescriptors.
    /// Renders as native NSMenu or themed panel based on appearance.
    func showMenu(descriptors: [MenuItemDescriptor], moduleName: String, anchorPoint: NSPoint) {
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
        // Hold a reference so ARC doesn't release the target while the menu is open
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

        let menuView = ThemedMenuView(descriptors: descriptors, fgColor: fgColor, bgColor: bgColor) { [weak self] in
            self?.dismissPopup()
        }

        menuView.layoutSubtreeIfNeeded()
        let contentSize = menuView.fittingSize
        let panelWidth = max(contentSize.width, 160)
        let panelHeight = max(contentSize.height, 20)

        var panelRect = NSRect(
            x: anchorPoint.x - panelWidth / 2,
            y: anchorPoint.y - panelHeight - 4,
            width: panelWidth,
            height: panelHeight
        )
        panelRect = clampToScreen(panelRect)

        let panel = makePopupPanel(rect: panelRect)

        let container = NSView(frame: NSRect(origin: .zero, size: panelRect.size))
        container.wantsLayer = true
        container.layer?.cornerRadius = 10
        container.layer?.masksToBounds = true
        container.layer?.backgroundColor = bgColor.cgColor

        menuView.frame = container.bounds
        menuView.autoresizingMask = [.width, .height]
        container.addSubview(menuView)

        panel.contentView = container
        panel.orderFrontRegardless()

        activePanel = panel
        activePopupId = menuId

        installDismissMonitors()
    }

    // MARK: - Popup

    func togglePopup(name: String, moduleName: String, anchorPoint: NSPoint) {
        let popupId = "\(moduleName):\(name)"

        if popupId == activePopupId, activePanel != nil {
            dismissPopup()
            return
        }

        dismissPopup()

        guard let contentView = createPopupContent(name: name, fgColor: fgColor, bgColor: bgColor) else { return }

        contentView.layoutSubtreeIfNeeded()
        let contentSize = contentView.fittingSize
        let panelWidth = max(contentSize.width, 200)
        let panelHeight = max(contentSize.height, 100)

        var panelRect = NSRect(
            x: anchorPoint.x - panelWidth / 2,
            y: anchorPoint.y - panelHeight - 4,
            width: panelWidth,
            height: panelHeight
        )
        panelRect = clampToScreen(panelRect)

        let panel = makePopupPanel(rect: panelRect)

        let container = NSView(frame: NSRect(origin: .zero, size: panelRect.size))
        container.wantsLayer = true
        container.layer?.cornerRadius = 10
        container.layer?.masksToBounds = true
        container.layer?.backgroundColor = bgColor.cgColor

        contentView.frame = container.bounds
        contentView.autoresizingMask = [.width, .height]
        container.addSubview(contentView)

        panel.contentView = container
        panel.orderFrontRegardless()

        activePanel = panel
        activePopupId = popupId

        installDismissMonitors()
    }

    func dismissPopup() {
        activePanel?.orderOut(nil)
        activePanel = nil
        activePopupId = nil

        if let local = localMonitor {
            NSEvent.removeMonitor(local)
            localMonitor = nil
        }
        if let global = globalMonitor {
            NSEvent.removeMonitor(global)
            globalMonitor = nil
        }
    }

    // MARK: - Panel Factories

    /// Creates a non-activating floating panel (for tooltips).
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

    /// Creates a popup/menu panel (non-activating, titled for full-size content).
    private func makePopupPanel(rect: NSRect) -> NSPanel {
        let panel = NSPanel(
            contentRect: rect,
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.hasShadow = true
        panel.backgroundColor = .clear
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovable = false
        panel.collectionBehavior = [.canJoinAllSpaces, .transient]
        return panel
    }

    /// Installs local + global click monitors that dismiss the active panel.
    private func installDismissMonitors() {
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self = self, let panel = self.activePanel else { return event }
            if event.window === panel { return event }

            if let hitView = event.window?.contentView?.hitTest(event.locationInWindow),
               hitView is InteractiveModuleView {
                return event
            }

            self.dismissPopup()
            return event
        }

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.dismissPopup()
        }
    }

    // MARK: - Built-in Popup Content

    private func createPopupContent(name: String, fgColor: NSColor, bgColor: NSColor) -> NSView? {
        switch name {
        case "calendar":
            return CalendarPopupView(fgColor: fgColor, bgColor: bgColor)
        case "battery-detail":
            return BatteryDetailPopupView(fgColor: fgColor, bgColor: bgColor)
        case "volume-detail":
            return VolumeDetailPopupView(fgColor: fgColor, bgColor: bgColor)
        case "wifi-detail":
            return WiFiDetailPopupView(fgColor: fgColor, bgColor: bgColor)
        default:
            return nil
        }
    }
}

// MARK: - Native Menu Action Target

/// Action target for native NSMenu items. Holds closures keyed to each item.
class NativeMenuActionTarget: NSObject {
    @objc func menuItemClicked(_ sender: NSMenuItem) {
        guard let action = sender.representedObject as? (() -> Void) else { return }
        action()
    }
}

// MARK: - Themed Menu View

/// A kantan-themed menu rendered as an NSView inside a non-activating panel.
/// Matches the visual style of existing popups (calendar, battery-detail, etc).
class ThemedMenuView: NSView {
    private let padding: CGFloat = 8
    private let itemHeight: CGFloat = 28
    private let headerHeight: CGFloat = 22
    private let separatorHeight: CGFloat = 9
    private let fgColor: NSColor
    private let bgColor: NSColor
    private let dismissHandler: () -> Void

    init(descriptors: [MenuItemDescriptor], fgColor: NSColor, bgColor: NSColor, dismissHandler: @escaping () -> Void) {
        self.fgColor = fgColor
        self.bgColor = bgColor
        self.dismissHandler = dismissHandler
        super.init(frame: .zero)
        buildMenu(descriptors)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func buildMenu(_ descriptors: [MenuItemDescriptor]) {
        let contentWidth: CGFloat = 220
        var yOffset: CGFloat = padding

        // Layout items bottom-to-top (AppKit coordinate system)
        // First, calculate total height
        var totalHeight: CGFloat = padding * 2
        for descriptor in descriptors {
            if descriptor.isSeparator {
                totalHeight += separatorHeight
            } else if descriptor.isHeader {
                totalHeight += headerHeight
            } else {
                totalHeight += itemHeight
            }
        }

        frame = NSRect(x: 0, y: 0, width: contentWidth, height: totalHeight)

        // Now lay out from top (highest y) down
        var y = totalHeight - padding

        for descriptor in descriptors {
            if descriptor.isSeparator {
                y -= separatorHeight
                let separator = NSView(frame: NSRect(x: padding, y: y + (separatorHeight - 1) / 2, width: contentWidth - padding * 2, height: 1))
                separator.wantsLayer = true
                separator.layer?.backgroundColor = fgColor.withAlphaComponent(0.15).cgColor
                addSubview(separator)
            } else if descriptor.isHeader {
                y -= headerHeight
                let label = NSTextField(labelWithString: descriptor.label ?? "")
                label.font = NSFont.systemFont(ofSize: 11, weight: .medium)
                label.textColor = fgColor.withAlphaComponent(0.5)
                label.frame = NSRect(x: padding + 8, y: y, width: contentWidth - padding * 2 - 8, height: headerHeight)
                addSubview(label)
            } else {
                y -= itemHeight
                let itemView = ThemedMenuItemView(
                    frame: NSRect(x: 0, y: y, width: contentWidth, height: itemHeight),
                    label: descriptor.label ?? "",
                    icon: descriptor.icon,
                    fgColor: fgColor,
                    bgColor: bgColor,
                    action: { [weak self] in
                        self?.dismissHandler()
                        descriptor.action?()
                    }
                )
                addSubview(itemView)
            }
        }
    }

    override var fittingSize: NSSize {
        return frame.size
    }
}

// MARK: - Themed Menu Item View

/// A single row in a ThemedMenuView. Highlights on hover, fires action on click.
class ThemedMenuItemView: NSView {
    private let label: NSTextField
    private let iconView: NSView?
    private let fgColor: NSColor
    private let bgColor: NSColor
    private let action: () -> Void
    private var trackingArea: NSTrackingArea?

    init(frame: NSRect, label: String, icon: NSView?, fgColor: NSColor, bgColor: NSColor, action: @escaping () -> Void) {
        self.fgColor = fgColor
        self.bgColor = bgColor
        self.action = action

        let horizontalPad: CGFloat = 16
        let iconSpace: CGFloat = icon != nil ? 24 : 0

        self.label = NSTextField(labelWithString: label)
        self.label.font = NSFont.systemFont(ofSize: 13)
        self.label.textColor = fgColor
        self.label.sizeToFit()
        self.label.frame.origin = NSPoint(x: horizontalPad + iconSpace, y: (frame.height - self.label.frame.height) / 2)

        self.iconView = icon

        super.init(frame: frame)

        wantsLayer = true
        layer?.cornerRadius = 4

        if let icon = icon {
            icon.frame.origin = NSPoint(x: horizontalPad, y: (frame.height - icon.frame.height) / 2)
            addSubview(icon)
        }
        addSubview(self.label)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        layer?.backgroundColor = fgColor.withAlphaComponent(0.1).cgColor
    }

    override func mouseExited(with event: NSEvent) {
        layer?.backgroundColor = nil
    }

    override func mouseUp(with event: NSEvent) {
        action()
    }
}

// MARK: - Calendar Popup View

class CalendarPopupView: NSView {
    private let calendar = Calendar.current
    private let padding: CGFloat = 16
    private let cellSize: CGFloat = 28
    private let headerHeight: CGFloat = 30
    private let fgColor: NSColor
    private let bgColor: NSColor

    init(fgColor: NSColor, bgColor: NSColor) {
        self.fgColor = fgColor
        self.bgColor = bgColor
        super.init(frame: .zero)
        setupView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupView() {
        let now = Date()
        let today = calendar.component(.day, from: now)
        let dimColor = fgColor.withAlphaComponent(0.5)

        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        let title = formatter.string(from: now)

        // Calculate grid
        guard let range = calendar.range(of: .day, in: .month, for: now),
              let firstOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) else {
            return
        }
        let startWeekday = calendar.component(.weekday, from: firstOfMonth)
        let blanks = (startWeekday - calendar.firstWeekday + 7) % 7
        let totalDays = range.count
        let totalCells = blanks + totalDays
        let rows = (totalCells + 6) / 7

        let gridWidth = cellSize * 7
        let totalWidth = gridWidth + padding * 2
        let weekdayHeaderHeight: CGFloat = 20
        let totalHeight = headerHeight + weekdayHeaderHeight + CGFloat(rows) * cellSize + padding * 2

        frame = NSRect(x: 0, y: 0, width: totalWidth, height: totalHeight)

        // Month/Year header
        let headerLabel = NSTextField(labelWithString: title)
        headerLabel.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        headerLabel.textColor = fgColor
        headerLabel.alignment = .center
        headerLabel.frame = NSRect(x: padding, y: totalHeight - padding - headerHeight, width: gridWidth, height: headerHeight)
        addSubview(headerLabel)

        // Weekday headers
        let weekdays = calendar.veryShortWeekdaySymbols
        let firstIdx = calendar.firstWeekday - 1
        let reordered = Array(weekdays[firstIdx...]) + Array(weekdays[..<firstIdx])
        for (i, symbol) in reordered.enumerated() {
            let label = NSTextField(labelWithString: symbol)
            label.font = NSFont.systemFont(ofSize: 10, weight: .medium)
            label.textColor = dimColor
            label.alignment = .center
            label.frame = NSRect(
                x: padding + CGFloat(i) * cellSize,
                y: totalHeight - padding - headerHeight - weekdayHeaderHeight,
                width: cellSize,
                height: weekdayHeaderHeight
            )
            addSubview(label)
        }

        // Day grid
        let gridTop = totalHeight - padding - headerHeight - weekdayHeaderHeight
        for cellIndex in 0..<totalCells {
            let dayNumber = cellIndex - blanks + 1
            guard dayNumber >= 1 && dayNumber <= totalDays else { continue }

            let col = cellIndex % 7
            let row = cellIndex / 7

            let x = padding + CGFloat(col) * cellSize
            let y = gridTop - CGFloat(row + 1) * cellSize

            let isToday = dayNumber == today

            let label = NSTextField(labelWithString: "\(dayNumber)")
            label.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: isToday ? .bold : .regular)
            label.textColor = isToday ? bgColor : fgColor
            label.alignment = .center
            label.sizeToFit()
            let textSize = label.frame.size
            let labelX = x + (cellSize - textSize.width) / 2
            let labelY = y + (cellSize - textSize.height) / 2
            label.frame = NSRect(x: labelX, y: labelY, width: textSize.width, height: textSize.height)

            if isToday {
                let circleDiameter = max(textSize.width, textSize.height) + 6
                let circleX = labelX + (textSize.width - circleDiameter) / 2
                let circleY = labelY + (textSize.height - circleDiameter) / 2
                let circle = NSView(frame: NSRect(x: circleX, y: circleY, width: circleDiameter, height: circleDiameter))
                circle.wantsLayer = true
                circle.layer?.cornerRadius = circleDiameter / 2
                circle.layer?.backgroundColor = fgColor.cgColor
                addSubview(circle)
            }

            addSubview(label)
        }
    }

    override var fittingSize: NSSize {
        return frame.size
    }
}

// MARK: - Battery Detail Popup View

class BatteryDetailPopupView: NSView {
    private let padding: CGFloat = 16
    private let fgColor: NSColor
    private let bgColor: NSColor

    init(fgColor: NSColor, bgColor: NSColor) {
        self.fgColor = fgColor
        self.bgColor = bgColor
        super.init(frame: .zero)
        setupView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupView() {
        let status = readBatteryStatusForPopup()
        let width: CGFloat = 200
        var yOffset: CGFloat = padding
        let dimColor = fgColor.withAlphaComponent(0.5)

        // State label
        let stateText: String
        if status.isCharging {
            stateText = "Charging"
        } else if status.isPluggedIn {
            stateText = "Plugged In"
        } else {
            stateText = "Battery"
        }
        let stateLabel = NSTextField(labelWithString: stateText)
        stateLabel.font = NSFont.systemFont(ofSize: 11)
        stateLabel.textColor = dimColor
        stateLabel.frame = NSRect(x: padding, y: yOffset, width: width - padding * 2, height: 16)
        addSubview(stateLabel)
        yOffset += 20

        // Level label
        let levelStr = status.isAvailable ? "\(status.level)%" : "Unavailable"
        let levelLabel = NSTextField(labelWithString: levelStr)
        levelLabel.font = NSFont.systemFont(ofSize: 24, weight: .semibold)
        levelLabel.textColor = fgColor
        levelLabel.frame = NSRect(x: padding, y: yOffset, width: width - padding * 2, height: 30)
        addSubview(levelLabel)
        yOffset += 38

        // Progress bar
        if status.isAvailable {
            let barBg = NSView(frame: NSRect(x: padding, y: yOffset, width: width - padding * 2, height: 6))
            barBg.wantsLayer = true
            barBg.layer?.cornerRadius = 3
            barBg.layer?.backgroundColor = fgColor.withAlphaComponent(0.2).cgColor
            addSubview(barBg)

            let barWidth = (width - padding * 2) * CGFloat(status.level) / 100.0
            let barFill = NSView(frame: NSRect(x: padding, y: yOffset, width: barWidth, height: 6))
            barFill.wantsLayer = true
            barFill.layer?.cornerRadius = 3
            let barColor: NSColor
            if status.isCharging {
                barColor = .systemGreen
            } else if status.level <= 10 {
                barColor = .systemRed
            } else if status.level <= 20 {
                barColor = .systemYellow
            } else {
                barColor = fgColor
            }
            barFill.layer?.backgroundColor = barColor.cgColor
            addSubview(barFill)
            yOffset += 14
        }

        yOffset += padding
        frame = NSRect(x: 0, y: 0, width: width, height: yOffset)
    }

    override var fittingSize: NSSize {
        return frame.size
    }

    private func readBatteryStatusForPopup() -> (level: Int, isCharging: Bool, isPluggedIn: Bool, isAvailable: Bool) {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFDictionary] else {
            return (0, false, false, false)
        }
        for source in sources {
            guard let sourceDict = source as? [String: Any],
                  let currentCapacity = sourceDict[kIOPSCurrentCapacityKey as String] as? Int,
                  let maxCapacity = sourceDict[kIOPSMaxCapacityKey as String] as? Int,
                  maxCapacity > 0 else { continue }
            let level = (currentCapacity * 100) / maxCapacity
            let isCharging = (sourceDict[kIOPSIsChargingKey as String] as? Bool) ?? false
            let powerSourceState = sourceDict[kIOPSPowerSourceStateKey as String] as? String
            let isPluggedIn = (powerSourceState == kIOPSACPowerValue as String)
            return (level, isCharging, isPluggedIn, true)
        }
        return (0, false, false, false)
    }
}

// MARK: - Volume Detail Popup View

class VolumeDetailPopupView: NSView {
    private let padding: CGFloat = 16
    private let fgColor: NSColor
    private let bgColor: NSColor

    init(fgColor: NSColor, bgColor: NSColor) {
        self.fgColor = fgColor
        self.bgColor = bgColor
        super.init(frame: .zero)
        setupView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupView() {
        let status = VolumeConfig.readVolumeStatus()
        let width: CGFloat = 200
        var yOffset: CGFloat = padding
        let dimColor = fgColor.withAlphaComponent(0.5)

        // State label
        let stateText = status.isMuted ? "Muted" : "Active"
        let stateLabel = NSTextField(labelWithString: stateText)
        stateLabel.font = NSFont.systemFont(ofSize: 11)
        stateLabel.textColor = dimColor
        stateLabel.frame = NSRect(x: padding, y: yOffset, width: width - padding * 2, height: 16)
        addSubview(stateLabel)
        yOffset += 20

        // Level label
        let levelStr = status.isMuted ? "Muted" : "\(status.level)%"
        let levelLabel = NSTextField(labelWithString: levelStr)
        levelLabel.font = NSFont.systemFont(ofSize: 24, weight: .semibold)
        levelLabel.textColor = fgColor
        levelLabel.frame = NSRect(x: padding, y: yOffset, width: width - padding * 2, height: 30)
        addSubview(levelLabel)
        yOffset += 38

        // Volume bar
        let barBg = NSView(frame: NSRect(x: padding, y: yOffset, width: width - padding * 2, height: 6))
        barBg.wantsLayer = true
        barBg.layer?.cornerRadius = 3
        barBg.layer?.backgroundColor = fgColor.withAlphaComponent(0.2).cgColor
        addSubview(barBg)

        if !status.isMuted {
            let barWidth = (width - padding * 2) * CGFloat(status.volume)
            let barFill = NSView(frame: NSRect(x: padding, y: yOffset, width: barWidth, height: 6))
            barFill.wantsLayer = true
            barFill.layer?.cornerRadius = 3
            barFill.layer?.backgroundColor = fgColor.cgColor
            addSubview(barFill)
        }
        yOffset += 14

        yOffset += padding
        frame = NSRect(x: 0, y: 0, width: width, height: yOffset)
    }

    override var fittingSize: NSSize {
        return frame.size
    }
}

// MARK: - WiFi Detail Popup View

class WiFiDetailPopupView: NSView {
    private let padding: CGFloat = 16
    private let fgColor: NSColor
    private let bgColor: NSColor

    init(fgColor: NSColor, bgColor: NSColor) {
        self.fgColor = fgColor
        self.bgColor = bgColor
        super.init(frame: .zero)
        setupView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupView() {
        let status = WiFiConfig.readWiFiStatus()
        let width: CGFloat = 220
        var yOffset: CGFloat = padding
        let dimColor = fgColor.withAlphaComponent(0.5)

        // State label
        let stateText = status.isConnected ? "Connected" : "Disconnected"
        let stateLabel = NSTextField(labelWithString: stateText)
        stateLabel.font = NSFont.systemFont(ofSize: 11)
        stateLabel.textColor = dimColor
        stateLabel.frame = NSRect(x: padding, y: yOffset, width: width - padding * 2, height: 16)
        addSubview(stateLabel)
        yOffset += 20

        // SSID label
        let ssidStr = status.ssid ?? "Not connected"
        let ssidLabel = NSTextField(labelWithString: ssidStr)
        ssidLabel.font = NSFont.systemFont(ofSize: 18, weight: .semibold)
        ssidLabel.textColor = fgColor
        ssidLabel.frame = NSRect(x: padding, y: yOffset, width: width - padding * 2, height: 24)
        addSubview(ssidLabel)
        yOffset += 32

        if status.isConnected {
            // Signal strength bar
            let signalLabel = NSTextField(labelWithString: "Signal")
            signalLabel.font = NSFont.systemFont(ofSize: 11)
            signalLabel.textColor = dimColor
            signalLabel.frame = NSRect(x: padding, y: yOffset, width: 60, height: 16)
            addSubview(signalLabel)
            yOffset += 18

            let barBg = NSView(frame: NSRect(x: padding, y: yOffset, width: width - padding * 2, height: 6))
            barBg.wantsLayer = true
            barBg.layer?.cornerRadius = 3
            barBg.layer?.backgroundColor = fgColor.withAlphaComponent(0.2).cgColor
            addSubview(barBg)

            let barWidth = (width - padding * 2) * CGFloat(status.signalQuality)
            let barFill = NSView(frame: NSRect(x: padding, y: yOffset, width: barWidth, height: 6))
            barFill.wantsLayer = true
            barFill.layer?.cornerRadius = 3
            let barColor: NSColor
            if status.signalQuality >= 0.66 {
                barColor = .systemGreen
            } else if status.signalQuality >= 0.33 {
                barColor = .systemYellow
            } else {
                barColor = .systemRed
            }
            barFill.layer?.backgroundColor = barColor.cgColor
            addSubview(barFill)
            yOffset += 14

            // RSSI detail
            let rssiLabel = NSTextField(labelWithString: "RSSI: \(status.rssi) dBm")
            rssiLabel.font = NSFont.systemFont(ofSize: 11)
            rssiLabel.textColor = dimColor
            rssiLabel.frame = NSRect(x: padding, y: yOffset, width: width - padding * 2, height: 16)
            addSubview(rssiLabel)
            yOffset += 18
        }

        yOffset += padding
        frame = NSRect(x: 0, y: 0, width: width, height: yOffset)
    }

    override var fittingSize: NSSize {
        return frame.size
    }
}
