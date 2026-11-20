import Foundation

// The part of the plugin that reads what is playing. macOS answers
// MediaRemote only for Apple's own programs, so the plugin loads this
// library into /usr/bin/perl and reads what it writes.

/// The MediaRemote functions the host calls, found by name.
private struct MediaRemote: Sendable {
  typealias GetInfo =
    @convention(c) (DispatchQueue, @escaping @convention(block) (CFDictionary?) -> Void) -> Void
  typealias GetPID =
    @convention(c) (DispatchQueue, @escaping @convention(block) (Int32) -> Void) -> Void
  typealias GetIsPlaying =
    @convention(c) (DispatchQueue, @escaping @convention(block) (Bool) -> Void) -> Void
  typealias Register = @convention(c) (DispatchQueue) -> Void
  typealias SendCommand = @convention(c) (UInt32, CFDictionary?) -> Bool
  typealias SetOverriddenApp = @convention(c) (CFString) -> Int32

  let getInfo: GetInfo
  let getPID: GetPID
  let getIsPlaying: GetIsPlaying
  let register: Register
  let sendCommand: SendCommand
  /// Makes the app with a bundle identifier the one macOS counts as playing
  /// now, or nil on a macOS without the function.
  let setOverriddenApp: SetOverriddenApp?

  init?() {
    let path = "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote"
    guard let framework = dlopen(path, RTLD_NOW),
      let getInfo = dlsym(framework, "MRMediaRemoteGetNowPlayingInfo"),
      let getPID = dlsym(framework, "MRMediaRemoteGetNowPlayingApplicationPID"),
      let getIsPlaying = dlsym(framework, "MRMediaRemoteGetNowPlayingApplicationIsPlaying"),
      let register = dlsym(framework, "MRMediaRemoteRegisterForNowPlayingNotifications"),
      let sendCommand = dlsym(framework, "MRMediaRemoteSendCommand")
    else { return nil }
    self.getInfo = unsafeBitCast(getInfo, to: GetInfo.self)
    self.getPID = unsafeBitCast(getPID, to: GetPID.self)
    self.getIsPlaying = unsafeBitCast(getIsPlaying, to: GetIsPlaying.self)
    self.register = unsafeBitCast(register, to: Register.self)
    self.sendCommand = unsafeBitCast(sendCommand, to: SendCommand.self)
    self.setOverriddenApp = dlsym(framework, "MRMediaRemoteSetOverriddenNowPlayingApplication")
      .map { unsafeBitCast($0, to: SetOverriddenApp.self) }
  }
}

/// The notifications MediaRemote posts when what any player is playing
/// changes, or the players themselves do.
private let changeNotifications = [
  "kMRMediaRemoteNowPlayingInfoDidChangeNotification",
  "kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification",
  "kMRMediaRemoteNowPlayingApplicationDidChangeNotification",
  "kMRMediaRemotePlayerIsPlayingDidChangeNotification",
  "kMRMediaRemotePlayerNowPlayingInfoDidChangeNotification",
  "kMRMediaRemotePlayerPlaybackStateDidChangeNotification",
  "kMRMediaRemoteActivePlayerPathsDidChange",
]

/// The key of the line the host writes for each key of MediaRemote's info.
private let infoKeys = [
  "kMRMediaRemoteNowPlayingInfoTitle": "title",
  "kMRMediaRemoteNowPlayingInfoArtist": "artist",
  "kMRMediaRemoteNowPlayingInfoAlbum": "album",
  "kMRMediaRemoteNowPlayingInfoDuration": "duration",
  "kMRMediaRemoteNowPlayingInfoElapsedTime": "elapsed",
  "kMRMediaRemoteNowPlayingInfoPlaybackRate": "rate",
  "kMRMediaRemoteNowPlayingInfoArtworkMIMEType": "artworkType",
]

/// The MediaRemote command that moves a player to a position in its track,
/// and the option that carries the position, in seconds.
private let seekCommand: UInt32 = 24
private let positionOption = "kMRMediaRemoteOptionPlaybackPosition"

/// What `info`, MediaRemote's info for a player, says of its track. A
/// number that isn't finite is left out, as the track has no such value. A
/// duration without end, as a live stream has, makes the track `live`.
private func track(from info: [String: Any]) -> [String: Any] {
  var track: [String: Any] = [:]
  for (key, name) in infoKeys {
    if let value = info[key] as? String {
      track[name] = value
    } else if let value = info[key] as? NSNumber {
      if value.doubleValue.isFinite {
        track[name] = value.doubleValue
      } else if name == "duration", value.doubleValue > 0 {
        track["live"] = true
      }
    }
  }
  if let timestamp = info["kMRMediaRemoteNowPlayingInfoTimestamp"] as? Date {
    track["timestamp"] = timestamp.timeIntervalSince1970
  }
  if let artwork = info["kMRMediaRemoteNowPlayingInfoArtworkData"] as? Data {
    track["artwork"] = artwork.base64EncodedString()
  }
  return track
}

