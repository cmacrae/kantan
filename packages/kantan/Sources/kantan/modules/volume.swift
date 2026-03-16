import AudioToolbox
import CoreAudio
import Foundation

struct VolumeConfigFactory: ModuleConfigurationFactory {
  /// Default tabler-icons for volume levels, muted state, and common devices.
  static let defaultLevelIcons = ["volume-4", "volume-2", "volume"]
  static let defaultMutedIcon = "volume-off"
  static let defaultDeviceIcons: [String: String] = [
    "AirPods": "device-airpods",
    "Headphones": "headphones",
  ]

  func configuration(from yaml: Yaml, configDir: String?, theme: ThemeConfig?) throws
    -> ModuleConfiguration
  {
    let iconsYaml = yaml["icons"]

    let levelIcons =
      iconsYaml["level"].array?.compactMap { $0.string } ?? Self.defaultLevelIcons

    guard !levelIcons.isEmpty else {
      throw DecodingError.dataCorrupted(
        DecodingError.Context(
          codingPath: [],
          debugDescription: "VolumeConfig requires a non-empty 'icons.level' array"
        ))
    }

    let mutedIcon = iconsYaml["muted"].string ?? Self.defaultMutedIcon

    // Device-specific icon overrides: icons.device maps device name
    // substrings to icon names. Keys are matched case-insensitively
    // against the CoreAudio device name.
    // Defaults to common device entries; set `device: {}` to disable.
    var deviceIcons: [String: String]
    if let deviceYaml = iconsYaml["device"].dictionary {
      deviceIcons = [:]
      for (key, value) in deviceYaml {
        if let k = key.string, let v = value.string {
          deviceIcons[k] = v
        }
      }
    } else {
      deviceIcons = Self.defaultDeviceIcons
    }

    return VolumeConfig(
      levelIcons: levelIcons, mutedIcon: mutedIcon, deviceIcons: deviceIcons)
  }

  func defaultConfiguration() -> ModuleConfiguration? {
    VolumeConfig(
      levelIcons: Self.defaultLevelIcons,
      mutedIcon: Self.defaultMutedIcon,
      deviceIcons: Self.defaultDeviceIcons
    )
  }
}

struct VolumeStatus: Sendable {
  let volume: Float  // 0.0 – 1.0
  let isMuted: Bool
  let deviceName: String

  static let unavailable = VolumeStatus(volume: 0, isMuted: false, deviceName: "")
  var isAvailable: Bool { volume >= 0 }

  /// Volume as an integer percentage (0–100).
  var level: Int { max(0, min(100, Int(volume * 100))) }
}

/// Event-driven volume module using CoreAudio property listeners.
/// Registers listeners for volume changes, mute state changes, and
/// default output device changes — updates fire instantly instead of
/// polling every 2s.
final class VolumeConfig: ModuleConfiguration, EventDrivenModule {
  var type: String { "volume" }
  let levelIcons: [String]
  let mutedIcon: String
  /// Maps device name substrings (case-insensitive) to icon names.
  /// When the current output device name contains a matching key,
  /// that icon is used instead of the level-based icons.
  let deviceIcons: [String: String]

  var redrawInterval: TimeInterval { 0 }

  nonisolated(unsafe) private var onChange: (@Sendable () -> Void)?
  nonisolated(unsafe) private var listenedDeviceID: AudioDeviceID = 0
  nonisolated(unsafe) private var _cachedStatus: VolumeStatus?
  private let _statusLock = NSLock()

  init(
    levelIcons: [String], mutedIcon: String, deviceIcons: [String: String] = [:]
  ) {
    self.levelIcons = levelIcons
    self.mutedIcon = mutedIcon
    self.deviceIcons = deviceIcons
  }

  required init(from decoder: Decoder) throws {
    self.levelIcons = []
    self.mutedIcon = ""
    self.deviceIcons = [:]
  }

  deinit {
    stopObserving()
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
    DispatchQueue.main.async { [weak self] in
      guard let self = self else { return }
      if propertySelector == kAudioHardwarePropertyDefaultOutputDevice {
        // Default device changed — re-register per-device listeners
        self.removeDeviceListeners()
        self.addDeviceListeners()
      }
      self.onChange?()
    }
  }

  // MARK: - Status Caching

  private func refreshCache() {
    let status = Self.readVolumeStatus()
    _statusLock.lock()
    _cachedStatus = status
    _statusLock.unlock()
  }

  private func getCachedStatus() -> VolumeStatus {
    _statusLock.lock()
    defer { _statusLock.unlock() }
    return _cachedStatus ?? .unavailable
  }

  // MARK: - ModuleConfiguration

  func getValue(completion: @escaping @Sendable (String) -> Void) {
    completion("")
  }

  func getIcon() -> String {
    refreshCache()
    let status = getCachedStatus()
    if status.isMuted {
      return mutedIcon
    }
    // Check for device-specific icon override (case-insensitive substring match).
    if let deviceIcon = iconForDevice(status.deviceName) {
      return deviceIcon
    }
    return iconForLevel(status.level, icons: levelIcons)
  }

  /// Returns the configured icon for a device name, or nil if no match.
  /// Matches are case-insensitive substrings of the CoreAudio device name.
  private func iconForDevice(_ deviceName: String) -> String? {
    guard !deviceName.isEmpty, !deviceIcons.isEmpty else { return nil }
    let lowered = deviceName.lowercased()
    for (key, icon) in deviceIcons {
      if lowered.contains(key.lowercased()) {
        return icon
      }
    }
    return nil
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

  static func readVolumeStatus() -> VolumeStatus {
    let deviceID = defaultOutputDeviceID()
    guard deviceID != 0 else { return .unavailable }

    // Read device name
    let deviceName = deviceName(for: deviceID)

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

    return VolumeStatus(volume: volume, isMuted: isMuted, deviceName: deviceName)
  }

  /// Read the human-readable name of an audio device via CoreAudio.
  private static func deviceName(for deviceID: AudioDeviceID) -> String {
    var nameRef: CFString = "" as CFString
    var size = UInt32(MemoryLayout<CFString>.size)
    var addr = AudioObjectPropertyAddress(
      mSelector: kAudioObjectPropertyName,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )
    let status = AudioObjectGetPropertyData(deviceID, &addr, 0, nil, &size, &nameRef)
    return status == noErr ? nameRef as String : ""
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
