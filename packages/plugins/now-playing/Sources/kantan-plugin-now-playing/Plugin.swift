import AppKit
import Foundation

// MARK: - Settings

/// A part of the module that a state shows or leaves out.
enum Part: String, Decodable, CaseIterable {
  case icon
  case artist
  case title
  case album
  /// The text the `format` setting writes.
  case text
}

/// The parts the module shows in each state. A state showing none takes
/// the module out of the bar.
struct Show: Decodable, Equatable {
  var playing: [Part] = [.icon, .text]
  var paused: [Part] = [.icon, .text]
  /// While a live stream plays. Unset, it is what `playing` shows.
  var live: [Part]?
  /// While no player has anything loaded.
  var stopped: [Part] = []
  /// The parts added while the pointer is over a module whose hover reveals.
  var hover: [Part] = []

  private enum CodingKeys: String, CodingKey {
    case playing, paused, live, stopped, hover
  }

  init() {}

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    // The parts a state lists, leaving out any that aren't parts.
    let parts = { (key: CodingKeys) in
      container.setting([String].self, forKey: key)?.compactMap(Part.init(rawValue:))
    }
    playing = parts(.playing) ?? playing
    paused = parts(.paused) ?? paused
    live = parts(.live)
    stopped = parts(.stopped) ?? stopped
    hover = parts(.hover) ?? hover
  }
}

/// An app's own icon and the colour it is drawn in, either left out for
/// the module's. Written as the icon alone, or as `icon` and `fg`.
struct AppIcon: Decodable, Equatable {
  var icon: String?
  var fg: String?

  private enum CodingKeys: String, CodingKey {
    case icon, fg
  }

  init(icon: String? = nil, fg: String? = nil) {
    self.icon = icon
    self.fg = fg
  }

  init(from decoder: Decoder) throws {
    if let icon = try? decoder.singleValueContainer().decode(String.self) {
      self.init(icon: icon)
    } else {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      self.init(
        icon: container.setting(String.self, forKey: .icon),
        fg: container.setting(String.self, forKey: .fg))
    }
  }
}

/// The colours of the popup's own marks.
struct Colors: Decodable, Equatable {
  /// The dot beside `LIVE` while a live stream shows.
  var live = "red"

  private enum CodingKeys: String, CodingKey {
    case live
  }

  init() {}

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    live = container.setting(String.self, forKey: .live) ?? live
  }
}

struct Settings: Decodable {
  /// What the `text` part writes.
  var format: Format
  /// The most characters of text in the bar; 0 sets no limit. Text over
  /// it loses the parts `drop` lists, one at a time, and is then cut short.
  var maxChars: Int
  /// The parts left out of text longer than `maxChars`, the first to go
  /// first.
  var drop: [Part]
  var show: Show
  /// The icon for an app without one in `icons`.
  var icon: String
  /// The icon for each app, and its colour, by the app's name or bundle
  /// identifier.
  var icons: [String: AppIcon]
  /// What goes between the artist, title and album parts.
  var separator: String
  /// The apps whose playing is never shown, by name or bundle identifier.
  var exclude: [String]
  var colors: Colors

  /// The artist, when there is one, then the title.
  static let defaultFormat = Format.segments([
    Format.Segment(text: "{artist} · ", fg: nil, when: "artist"),
    Format.Segment(text: "{title}", fg: nil, when: nil),
  ])

  private enum CodingKeys: String, CodingKey {
    case format, maxChars, drop, show, icon, icons, separator, exclude, colors
  }

  init() {
    self.format = Self.defaultFormat
    self.maxChars = 40
    self.drop = [.album, .artist]
    self.show = Show()
    self.icon = "music"
    self.icons = [:]
    self.separator = " · "
    self.exclude = []
    self.colors = Colors()
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.format = container.setting(Format.self, forKey: .format) ?? Self.defaultFormat
    self.maxChars = container.setting(Int.self, forKey: .maxChars) ?? 40
    self.drop =
      container.setting([String].self, forKey: .drop)?.compactMap(Part.init(rawValue:))
      ?? [.album, .artist]
    self.show = container.setting(Show.self, forKey: .show) ?? Show()
    self.icon = container.setting(String.self, forKey: .icon) ?? "music"
    self.icons = container.setting([String: AppIcon].self, forKey: .icons) ?? [:]
    self.separator = container.setting(String.self, forKey: .separator) ?? " · "
    self.exclude = container.setting([String].self, forKey: .exclude) ?? []
    self.colors = container.setting(Colors.self, forKey: .colors) ?? Colors()
  }

