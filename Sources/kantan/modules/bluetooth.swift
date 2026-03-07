import AppKit
import Foundation
import IOBluetooth
import Yaml

struct BluetoothConfigFactory: ModuleConfigurationFactory {
    func configuration(from yaml: Yaml) throws -> ModuleConfiguration {
        let showCount = yaml["showCount"].bool ?? false

        guard let icon = yaml["icon"].string else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: [],
                    debugDescription: "BluetoothConfig requires an 'icon' string"
                ))
        }

        let disabledIcon = yaml["disabledIcon"].string ?? icon

        return BluetoothConfig(showCount: showCount, icon: icon, disabledIcon: disabledIcon)
    }
}

struct BluetoothDeviceInfo: Sendable {
    let name: String
    let address: String
    let isConnected: Bool
    let majorClass: UInt32
    let minorClass: UInt32
}

struct BluetoothStatus: Sendable {
    let isPoweredOn: Bool
    let pairedDevices: [BluetoothDeviceInfo]

    static let unavailable = BluetoothStatus(isPoweredOn: false, pairedDevices: [])

    var connectedDevices: [BluetoothDeviceInfo] {
        pairedDevices.filter { $0.isConnected }
    }

    var connectedCount: Int { connectedDevices.count }
    var hasConnectedDevices: Bool { connectedCount > 0 }
}

struct BluetoothConfig: ModuleConfiguration {
    var type: String { "bluetooth" }
    let showCount: Bool
    let icon: String
    let disabledIcon: String

    var redrawInterval: TimeInterval { 5.0 }

    func getValue(completion: @escaping @Sendable (String) -> Void) {
        let status = Self.readBluetoothStatus()
        if showCount && status.hasConnectedDevices {
            completion("\(status.connectedCount)")
        } else {
            completion("")
        }
    }

    func getIcon() -> String {
        let status = Self.readBluetoothStatus()
        if !status.isPoweredOn {
            return disabledIcon
        }
        return icon
    }

    /// Returns false when Bluetooth is on but no devices are connected,
    /// causing drawModule() to dim the icon (like inactive workspace indicators).
    func isActive() -> Bool {
        let status = Self.readBluetoothStatus()
        if !status.isPoweredOn { return false }
        return status.hasConnectedDevices
    }

    func getTemplateVariables() -> [String: String] {
        let status = Self.readBluetoothStatus()
        let deviceNames = status.connectedDevices.map { $0.name }.joined(separator: ", ")
        let state: String
        if !status.isPoweredOn {
            state = "disabled"
        } else if status.hasConnectedDevices {
            state = "connected"
        } else {
            state = "disconnected"
        }
        return [
            "count": "\(status.connectedCount)",
            "devices": deviceNames.isEmpty ? "none" : deviceNames,
            "state": state,
        ]
    }

    // MARK: - IOBluetooth

    static func readBluetoothStatus() -> BluetoothStatus {
        guard let controller = IOBluetoothHostController.default() else {
            return .unavailable
        }

        let isPoweredOn = controller.powerState == kBluetoothHCIPowerStateON

        guard isPoweredOn else {
            return BluetoothStatus(isPoweredOn: false, pairedDevices: [])
        }

        guard let devices = IOBluetoothDevice.pairedDevices() else {
            return BluetoothStatus(isPoweredOn: true, pairedDevices: [])
        }

        let infos: [BluetoothDeviceInfo] = devices.compactMap { item in
            guard let device = item as? IOBluetoothDevice else { return nil }
            return BluetoothDeviceInfo(
                name: device.nameOrAddress ?? "Unknown",
                address: device.addressString ?? "",
                isConnected: device.isConnected(),
                majorClass: device.deviceClassMajor,
                minorClass: device.deviceClassMinor
            )
        }

        return BluetoothStatus(isPoweredOn: true, pairedDevices: infos)
    }

    /// Connect to a paired Bluetooth device by address.
    static func connectDevice(address: String) {
        guard let device = IOBluetoothDevice(addressString: address) else { return }
        device.openConnection()
    }