/// The name, process and bundle identifiers of `client`, a program that
/// plays: its own, and that of the app it plays for when it is a helper,
/// such as a browser's.
private func identity(of client: NSObject) -> [String: Any] {
  var found: [String: Any] = [:]
  for (key, name) in [
    "bundleIdentifier": "bundle", "parentApplicationBundleIdentifier": "parentBundle",
    "displayName": "name",
  ] where client.responds(to: NSSelectorFromString(key)) {
    if let value = client.value(forKey: key) as? String { found[name] = value }
  }
  if client.responds(to: NSSelectorFromString("processIdentifier")),
    let pid = client.value(forKey: "processIdentifier") as? NSNumber, pid.intValue > 0
  {
    found["pid"] = pid.intValue
  }
  return found
}

/// The program MediaRemote counts as the one playing now.
private func currentClient() -> NSObject? {
  let path = NSSelectorFromString("localNowPlayingPlayerPath")
  guard let request = NSClassFromString("MRNowPlayingRequest") as AnyObject?,
    request.responds(to: path),
    let playerPath = request.perform(path)?.takeUnretainedValue() as? NSObject,
    playerPath.responds(to: NSSelectorFromString("client"))
  else { return nil }
  return playerPath.value(forKey: "client") as? NSObject
}

/// MediaRemote's requests of one player, made through its Objective-C
/// classes, which have no C functions for a player other than the current.
private struct PlayerRequests: @unchecked Sendable {
  typealias GetClients =
    @convention(c) (DispatchQueue, @escaping @convention(block) (CFArray?) -> Void) -> Void
  typealias InitPath =
    @convention(c) (AnyObject, Selector, AnyObject?, AnyObject?, AnyObject?) -> Unmanaged<
      AnyObject
    >?
  typealias InitRequest = @convention(c) (AnyObject, Selector, AnyObject?) -> Unmanaged<AnyObject>?
  /// A request answered with a truth value, then an error.
  typealias AskFlag =
    @convention(c) (
      AnyObject, Selector, DispatchQueue, @escaping @convention(block) (Bool, AnyObject?) -> Void
    ) -> Void
  /// A request answered with an object, then an error.
  typealias AskObject =
    @convention(c) (
      AnyObject, Selector, DispatchQueue,
      @escaping @convention(block) (AnyObject?, AnyObject?) -> Void
    ) -> Void
  typealias Send =
    @convention(c) (
      AnyObject, Selector, UInt32, AnyObject?, DispatchQueue,
      @escaping @convention(block) (AnyObject?) -> Void
    ) -> Void

  let getClients: GetClients
  let pathClass: AnyClass
  let requestClass: AnyClass
  let origin: AnyObject

  private static let initPath = NSSelectorFromString("initWithOrigin:client:player:")
  private static let initRequest = NSSelectorFromString("initWithPlayerPath:")
  private static let isPlaying = NSSelectorFromString("requestIsPlayingOnQueue:completion:")
  private static let info = NSSelectorFromString("requestNowPlayingInfoOnQueue:completion:")
  private static let artwork = NSSelectorFromString(
    "requestNowPlayingItemArtworkOnQueue:completion:")
  private static let send = NSSelectorFromString("sendCommand:options:queue:completion:")
  private static let commands = NSSelectorFromString("requestSupportedCommandsOnQueue:completion:")

  /// Nil on a macOS whose MediaRemote lacks any of what the requests use.
  init?() {
    let path = "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote"
    guard let framework = dlopen(path, RTLD_NOW),
      let getClients = dlsym(framework, "MRMediaRemoteGetNowPlayingClients"),
      let pathClass = NSClassFromString("MRPlayerPath"),
      let requestClass = NSClassFromString("MRNowPlayingRequest"),
      let originClass = NSClassFromString("MROrigin") as AnyObject?,
      originClass.responds(to: NSSelectorFromString("localOrigin")),
      let origin = originClass.perform(NSSelectorFromString("localOrigin"))?.takeUnretainedValue(),
      class_respondsToSelector(pathClass, Self.initPath),
      [Self.initRequest, Self.isPlaying, Self.info, Self.artwork, Self.send].allSatisfy({
        class_respondsToSelector(requestClass, $0)
      })
    else { return nil }
    self.getClients = unsafeBitCast(getClients, to: GetClients.self)
    self.pathClass = pathClass
    self.requestClass = requestClass
    self.origin = origin
  }