  /// What `icons` gives the app `source`, by its name or bundle
  /// identifier, whatever their case.
  private func entry(for source: Source?) -> AppIcon? {
    guard let source else { return nil }
    let names = [source.name.lowercased(), source.bundle.lowercased()]
    return icons.first { names.contains($0.key.lowercased()) }?.value
  }

  /// The icon for the app `source`: its own, or the default.
  func icon(for source: Source?) -> String {
    entry(for: source)?.icon ?? icon
  }

  /// The colour of the icon while the app `source` plays, or nil for the
  /// module's.
  func iconColor(for source: Source?) -> String? {
    entry(for: source)?.fg
  }
}

// MARK: - Track

/// What is playing, as the host reads it from MediaRemote.
struct Track: Decodable, Equatable, Sendable {
  var title: String?
  var artist: String?
  var album: String?
  var duration: Double?
  /// The position, in seconds, at `timestamp`.
  var elapsed: Double?
  /// When `elapsed` was read, in seconds since 1970.
  var timestamp: Double?
  /// How fast it plays: 0 while paused. It follows a change of `playing`
  /// when the app playing updates it, which may be a moment later.
  var rate: Double?
  /// Whether it is playing, which changes the moment playback does.
  var playing: Bool?
  /// The artwork's bytes in Base64, in the updates that carry them.
  var artwork: String?
  var artworkType: String?
  var pid: Int32?
  /// The bundle identifier of the program playing, and that of the app it
  /// plays for when it is a helper.
  var bundle: String?
  var parentBundle: String?
  /// The name the program playing goes by.
  var name: String?
  /// Whether macOS counts this player as the one playing now.
  var current: Bool?
  /// Whether the player takes a position to move to, when macOS tells.
  var seekable: Bool?
  /// Whether it is a live stream, whose duration has no end.
  var live: Bool?
  /// When it last played, in seconds since 1970: now, while it plays.
  var lastPlayed: Double?

  /// What tells the player apart from the others.
  var key: String { bundle ?? name ?? "" }

  var isPlaying: Bool { playing ?? ((rate ?? 0) > 0) }
  var isLive: Bool { live == true }

  /// The position at `now`, in seconds, within the track's duration. It
  /// keeps time only once the rate says it plays too, as until then
  /// `elapsed` and `timestamp` are from before playback began.
  func position(at now: Date) -> Double {
    var position = elapsed ?? 0
    if isPlaying, (rate ?? 0) > 0, let timestamp {
      position += max(0, now.timeIntervalSince1970 - timestamp) * (rate ?? 1)
    }
    return max(0, duration.map { min(position, $0) } ?? position)
  }

  /// Whether `names`, apps by name or bundle identifier in any case,
  /// hold the app this plays from.
  func plays(fromOneOf names: [String]) -> Bool {
    let own = [bundle, parentBundle, name].compactMap { $0?.lowercased() }
    return names.contains { own.contains($0.lowercased()) }
  }

  /// Every player's track in the host's line of JSON.
  static func players(in line: Data) -> [Track] {
    struct Line: Decodable { var players: [Track] }
    return (try? JSONDecoder().decode(Line.self, from: line))?.players ?? []
  }

  /// The players of `players` with a track loaded, passing over apps
  /// among `excluded`.
  static func loaded(of players: [Track], excluding excluded: [String]) -> [Track] {
    players.filter { !($0.title ?? "").isEmpty && !$0.plays(fromOneOf: excluded) }
  }

  /// The track to show of `players`, or nil while none has anything
  /// loaded: the player `pinned` names, while it has a track, or else one
  /// playing before one that isn't, and of those, the one whose playing most
  /// recently started or stopped, by `changed`, the times of those changes
  /// by each player's key, or when it last played. Of players as recent, the
  /// one macOS counts as playing now comes first. Apps among `excluded` are
  /// passed over.
  static func shown(
    of players: [Track], excluding excluded: [String], changed: [String: Double] = [:],
    pinned: String? = nil
  ) -> Track? {
    let loaded = loaded(of: players, excluding: excluded)
    if let pinned, let track = loaded.first(where: { $0.key == pinned }) { return track }
    let rank = { (track: Track) in
      (
        track.isPlaying ? 1 : 0, changed[track.key] ?? track.lastPlayed ?? 0,
        track.current == true ? 1 : 0
      )
    }
    return loaded.max { rank($0) < rank($1) }
  }
}

