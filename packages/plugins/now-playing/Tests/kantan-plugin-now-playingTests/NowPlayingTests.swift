import Foundation
import Testing

@testable import kantan_plugin_now_playing

private func settings(_ json: String) throws -> Settings {
  try JSONDecoder().decode(Settings.self, from: Data(json.utf8))
}

private let now = Date(timeIntervalSince1970: 1_000_000)

private func track(artist: String? = "Teebs", rate: Double = 1) -> Track {
  Track(
    title: "While You Doooo", artist: artist, album: "Ardour", duration: 200, elapsed: 30,
    timestamp: now.timeIntervalSince1970 - 20, rate: rate)
}

private func shown(_ track: Track?, _ settings: Settings) -> PluginOutput {
  render(track: track, artwork: nil, source: nil, settings: settings, now: now)
}

final class NowPlayingTests {
  @Test func testTheValueFollowsTheFormat() throws {
    #expect(shown(track(), Settings()).value == "Teebs · While You Doooo")
    #expect(shown(track(artist: nil), Settings()).value == "While You Doooo")
    let custom = try settings(#"{"format":"{title} ({album})"}"#)
    #expect(shown(track(), custom).value == "While You Doooo (Ardour)")
  }

  @Test func testTextTooLongLosesPartsThenIsCutShort() throws {
    let parts = #""show":{"playing":["artist","title","album"]}"#
    #expect(
      shown(track(), try settings("{\(parts)}")).value == "Teebs · While You Doooo · Ardour")
    // Over the limit, the album goes first, then the artist.
    #expect(
      shown(track(), try settings("{\(parts),\"maxChars\":25}")).value
        == "Teebs · While You Doooo")
    #expect(shown(track(), try settings("{\(parts),\"maxChars\":20}")).value == "While You Doooo")
    // With nothing left to drop, the text is cut short.
    let cut = shown(track(), try settings("{\(parts),\"maxChars\":10}"))
    #expect(cut.value == "While You...")
    #expect(cut.variables["title"] == "While You Doooo")
  }

  @Test func testAPartTheTextLosesWaitsForAHoverThatListsIt() throws {
    let fits = try settings(
      #"{"show":{"playing":["artist","title"],"hover":["artist"]},"maxChars":20,"drop":["artist"]}"#
    )
    #expect(
      shown(track(), fits).segments == [
        ValueSegment(text: "Teebs", fg: nil, reveal: true),
        ValueSegment(text: " · ", fg: nil, reveal: true),
        ValueSegment(text: "While You Doooo", fg: nil),
      ])
  }

  @Test func testThePositionKeepsTimeOnlyWhilePlaying() {
    #expect(shown(track(), Settings()).variables["elapsed"] == "0:50")
    #expect(shown(track(rate: 0), Settings()).variables["elapsed"] == "0:30")
  }

  @Test func testThePositionBarSeeksUnlessThePlayerCant() throws {
    let view = { (track: Track) in
      String(decoding: try JSONEncoder().encode(shown(track, Settings()).view), as: UTF8.self)
    }
    var fixed = track()
    fixed.seekable = false
    #expect(try view(track()).contains("--seek {value}"))
    #expect(try !view(fixed).contains("--seek"))
  }

  @Test func testEachStateShowsItsParts() throws {
    let paused = track(rate: 0)
    #expect(shown(nil, Settings()).hidden == true)
    #expect(shown(paused, Settings()).hidden == false)
    #expect(shown(paused, Settings()).active == false)

    let quiet = try settings(#"{"show":{"playing":["title"],"paused":[],"stopped":["icon"]}}"#)
    #expect(shown(track(), quiet).value == "While You Doooo")
    #expect(shown(track(), quiet).icon == nil)
    #expect(shown(paused, quiet).hidden == true)
    #expect(shown(nil, quiet).hidden == false)
    #expect(shown(nil, quiet).icon == "music")
  }

  @Test func testHoverPartsWaitForTheHover() throws {
    let hover = try settings(#"{"show":{"playing":["title"],"hover":["icon","artist"]}}"#)
    let output = shown(track(), hover)
    #expect(output.reveal == ["icon"])
    #expect(
      output.segments == [
        ValueSegment(text: "Teebs", fg: nil, reveal: true),
        ValueSegment(text: " · ", fg: nil, reveal: true),
        ValueSegment(text: "While You Doooo", fg: nil),
      ])
  }

  @Test func testThePlayerThatIsPlayingIsShown() {
    var spotify = track(rate: 0)
    spotify.bundle = "com.spotify.client"
    spotify.name = "Spotify"
    spotify.playing = false
    spotify.current = true
    var browser = track(artist: nil)
    browser.title = "A video"
    browser.bundle = "company.thebrowser.Browser"
    browser.playing = true
    // A browser playing comes before the paused player macOS counts as current.
    #expect(Track.shown(of: [spotify, browser], excluding: [])?.title == "A video")
    browser.playing = false
    #expect(Track.shown(of: [spotify, browser], excluding: [])?.bundle == "com.spotify.client")
    #expect(Track.shown(of: [spotify, browser], excluding: ["spotify"])?.title == "A video")
    #expect(Track.shown(of: [spotify], excluding: ["com.spotify.client"]) == nil)
  }

  @Test func testAnAppsIconComesBeforeTheDefault() throws {
    let icons = try settings(
      #"{"icon":"disc","icons":{"spotify":"brand-spotify","Arc":{"icon":"brand-arc","fg":"FF00FF"}}}"#
    )
    let spotify = Source(name: "Spotify", bundle: "com.spotify.client")
    let arc = Source(name: "Arc", bundle: "company.thebrowser.Browser")
    #expect(icons.icon(for: spotify) == "brand-spotify")
    #expect(icons.iconColor(for: spotify) == nil)
    #expect(icons.icon(for: arc) == "brand-arc")
    #expect(icons.iconColor(for: arc) == "FF00FF")
    #expect(icons.icon(for: Source(name: "Music", bundle: "com.apple.Music")) == "disc")
    #expect(icons.icon(for: nil) == "disc")
  }
}
