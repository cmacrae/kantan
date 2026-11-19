import AppKit
import AudioToolbox
import CoreAudio
import Foundation

struct WaveformConfigFactory: ModuleConfigurationFactory {
  func configuration(from yaml: Yaml, configDir: String?, theme: ThemeConfig?) throws
    -> ModuleConfiguration
  {
    let number = { (key: String) in yaml[key].double ?? yaml[key].int.map(Double.init) }
    return WaveformConfig(
      style: yaml["style"].string.flatMap(WaveformStyle.init(rawValue:)) ?? .bars,
      bars: min(max(yaml["bars"].int ?? 8, 1), AudioAnalysis.bandCount),
      width: max(number("width") ?? 40, 4),
      height: max(number("height") ?? 14, 2),
      hidesWhenSilent: yaml["hide"].string != "never",
      silenceDelay: max(number("silenceDelay") ?? WaveformConfig.defaultSilenceDelay, 0),
      colors: WaveformColors(yaml: yaml), matchWidth: yaml["matchWidth"].string,
      sensitivity: number("sensitivity").map { max($0, 0) },
      filter: AudioFilter(
        appsOnly: yaml["sources"].string != "all",
        excluded: yaml["exclude"].array?.compactMap(\.string) ?? []))
  }

  func defaultConfiguration() -> ModuleConfiguration? {
    WaveformConfig(style: .bars, bars: 8, width: 40, height: 14, hidesWhenSilent: true)
  }
}

/// How a waveform module draws the sound: the level of each band of
/// frequencies as a bar, or the wave itself as a line.
enum WaveformStyle: String, Sendable {
  case bars
  case wave
}

/// The colours of a waveform module's bars, the lowest frequency first.
enum WaveformColors: Sendable, Equatable {
  /// Each bar in the colour of the module's icon.
  case module
  /// The bars take these in order, going round again past the last.
  case palette([String])
  /// The first bar is `low`, the last `high`, and those between pass from
  /// one to the other.
  case gradient(low: String, high: String)

  /// The colours a module's `gradient` or `rainbow` gives its bars: a
  /// gradient comes first, and a rainbow's colours are shuffled for
  /// `bars` unless it isn't `random`.
  init(yaml: Yaml) {
    let rainbow = yaml["rainbow"]
    let palette = rainbow["colors"].array?.compactMap(\.string) ?? []
    if let low = yaml["gradient"]["low"].string, let high = yaml["gradient"]["high"].string {
      self = .gradient(low: low, high: high)
    } else if rainbow["enabled"].bool == true, !palette.isEmpty {
      let bars = min(max(yaml["bars"].int ?? 8, 1), AudioAnalysis.bandCount)
      self = .palette(
        rainbow["random"].bool ?? true
          ? WorkspaceConfig.shuffledRainbow(palette, spaceCount: bars) : palette)
    } else {
      self = .module
    }
  }

  /// The colour between the hex colours `low` and `high`, `fraction` of the
  /// way from the first, as a hex colour.
  static func blend(_ low: String, _ high: String, fraction: Double) -> String {
    let (from, to) = (NSColor(hex: low), NSColor(hex: high))
    let mixed = { (a: CGFloat, b: CGFloat) in Int((a + (b - a) * fraction).clamped * 255 + 0.5) }
    return String(
      format: "%02X%02X%02X",
      mixed(from.redComponent, to.redComponent), mixed(from.greenComponent, to.greenComponent),
      mixed(from.blueComponent, to.blueComponent))
  }

  /// The colour of each of `count` bars as a hex colour, or nil for the
  /// module's. `resolve` turns a colour as written into a hex colour.
  func colors(count: Int, resolve: (String) -> String) -> [String]? {
    switch self {
    case .module:
      return nil
    case .palette(let palette):
      return (0..<count).map { resolve(palette[$0 % palette.count]) }
    case .gradient(let low, let high):
      let (low, high) = (resolve(low), resolve(high))
      return (0..<count).map {
        Self.blend(low, high, fraction: count > 1 ? Double($0) / Double(count - 1) : 0)
      }
    }
  }
}

extension CGFloat {
  fileprivate var clamped: CGFloat { Swift.min(Swift.max(self, 0), 1) }
}