    /// Disconnect a paired Bluetooth device by address.
    /// Uses registerForDisconnectNotification + CFRunLoop pattern
    /// (same approach as blueutil) to wait for actual disconnect.
    static func disconnectDevice(address: String) {
        guard let device = IOBluetoothDevice(addressString: address) else { return }

        let stopper = BluetoothDisconnectObserver(expectedDevice: device)

        device.register(forDisconnectNotification: stopper,
                        selector: #selector(BluetoothDisconnectObserver.deviceDisconnected(_:device:)))

        guard device.closeConnection() == kIOReturnSuccess else { return }

        // Block until the disconnect notification fires and stops the run loop.
        // Timeout after 10s so we don't block forever if something goes wrong.
        CFRunLoopRunInMode(.defaultMode, 10.0, false)
    }

    /// Open the macOS Bluetooth Settings pane.
    static func openBluetoothSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.BluetoothSettings") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Build an NSMenu with paired devices (connect/disconnect) and a settings item.
    static func buildBluetoothMenu(target: AnyObject, connectAction: Selector,
                                   disconnectAction: Selector,
                                   settingsAction: Selector) -> NSMenu
    {
        let menu = NSMenu()
        let status = readBluetoothStatus()

        // Connected devices section
        let connected = status.connectedDevices
        if !connected.isEmpty {
            let header = NSMenuItem(title: "Connected", action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)

            for device in connected {
                let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
                let address = device.address
                item.view = BluetoothMenuItemView(
                    deviceName: device.name,
                    isConnected: true,
                    action: {
                        DispatchQueue.global(qos: .userInitiated).async {
                            BluetoothConfig.disconnectDevice(address: address)
                        }
                    }
                )
                menu.addItem(item)
            }
        }

        // Disconnected paired devices section
        let disconnected = status.pairedDevices.filter { !$0.isConnected }
        if !disconnected.isEmpty {
            if !connected.isEmpty {
                menu.addItem(NSMenuItem.separator())
            }
            let header = NSMenuItem(title: "Not Connected", action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)

            for device in disconnected {
                let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
                let address = device.address
                item.view = BluetoothMenuItemView(
                    deviceName: device.name,
                    isConnected: false,
                    action: {
                        DispatchQueue.global(qos: .userInitiated).async {
                            BluetoothConfig.connectDevice(address: address)
                        }
                    }
                )
                menu.addItem(item)
            }
        }

        menu.addItem(NSMenuItem.separator())

        let settingsItem = NSMenuItem(
            title: "Bluetooth Settings…",
            action: settingsAction,
            keyEquivalent: ""
        )
        settingsItem.target = target
        menu.addItem(settingsItem)

        return menu
    }
}

// MARK: - Disconnect Notification Observer

/// Observer that blocks the current run loop until a Bluetooth device disconnects.
/// Replicates blueutil's DeviceNotificationRunLoopStopper pattern in native Swift.
class BluetoothDisconnectObserver: NSObject {
    private let expectedDevice: IOBluetoothDevice

    init(expectedDevice: IOBluetoothDevice) {
        self.expectedDevice = expectedDevice
        super.init()
    }

    @objc func deviceDisconnected(_ notification: IOBluetoothUserNotification,
                                  device: IOBluetoothDevice)
    {
        if expectedDevice.isEqual(device) {
            notification.unregister()
            CFRunLoopStop(CFRunLoopGetCurrent())
        }
    }
}

// MARK: - Bluetooth Menu Item View

/// Custom NSView for Bluetooth device menu items.
/// Shows a rounded indicator circle (filled when connected, empty when not)
/// alongside the device name. On click, triggers connect/disconnect.
class BluetoothMenuItemView: NSView {
    private let nameLabel: NSTextField
    private let indicator: NSView
    private var trackingArea: NSTrackingArea?
    private let action: @MainActor @Sendable () -> Void
    private let isConnected: Bool
    private let itemHeight: CGFloat = 22
    private let itemWidth: CGFloat = 220
    private let indicatorSize: CGFloat = 10

    init(deviceName: String, isConnected: Bool,
         action: @MainActor @escaping @Sendable () -> Void)
    {
        self.action = action
        self.isConnected = isConnected

        indicator = NSView(frame: .zero)
        indicator.wantsLayer = true
        indicator.layer?.cornerRadius = 5 // half of indicatorSize
        if isConnected {
            indicator.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
        } else {
            indicator.layer?.backgroundColor = NSColor.clear.cgColor
            indicator.layer?.borderColor = NSColor.tertiaryLabelColor.cgColor
            indicator.layer?.borderWidth = 1.5
        }

        nameLabel = NSTextField(labelWithString: deviceName)
        nameLabel.font = NSFont.menuFont(ofSize: 13)
        nameLabel.textColor = .labelColor
        nameLabel.sizeToFit()

        super.init(frame: NSRect(x: 0, y: 0, width: itemWidth, height: itemHeight))

        addSubview(indicator)
        addSubview(nameLabel)

        let yCenter = (itemHeight - nameLabel.frame.height) / 2
        indicator.frame = NSRect(
            x: 12,
            y: (itemHeight - indicatorSize) / 2,
            width: indicatorSize,
            height: indicatorSize
        )
        nameLabel.frame.origin = NSPoint(x: 28, y: yCenter)
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
        wantsLayer = true
        layer?.backgroundColor = NSColor.selectedContentBackgroundColor.cgColor
        layer?.cornerRadius = 4
        nameLabel.textColor = .white
        if isConnected {
            indicator.layer?.backgroundColor = NSColor.white.cgColor
        } else {
            indicator.layer?.borderColor = NSColor.white.withAlphaComponent(0.5).cgColor
        }
    }

    override func mouseExited(with event: NSEvent) {
        layer?.backgroundColor = nil
        nameLabel.textColor = .labelColor
        if isConnected {
            indicator.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
        } else {
            indicator.layer?.borderColor = NSColor.tertiaryLabelColor.cgColor
        }
    }

    override func mouseUp(with event: NSEvent) {
        // Animate indicator to show state change
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            if isConnected {
                // Connected → disconnecting: filled circle → empty circle
                indicator.layer?.backgroundColor = NSColor.clear.cgColor
                indicator.layer?.borderColor = NSColor.white.withAlphaComponent(0.5).cgColor
                indicator.layer?.borderWidth = 1.5
            } else {
                // Disconnected → connecting: empty circle → filled circle
                indicator.layer?.backgroundColor = NSColor.white.cgColor
                indicator.layer?.borderWidth = 0
            }
        }

        // Dismiss the menu and fire the action
        enclosingMenuItem?.menu?.cancelTracking()
        action()
    }
}
