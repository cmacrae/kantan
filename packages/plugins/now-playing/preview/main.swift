import Foundation

// Prints the states of the now-playing module's preview: a track playing
// and the same track paused, and a live stream playing and paused, each
// leading to the other of its pair by its play button.

/// A state of the preview: its name, the output the plugin prints in it,
/// and the output each command run from it leads to.
struct PreviewState: Encodable {
  let name: String
  let output: PluginOutput
  let after: [String: PluginOutput]
}

let now = Date(timeIntervalSince1970: 1_794_000_000)
let settings = loadSettings(defaults: Settings())

/// The preview's track, playing or paused, 84 seconds in.
func output(playing: Bool) -> PluginOutput {
  render(
    track: Track(
      title: "Alberto Balsalm", artist: "Aphex Twin", album: "…I Care Because You Do",
      duration: 310, elapsed: 84, timestamp: now.timeIntervalSince1970, rate: playing ? 1 : 0),
    artwork: nil, source: Source(name: "Spotify", bundle: "com.spotify.client"),
    settings: settings, now: now)
}

/// The preview's live stream, playing or paused.
func live(playing: Bool) -> PluginOutput {
  render(
    track: Track(
      title: "Twitch stream", elapsed: 0, timestamp: now.timeIntervalSince1970,
      rate: playing ? 1 : 0, live: true),
    artwork: nil, source: nil, settings: settings, now: now)
}

let encoder = JSONEncoder()
encoder.outputFormatting = [.sortedKeys]
let preview = [
  "states": [
    PreviewState(
      name: "Playing", output: output(playing: true),
      after: [toggleCommand: output(playing: false)]),
    PreviewState(
      name: "Paused", output: output(playing: false),
      after: [toggleCommand: output(playing: true)]),
    PreviewState(
      name: "Live", output: live(playing: true),
      after: [toggleCommand: live(playing: false)]),
    PreviewState(
      name: "Live, paused", output: live(playing: false),
      after: [toggleCommand: live(playing: true)]),
  ]
]
print(String(decoding: try encoder.encode(preview), as: UTF8.self))