  private func method<T>(_ selector: Selector, of cls: AnyClass, as type: T.Type) -> T {
    unsafeBitCast(class_getMethodImplementation(cls, selector), to: T.self)
  }

  /// A request of the player `client` is.
  func request(for client: AnyObject) -> AnyObject? {
    let alloc = NSSelectorFromString("alloc")
    guard let path = (pathClass as AnyObject).perform(alloc)?.takeUnretainedValue(),
      let made = method(Self.initPath, of: pathClass, as: InitPath.self)(
        path, Self.initPath, origin, client, nil)?.takeUnretainedValue(),
      let request = (requestClass as AnyObject).perform(alloc)?.takeUnretainedValue()
    else { return nil }
    return method(Self.initRequest, of: requestClass, as: InitRequest.self)(
      request, Self.initRequest, made)?.takeUnretainedValue()
  }

  func isPlaying(_ request: AnyObject, then done: @escaping (Bool) -> Void) {
    method(Self.isPlaying, of: requestClass, as: AskFlag.self)(request, Self.isPlaying, .main) {
      playing, _ in done(playing)
    }
  }

  func info(_ request: AnyObject, then done: @escaping ([String: Any]) -> Void) {
    method(Self.info, of: requestClass, as: AskObject.self)(request, Self.info, .main) {
      info, _ in done(info as? [String: Any] ?? [:])
    }
  }

  /// The artwork's bytes and type, when the player has any.
  func artwork(_ request: AnyObject, then done: @escaping (Data?, String?) -> Void) {
    method(Self.artwork, of: requestClass, as: AskObject.self)(request, Self.artwork, .main) {
      artwork, _ in
      let artwork = artwork as? NSObject
      let has = { (key: String) in artwork?.responds(to: NSSelectorFromString(key)) == true }
      done(
        has("imageData") ? artwork?.value(forKey: "imageData") as? Data : nil,
        has("mimeType") ? artwork?.value(forKey: "mimeType") as? String : nil)
    }
  }

  /// Whether the player takes a position to move to, or nil on a macOS
  /// that can't be asked.
  func seekable(_ request: AnyObject, then done: @escaping (Bool?) -> Void) {
    guard class_respondsToSelector(requestClass, Self.commands) else { return done(nil) }
    method(Self.commands, of: requestClass, as: AskObject.self)(request, Self.commands, .main) {
      commands, _ in
      guard let commands = commands as? [NSObject] else { return done(nil) }
      done(
        commands.contains {
          $0.responds(to: NSSelectorFromString("command"))
            && $0.responds(to: NSSelectorFromString("isEnabled"))
            && ($0.value(forKey: "command") as? NSNumber)?.uint32Value == seekCommand
            && ($0.value(forKey: "enabled") as? NSNumber)?.boolValue == true
        })
    }
  }

  func send(
    _ command: UInt32, options: [String: Any]?, to request: AnyObject,
    then done: @escaping () -> Void
  ) {
    method(Self.send, of: requestClass, as: Send.self)(
      request, Self.send, command, options as NSDictionary?, .main
    ) { _ in done() }
  }
}

/// The players a line is being gathered from, as each answers. Used on the
/// main queue alone.
private final class Gathering: @unchecked Sendable {
  var players: [[String: Any]] = []
}

private func write(_ line: [String: Any]) {
  if let json = try? JSONSerialization.data(withJSONObject: line) {
    FileHandle.standardOutput.write(json + Data("\n".utf8))
  }
}

/// Writes every player as a line of JSON, `{"players": [...]}`: each one's
/// track, whether it plays, whether it takes a position to move to, and
/// whether it is the one MediaRemote counts as playing now. Then calls `done`.
private func writeLine(
  _ remote: MediaRemote, _ requests: PlayerRequests?,
  then done: @escaping @Sendable () -> Void = {}
) {
  guard let requests else { return writeCurrent(remote, then: done) }
  let current = currentClient().map(identity)?["bundle"] as? String
  requests.getClients(.main) { clients in
    let gathering = Gathering()
    let group = DispatchGroup()
    for client in clients as? [AnyObject] ?? [] {
      guard let client = client as? NSObject, let request = requests.request(for: client) else {
        continue
      }
      var player = identity(of: client)
      player["current"] = player["bundle"] as? String == current
      let index = gathering.players.count
      gathering.players.append(player)
      group.enter()
      requests.isPlaying(request) { playing in
        gathering.players[index]["playing"] = playing
        group.leave()
      }
      group.enter()
      requests.info(request) { info in
        gathering.players[index].merge(track(from: info)) { $1 }
        group.leave()
      }
      group.enter()
      requests.seekable(request) { seekable in
        if let seekable { gathering.players[index]["seekable"] = seekable }
        group.leave()
      }
      group.enter()
      requests.artwork(request) { artwork, type in
        if let artwork, !artwork.isEmpty {
          gathering.players[index]["artwork"] = artwork.base64EncodedString()
          if let type { gathering.players[index]["artworkType"] = type }
        }
        group.leave()
      }
    }
    group.notify(queue: .main) {
      write(["players": gathering.players])
      done()
    }
  }
}

