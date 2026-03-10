import AppKit
import Foundation
import IOBluetooth
import Yaml

struct BluetoothConfigFactory: ModuleConfigurationFactory {
    func configuration(from yaml: Yaml, configDir: String?) throws -> ModuleConfiguration {
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

}