/// Waveform module drawing the sound the Mac is playing, from any app, as
/// it plays. It shows while there is sound, and its toggle brings the app
/// making the sound to the front.
final class WaveformConfig: ModuleConfiguration, EventDrivenModule {
  var type: String { "waveform" }
  var redrawInterval: TimeInterval { noPoll }

  let style: WaveformStyle
  /// How many bars the `bars` style draws.
  let bars: Int
  /// The width of the `wave` style's line, in points.
  let width: Double
  let height: Double
  let hidesWhenSilent: Bool
  /// How long the output stays quiet before the module counts it silent,
  /// in seconds: long enough to pass over a pause within the sound, or 0
  /// to follow the sound as it stops.
  let silenceDelay: TimeInterval
  let colors: WaveformColors
  /// The name of a module whose width this one follows while that module
  /// is in the bar and wider than this one's own `bars` or `width`.
  let matchWidth: String?

  /// How much taller than measured the sound is drawn: 1 as it is, 2 twice
  /// as tall, up to the module's height. Nil follows the number of bars.
  let sensitivity: Double?
  /// Whose sound the module draws.
  let filter: AudioFilter

  static let defaultSilenceDelay: TimeInterval = 0.3
  /// The most bars a module following another's width draws.
  static let maxMatchedBars = AudioAnalysis.bandCount

  init(
    style: WaveformStyle, bars: Int, width: Double, height: Double, hidesWhenSilent: Bool,
    silenceDelay: TimeInterval = WaveformConfig.defaultSilenceDelay,
    colors: WaveformColors = .module, matchWidth: String? = nil,
    sensitivity: Double? = nil, filter: AudioFilter = AudioFilter()
  ) {
    self.style = style
    self.bars = bars
    self.width = width
    self.height = height
    self.hidesWhenSilent = hidesWhenSilent
    self.silenceDelay = silenceDelay
    self.colors = colors
    self.matchWidth = matchWidth
    self.sensitivity = sensitivity
    self.filter = filter
  }

  /// How much taller than measured the sound is drawn as `bars` bars, or
  /// as a wave without any: the module's own `sensitivity`, or one that
  /// follows the bars. Each doubling of the bars past 8 adds a quarter, as
  /// a bar that covers fewer bands of the sound holds less of it.
  func sensitivity(bars: Int?) -> Double {
    if let sensitivity { return sensitivity }
    guard let bars, bars > 8 else { return 1 }
    return 1 + 0.25 * log2(Double(bars) / 8)
  }

  /// How many bars of `barWidth` set `spacing` apart the module draws
  /// beside a module `matched` points wide: as many as fit that width, and
  /// no fewer than its own `bars`.
  func barCount(matching matched: CGFloat?, barWidth: CGFloat, spacing: CGFloat) -> Int {
    guard let matched else { return bars }
    let fitting = Int((matched + spacing) / (barWidth + spacing))
    return min(max(fitting, bars), Self.maxMatchedBars)
  }

  deinit {
    stopObserving()
  }

  // MARK: - EventDrivenModule

  func startObserving(onChange: @escaping @Sendable () -> Void) {
    AudioMeter.shared.addObserver(
      ObjectIdentifier(self), silenceDelay: silenceDelay, filter: filter, onChange: onChange)
  }

  func stopObserving() {
    AudioMeter.shared.removeObserver(ObjectIdentifier(self))
  }

  // MARK: - ModuleConfiguration

  func getValue(completion: @escaping @Sendable (String) -> Void) {
    completion("")
  }

  func shouldDisplay() -> Bool {
    Self.shouldDisplay(
      silent: AudioMeter.shared.isSilent(for: ObjectIdentifier(self)),
      hidesWhenSilent: hidesWhenSilent)
  }

  func getTemplateVariables() -> [String: String] {
    Self.templateVariables(silent: AudioMeter.shared.isSilent(for: ObjectIdentifier(self)))
  }

  static func shouldDisplay(silent: Bool, hidesWhenSilent: Bool) -> Bool {
    !(silent && hidesWhenSilent)
  }

  /// `{state}` is `Playing` while there is sound and `Silent` otherwise.
  static func templateVariables(silent: Bool) -> [String: String] {
    ["state": silent ? "Silent" : "Playing"]
  }