/// Writes the one player MediaRemote counts as playing now, for a macOS
/// that can't be asked of the others.
private func writeCurrent(_ remote: MediaRemote, then done: @escaping @Sendable () -> Void) {
  remote.getPID(.main) { pid in
    // Whether it is playing is asked for on its own: it changes the moment
    // playback does, while the info's rate follows when the app updates it.
    remote.getIsPlaying(.main) { playing in
      remote.getInfo(.main) { info in
        var player: [String: Any] = [:]
        if let info = info as? [String: Any] {
          player = track(from: info)
          if pid > 0 { player["pid"] = Int(pid) }
          player["playing"] = playing
          player["current"] = true
          player.merge(currentClient().map(identity) ?? [:]) { $1 }
        }
        write(["players": player.isEmpty ? [] : [player]])
        done()
      }
    }
  }
}

/// Sends the MediaRemote command `number` with `options` to the player with
/// the bundle identifier `bundle`, or without one, to the one MediaRemote
/// counts as playing now. Then exits.
private func send(
  _ number: UInt32, options: [String: Any]?, to bundle: String?, _ remote: MediaRemote,
  _ requests: PlayerRequests?
) {
  let finish: @Sendable () -> Void = {
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { exit(0) }
  }
  let sendToCurrent = {
    _ = remote.sendCommand(number, options as CFDictionary?)
    finish()
  }
  guard let requests, let bundle else { return sendToCurrent() }
  requests.getClients(.main) { clients in
    let player = (clients as? [AnyObject] ?? []).compactMap { $0 as? NSObject }
      .first { identity(of: $0)["bundle"] as? String == bundle }
    guard let request = player.flatMap(requests.request) else { exit(1) }
    // MediaRemote sends every command to the player macOS counts as playing
    // now, whichever player it is addressed to, so the player is made that
    // one first. Without a way to, the command goes nowhere.
    let isCurrent = currentClient().map(identity)?["bundle"] as? String == bundle
    if !isCurrent {
      guard let makeCurrent = remote.setOverriddenApp else { exit(1) }
      _ = makeCurrent(bundle as CFString)
    }
    requests.send(number, options: options, to: request, then: finish)
  }
}

/// The host's entry point, which Perl calls. What follows `--` on Perl's
/// command line is this library's path and then what to do: `stream` writes
/// a line now and after every change until stdin closes, `once` writes a
/// line, `command <number> [<bundle>]` sends the MediaRemote command of
/// that number to the player with that bundle identifier, or without one,
/// to the one MediaRemote counts as playing now, and
/// `seek <seconds> [<bundle>]` moves that player to that position in its
/// track.
@_cdecl("kantan_now_playing_host")
public func host() {
  let arguments = Array(CommandLine.arguments.drop { $0 != "--" }.dropFirst(2))
  guard let remote = MediaRemote(), let mode = arguments.first else { exit(1) }
  let requests = PlayerRequests()

  switch mode {
  case "stream":
    remote.register(.main)
    // A change brings several notifications, which one line answers.
    let pending = Gathering()
    for name in changeNotifications {
      NotificationCenter.default.addObserver(
        forName: Notification.Name(name), object: nil, queue: .main
      ) { _ in
        guard pending.players.isEmpty else { return }
        pending.players = [[:]]
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) {
          pending.players = []
          writeLine(remote, requests)
        }
      }
    }
    writeLine(remote, requests)
    DispatchQueue.global().async {
      while !FileHandle.standardInput.availableData.isEmpty {}
      exit(0)
    }
  case "once":
    writeLine(remote, requests) { exit(0) }
  case "command":
    guard let number = arguments.dropFirst().first.flatMap({ UInt32($0) }) else { exit(1) }
    send(number, options: nil, to: arguments.dropFirst(2).first, remote, requests)
  case "seek":
    guard let seconds = arguments.dropFirst().first.flatMap({ Double($0) }) else { exit(1) }
    send(
      seekCommand, options: [positionOption: seconds], to: arguments.dropFirst(2).first, remote,
      requests)
  default:
    exit(1)
  }
  RunLoop.main.run()
}
