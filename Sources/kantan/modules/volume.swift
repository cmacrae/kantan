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

struct VolumeConfig: ModuleConfiguration {
    var type: String { "volume" }
    let showLevel: Bool
    let icons: [String]
    let mutedIcon: String

    var redrawInterval: TimeInterval { 2.0 }

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

    static func readVolumeStatus() -> VolumeStatus {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)

        var defaultAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &defaultAddr, 0, nil, &size, &deviceID
        )
        guard status == noErr else { return .unavailable }

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