  func handleToggle(completion: @escaping @Sendable () -> Void) {
    DispatchQueue.global(qos: .userInitiated).async {
      if let app = AudioSource.loudest(of: self.filter) {
        DispatchQueue.main.async { app.activate() }
      }
      completion()
    }
  }
}

// MARK: - Module Widths

/// How wide each module's content is drawn in the bar, by module name, for
/// a module that follows another's width. A module out of the bar is 0 wide.
@MainActor
final class ModuleWidths: ObservableObject {
  static let shared = ModuleWidths()
  @Published private(set) var widths: [String: CGFloat] = [:]

  /// Records a module's width once the layout pass reporting it is over:
  /// the views following a width can't be told of it during one.
  func set(_ width: CGFloat, for module: String) {
    guard abs((widths[module] ?? -1) - width) >= 0.5 else { return }
    DispatchQueue.main.async {
      MainActor.assumeIsolated {
        guard abs((self.widths[module] ?? -1) - width) >= 0.5 else { return }
        self.widths[module] = width
      }
    }
  }
}

// MARK: - Audio Tap

/// Reads the sound processes send to the Mac's output through a Core Audio
/// tap, keeping the latest of it as mono samples.
final class AudioTap: @unchecked Sendable {
  /// How many of the latest samples are kept.
  static let capacity = 8192

  private let lock = NSLock()
  private var ring = [Float](repeating: 0, count: AudioTap.capacity)
  private var writeIndex = 0
  private var tapID = AudioObjectID(kAudioObjectUnknown)
  private var deviceID = AudioObjectID(kAudioObjectUnknown)
  private var procID: AudioDeviceIOProcID?
  private(set) var sampleRate: Double = 48000

  /// Starts reading the sound of `processes`, or when there are none, of
  /// every process but those `excluded`. False when macOS doesn't allow it.
  func start(processes: [AudioObjectID] = [], excluding excluded: [AudioObjectID] = []) -> Bool {
    let description =
      processes.isEmpty
      ? CATapDescription(stereoGlobalTapButExcludeProcesses: excluded)
      : CATapDescription(stereoMixdownOfProcesses: processes)
    description.uuid = UUID()
    description.isPrivate = true
    description.muteBehavior = .unmuted
    guard AudioHardwareCreateProcessTap(description, &tapID) == noErr else { return false }

    var format = AudioStreamBasicDescription()
    var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioTapPropertyFormat, mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain)
    if AudioObjectGetPropertyData(tapID, &address, 0, nil, &size, &format) == noErr,
      format.mSampleRate > 0
    {
      sampleRate = format.mSampleRate
    }

    // An aggregate device of the tap alone, which follows the processes
    // whichever device they play through.
    let device: [String: Any] = [
      kAudioAggregateDeviceNameKey: "kantan",
      kAudioAggregateDeviceUIDKey: UUID().uuidString,
      kAudioAggregateDeviceIsPrivateKey: true,
      kAudioAggregateDeviceTapAutoStartKey: true,
      kAudioAggregateDeviceTapListKey: [
        [kAudioSubTapUIDKey: description.uuid.uuidString, kAudioSubTapDriftCompensationKey: true]
      ],
    ]
    guard AudioHardwareCreateAggregateDevice(device as CFDictionary, &deviceID) == noErr,
      AudioDeviceCreateIOProcIDWithBlock(
        &procID, deviceID, DispatchQueue(label: "bar.kantan.audio-tap"),
        { [weak self] _, input, _, _, _ in self?.received(input) }) == noErr,
      AudioDeviceStart(deviceID, procID) == noErr
    else {
      stop()
      return false
    }
    return true
  }

  func stop() {
    if deviceID != kAudioObjectUnknown {
      if let procID {
        AudioDeviceStop(deviceID, procID)
        AudioDeviceDestroyIOProcID(deviceID, procID)
      }
      AudioHardwareDestroyAggregateDevice(deviceID)
    }
    if tapID != kAudioObjectUnknown { AudioHardwareDestroyProcessTap(tapID) }
    procID = nil
    deviceID = AudioObjectID(kAudioObjectUnknown)
    tapID = AudioObjectID(kAudioObjectUnknown)
  }

  /// Keeps the first buffer's frames, its channels averaged into one.
  private func received(_ input: UnsafePointer<AudioBufferList>) {
    let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
    guard let buffer = buffers.first, let data = buffer.mData else { return }
    let channels = max(Int(buffer.mNumberChannels), 1)
    let samples = UnsafeBufferPointer(
      start: data.assumingMemoryBound(to: Float.self),
      count: Int(buffer.mDataByteSize) / MemoryLayout<Float>.size)
    lock.lock()
    defer { lock.unlock() }
    var frame = 0
    while frame + channels <= samples.count {
      var sum: Float = 0
      for channel in 0..<channels { sum += samples[frame + channel] }
      ring[writeIndex] = sum / Float(channels)
      writeIndex = (writeIndex + 1) % Self.capacity
      frame += channels
    }
  }

  /// The latest `count` samples, the oldest first.
  func latest(_ count: Int) -> [Float] {
    lock.lock()
    defer { lock.unlock() }
    let count = min(count, Self.capacity)
    return (0..<count).map { ring[(writeIndex - count + $0 + Self.capacity) % Self.capacity] }
  }
}