/// A player picked in the popup, by its key, and when, in seconds since 1970.
struct Pin: Codable, Equatable {
  var player: String
  var at: Double
}

/// Which player the module shows, kept as the host reports each change: the
/// one picked in the popup, until it stops or another starts playing, or
/// else the one playing that started last, or with none playing, the one
/// that stopped last.
struct Selection {
  var pin: Pin?
  /// When each player's playing last started or stopped, by its key.
  private(set) var changed: [String: Double] = [:]
  private var wasPlaying: [String: Bool] = [:]

  /// Notes `players` as reported at `now`, and returns the keys of those
  /// that started or stopped playing since the last report. A player seen
  /// for the first time changed when it last played, or now when it plays.
  /// The pin goes when its player stops playing or has no track, or another
  /// player starts playing.
  @discardableResult
  mutating func note(_ players: [Track], excluding excluded: [String], at now: Double)
    -> [String]
  {
    let loaded = Track.loaded(of: players, excluding: excluded)
    var playing: [String: Bool] = [:]
    var switched: [String] = []
    for track in loaded {
      playing[track.key] = track.isPlaying
      if let was = wasPlaying[track.key] {
        guard was != track.isPlaying else { continue }
        changed[track.key] = now
        switched.append(track.key)
        // The pinned player stopping, or another starting, ends the pin.
        if let pin, now > pin.at, pin.player == track.key ? !track.isPlaying : track.isPlaying {
          self.pin = nil
        }
      } else {
        changed[track.key] = track.isPlaying ? now : track.lastPlayed ?? 0
      }
    }
    wasPlaying = playing
    changed = changed.filter { playing[$0.key] != nil }
    if let pin, playing[pin.player] == nil { self.pin = nil }
    return switched
  }

  /// The track to show of `players`.
  func shown(of players: [Track], excluding excluded: [String]) -> Track? {
    Track.shown(of: players, excluding: excluded, changed: changed, pinned: pin?.player)
  }
}

/// The pin and the player the watch shows, kept in files, so the popup can
/// pin a player and the plugin's commands act on the one that shows.
struct SelectionStore {
  let directory: URL

  static var standard: SelectionStore {
    let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
    return SelectionStore(directory: caches.appendingPathComponent("kantan/now-playing-selection"))
  }

  private var pinFile: URL { directory.appendingPathComponent("pin.json") }
  private var shownFile: URL { directory.appendingPathComponent("shown") }

  var pin: Pin? {
    (try? Data(contentsOf: pinFile)).flatMap { try? JSONDecoder().decode(Pin.self, from: $0) }
  }

  /// The key of the player the watch shows.
  var shown: String? {
    (try? String(contentsOf: shownFile, encoding: .utf8)).flatMap { $0.isEmpty ? nil : $0 }
  }

  func save(pin: Pin?) {
    if let pin {
      write(try? JSONEncoder().encode(pin), to: pinFile)
    } else {
      try? FileManager.default.removeItem(at: pinFile)
    }
  }

  func save(shown: String?) {
    write(Data((shown ?? "").utf8), to: shownFile)
  }

  private func write(_ data: Data?, to file: URL) {
    guard let data else { return }
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try? data.write(to: file, options: .atomic)
  }
}

/// The app a track plays from.
struct Source: Equatable {
  var name: String
  var bundle: String
}

// MARK: - Helpers

/// `seconds` as minutes and seconds, such as `3:07`, with hours from an hour.
/// A time outside 0 to 99:59:59, or that isn't a number, is held to it.
func clockTime(_ seconds: Double) -> String {
  let total = seconds.isNaN ? 0 : Int(min(max(seconds, 0), 359_999).rounded(.down))
  let (hours, minutes, secs) = (total / 3600, total / 60 % 60, total % 60)
  let padded = { (number: Int) in number < 10 ? "0\(number)" : "\(number)" }
  return hours > 0 ? "\(hours):\(padded(minutes)):\(padded(secs))" : "\(minutes):\(padded(secs))"
}

/// FNV-1a over `bytes`, in hexadecimal.
func fingerprint(_ bytes: some Sequence<UInt8>) -> String {
  var hash: UInt64 = 0xcbf2_9ce4_8422_2325
  for byte in bytes {
    hash = (hash ^ UInt64(byte)) &* 0x100_0000_01b3
  }
  return String(hash, radix: 16)
}

// MARK: - Artwork

