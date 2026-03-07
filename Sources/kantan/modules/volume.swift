import CoreAudio
import AudioToolbox
import Foundation
import Yaml

struct VolumeConfigFactory: ModuleConfigurationFactory {
    func configuration(from yaml: Yaml) throws -> ModuleConfiguration {
        let showLevel = yaml["showLevel"].bool ?? false

        guard let iconsYaml = yaml["icons"].array,
              let icons = Optional(iconsYaml.compactMap({ $0.string })),
              !icons.isEmpty else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: [],
                    debugDescription: "VolumeConfig requires a non-empty 'icons' array"
                ))
        }

        let mutedIcon = yaml["mutedIcon"].string ?? icons.first ?? ""

        return VolumeConfig(showLevel: showLevel, icons: icons, mutedIcon: mutedIcon)
    }
}

struct VolumeStatus: Sendable {
    let volume: Float   // 0.0 – 1.0
    let isMuted: Bool

    static let unavailable = VolumeStatus(volume: 0, isMuted: false)
    var isAvailable: Bool { volume >= 0 }

    /// Volume as an integer percentage (0–100).
    var level: Int { max(0, min(100, Int(volume * 100))) }
}

struct AudioOutputDevice: Sendable, Identifiable {
    let id: AudioDeviceID
    let name: String
    let transportType: UInt32
    let isDefault: Bool

    var transportLabel: String {
        switch transportType {
        case kAudioDeviceTransportTypeBuiltIn: return "Built-in"
        case kAudioDeviceTransportTypeBluetooth,
             kAudioDeviceTransportTypeBluetoothLE: return "Bluetooth"
        case kAudioDeviceTransportTypeUSB: return "USB"
        case kAudioDeviceTransportTypeHDMI: return "HDMI"
        case kAudioDeviceTransportTypeDisplayPort: return "DisplayPort"
        case kAudioDeviceTransportTypeAirPlay: return "AirPlay"
        default: return ""
        }
    }
}

/// Event-driven volume module using CoreAudio property listeners.
/// Registers listeners for volume changes, mute state changes, and
/// default output device changes — updates fire instantly instead of
/// polling every 2s.
final class VolumeConfig: ModuleConfiguration, EventDrivenModule {
    var type: String { "volume" }
    let showLevel: Bool
    let icons: [String]
    let mutedIcon: String

    var redrawInterval: TimeInterval { 0 }

    nonisolated(unsafe) private var onChange: (@Sendable () -> Void)?
    nonisolated(unsafe) private var listenedDeviceID: AudioDeviceID = 0

    init(showLevel: Bool, icons: [String], mutedIcon: String) {
        self.showLevel = showLevel
        self.icons = icons
        self.mutedIcon = mutedIcon
    }

    required init(from decoder: Decoder) throws {
        self.showLevel = false
        self.icons = []
        self.mutedIcon = ""
    }

    func encode(to encoder: Encoder) throws {}

    // MARK: - EventDrivenModule

    func startObserving(onChange: @escaping @Sendable () -> Void) {
        self.onChange = onChange

        // Listen for default output device changes
        var defaultDeviceAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        AudioObjectAddPropertyListener(
            AudioObjectID(kAudioObjectSystemObject),
            &defaultDeviceAddr,
            audioPropertyListener,
            selfPtr
        )

        // Listen for volume and mute on the current default device
        addDeviceListeners()
    }

    func stopObserving() {
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        // Remove default device listener
        var defaultDeviceAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectRemovePropertyListener(
            AudioObjectID(kAudioObjectSystemObject),
            &defaultDeviceAddr,
            audioPropertyListener,
            selfPtr
        )

        // Remove per-device listeners
        removeDeviceListeners()
        onChange = nil
    }

    private func addDeviceListeners() {
        let deviceID = Self.defaultOutputDeviceID()
        guard deviceID != 0 else { return }

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        var volumeAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListener(deviceID, &volumeAddr, audioPropertyListener, selfPtr)

        var muteAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListener(deviceID, &muteAddr, audioPropertyListener, selfPtr)

        listenedDeviceID = deviceID
    }

    private func removeDeviceListeners() {
        guard listenedDeviceID != 0 else { return }
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        var volumeAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectRemovePropertyListener(listenedDeviceID, &volumeAddr, audioPropertyListener, selfPtr)

        var muteAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectRemovePropertyListener(listenedDeviceID, &muteAddr, audioPropertyListener, selfPtr)

        listenedDeviceID = 0
    }

    /// Called from the CoreAudio callback when any listened property changes.
    fileprivate func handlePropertyChange(propertySelector: AudioObjectPropertySelector) {
        if propertySelector == kAudioHardwarePropertyDefaultOutputDevice {
            // Default device changed — re-register per-device listeners
            removeDeviceListeners()
            addDeviceListeners()
        }
        onChange?()
    }

    // MARK: - ModuleConfiguration

    func getValue(completion: @escaping @Sendable (String) -> Void) {
        let status = Self.readVolumeStatus()
        if status.isMuted {
            completion(showLevel ? "muted" : "")
        } else {
            completion(showLevel ? "\(status.level)%" : "")
        }
    }