// MARK: - Audio Meter

/// What waveform modules draw: the level of each band, 0 to 1, and the
/// wave's latest stretch, -1 to 1.
@MainActor
final class AudioLevels: ObservableObject {
  static let shared = AudioLevels()
  @Published var bands = [Float](repeating: 0, count: AudioAnalysis.bandCount)
  @Published var wave = [Float](repeating: 0, count: AudioAnalysis.wavePoints)
}

/// Measures the sound the Mac plays while waveform modules observe it:
/// publishes its levels to `AudioLevels` thirty times a second, and tells
/// each observer when sound starts and when it has been quiet for as long
/// as the observer waits.
final class AudioMeter: @unchecked Sendable {
  static let shared = AudioMeter()

  /// A module observing the sound, and whether it has gone quiet for it.
  private struct Observer {
    /// How long the output stays quiet before it counts as silent.
    let silenceDelay: TimeInterval
    let filter: AudioFilter
    let onChange: @Sendable () -> Void
    var silent = true
  }

  /// How often the sound is measured while every observer waits for some.
  private static let idleInterval: TimeInterval = 1.0 / 20
  private static let activeInterval: TimeInterval = 1.0 / 30

  private let lock = NSLock()
  private var observers: [ObjectIdentifier: Observer] = [:]
  private let tap = AudioTap()
  private var timer: Timer?
  private var interval: TimeInterval = 0
  private var bands = [Float](repeating: 0, count: AudioAnalysis.bandCount)
  private var lastSound = Date.distantPast
  /// The processes the tap leaves out.
  private var excluded: [AudioObjectID] = []
  private var tapRunning = false
  private var lastWatch = Date.distantPast
  /// The tap's stopping, waiting out `tapLinger`.
  private var tapStop: DispatchWorkItem?
  /// How long after the last app stops playing the tap keeps running, so
  /// a gap between two tracks doesn't stop and start it.
  private static let tapLinger: TimeInterval = 3
  /// How often the apps are looked over, besides when Core Audio says one
  /// has begun or stopped playing.
  private static let watchInterval: TimeInterval = 1

  /// Whether the output has been quiet for as long as `observer` waits.
  func isSilent(for observer: ObjectIdentifier) -> Bool {
    lock.lock()
    defer { lock.unlock() }
    return observers[observer]?.silent ?? true
  }

  func addObserver(
    _ observer: ObjectIdentifier, silenceDelay: TimeInterval, filter: AudioFilter,
    onChange: @escaping @Sendable () -> Void
  ) {
    lock.lock()
    let first = observers.isEmpty
    observers[observer] = Observer(silenceDelay: silenceDelay, filter: filter, onChange: onChange)
    lock.unlock()
    DispatchQueue.main.async { first ? self.start() : self.sourcesChanged() }
  }

  /// Whose sound is measured: every observer's exclusions together, and
  /// apps alone when any observer draws only theirs.
  private var filter: AudioFilter {
    lock.lock()
    defer { lock.unlock() }
    return AudioFilter(
      appsOnly: observers.values.contains { $0.filter.appsOnly },
      excluded: observers.values.flatMap(\.filter.excluded))
  }

  func removeObserver(_ observer: ObjectIdentifier) {
    lock.lock()
    let last = observers.removeValue(forKey: observer) != nil && observers.isEmpty
    lock.unlock()
    if last { DispatchQueue.main.async { self.stop() } }
  }