/// Keeps the playing track's artwork in a file the popup's image loads.
/// MediaRemote sends the artwork with only some of a track's updates, so
/// the file is named for its track and found again for the others.
struct ArtworkCache {
  let directory: URL

  static var standard: ArtworkCache {
    let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
    return ArtworkCache(directory: caches.appendingPathComponent("kantan/now-playing"))
  }

  /// The file holding `track`'s artwork, written from the track when it
  /// carries artwork, or nil when none has arrived for it.
  func file(for track: Track) -> URL? {
    let files = FileManager.default
    let key = fingerprint("\(track.title ?? "")\n\(track.artist ?? "")\n\(track.album ?? "")".utf8)
    let stored = (try? files.contentsOfDirectory(atPath: directory.path)) ?? []
    guard let artwork = track.artwork.flatMap({ Data(base64Encoded: $0) }), !artwork.isEmpty else {
      return stored.first { $0.hasPrefix("\(key)-") }.map(directory.appendingPathComponent)
    }
    let type = track.artworkType == "image/png" ? "png" : "jpg"
    let name = "\(key)-\(fingerprint(artwork)).\(type)"
    if !stored.contains(name) {
      try? files.createDirectory(at: directory, withIntermediateDirectories: true)
      guard
        (try? artwork.write(to: directory.appendingPathComponent(name), options: .atomic)) != nil
      else { return nil }
    }
    for other in stored where other != name {
      try? files.removeItem(at: directory.appendingPathComponent(other))
    }
    return directory.appendingPathComponent(name)
  }
}

// MARK: - Source App

/// The running app `track` plays from: the one a helper plays for, the
/// program itself, or the app whose bundle identifier begins the helper's,
/// as a browser's does its helpers'.
@MainActor
func sourceApp(of track: Track) -> Source? {
  let running = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
  let own =
    track.bundle
    ?? track.pid.flatMap { NSRunningApplication(processIdentifier: $0) }?
    .bundleIdentifier
  let app =
    [track.parentBundle, own].compactMap { $0 }.lazy
    .compactMap { bundle in running.first { $0.bundleIdentifier == bundle } }.first
    ?? own.flatMap { helper in
      running.first {
        $0.bundleIdentifier.map { helper.lowercased().hasPrefix($0.lowercased() + ".") } ?? false
      }
    }
  guard let app, let bundle = app.bundleIdentifier else { return nil }
  return Source(name: app.localizedName ?? track.name ?? "", bundle: bundle)
}

// MARK: - Rendering

let plugin = "kantan-plugin-now-playing"

/// The commands the popup's controls run.
let previousCommand = "\(plugin) --previous"
let toggleCommand = "\(plugin) --toggle"
let nextCommand = "\(plugin) --next"
let openCommand = "\(plugin) --open"
/// Moves the track to where its position bar was clicked or dragged to.
let seekCommand = "\(plugin) --seek {value}"

/// Pins the player with the key `player`, so the module shows it.
func selectCommand(_ player: String) -> String {
  "\(plugin) --select \(shellQuote(player))"
}

/// A player the popup's switcher offers, by its key, with its icon and the
/// icon's colour.
struct Choice: Equatable {
  var player: String
  var icon: String
  var color: String?
}

/// The length of the text `segments` show before a hover.
func restingLength(_ segments: [ValueSegment]) -> Int {
  segments.reduce(0) { $0 + ($1.reveal == true ? 0 : $1.text.count) }
}

/// `segments` with the text they show before a hover cut to `maxChars`
/// characters, ending in an ellipsis, or as they are when it fits or
/// `maxChars` is 0. Segments that wait for a hover are kept whole.
func truncated(_ segments: [ValueSegment], maxChars: Int) -> [ValueSegment] {
  guard maxChars > 0, restingLength(segments) > maxChars else { return segments }
  var room = maxChars
  var kept: [ValueSegment] = []
  for segment in segments {
    if segment.reveal == true {
      kept.append(segment)
    } else if segment.text.count <= room {
      kept.append(segment)
      room -= segment.text.count
    } else if room >= 0 {
      let cut = String(segment.text.prefix(room)).trimmingCharacters(in: .whitespaces) + "..."
      kept.append(ValueSegment(text: cut, fg: segment.fg))
      room = -1
    }
  }
  return kept
}

