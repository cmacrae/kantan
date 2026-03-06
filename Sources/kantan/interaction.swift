import AppKit
import IOKit.ps

// MARK: - Status Bar View

/// Custom NSView for the status bar that only responds to mouse events
/// on InteractiveModuleView children. All other areas pass events through
/// to the windows below, preserving tiling WM interaction.
class StatusBarContainerView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        // Only return hits on InteractiveModuleView instances
        for subview in subviews.reversed() {
            if let interactive = subview as? InteractiveModuleView {
                let localPoint = interactive.convert(point, from: self)
                if interactive.bounds.contains(localPoint) {
                    return interactive
                }
            }
        }
        // Return nil so events pass through to underlying windows
        return nil
    }
}

// MARK: - Interactive Module View

/// A transparent hit-test view placed over module subviews to capture
/// hover and click events. Uses NSTrackingArea for hover detection.
/// The parent window must be a non-activating NSPanel so interactions
/// never steal focus from the user's tiling window manager.
class InteractiveModuleView: NSView {
    let moduleName: String
    var interaction: InteractionConfig?
    var templateVariableProvider: (() -> [String: String])?
    var currentValue: (() -> String?)?
    var currentIcon: (() -> String?)?
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
        // Don't show tooltip if a popup or menu is currently active
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
        // Hide tooltip on click — user is interacting now
        popupManager?.hideTooltip()

        guard let click = interaction?.click else { return }

        switch click.type {
        case "menu":
            showMenu(click)
        case "popup":
            showPopup(click)
        default:
            break
        }
    }

    // Ensure this view is the hit target even though it's transparent
    override func hitTest(_ point: NSPoint) -> NSView? {
        let localPoint = convert(point, from: superview)
        if bounds.contains(localPoint) {
            return self
        }
        return nil
    }

    // MARK: - Template Resolution

    private func resolveTemplate(_ template: String) -> String {
        var result = template

        // Built-in variables
        if let value = currentValue?() {
            result = result.replacingOccurrences(of: "{value}", with: value)
        }
        if let icon = currentIcon?() {
            result = result.replacingOccurrences(of: "{icon}", with: icon)
        }

        // Module-specific variables
        if let vars = templateVariableProvider?() {
            for (key, val) in vars {
                result = result.replacingOccurrences(of: "{\(key)}", with: val)
            }
        }

        return result
    }

    // MARK: - Menu

    private func showMenu(_ config: ClickConfig) {
        guard let items = config.items, !items.isEmpty else { return }

        let menu = NSMenu()
        for item in items {
            if item.separator == true {
                menu.addItem(NSMenuItem.separator())
            } else if let label = item.label {
                let menuItem = NSMenuItem(title: label, action: #selector(menuItemClicked(_:)), keyEquivalent: "")
                menuItem.target = self
                menuItem.representedObject = item.command
                menu.addItem(menuItem)
            }
        }

        let locationInWindow = convert(NSPoint(x: 0, y: 0), to: nil)
        guard let screenPoint = window?.convertPoint(toScreen: locationInWindow) else { return }
        menu.popUp(positioning: nil, at: NSPoint(x: screenPoint.x, y: screenPoint.y), in: nil)
    }

    @objc private func menuItemClicked(_ sender: NSMenuItem) {
        guard let command = sender.representedObject as? String, !command.isEmpty else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = ["-c", command]
            process.standardOutput = Pipe()
            process.standardError = Pipe()
            try? process.run()
        }
    }

    // MARK: - Popup

    private func showPopup(_ config: ClickConfig) {
        guard let popupName = config.popup else { return }
        let locationInWindow = convert(NSPoint(x: bounds.midX, y: 0), to: nil)
        guard let screenPoint = window?.convertPoint(toScreen: locationInWindow) else { return }
        popupManager?.togglePopup(name: popupName, moduleName: moduleName, anchorPoint: screenPoint)
    }
}

// MARK: - Popup Manager

/// Manages popup and tooltip panels. Uses NSPanel with .nonactivatingPanel
/// so interactions never steal focus from the user's windows.
@MainActor
class PopupManager {
    private var activePanel: NSPanel?
    private var activePopupId: String?
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var tooltipPanel: NSPanel?
    var fgColor: NSColor = .labelColor
    var bgColor: NSColor = .windowBackgroundColor

    /// Whether a popup panel is currently showing.
    var isPopupActive: Bool {
        return activePanel != nil
    }

    // MARK: - Screen Clamping

    /// Clamps a rect to fit within the visible screen area.
    private func clampToScreen(_ rect: NSRect) -> NSRect {
        guard let screen = NSScreen.main?.visibleFrame else { return rect }
        var clamped = rect
        // Clamp right edge
        if clamped.maxX > screen.maxX {
            clamped.origin.x = screen.maxX - clamped.width
        }
        // Clamp left edge
        if clamped.origin.x < screen.minX {
            clamped.origin.x = screen.minX
        }
        // Clamp bottom edge
        if clamped.origin.y < screen.minY {
            clamped.origin.y = screen.minY
        }
        // Clamp top edge
        if clamped.maxY > screen.maxY {
            clamped.origin.y = screen.maxY - clamped.height
        }
        return clamped
    }

    // MARK: - Tooltip

    func showTooltip(text: String, anchorPoint: NSPoint) {
        // Don't show tooltip if a popup is active
        guard !isPopupActive else { return }

        hideTooltip()

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

        let panel = NSPanel(
            contentRect: panelRect,
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

    // MARK: - Popup

    func togglePopup(name: String, moduleName: String, anchorPoint: NSPoint) {
        let popupId = "\(moduleName):\(name)"

        // If same popup is already showing, dismiss it (toggle off)
        if popupId == activePopupId, activePanel != nil {
            dismissPopup()
            return
        }

        // Dismiss any other popup
        dismissPopup()

        // Create popup content with user's colour config
        guard let contentView = createPopupContent(name: name, fgColor: fgColor, bgColor: bgColor) else { return }

        // Size the content
        contentView.layoutSubtreeIfNeeded()
        let contentSize = contentView.fittingSize
        let panelWidth = max(contentSize.width, 200)
        let panelHeight = max(contentSize.height, 100)

        // Position below the anchor point, clamped to screen
        var panelRect = NSRect(
            x: anchorPoint.x - panelWidth / 2,
            y: anchorPoint.y - panelHeight - 4,
            width: panelWidth,
            height: panelHeight
        )
        panelRect = clampToScreen(panelRect)

        let panel = NSPanel(
            contentRect: panelRect,
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

        // Background container with rounded corners and user's bg colour
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

        // Local monitor: clicks within our app's windows.
        // Skip if the click lands on an InteractiveModuleView — let its
        // mouseDown handler decide whether to toggle.
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self = self, let panel = self.activePanel else { return event }
            if event.window === panel { return event }

            // Check if the click is on an InteractiveModuleView — if so,
            // let mouseDown handle the toggle; don't dismiss here.
            if let hitView = event.window?.contentView?.hitTest(event.locationInWindow),
               hitView is InteractiveModuleView {
                return event
            }

            self.dismissPopup()
            return event
        }

        // Global monitor: clicks outside our app entirely
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.dismissPopup()
        }
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

    // MARK: - Built-in Popup Content

    private func createPopupContent(name: String, fgColor: NSColor, bgColor: NSColor) -> NSView? {
        switch name {
        case "calendar":
            return CalendarPopupView(fgColor: fgColor, bgColor: bgColor)
        case "battery-detail":
            return BatteryDetailPopupView(fgColor: fgColor, bgColor: bgColor)
        default:
            return nil
        }
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