  /// Begins watching for apps that play. The tap, and with it macOS's
  /// recording indicator, runs only while one does.
  private func start() {
    lock.lock()
    let wanted = !observers.isEmpty
    lock.unlock()
    guard wanted, timer == nil else { return }
    AudioSource.onProcessesChange { [weak self] in
      DispatchQueue.main.async { self?.sourcesChanged() }
    }
    schedule(every: Self.watchInterval)
    sourcesChanged()
  }

  /// Starts the tap when a process it would hear begins to play, and stops
  /// it once none has played for `tapLinger`.
  private func sourcesChanged() {
    guard timer != nil else { return }
    if AudioSource.isOutputting(within: filter) {
      tapStop?.cancel()
      tapStop = nil
      tapRunning ? retap() : startTap()
    } else if tapRunning, tapStop == nil {
      let stop = DispatchWorkItem { [weak self] in
        MainActor.assumeIsolated {
          guard let self else { return }
          self.tapStop = nil
          if !AudioSource.isOutputting(within: self.filter) { self.stopTap() }
        }
      }
      tapStop = stop
      DispatchQueue.main.asyncAfter(deadline: .now() + Self.tapLinger, execute: stop)
    }
  }

  private func startTap() {
    excluded = AudioSource.processes(outside: filter)
    guard tap.start(excluding: excluded) else { return }
    tapRunning = true
    schedule(every: Self.idleInterval)
  }

  /// Stops the tap, leaving every observer with silence.
  @MainActor
  private func stopTap() {
    guard tapRunning else { return }
    tap.stop()
    tapRunning = false
    lock.lock()
    var callbacks: [@Sendable () -> Void] = []
    for (id, observer) in observers where !observer.silent {
      observers[id]?.silent = true
      callbacks.append(observer.onChange)
    }
    lock.unlock()
    callbacks.forEach { $0() }
    bands = [Float](repeating: 0, count: AudioAnalysis.bandCount)
    AudioLevels.shared.bands = bands
    AudioLevels.shared.wave = [Float](repeating: 0, count: AudioAnalysis.wavePoints)
    if timer != nil { schedule(every: Self.watchInterval) }
  }

  /// Starts the tap again when the processes it leaves out have changed:
  /// as one starts or quits, or an observer with another filter joins.
  private func retap() {
    guard tapRunning else { return }
    let excluded = AudioSource.processes(outside: filter)
    guard excluded != self.excluded else { return }
    self.excluded = excluded
    tap.stop()
    _ = tap.start(excluding: excluded)
  }

  private func stop() {
    lock.lock()
    let wanted = !observers.isEmpty
    lock.unlock()
    guard !wanted else { return }
    timer?.invalidate()
    timer = nil
    tapStop?.cancel()
    tapStop = nil
    AudioSource.onProcessesChange(nil)
    MainActor.assumeIsolated { stopTap() }
  }

  /// Measures every `interval`: more often while there is sound to draw.
  private func schedule(every interval: TimeInterval) {
    guard timer == nil || interval != self.interval else { return }
    self.interval = interval
    timer?.invalidate()
    let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated {
        guard let self else { return }
        if self.tapRunning { self.measure() }
        // The apps are looked over every `watchInterval` as well as when
        // Core Audio says one has begun or stopped playing, should it not.
        if Date().timeIntervalSince(self.lastWatch) >= Self.watchInterval {
          self.lastWatch = Date()
          self.sourcesChanged()
        }
      }
    }
    RunLoop.main.add(timer, forMode: .common)
    self.timer = timer
  }

  @MainActor
  private func measure() {
    let samples = tap.latest(AudioAnalysis.window)
    // The newest samples alone say whether there is sound now, so quiet is
    // noticed as it begins, not once it fills the window.
    let sounding =
      AudioAnalysis.peak(Array(samples.suffix(AudioAnalysis.recent)))
      > AudioAnalysis.silenceThreshold
    if sounding { lastSound = Date() }
    let quiet = Date().timeIntervalSince(lastSound)

    lock.lock()
    var callbacks: [@Sendable () -> Void] = []
    for (id, observer) in observers {
      let silent = !sounding && quiet >= observer.silenceDelay
      if silent != observer.silent {
        observers[id]?.silent = silent
        callbacks.append(observer.onChange)
      }
    }
    let allSilent = observers.values.allSatisfy(\.silent)
    lock.unlock()

    schedule(every: allSilent ? Self.idleInterval : Self.activeInterval)
    callbacks.forEach { $0() }
    if allSilent, !callbacks.isEmpty {
      // A module leaving the bar keeps its last levels as it slides away;
      // one that stays settles to nothing once it would have gone.
      DispatchQueue.main.asyncAfter(deadline: .now() + ModuleAnimation.duration) { [weak self] in
        MainActor.assumeIsolated {
          guard let self, Date().timeIntervalSince(self.lastSound) >= ModuleAnimation.duration
          else { return }
          self.bands = [Float](repeating: 0, count: AudioAnalysis.bandCount)
          AudioLevels.shared.bands = self.bands
          AudioLevels.shared.wave = [Float](repeating: 0, count: AudioAnalysis.wavePoints)
        }
      }
    }
    // The levels hold through a quiet moment, so they don't drop away
    // just before a module does.
    guard sounding else { return }
    bands = AudioAnalysis.smoothed(
      AudioAnalysis.bands(of: samples, sampleRate: tap.sampleRate), over: bands)
    AudioLevels.shared.bands = bands
    AudioLevels.shared.wave = AudioAnalysis.wave(of: samples)
  }
}