/// The module's icon and text for a state that shows the parts `shown`,
/// with the parts `hover` adds marked to wait for a hover: the icon when it
/// is a part, the output's `reveal` marks, the value and its segments. The
/// artist, title and album are joined by the separator, which waits with a
/// part that does.
///
/// The `maxChars` setting limits the text shown before a hover. Text over
/// it loses the parts the `drop` setting lists, one at a time until it
/// fits, and is then cut short. A part it loses that `hover` lists waits
/// for the hover instead, which shows every part whatever the length.
func barContent(
  showing shown: [Part], hover: [Part], variables: [String: String],
  source: Source?, settings: Settings
) -> (icon: String?, reveal: [String], value: String, segments: [ValueSegment]) {
  var resting = shown
  var revealed: [Part] { hover.filter { !resting.contains($0) } }
  let waits = { (part: Part) in revealed.contains(part) ? true : nil as Bool? }

  /// The text of `parts`, in their order.
  func written(_ parts: [Part]) -> [ValueSegment] {
    var segments: [ValueSegment] = []
    for part in parts {
      switch part {
      case .icon:
        continue
      case .artist, .title, .album:
        let text = variables[part.rawValue] ?? ""
        guard !text.isEmpty else { continue }
        // The separator before a part waits when the part does, or the
        // one before it does.
        if let previous = segments.last {
          let joined = ValueSegment(
            text: settings.separator, fg: nil, reveal: waits(part) ?? previous.reveal)
          segments.append(joined)
        }
        segments.append(ValueSegment(text: text, fg: nil, reveal: waits(part)))
      case .text:
        let text = settings.format.apply(variables)
        let pieces = text.segments ?? [ValueSegment(text: text.value, fg: nil)]
        segments += pieces.filter { !$0.text.isEmpty }.map {
          ValueSegment(text: $0.text, fg: $0.fg, reveal: waits(.text) ?? $0.reveal)
        }
      }
    }
    return segments
  }

  /// The text of the resting and the revealed parts together.
  func text() -> [ValueSegment] {
    written(Part.allCases.filter { resting.contains($0) || revealed.contains($0) })
  }

  var segments = text()
  for dropped in settings.drop
  where dropped != .icon && settings.maxChars > 0 && restingLength(segments) > settings.maxChars {
    resting.removeAll { $0 == dropped }
    segments = text()
  }
  segments = truncated(segments, maxChars: settings.maxChars)
  let showsIcon = resting.contains(.icon) || revealed.contains(.icon)

  return (
    showsIcon ? settings.icon(for: source) : nil,
    // Always given, as an output without it has its text wait for a hover.
    showsIcon && revealed.contains(.icon) ? ["icon"] : [],
    segments.map(\.text).joined(), segments
  )
}

