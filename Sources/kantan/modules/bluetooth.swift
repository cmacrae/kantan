import AppKit
import Foundation
import IOBluetooth
import Yaml

// Private IOBluetooth SPI for power control (same approach as blueutil)
@_silgen_name("IOBluetoothPreferenceGetControllerPowerState")
func IOBluetoothPreferenceGetControllerPowerState() -> CInt

@_silgen_name("IOBluetoothPreferenceSetControllerPowerState")
func IOBluetoothPreferenceSetControllerPowerState(_ state: CInt)

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

    static func isPoweredOn() -> Bool {
        return IOBluetoothPreferenceGetControllerPowerState() != 0
    }

    static func setPower(_ enabled: Bool) {
        IOBluetoothPreferenceSetControllerPowerState(enabled ? 1 : 0)
    }

    /// Build menu item descriptors for the bluetooth device menu.
    /// Used by PopupManager to render as either native or themed menu.
    static func buildMenuDescriptors() -> [MenuItemDescriptor] {
        let status = readBluetoothStatus()
        var descriptors: [MenuItemDescriptor] = []

        descriptors.append(.toggle("Bluetooth", isOn: status.isPoweredOn) { completion in
            DispatchQueue.global(qos: .userInitiated).async {
                BluetoothConfig.setPower(!status.isPoweredOn)
                // Brief delay for radio state to settle
                Thread.sleep(forTimeInterval: 0.5)
                DispatchQueue.main.async { completion() }
            }
        })
        descriptors.append(.separator())

        let connected = status.connectedDevices
        if !connected.isEmpty {
            descriptors.append(.header("Connected"))
            for device in connected {
                let address = device.address
                let indicator = makeIndicatorView(isConnected: true)
                descriptors.append(.item(device.name, icon: indicator) {
                    DispatchQueue.global(qos: .userInitiated).async {
                        BluetoothConfig.disconnectDevice(address: address)
                    }
                })
            }
        }

        let disconnected = status.pairedDevices.filter { !$0.isConnected }
        if !disconnected.isEmpty {
            if !connected.isEmpty {
                descriptors.append(.separator())
            }
            descriptors.append(.header("Not Connected"))
            for device in disconnected {
                let address = device.address
                let indicator = makeIndicatorView(isConnected: false)
                descriptors.append(.item(device.name, icon: indicator) {
                    DispatchQueue.global(qos: .userInitiated).async {
                        BluetoothConfig.connectDevice(address: address)
                    }
                })
            }
        }

        descriptors.append(.separator())
        descriptors.append(.item("Bluetooth Settings\u{2026}") {
            BluetoothConfig.openBluetoothSettings()
        })

        return descriptors
    }

    /// Creates a small rounded indicator circle for bluetooth device menu items.
    private static func makeIndicatorView(isConnected: Bool) -> NSView {
        let size: CGFloat = 10
        let view = NSView(frame: NSRect(x: 0, y: 0, width: size, height: size))
        view.wantsLayer = true
        view.layer?.cornerRadius = size / 2
        if isConnected {
            view.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
        } else {
            view.layer?.backgroundColor = NSColor.clear.cgColor
            view.layer?.borderColor = NSColor.tertiaryLabelColor.cgColor
            view.layer?.borderWidth = 1.5
        }
        return view
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