// MARK: - Audio Source

/// Whose sound a waveform module draws.
struct AudioFilter: Sendable, Equatable {
  /// Whether only apps in the Dock, and the helpers that play for them,
  /// count: not the system's own sounds, such as a notification's.
  var appsOnly = true
  /// Apps left out, by name or bundle identifier in any case.
  var excluded: [String] = []
}

/// Finds the processes and apps making the sound.
enum AudioSource {
  /// Called when the processes that make sound change.
  nonisolated(unsafe) private static var processesChanged: (@Sendable () -> Void)?
  nonisolated(unsafe) private static let listener: AudioObjectPropertyListenerBlock = { _, _ in
    // The processes to listen to follow those there are.
    if processesChanged != nil { watchOutputs(of: Set(allProcesses())) }
    processesChanged?()
  }

  /// The processes whose playing is listened for.
  nonisolated(unsafe) private static var watched: Set<AudioObjectID> = []
  private static var outputAddress: AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(
      mSelector: kAudioProcessPropertyIsRunningOutput,
      mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
  }

  /// Listens for each process known to Core Audio starting or stopping
  /// its output, and no longer for those that have gone.
  private static func watchOutputs(of processes: Set<AudioObjectID>) {
    var address = outputAddress
    for gone in watched.subtracting(processes) {
      AudioObjectRemovePropertyListenerBlock(gone, &address, .main, listener)
    }
    for new in processes.subtracting(watched) {
      AudioObjectAddPropertyListenerBlock(new, &address, .main, listener)
    }
    watched = processes
  }

  /// Has `changed` called as a process comes to or leaves Core Audio, or
  /// starts or stops playing, or with nil, no longer.
  static func onProcessesChange(_ changed: (@Sendable () -> Void)?) {
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioHardwarePropertyProcessObjectList,
      mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    let system = AudioObjectID(kAudioObjectSystemObject)
    if processesChanged != nil {
      AudioObjectRemovePropertyListenerBlock(system, &address, .main, listener)
    }
    processesChanged = changed
    if changed != nil {
      AudioObjectAddPropertyListenerBlock(system, &address, .main, listener)
    }
    watchOutputs(of: changed == nil ? [] : Set(allProcesses()))
  }

  /// The audio objects of every process known to Core Audio.
  private static func allProcesses() -> [AudioObjectID] {
    let system = AudioObjectID(kAudioObjectSystemObject)
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioHardwarePropertyProcessObjectList,
      mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else {
      return []
    }
    var processes = [AudioObjectID](
      repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
    guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &processes) == noErr else {
      return []
    }
    return processes
  }

  private static var dockApps: [NSRunningApplication] {
    NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
  }

  /// Whether `filter` leaves out the process `pid`, which plays for `app`.
  private static func leavesOut(_ filter: AudioFilter, pid: pid_t, app: NSRunningApplication?)
    -> Bool
  {
    if filter.appsOnly, app == nil { return true }
    let own = NSRunningApplication(processIdentifier: pid)
    let names = [
      own?.bundleIdentifier, own?.localizedName, app?.bundleIdentifier, app?.localizedName,
    ].compactMap { $0?.lowercased() }
    return filter.excluded.contains { names.contains($0.lowercased()) }
  }