/// The module for `track` at `now`: the parts its state shows, its
/// variables, and the popup showing `artwork` and the controls.
func render(
  track: Track?, artwork: URL?, source: Source?, settings: Settings, now: Date,
  choices: [Choice] = []
) -> PluginOutput {
  guard let track else {
    let bar = barContent(
      showing: settings.show.stopped, hover: [], variables: [:], source: nil,
      settings: settings)
    return PluginOutput(
      value: "", icon: bar.icon, hidden: settings.show.stopped.isEmpty, active: false,
      variables: ["state": "Stopped"],
      view: vstack(
        padding: .int(14), children: [text("Nothing is playing", style: "secondary")]))
  }

  // A live stream has no length to be a position in.
  let position = track.position(at: now)
  let duration = track.isLive ? 0 : track.duration ?? 0
  let state = !track.isPlaying ? "Paused" : track.isLive ? "Live" : "Playing"
  var variables = [
    "title": track.title ?? "",
    "artist": track.artist ?? "",
    "album": track.album ?? "",
    "app": source?.name ?? "",
    "state": state,
    "elapsed": track.isLive ? "" : clockTime(position),
    "duration": duration > 0 ? clockTime(duration) : "",
  ]
  let shown =
    switch state {
    case "Paused": settings.show.paused
    case "Live": settings.show.live ?? settings.show.playing
    default: settings.show.playing
    }
  let bar = barContent(
    showing: shown, hover: settings.show.hover, variables: variables, source: source,
    settings: settings)
  variables["artwork"] = artwork?.absoluteString ?? ""

  let cover =
    artwork.map { image(url: $0.absoluteString, width: 48, height: 48, cornerRadius: 8) }
    ?? zstack(children: [
      rect(width: 48, height: 48, color: "accent", cornerRadius: 8),
      icon("music", size: 22, color: "white"),
    ])
  // The track's text is given as variables, which kantan writes as they are.
  var details = [text("{title}", weight: "semibold")]
  for line in ["artist", "album"] where !variables[line]!.isEmpty {
    details.append(text("{\(line)}", size: 11, style: "secondary"))
  }
  var rows: [JSONValue] = []
  // With more than one player holding a track, a switcher picks the one shown.
  if choices.count > 1 {
    let buttons = choices.map { choice in
      button(
        icon: choice.icon, command: selectCommand(choice.player),
        style: choice.player == track.key ? "bordered" : "borderless", color: choice.color,
        dismiss: false)
    }
    rows.append(hstack(spacing: 4, children: [spacer()] + buttons + [spacer()]))
  }
  rows.append(
    hstack(
      spacing: 12, command: openCommand,
      children: [cover, vstack(spacing: 2, alignment: "leading", children: details), spacer()]))
  if track.isLive {
    rows.append(
      hstack(
        spacing: 5,
        children: [
          spacer(), circle(size: 7, color: settings.colors.live),
          text("LIVE", size: 10, weight: "semibold", style: "secondary"), spacer(),
        ]))
  } else if duration > 0 {
    rows += [
      progress(
        value: position / duration, color: "accent",
        command: track.seekable == false ? nil : seekCommand),
      hstack(children: [
        text(variables["elapsed"]!, size: 10, style: "secondary"), spacer(),
        text(variables["duration"]!, size: 10, style: "secondary"),
      ]),
    ]
  }
  // A live stream has no track before or after it to skip to.
  let toggle = button(
    icon: track.isPlaying ? "player-pause" : "player-play", command: toggleCommand,
    style: "bordered", dismiss: false)
  let controls =
    track.isLive
    ? [toggle]
    : [
      button(
        icon: "player-skip-back", command: previousCommand, style: "borderless", dismiss: false),
      toggle,
      button(
        icon: "player-skip-forward", command: nextCommand, style: "borderless", dismiss: false),
    ]
  rows.append(hstack(spacing: 6, children: [spacer()] + controls + [spacer()]))

  return PluginOutput(
    value: bar.value, segments: bar.segments, icon: bar.icon, hidden: shown.isEmpty,
    active: track.isPlaying, reveal: bar.reveal, variables: variables,
    view: vstack(spacing: 10, padding: .int(14), frame: .object(["w": .int(250)]), children: rows),
    style: settings.iconColor(for: source).map { .object(["icon": .object(["fg": .string($0)])]) })
}

// MARK: - Host

/// The MediaRemote commands the plugin sends.
enum PlayerCommand: UInt32 {
  case toggle = 2
  case next = 4
  case previous = 5
}

/// Loads the library at `$ARGV[0]` and calls its entry point.
private let hostScript = """
  my $library = DynaLoader::dl_load_file($ARGV[0]) or die DynaLoader::dl_error();
  my $entry = DynaLoader::dl_find_symbol($library, "kantan_now_playing_host") or die "no entry point";
  DynaLoader::dl_install_xsub("main::host", $entry);
  main::host();
  """

/// The host library: beside the plugin as Swift builds it, or in the
/// plugin's share directory as it is installed.
func hostLibrary() -> URL? {
  guard
    let directory = Bundle.main.executableURL?.resolvingSymlinksInPath()
      .deletingLastPathComponent()
  else { return nil }
  let name = "libKantanNowPlayingHost.dylib"
  return [
    directory.appendingPathComponent(name),
    directory.appendingPathComponent("../share/\(plugin)/\(name)").standardizedFileURL,
  ].first { FileManager.default.fileExists(atPath: $0.path) }
}

/// The host, ready to run with `arguments`, or nil without its library.
func hostProcess(_ arguments: [String]) -> Process? {
  guard let library = hostLibrary() else { return nil }
  let process = Process()
  process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
  process.arguments = ["-MDynaLoader", "-e", hostScript, "--", library.path] + arguments
  process.standardError = FileHandle.nullDevice
  return process
}

/// The track to show now, read by running the host once: the one the watch
/// shows, when it still has a track, so commands act on what the popup shows.
func currentTrack(excluding excluded: [String]) -> Track? {
  guard let host = hostProcess(["once"]) else { return nil }
  let output = Pipe()
  host.standardInput = FileHandle.nullDevice
  host.standardOutput = output
  guard (try? host.run()) != nil else { return nil }
  DispatchQueue.global().asyncAfter(deadline: .now() + 3) { host.terminate() }
  let players = Track.players(in: output.fileHandleForReading.readDataToEndOfFile())
  let store = SelectionStore.standard
  if let shown = store.shown,
    let track = Track.loaded(of: players, excluding: excluded).first(where: { $0.key == shown })
  {
    return track
  }
  return Track.shown(of: players, excluding: excluded, pinned: store.pin?.player)
}