    func getIcon() -> String {
        let status = Self.readVolumeStatus()
        if status.isMuted {
            return mutedIcon
        }
        guard !icons.isEmpty else { return "" }
        let step = 1.0 / Float(icons.count)
        let index = min(Int(status.volume / step), icons.count - 1)
        return icons[max(0, index)]
    }

    func getTemplateVariables() -> [String: String] {
        let status = Self.readVolumeStatus()
        let state: String
        if status.isMuted {
            state = "muted"
        } else {
            state = "active"
        }
        return ["level": "\(status.level)", "state": state]
    }

    // MARK: - CoreAudio

    private static func defaultOutputDeviceID() -> AudioDeviceID {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &addr, 0, nil, &size, &deviceID
        )
        return status == noErr ? deviceID : 0
    }

    // MARK: - Audio Output Device Control

    static func listOutputDevices() -> [AudioOutputDevice] {
        let defaultID = defaultOutputDeviceID()

        var devicesAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &devicesAddr, 0, nil, &dataSize
        )
        guard status == noErr, dataSize > 0 else { return [] }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)

        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &devicesAddr, 0, nil, &dataSize, &deviceIDs
        )
        guard status == noErr else { return [] }

        var devices: [AudioOutputDevice] = []
        for deviceID in deviceIDs {
            // Check for output streams
            var streamsAddr = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreams,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: kAudioObjectPropertyElementMain
            )
            var streamsSize: UInt32 = 0
            let streamsStatus = AudioObjectGetPropertyDataSize(deviceID, &streamsAddr, 0, nil, &streamsSize)
            guard streamsStatus == noErr, streamsSize > 0 else { continue }

            // Read device name
            var nameAddr = AudioObjectPropertyAddress(
                mSelector: kAudioObjectPropertyName,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var name: CFString = "" as CFString
            var nameSize = UInt32(MemoryLayout<CFString>.size)
            AudioObjectGetPropertyData(deviceID, &nameAddr, 0, nil, &nameSize, &name)

            // Read transport type
            var transportAddr = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyTransportType,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var transport: UInt32 = 0
            var transportSize = UInt32(MemoryLayout<UInt32>.size)
            AudioObjectGetPropertyData(deviceID, &transportAddr, 0, nil, &transportSize, &transport)

            devices.append(AudioOutputDevice(
                id: deviceID,
                name: name as String,
                transportType: transport,
                isDefault: deviceID == defaultID
            ))
        }

        // Sort: default device first
        return devices.sorted { $0.isDefault && !$1.isDefault }
    }

    static func setDefaultOutputDevice(_ deviceID: AudioDeviceID) {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var id = deviceID
        AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &addr, 0, nil,
            UInt32(MemoryLayout<AudioDeviceID>.size), &id
        )
    }

    static func setVolume(_ volume: Float) {
        let deviceID = defaultOutputDeviceID()
        guard deviceID != 0 else { return }

        var volumeAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var vol = volume
        AudioObjectSetPropertyData(
            deviceID, &volumeAddr, 0, nil,
            UInt32(MemoryLayout<Float32>.size), &vol
        )
    }

    static func setMuted(_ muted: Bool) {
        let deviceID = defaultOutputDeviceID()
        guard deviceID != 0 else { return }

        var muteAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var muteValue: UInt32 = muted ? 1 : 0
        AudioObjectSetPropertyData(
            deviceID, &muteAddr, 0, nil,
            UInt32(MemoryLayout<UInt32>.size), &muteValue
        )
    }

    static func readVolumeStatus() -> VolumeStatus {
        let deviceID = defaultOutputDeviceID()
        guard deviceID != 0 else { return .unavailable }

        // Read volume
        var volume: Float32 = 0
        var volumeSize = UInt32(MemoryLayout<Float32>.size)
        var volumeAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        let volStatus = AudioObjectGetPropertyData(
            deviceID, &volumeAddr, 0, nil, &volumeSize, &volume
        )
        if volStatus != noErr {
            volume = 0
        }

        // Read mute state
        var muted: UInt32 = 0
        var muteSize = UInt32(MemoryLayout<UInt32>.size)
        var muteAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        let muteStatus = AudioObjectGetPropertyData(
            deviceID, &muteAddr, 0, nil, &muteSize, &muted
        )
        let isMuted = (muteStatus == noErr) ? (muted != 0) : false

        return VolumeStatus(volume: volume, isMuted: isMuted)
    }
}

// MARK: - CoreAudio Property Listener Callback

/// C-function callback for CoreAudio property changes. Bridges to
/// VolumeConfig.handlePropertyChange() on the main thread.
private func audioPropertyListener(
    _ objectID: AudioObjectID,
    _ numberAddresses: UInt32,
    _ addresses: UnsafePointer<AudioObjectPropertyAddress>,
    _ context: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let context = context else { return noErr }
    let config = Unmanaged<VolumeConfig>.fromOpaque(context).takeUnretainedValue()
    let selector = addresses.pointee.mSelector
    config.handlePropertyChange(propertySelector: selector)
    return noErr
}
