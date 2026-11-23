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

  @Test func testAHugeDurationShowsAsTheLongestTime() {
    var huge = track()
    huge.duration = 1e300
    huge.elapsed = 1e300
    #expect(shown(huge, Settings()).variables["duration"] == "99:59:59")
    #expect(shown(huge, Settings()).variables["elapsed"] == "99:59:59")
    #expect(clockTime(-5) == "0:00")
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

  @Test func testALiveStreamShowsItsOwnState() throws {
    var live = track()
    live.duration = nil
    live.live = true
    let view = { (output: PluginOutput) in
      String(decoding: try JSONEncoder().encode(output.view), as: UTF8.self)
    }
    let output = shown(live, try settings(#"{"show":{"live":["title"]},"colors":{"live":"F00"}}"#))
    #expect(output.variables["state"] == "Live")
    #expect(output.value == "While You Doooo")
    #expect(output.variables["elapsed"] == "")
    #expect(try view(output).contains(#""color":"F00""#))
    #expect(try view(output).contains("LIVE"))
    #expect(try !view(output).contains("--seek"))
    #expect(try !view(output).contains("--next"))
    // Unset, the live state shows what playing does.
    #expect(shown(live, Settings()).value == "Teebs · While You Doooo")
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

  @Test func testThePlayerThatStartedLastIsShownUnlessOneIsPinned() {
    let player = { (bundle: String, playing: Bool) in
      var track = track()
      track.bundle = bundle
      track.playing = playing
      return track
    }
    let players = { (arc: Bool, spotify: Bool) in [player("arc", arc), player("spotify", spotify)] }
    var selection = Selection()
    let shown = { (players: [Track]) in selection.shown(of: players, excluding: [])?.bundle }

    // A stream plays, then music starts beside it: the music shows.
    selection.note([player("arc", true)], excluding: [], at: 0)
    selection.note(players(true, true), excluding: [], at: 10)
    #expect(shown(players(true, true)) == "spotify")
    // Paused, the music gives way to the stream still playing.
    selection.note(players(true, false), excluding: [], at: 20)
    #expect(shown(players(true, false)) == "arc")
    #expect(selection.note(players(true, true), excluding: [], at: 25) == ["spotify"])

    // The stream picked, then paused: the pin goes, and the music shows.
    selection.pin = Pin(player: "arc", at: 30)
    #expect(shown(players(true, true)) == "arc")
    selection.note(players(false, true), excluding: [], at: 40)
    #expect(selection.pin == nil)
    #expect(shown(players(false, true)) == "spotify")

    // A paused player picked stays shown, and through its own start.
    selection.pin = Pin(player: "arc", at: 45)
    #expect(shown(players(false, true)) == "arc")
    selection.note(players(true, true), excluding: [], at: 50)
    #expect(selection.pin?.player == "arc")
    // Another stopping leaves the pin; with nothing playing, the last to stop shows.
    selection.note(players(true, false), excluding: [], at: 60)
    #expect(selection.pin?.player == "arc")
    selection.note(players(false, false), excluding: [], at: 70)
    #expect(selection.pin == nil)
    #expect(shown(players(false, false)) == "arc")

    // Another starting ends a pin, as does its player having no track.
    selection.pin = Pin(player: "arc", at: 75)
    selection.note(players(false, true), excluding: [], at: 80)
    #expect(selection.pin == nil)
    selection.pin = Pin(player: "arc", at: 85)
    selection.note([player("spotify", true)], excluding: [], at: 90)
    #expect(selection.pin == nil)
  }

  @Test func testTheSwitcherOffersEachPlayerWhenThereIsMoreThanOne() throws {
    let view = { (choices: [Choice]) in
      let output = render(
        track: track(), artwork: nil, source: nil, settings: Settings(), now: now,
        choices: choices)
      return String(decoding: try JSONEncoder().encode(output.view), as: UTF8.self)
    }
    let arc = Choice(player: "company.thebrowser.Browser", icon: "brand-arc")
    let spotify = Choice(player: "com.spotify.client", icon: "brand-spotify")
    #expect(try view([arc, spotify]).contains("--select 'com.spotify.client'"))
    #expect(try !view([arc]).contains("--select"))
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