/// Pins the player with the key `player`, which the watch then shows.
func select(_ player: String) -> Int32 {
  SelectionStore.standard.save(pin: Pin(player: player, at: Date().timeIntervalSince1970))
  return 0
}

/// Sends `command` to the player whose track is shown.
func send(_ command: PlayerCommand, settings: Settings) -> Int32 {
  let player = currentTrack(excluding: settings.exclude)?.bundle
  return runHost(["command", String(command.rawValue)] + (player.map { [$0] } ?? []))
}

/// Moves the track shown to `fraction` of the way through it, from 0 to 1.
func seek(to fraction: Double, settings: Settings) -> Int32 {
  guard let track = currentTrack(excluding: settings.exclude), let duration = track.duration,
    duration > 0
  else { return 1 }
  let position = min(max(fraction, 0), 1) * duration
  return runHost(["seek", String(position)] + (track.bundle.map { [$0] } ?? []))
}

/// Runs the host with `arguments` until it exits, or for 3 seconds at
/// most, and returns its status.
private func runHost(_ arguments: [String]) -> Int32 {
  guard let host = hostProcess(arguments) else { return 1 }
  host.standardInput = FileHandle.nullDevice
  host.standardOutput = FileHandle.nullDevice
  guard (try? host.run()) != nil else { return 1 }
  DispatchQueue.global().asyncAfter(deadline: .now() + 3) { host.terminate() }
  host.waitUntilExit()
  return host.terminationStatus
}

/// Brings the app whose track is shown to the front.
@MainActor
func openSource(settings: Settings) -> Int32 {
  guard let source = currentTrack(excluding: settings.exclude).flatMap(sourceApp) else {
    return 1
  }
  let open = Process()
  open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
  open.arguments = ["-b", source.bundle]
  guard (try? open.run()) != nil else { return 1 }
  open.waitUntilExit()
  return open.terminationStatus
}

// MARK: - Watch

/// The lines of the host's output, gathered from the chunks it arrives in.
private final class HostLines: @unchecked Sendable {
  private let lock = NSLock()
  private var partial = Data()

  func append(_ output: Data) -> [Data] {
    lock.lock()
    defer { lock.unlock() }
    partial.append(output)
    var lines: [Data] = []
    while let newline = partial.firstIndex(of: UInt8(ascii: "\n")) {
      lines.append(partial[..<newline])
      partial = partial[partial.index(after: newline)...]
    }
    return lines
  }
}

/// Shows what is playing as the host reports each change, and every second
/// while it plays, so the popup's position keeps time.
@MainActor
final class NowPlayingWatch {
  private let settings: Settings
  private let output = WatchOutput()
  private let cache = ArtworkCache.standard
  private let store = SelectionStore.standard
  /// The players the host last reported.
  private var players: [Track] = []
  private var selection = Selection()
  private var track: Track?
  /// Watches the store's directory for a pin made in the popup.
  private var pins: DispatchSourceFileSystemObject?
  /// The host's exits since it last wrote a line.
  private var failures = 0

  init(settings: Settings) {
    self.settings = settings
  }

  /// Notes the players the host reported, then shows the one chosen. When a
  /// player has started or stopped playing, the one now shown, while it
  /// plays, is made the one macOS counts as playing now, so the media keys
  /// and Control Centre follow it too.
  private func receive(_ players: [Track]) {
    self.players = players
    let switched = selection.note(
      players, excluding: settings.exclude, at: Date().timeIntervalSince1970)
    if selection.pin != store.pin { store.save(pin: selection.pin) }
    choose()
    if !switched.isEmpty, let track, track.isPlaying, track.current != true,
      let bundle = track.bundle
    {
      let host = hostProcess(["current", bundle])
      host?.standardInput = FileHandle.nullDevice
      host?.standardOutput = FileHandle.nullDevice
      try? host?.run()
    }
  }

  /// Chooses the track to show, keeps which it is for the plugin's
  /// commands, and shows it.
  private func choose() {
    track = selection.shown(of: players, excluding: settings.exclude)
    if store.shown != track?.key { store.save(shown: track?.key) }
    show()
  }