  /// Whether a process `filter` doesn't leave out is sending sound to an
  /// output.
  static func isOutputting(within filter: AudioFilter) -> Bool {
    let apps = dockApps
    return outputtingProcesses().contains { process in
      guard let pid = property(process, kAudioProcessPropertyPID, pid_t(0)) else { return false }
      return !leavesOut(filter, pid: pid, app: app(of: process, among: apps))
    }
  }

  /// The audio objects of the processes whose sound `filter` leaves out.
  static func processes(outside filter: AudioFilter) -> [AudioObjectID] {
    let apps = dockApps
    return allProcesses().filter { process in
      guard let pid = property(process, kAudioProcessPropertyPID, pid_t(0)) else { return false }
      return leavesOut(filter, pid: pid, app: app(of: process, among: apps))
    }.sorted()
  }

  private static func property<T>(
    _ object: AudioObjectID, _ selector: AudioObjectPropertySelector, _ initial: T
  ) -> T? {
    var address = AudioObjectPropertyAddress(
      mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain)
    var size = UInt32(MemoryLayout<T>.size)
    var value = initial
    let status = withUnsafeMutablePointer(to: &value) {
      AudioObjectGetPropertyData(object, &address, 0, nil, &size, $0)
    }
    return status == noErr ? value : nil
  }

  /// The audio objects of the processes sending sound to an output.
  private static func outputtingProcesses() -> [AudioObjectID] {
    allProcesses().filter { property($0, kAudioProcessPropertyIsRunningOutput, UInt32(0)) == 1 }
  }

  /// The process that started `pid`, or nil when it can't be told.
  private static func parent(of pid: pid_t) -> pid_t? {
    var info = proc_bsdinfo()
    let size = Int32(MemoryLayout<proc_bsdinfo>.size)
    guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size, info.pbi_ppid > 1 else {
      return nil
    }
    return pid_t(info.pbi_ppid)
  }

  /// The app in the Dock that the audio process `process` plays for: the
  /// process itself, the app that started it, as a browser starts its
  /// helpers, or the app whose bundle identifier begins its own.
  static func app(of process: AudioObjectID, among running: [NSRunningApplication])
    -> NSRunningApplication?
  {
    guard var pid = property(process, kAudioProcessPropertyPID, pid_t(0)) else { return nil }
    let helper =
      (property(process, kAudioProcessPropertyBundleID, "" as CFString) as String?)
      ?? NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
    // A helper may itself be started by a helper.
    for _ in 0..<4 {
      if let app = running.first(where: { $0.processIdentifier == pid }) { return app }
      guard let started = parent(of: pid) else { break }
      pid = started
    }
    guard let helper, !helper.isEmpty else { return nil }
    return running.first {
      $0.bundleIdentifier.map { helper.lowercased().hasPrefix($0.lowercased() + ".") } ?? false
    }
  }

  /// The app whose sound is loudest at the moment, of those sending any to
  /// an output that `filter` doesn't leave out. Listens to each for a
  /// moment when there are several.
  static func loudest(of filter: AudioFilter) -> NSRunningApplication? {
    let running = dockApps
    var sources: [(app: NSRunningApplication, processes: [AudioObjectID])] = []
    for process in outputtingProcesses() {
      guard let pid = property(process, kAudioProcessPropertyPID, pid_t(0)),
        let app = app(of: process, among: running), !leavesOut(filter, pid: pid, app: app)
      else { continue }
      if let known = sources.firstIndex(where: { $0.app == app }) {
        sources[known].processes.append(process)
      } else {
        sources.append((app, [process]))
      }
    }
    guard sources.count > 1 else { return sources.first?.app }

    let taps = sources.map { source -> AudioTap? in
      let tap = AudioTap()
      return tap.start(processes: source.processes) ? tap : nil
    }
    Thread.sleep(forTimeInterval: 0.3)
    let peaks = taps.map { $0.map { AudioAnalysis.peak($0.latest(AudioTap.capacity)) } ?? 0 }
    taps.forEach { $0?.stop() }
    return zip(sources, peaks).max { $0.1 < $1.1 }?.0.app
  }
}