  private func show() {
    let choices = Track.loaded(of: players, excluding: settings.exclude)
      .sorted { ($0.name ?? $0.key).lowercased() < ($1.name ?? $1.key).lowercased() }
      .map { player in
        let source = sourceApp(of: player)
        return Choice(
          player: player.key, icon: settings.icon(for: source),
          color: settings.iconColor(for: source))
      }
    output.show(
      render(
        track: track, artwork: track.flatMap(cache.file), source: track.flatMap(sourceApp),
        settings: settings, now: Date(), choices: choices))
  }

  /// Shows the player pinned in the popup as soon as the pin is written.
  private func watchPins() {
    try? FileManager.default.createDirectory(
      at: store.directory, withIntermediateDirectories: true)
    let descriptor = open(store.directory.path, O_EVTONLY)
    guard descriptor >= 0 else { return }
    let source = DispatchSource.makeFileSystemObjectSource(
      fileDescriptor: descriptor, eventMask: .write, queue: .main)
    source.setEventHandler {
      MainActor.assumeIsolated {
        let pin = self.store.pin
        guard pin != self.selection.pin else { return }
        self.selection.pin = pin
        self.choose()
      }
    }
    source.setCancelHandler { close(descriptor) }
    source.resume()
    pins = source
  }

  /// Runs the host, starting it again when it exits: after a second at
  /// first, doubling to a minute while it keeps exiting without output.
  private func launch() {
    let lines = HostLines()
    let stdout = Pipe()
    guard let host = hostProcess(["stream"]) else { return show() }
    // The host exits when its stdin closes, as it does when the plugin exits.
    host.standardInput = Pipe()
    host.standardOutput = stdout
    stdout.fileHandleForReading.readabilityHandler = { handle in
      let received = lines.append(handle.availableData).map(Track.players)
      guard let players = received.last else { return }
      DispatchQueue.main.async {
        MainActor.assumeIsolated {
          self.failures = 0
          self.receive(players)
        }
      }
    }
    host.terminationHandler = { _ in
      stdout.fileHandleForReading.readabilityHandler = nil
      DispatchQueue.main.async {
        MainActor.assumeIsolated {
          self.players = []
          self.track = nil
          self.show()
          self.failures += 1
          let delay = TimeInterval(1 << min(self.failures - 1, 6))
          DispatchQueue.main.asyncAfter(deadline: .now() + min(delay, 60)) {
            MainActor.assumeIsolated { self.launch() }
          }
        }
      }
    }
    if (try? host.run()) == nil { host.terminationHandler?(host) }
  }

  func run() -> Never {
    selection.pin = store.pin
    watchPins()
    launch()
    let seconds = Timer(timeInterval: 1, repeats: true) { _ in
      MainActor.assumeIsolated {
        if self.track?.isPlaying == true { self.show() }
      }
    }
    RunLoop.main.add(seconds, forMode: .common)
    exitWhenStdinCloses()
    RunLoop.main.run()
    exit(0)
  }
}

// MARK: - Entry Point

@MainActor
func main() -> Int32 {
  let settings = loadSettings(defaults: Settings())
  switch CommandLine.arguments.dropFirst().first {
  case "--watch":
    NowPlayingWatch(settings: settings).run()
  case "--toggle":
    return send(.toggle, settings: settings)
  case "--next":
    return send(.next, settings: settings)
  case "--previous":
    return send(.previous, settings: settings)
  case "--open":
    return openSource(settings: settings)
  case "--select":
    guard let player = CommandLine.arguments.dropFirst(2).first else {
      FileHandle.standardError.write(Data("\(plugin): --select takes a player\n".utf8))
      return 2
    }
    return select(player)
  case "--seek":
    guard let fraction = CommandLine.arguments.dropFirst(2).first.flatMap(Double.init) else {
      FileHandle.standardError.write(Data("\(plugin): --seek takes a number from 0 to 1\n".utf8))
      return 2
    }
    return seek(to: fraction, settings: settings)
  case nil:
    let track = currentTrack(excluding: settings.exclude)
    printJSON(
      render(
        track: track, artwork: track.flatMap(ArtworkCache.standard.file),
        source: track.flatMap(sourceApp), settings: settings, now: Date()))
    return 0
  case let argument?:
    FileHandle.standardError.write(Data("\(plugin): unknown argument '\(argument)'\n".utf8))
    return 2
  }
}
