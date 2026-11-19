import AppKit
import Combine
import CoreGraphics
import Foundation
import SwiftUI
import Testing
import os

@testable import kantan

/// Something a test waits for, fulfilled from any thread.
final class Expectation: @unchecked Sendable {
  private let lock = NSLock()
  private var fulfilled = false

  func fulfill() { lock.withLock { fulfilled = true } }

  var isFulfilled: Bool { lock.withLock { fulfilled } }
}

/// Whether every one of `expectations` is fulfilled within `timeout`.
func fulfillment(of expectations: [Expectation], timeout: TimeInterval) async -> Bool {
  let deadline = Date(timeIntervalSinceNow: timeout)
  while !expectations.allSatisfy(\.isFulfilled), Date() < deadline {
    try? await Task.sleep(for: .milliseconds(10))
  }
  return expectations.allSatisfy(\.isFulfilled)
}

/// Runs the main run loop, and the main actor's other work, for `duration`.
@MainActor
func runMainLoop(for duration: TimeInterval) async {
  let deadline = Date(timeIntervalSinceNow: duration)
  while Date() < deadline {
    spinMainLoop(until: min(deadline, Date(timeIntervalSinceNow: 0.01)))
    try? await Task.sleep(for: .milliseconds(1))
  }
}

/// Runs the main run loop until `date`.
@MainActor
private func spinMainLoop(until date: Date) {
  RunLoop.main.run(until: date)
}

final class FontConfigTests {
  @Test func testNameWeightSizeDescriptorParsesBoth() {
    let font = FontConfig(descriptor: "HelveticaNeue:medium:20")
    #expect(font.name == "HelveticaNeue")
    #expect(font.weight == .medium)
    #expect(font.size == 20)
  }

  @Test func testWeightAliases() {
    #expect(FontConfig(descriptor: "Foo:ultralight").weight == .ultraLight)
    #expect(FontConfig(descriptor: "Foo:semibold").weight == .semibold)
    #expect(FontConfig(descriptor: "Foo:demi-bold").weight == .semibold)
    #expect(FontConfig(descriptor: "Foo:heavy").weight == .heavy)
    #expect(FontConfig(descriptor: "Foo:extrabold").weight == .heavy)
    #expect(FontConfig(descriptor: "Foo:black").weight == .black)
  }
}

final class FontWeightTests {
  private func faceName(_ descriptor: String) -> String {
    FontConfig(descriptor: descriptor, source: .system).nsFont.fontName
  }

  @Test func testWeightsPickTheFamilysFace() {
    #expect(faceName("HelveticaNeue:13") == "HelveticaNeue")
    #expect(faceName("HelveticaNeue:medium:13") == "HelveticaNeue-Medium")
    #expect(faceName("Helvetica Neue:light:13") == "HelveticaNeue-Light")
    #expect(faceName("HelveticaNeue:bold:13") == "HelveticaNeue-Bold")
  }
}

final class NSColorHexTests {
  @Test func testEightDigitHexCarriesAlpha() {
    let color = NSColor(hex: "#FF000080").usingColorSpace(.deviceRGB)!
    #expect(abs(color.redComponent - 1.0) <= 0.01)
    #expect(abs(color.greenComponent - 0.0) <= 0.01)
    #expect(abs(color.blueComponent - 0.0) <= 0.01)
    #expect(abs(color.alphaComponent - (128.0 / 255.0)) <= 0.01)
  }

  @Test func testInvalidHexFallsBackToDefault() {
    let fallback = NSColor.red
    let color = NSColor(hex: "not-hex", defaultColor: fallback).usingColorSpace(.deviceRGB)!
    let expected = fallback.usingColorSpace(.deviceRGB)!
    #expect(abs(color.redComponent - expected.redComponent) <= 0.01)
    #expect(abs(color.greenComponent - expected.greenComponent) <= 0.01)
    #expect(abs(color.blueComponent - expected.blueComponent) <= 0.01)
  }
}

final class PlacementSpecTests {
  @Test func testOrPairPicksNotchVariantOnNotchedScreens() {
    let spec = PlacementSpec(raw: "notchleft|left")
    #expect(spec.resolve(hasNotch: true) == "notchleft")
    #expect(spec.resolve(hasNotch: false) == "left")
  }

  @Test func testCenterPairKeepsItsSideOfTheNotchOnScreensWithoutOne() {
    let spec = PlacementSpec(raw: "notchright|center")
    #expect(spec.resolve(hasNotch: true) == "notchright")
    #expect(spec.resolve(hasNotch: false) == "notchright")
    #expect(PlacementSpec(raw: "center").resolve(hasNotch: false) == "center")
    #expect(PlacementSpec(raw: "center").resolve(hasNotch: true) == nil)
  }
}

final class StyleParsingTests {
  @Test func testParseStyleConfigWithNestedLightAndDark() {
    let yaml: Yaml = .dictionary([
      .string("light"): .dictionary([
        .string("fg"): .string("#000000"),
        .string("bg"): .string("#ffffff"),
      ]),
      .string("dark"): .dictionary([
        .string("fg"): .string("#ffffff"),
        .string("bg"): .string("#000000"),
      ]),
    ])
    let style = parseStyleConfig(from: yaml)
    #expect(style?.light?.fg == "#000000")
    #expect(style?.light?.bg == "#ffffff")
    #expect(style?.dark?.fg == "#ffffff")
    #expect(style?.dark?.bg == "#000000")
  }

  @Test func testParseStyleConfigFlatAppliesToBothModes() {
    let yaml: Yaml = .dictionary([
      .string("fg"): .string("#abcdef"),
      .string("bg"): .string("#012345"),
    ])
    let style = parseStyleConfig(from: yaml)
    #expect(style?.light?.fg == "#abcdef")
    #expect(style?.dark?.fg == "#abcdef")
    #expect(style?.light?.bg == "#012345")
    #expect(style?.dark?.bg == "#012345")
  }
}

final class ModuleMergeTests {
  private func mod(_ name: String, _ placement: String) -> ModuleConfig {
    ModuleConfig(name: name, placement: PlacementSpec(raw: placement), type: "text")
  }

  @Test func testMergeAppendsExtrasLeftAndPrependsExtrasRight() {
    let base = [mod("L1", "left"), mod("L2", "left"), mod("R1", "right"), mod("R2", "right")]
    let extra = [mod("EL", "left"), mod("ER", "right")]
    let result = mergeModules(base: base, extra: extra).map(\.name)
    #expect(result == ["L1", "L2", "EL", "ER", "R1", "R2"])
  }
}

final class OverlapTests {
  private func resolve(
    collides: Bool = true, drawerOpen: Bool = true, engaged: Bool = false,
    displaced: Bool = false, yielded: Bool = false
  ) -> OverlapAction {
    OverlapAction.resolve(
      collides: collides, drawerOpen: drawerOpen, engaged: engaged, displaced: displaced,
      yielded: yielded)
  }

  @Test func testWhicheverIsInUseKeepsItsPlace() {
    // An open drawer displaces the modules beside the notch it runs into,
    // until it closes or there is room.
    #expect(resolve() == .displace)
    #expect(resolve(collides: false) == .none)
    #expect(resolve(displaced: true) == .none)
    #expect(resolve(drawerOpen: false, displaced: true) == .restore)
    #expect(resolve(collides: false, displaced: true) == .restore)
    // A module in use closes the drawer it grows into, which opens again
    // once the module is let go.
    #expect(resolve(engaged: true) == .closeDrawer)
    #expect(resolve(drawerOpen: false, engaged: true, yielded: true) == .none)
    #expect(resolve(drawerOpen: false, yielded: true) == .reopenDrawer)
  }
}

final class AudioAnalysisTests {
  @Test func testATonesBandIsTheLoudest() {
    let rate = 48000.0
    let tone = (0..<AudioAnalysis.window).map {
      Float(0.5 * sin(2 * Double.pi * 1000 * Double($0) / rate))
    }
    let bands = AudioAnalysis.bands(of: tone, sampleRate: rate)
    // 1 kHz lies in band 132 of the 256 spanning 50 Hz to 16 kHz.
    #expect(bands.firstIndex(of: bands.max()!) == 132)
    #expect(bands[132] > 0.9)
    #expect(bands[20] == 0 && bands[240] == 0)
    let silence = [Float](repeating: 0, count: AudioAnalysis.window)
    #expect(AudioAnalysis.bands(of: silence, sampleRate: rate).allSatisfy { $0 == 0 })
  }
}

final class IconForLevelTests {
  @Test func testFirstBucketForLowLevel() {
    let icons = ["empty", "quarter", "half", "three-quarter", "full"]
    #expect(iconForLevel(0, icons: icons) == "empty")
    #expect(iconForLevel(10, icons: icons) == "empty")
  }

  @Test func testClampsAboveMax() {
    let icons = ["a", "b", "c"]
    #expect(iconForLevel(500, icons: icons) == "c")
  }
}

final class YamlTests {
  @Test func testLoadParsesScalarsAndCollections() throws {
    let source = """
      height: 33
      padding: 10
      modules:
        - name: clock
          enabled: true
      """
    let yaml = try Yaml.load(source)
    #expect(yaml["height"].int == 33)
    #expect(yaml["padding"].int == 10)
    #expect(yaml["modules"].array?.count == 1)
    #expect(yaml["modules"][0]["name"].string == "clock")
    #expect(yaml["modules"][0]["enabled"].bool == true)
  }

  @Test func testIntRejectsNumbersNoIntHolds() throws {
    for value in [Double.infinity, -.infinity, .nan, 1.0e30] {
      #expect(Yaml.double(value).int == nil)
    }
    #expect(try Yaml.load("height: .inf\n")["height"].int == nil)
  }

  @Test func testSettingsJSONCannotHoldIsDropped() throws {
    let config = try CommandConfig(
      yaml: try Yaml.load("command: echo\nsettings:\n  limit: .inf\n"))
    #expect(config.resolvedSettings(isDark: true) == nil)
  }
}

final class ConfigShapeTests {
  @Test func testNeedsBundledIconFontsTrueWhenAnyModuleUsesBundled() {
    let bundledModule = ModuleConfig(
      name: "x", placement: PlacementSpec(raw: "left"), type: "text",
      iconFont: FontConfig(descriptor: "tabler-icons", source: .bundled)
    )
    let cfg = Config(
      theme: nil, style: StyleConfig(light: nil, dark: nil),
      height: 33, padding: 10, iconTextSpacing: 4,
      iconFont: FontConfig(descriptor: "SF Pro", source: .system), textFont: nil,
      cornerRadius: 0, blur: 0, gaps: .default,
      autohide: .default, displays: .main, modules: [bundledModule]
    )
    #expect(cfg.needsBundledIconFonts)
  }
}

final class DSLColorFromHexTests {
  private func components(_ color: Color) -> (r: Double, g: Double, b: Double, a: Double)? {
    guard let ns = NSColor(color).usingColorSpace(.deviceRGB) else { return nil }
    return (
      Double(ns.redComponent), Double(ns.greenComponent),
      Double(ns.blueComponent), Double(ns.alphaComponent)
    )
  }

  @Test func testParses8CharRGBAExtractsAlpha() {
    guard let c = dslColorFromHex("ff000080"), let comps = components(c) else {
      Issue.record("expected non-nil color")
      return
    }
    #expect(abs(comps.r - 1.0) <= 0.01)
    #expect(abs(comps.g - 0.0) <= 0.01)
    #expect(abs(comps.b - 0.0) <= 0.01)
    #expect(abs(comps.a - (128.0 / 255.0)) <= 0.01)
  }

  @Test func testRejectsNonHexString() {
    #expect(dslColorFromHex("not-a-color") == nil)
  }
}

final class CommandLineTests {
  @Test func testNoWordsRunsTheBarIgnoringDashArguments() {
    #expect(parseCommand([]) == .run)
    #expect(parseCommand(["-NSDocumentRevisionsDebugMode", "-psn_0_1"]) == .run)
  }

  @Test func testATriggerNeedsAModuleAndAnAction() {
    #expect(
      parseCommand(["trigger", "clock", "set", "value=", "module=other"])
        == .trigger(["module": "clock", "action": "set", "value": ""]))
    #expect(
      parseCommand(["trigger", "clock"]) == .usageError("trigger needs a module and an action"))
    #expect(parseCommand(["trigger"]) == .usageError("trigger needs a module and an action"))
  }

  @Test func testFlagsSetOptionsAnywhereAndExpandTilde() {
    let parsed = parseArguments([
      "trigger", "--config", "~/k.yaml", "clock", "--themes-dir", "/t", "refresh",
    ])
    #expect(
      parsed.options
        == KantanOptions(configPath: NSHomeDirectory() + "/k.yaml", themesDirPath: "/t"))
    #expect(parsed.command == .trigger(["module": "clock", "action": "refresh"]))
  }

  @Test func testHelpAndVersionWinOverEverythingElse() {
    #expect(parseArguments(["--help"]).command == .help)
    #expect(parseArguments(["-h", "--confg"]).command == .help)
    #expect(parseArguments(["trigger", "x", "-V"]).command == .version)
    #expect(parseArguments(["--version"]).command == .version)
  }

  @Test func testUnknownFlagsAndMissingPathsAreErrors() {
    #expect(parseArguments(["--confg", "x"]).command == .usageError("unknown option '--confg'"))
    #expect(parseArguments(["--config"]).command == .usageError("--config needs a path"))
    #expect(parseArguments(["-psn_0_1"]).command == .run)
  }

  @Test func testAnUnknownCommandIsAnError() {
    #expect(
      parseCommand(["trgger", "clock", "refresh"]) == .usageError("unknown command 'trgger'"))
  }
}

final class TriggerFieldsTests {
  @Test func testFieldsKeepEmptyValuesAndEverythingAfterTheFirstEquals() {
    #expect(
      parseTriggerFields(["value=", "icon=bell", "fg=#FF0000", "cmd=a=b", "loose", "=x"]) == [
        "value": "", "icon": "bell", "fg": "#FF0000", "cmd": "a=b",
      ])
  }
}

final class WiFiEventsTests {
  private func module() -> WiFiConfig {
    WiFiConfig(strengthIcons: ["wifi"], disconnectedIcon: "wifi-off", hotspotIcon: "hotspot")
  }

  @Test func testEveryWiFiModuleHearsTheEventsUntilItStops() async {
    let first = module()
    let second = module()
    let heard = OSAllocatedUnfairLock(initialState: [0, 0])
    first.startObserving { heard.withLock { $0[0] += 1 } }
    second.startObserving { heard.withLock { $0[1] += 1 } }
    WiFiEvents.shared.ssidDidChangeForWiFiInterface(withName: "en0")
    #expect(heard.withLock { $0 } == [1, 1])

    first.stopObserving()
    WiFiEvents.shared.ssidDidChangeForWiFiInterface(withName: "en0")
    #expect(heard.withLock { $0 } == [1, 2])
    second.stopObserving()
  }

  @Test func testAHotspotChangesOnlyWhenTheNetworkDoes() {
    let events = WiFiEvents()
    #expect(!events.isHotspot)
    #expect(!events.setHotspot(false))
    #expect(events.setHotspot(true))
    #expect(events.isHotspot)
    #expect(!events.setHotspot(true))
    #expect(events.setHotspot(false))
  }
}

final class WiFiStatusTests {
  private func module(_ yaml: String) throws -> WiFiConfig {
    try #require(
      try WiFiConfigFactory().configuration(
        from: try Yaml.load(yaml), configDir: nil, theme: nil) as? WiFiConfig)
  }

  @Test func testDisconnectedOutranksAHotspot() throws {
    let wifi = try module("icons: {}\n")
    #expect(wifi.icon(for: WiFiStatus(rssi: 0, isConnected: false, isHotspot: true)) == "wifi-off")
  }

  @Test func testAnAllZeroBSSIDNeedsASignalToCountAsAssociated() {
    let zero = Data(count: 6)
    #expect(!WiFiConfig.isAssociated(bssid: zero, rssi: 0))
    #expect(WiFiConfig.isAssociated(bssid: zero, rssi: -60))
    #expect(WiFiConfig.isAssociated(bssid: Data([0, 1, 2, 3, 4, 5]), rssi: 0))
    #expect(!WiFiConfig.isAssociated(bssid: Data(), rssi: -60))
    #expect(!WiFiConfig.isAssociated(bssid: nil, rssi: -60))
  }
}

final class TemplateResolverTests {
  @Test func testScopeStackOverridesVariables() {
    let r = TemplateResolver(variables: ["v": "outer"], data: [:])
    r.pushScope(["v": "inner"])
    #expect(r.resolve("{v}") == "inner")
    r.popScope()
    #expect(r.resolve("{v}") == "outer")
  }

  @Test func testAValueRepeatingItsOwnPlaceholderExpandsOnce() {
    let title = String(repeating: "{title}", count: 3)
    let r = TemplateResolver(variables: ["title": title], data: [:])
    #expect(r.resolve("{title} {title}") == title + " " + title)
  }
}

final class CommandTemplateTests {
  private let hostile = #"a b; echo pwned $(id) `id` 'q' "dq" \"#
  private lazy var resolver = TemplateResolver(
    variables: [
      "v": hostile, "empty": "", "id": "x-1",
      "cmd": "kantan-plugin-reminders --complete 'x-1' && kantan trigger r refresh",
    ], data: [:])

  /// What `sh -c` prints for `command`.
  private func shell(_ command: String) throws -> String {
    let process = Process()
    let pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/bin/sh")
    process.arguments = ["-c", command]
    process.standardOutput = pipe
    try process.run()
    process.waitUntilExit()
    return String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
  }

  @Test func testValuesStayOneArgumentWhereverThePlaceholderSits() throws {
    for template in [
      "printf '[%s]' {v}", "printf '[%s]' '{v}'", #"printf '[%s]' "{v}""#,
      #"printf '[%s]' pre{v}"#,
    ] {
      let command = resolver.resolveCommand(template)
      let expected = template.hasSuffix("pre{v}") ? "[pre\(hostile)]" : "[\(hostile)]"
      #expect((try shell(command)) == expected, "\(template)")
    }
  }

  @Test func testAnEmptyBareValueLeavesNothing() {
    #expect(resolver.resolveCommand("cmd {empty} --x {id}") == "cmd  --x 'x-1'")
  }

  @Test func testACommandThatIsOnePlaceholderRunsAsTheValue() {
    #expect(
      resolver.resolveCommand(" {cmd} ")
        == "kantan-plugin-reminders --complete 'x-1' && kantan trigger r refresh")
  }

  @Test func testAPluginBuiltCommandIsNotResolvedAgain() throws {
    let title = "{title}'; echo pwned; '"
    let openCmd = "printf '[%s]' '\(title.replacingOccurrences(of: "'", with: #"'\''"#))'"
    let r = TemplateResolver(variables: ["title": title, "open_cmd": openCmd], data: [:])
    #expect((try shell(r.resolveCommand("{open_cmd}"))) == "[\(title)]")
    #expect((try shell(r.resolveCommand("printf '[%s]' {open_cmd}"))) == "[\(openCmd)]")
  }

  @Test func testSchemesWithDigitsDashesAndDotsAreURLs() {
    for url in ["ms-teams:", "x-apple.systempreferences:com.apple.Wi-Fi", "web+app:x", "https://a"]
    {
      #expect(isURLCommand(url), "\(url)")
    }
    for command in ["open -a Mail", "1password:x", "-x:y", ":x", "/usr/bin/x:y", "a_b:c"] {
      #expect(!isURLCommand(command), "\(command)")
    }
  }

  @Test func testURLCommandsPercentEncodeValues() {
    let r = TemplateResolver(variables: ["q": "a b&c=d"], data: [:])
    #expect(
      r.resolveCommand("https://example.com/search?q={q}")
        == "https://example.com/search?q=a%20b%26c%3Dd")
  }
}

final class DSLCanonicalNormalisationTests {
  @Test func testCanonicalBoolRoundTripsThroughResolveBool() {
    let r = TemplateResolver(
      variables: ["t": dslCanonicalBool(true), "f": dslCanonicalBool(false)],
      data: [:])
    #expect(r.resolveBool("{t}"))
    #expect(!r.resolveBool("{f}"))
  }

  @Test func testCanonicalNumberRoundTripsThroughDouble() {
    for value in [0.0, 1.0, 75.0, -3.0, 3.5, 0.125, 1e6] {
      #expect(Double(dslCanonicalNumber(value)) == value)
    }
  }
}

final class CachedStatusTests {
  @Test func testConcurrentSetAndGetDoesNotCrash() {
    let cache = CachedStatus<Int>(fallback: 0)
    let iterations = 1_000
    let group = DispatchGroup()
    let writers = DispatchQueue(label: "test.writers", attributes: .concurrent)
    let readers = DispatchQueue(label: "test.readers", attributes: .concurrent)
    for i in 0..<iterations {
      group.enter()
      writers.async {
        cache.set(i)
        group.leave()
      }
      group.enter()
      readers.async {
        _ = cache.get()
        group.leave()
      }
    }
    #expect(group.wait(timeout: .now() + 5) == .success)
  }
}

// MARK: - loadConfig() end-to-end

final class PointerHoverTests {
  @Test func testHoverChangesOnlyOnEnteringLeavingOrPressing() {
    let frame = NSRect(x: 100, y: 0, width: 40, height: 24)
    var hover = PointerHover()
    #expect(hover.pointer(at: NSPoint(x: 10, y: 10), in: frame, pressed: false) == nil)
    #expect(hover.pointer(at: NSPoint(x: 110, y: 10), in: frame, pressed: false) == true)
    #expect(hover.pointer(at: NSPoint(x: 120, y: 12), in: frame, pressed: false) == nil)
    #expect(hover.pointer(at: NSPoint(x: 120, y: 12), in: frame, pressed: true) == false)
    #expect(hover.pointer(at: NSPoint(x: 121, y: 12), in: frame, pressed: false) == true)
    #expect(hover.pointer(at: NSPoint(x: 200, y: 12), in: frame, pressed: false) == false)
  }
}

@MainActor
final class DrawerIconTests {
  @Test func testTheDrawerKeepsItsHideIconWhileOpenThroughUpdates() async throws {
    let yaml = try Yaml.load(
      """
      modules:
        - name: drawer
          type: drawer
          placement: right
          config:
            icons: {show: "S", hide: "H"}
        - name: hidden
          type: text
          placement: right
          config:
            value: x
      """)
    let bar = BarViewModel(config: try #require(loadConfig(from: yaml)))
    let drawer = try #require(bar.allModules.first { $0.moduleConfig.name == "drawer" })
    await waitUntil { drawer.displayIcon == "S" }

    bar.toggleDrawer(side: "right")
    await waitUntil { drawer.displayIcon == "H" }
    drawer.update()
    await runMainLoop(for: 0.2)
    #expect(drawer.displayIcon == "H")

    bar.toggleDrawer(side: "right")
    await waitUntil { drawer.displayIcon == "S" }
  }
}

@MainActor
final class PopupClampTests {
  private let screens = [
    (
      frame: NSRect(x: 0, y: 0, width: 1000, height: 800),
      visible: NSRect(x: 0, y: 0, width: 1000, height: 776)
    ),
    (
      frame: NSRect(x: 1000, y: 0, width: 1000, height: 800),
      visible: NSRect(x: 1000, y: 0, width: 1000, height: 776)
    ),
  ]

  @Test func testAPopupPastADisplaysRightEdgeMovesBackOntoIt() {
    let rect = NSRect(x: 980 - 80, y: 600, width: 160, height: 100)
    let clamped = PopupManager.clamp(rect, screens: screens, fallback: nil)
    #expect(clamped.maxX == 1000)
  }
}

@MainActor
final class MaskedModuleInteractionTests {
  init() {
    // ThemeProvider reads NSApp's appearance.
    _ = NSApplication.shared
  }

  private func module(_ name: String, _ extra: String = "") throws -> ModuleConfig {
    let yaml = try Yaml.load(
      "name: \(name)\ntype: text\nplacement: right\nconfig:\n  value: x\n" + extra)
    return try #require(parseModuleConfig(from: yaml))
  }

  @Test func testAMaskedModulePassesClicksThroughUnlessItSetsAClickType() throws {
    let masked = try module("masked", "mask:\n  name: battery\n")
    let menu = try module(
      "menu", "mask:\n  name: battery\ninteraction:\n  click:\n    type: popup\n")
    #expect(masked.isPassthrough)
    #expect(!menu.isPassthrough)

    let groups = BarViewModel.buildGroupsForPlacement(
      from: [masked, menu].map { ModuleViewModel(moduleConfig: $0) }, placement: "right")
    #expect((groups.map { $0.modules.map(\.moduleConfig.name) }) == [["masked"], ["menu"]])
    #expect(groups.map(\.isPassthrough) == [true, false])
  }

  @Test func testNoDrawerClickPanelCoversTheNativeMenuBar() throws {
    let config = try #require(
      loadConfig(
        from: try Yaml.load(
          """
          modules:
            - name: drawer
              type: drawer
              placement: right
          """)))
    let screen = try #require(NSScreen.screens.first)
    let display = DisplayInstance(screenName: screen.localizedName, barHeight: 24, config: config)
    defer { display.teardown() }
    let bar = BarViewModel(config: config)
    display.createPanels(for: screen, bar: bar, theme: ThemeProvider(config: config))
    display.updateDrawerClickPanels()
    #expect(!display.drawerClickPanels.isEmpty)

    display.isMenuBarShowing = true
    display.updateDrawerClickPanels()
    #expect(display.drawerClickPanels.isEmpty)
    withExtendedLifetime(bar) {}
  }

  @Test func testADrawerOpenedAgainWhileClosingKeepsItsContent() async throws {
    let config = try #require(
      loadConfig(
        from: try Yaml.load(
          """
          modules:
            - name: inside
              type: text
              placement: right
              config:
                value: x
            - name: drawer
              type: drawer
              placement: right
          """)))
    let screen = try #require(NSScreen.screens.first)
    let display = DisplayInstance(screenName: screen.localizedName, barHeight: 24, config: config)
    defer { display.teardown() }
    let bar = BarViewModel(config: config)
    display.createPanels(for: screen, bar: bar, theme: ThemeProvider(config: config))
    let content = display.groupPanels.filter(\.group.isDrawerContent).map(\.panel)
    #expect(!content.isEmpty)

    display.animateDrawerToggle(side: "right", open: true)
    await runMainLoop(for: 0.4)
    display.animateDrawerToggle(side: "right", open: false)
    display.animateDrawerToggle(side: "right", open: true)
    await runMainLoop(for: 0.6)
    #expect(content.allSatisfy { $0.isVisible })
    withExtendedLifetime(bar) {}
  }

  @Test func testShowingTheBarLeavesOutMasksWithNothingToCover() throws {
    let config = try #require(loadConfig(from: try Yaml.load("modules: []")))
    let display = DisplayInstance(screenName: "test", barHeight: 24, config: config)
    let theme = ThemeProvider(config: config)
    let configs = [
      try module("tailscale", "mask:\n  name: tailscale\n"),
      try module("battery", "mask:\n  name: battery\n"),
      try module("hidden", "mask:\n  name: wifi\n"),
      try module("text"),
    ]
    for moduleConfig in configs {
      let vm = ModuleViewModel(moduleConfig: moduleConfig)
      vm.shouldDisplay = moduleConfig.name != "hidden"
      let group = ModuleGroup(
        id: moduleConfig.name, modules: [vm], isPassthrough: true, placement: "right",
        isDrawerContent: false)
      let hostingView = NSHostingView(
        rootView: ModuleGroupView(
          modules: [vm], placement: "right", popupManager: PopupManager(), themeProvider: theme,
          displaced: DisplacedPlacements()))
      let panel = NSPanel(
        contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered,
        defer: true)
      display.groupPanels.append((panel: panel, hostingView: hostingView, group: group))
    }
    func shown(_ items: [NativeMenuBarItem]) -> [String] {
      let panels = display.visiblePanels(nativeItems: items)
      return display.groupPanels.filter { entry in panels.contains { $0 === entry.panel } }
        .map(\.group.id)
    }
    func item(_ identifier: String) -> NativeMenuBarItem {
      NativeMenuBarItem(
        index: 0, cgRect: .zero, owner: "MenuBarAgent", identifier: identifier)
    }

    #expect(shown([item("Battery"), item("WiFi")]) == ["battery", "text"])
    #expect(
      shown([item("Battery"), item("Tailscale"), item("WiFi")]) == ["tailscale", "battery", "text"])
    #expect(shown([]) == ["text"])
  }
}

final class LoadConfigFileTests {
  private var dir: URL!

  init() throws {
    dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(
      at: dir.appendingPathComponent("modules.d"), withIntermediateDirectories: true)
  }

  deinit {
    try? FileManager.default.removeItem(at: dir)
  }

  private func write(_ contents: String, to name: String) throws -> String {
    let file = dir.appendingPathComponent(name)
    try contents.write(to: file, atomically: true, encoding: .utf8)
    return file.path
  }

  private var modulesDir: String { dir.appendingPathComponent("modules.d").path }

  @Test func testAPerModeThemeTakesAMissingModeFromTheOther() throws {
    try FileManager.default.createDirectory(
      at: dir.appendingPathComponent("themes"), withIntermediateDirectories: true)
    _ = try write(
      "dark:\n  fg: \"#eeeeee\"\n  bg: \"#111111\"\n", to: "themes/night.yaml")
    let theme = loadThemeConfig(
      from: try Yaml.load("light: night\ndark: night\n"), configDir: dir.path)
    #expect(theme?.lightPalette.bg == "#111111")
    #expect(theme?.darkPalette.bg == "#111111")
  }

  @Test func testAModuleNamedLikeAnEarlierOneIsSkipped() throws {
    let path = try write(
      """
      modules:
        - {name: a, type: text, placement: left, config: {value: one}}
        - {name: a, type: text, placement: left, config: {value: two}}
        - {name: b, type: text, placement: right, config: {value: three}}
      """, to: "config.yaml")
    _ = try write(
      "{name: b, type: text, placement: left, config: {value: four}}\n",
      to: "modules.d/00-b.yaml")
    _ = try write(
      "{name: c, type: text, placement: left, config: {value: five}}\n",
      to: "modules.d/01-c.yaml")
    guard case .success(let config) = loadConfigFile(at: path, modulesDir: modulesDir) else {
      Issue.record("the config didn't load")
      return
    }
    let values = config.modules.map { ($0.config as? TextConfig)?.value }
    #expect(config.modules.map(\.name) == ["a", "c", "b"])
    #expect(values == ["one", "five", "three"])
  }

  @Test func testAnEmptyOrRelativeXDGConfigHomeIsIgnored() {
    let home = ("~/.config" as NSString).expandingTildeInPath
    #expect(xdgConfigHome([:]) == home)
    #expect(xdgConfigHome(["XDG_CONFIG_HOME": ""]) == home)
    #expect(xdgConfigHome(["XDG_CONFIG_HOME": "conf"]) == home)
    #expect(xdgConfigHome(["XDG_CONFIG_HOME": "/etc/xdg"]) == "/etc/xdg")
  }

  @Test func testAConfigInTheWorkingDirectoryIsNotDiscovered() throws {
    let cwdConfig = URL(fileURLWithPath: "config.yaml").standardizedFileURL
    try #require(!FileManager.default.fileExists(atPath: cwdConfig.path))
    try "height: 30\n".write(to: cwdConfig, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: cwdConfig) }
    let environment = ["XDG_CONFIG_HOME": dir.path]
    #expect(resolveConfigPath(explicit: nil, silent: true, environment: environment) == nil)

    try FileManager.default.createDirectory(
      at: dir.appendingPathComponent("kantan"), withIntermediateDirectories: true)
    let xdgConfig = try write("height: 30\n", to: "kantan/config.yaml")
    #expect(
      resolveConfigPath(explicit: nil, silent: true, environment: environment)
        == URL(fileURLWithPath: xdgConfig).standardizedFileURL.path)
  }

  private func error(loading path: String) -> ConfigLoadError? {
    if case .failure(let error) = loadConfigFile(at: path, modulesDir: nil) { return error }
    return nil
  }

  @Test func testFailuresSayWhy() throws {
    #expect(error(loading: dir.appendingPathComponent("missing.yaml").path) == .unreadable)
    guard case .invalidYaml = error(loading: try write("height: [33\n", to: "bad.yaml")) else {
      Issue.record("expected invalid YAML")
      return
    }
    #expect(
      error(loading: try write("style:\n  light:\n    fg: \"#000000\"\n", to: "partial.yaml"))
        == .invalidConfig)
  }

  @Test func testMergesModulesDirAndFallsBackToTheWelcomeModules() throws {
    let path = try write("height: 30\n", to: "config.yaml")
    #expect(
      (try loadConfigFile(at: path, modulesDir: modulesDir).get().modules.map(\.name))
        == Config.welcome.modules.map(\.name))

    _ = try write(
      "name: extra\ntype: text\nplacement: right\nconfig:\n  value: hi\n",
      to: "modules.d/extra.yaml")
    let config = try loadConfigFile(at: path, modulesDir: modulesDir).get()
    #expect(config.height == 30)
    #expect(config.modules.map(\.name) == ["extra"])
  }

  @Test func testTheLoadErrorBarNamesTheFileAndWhy() {
    let config = Config.loadError(.invalidConfig, path: "/a/b/config.yaml")
    #expect(
      (config.modules.compactMap { ($0.config as? TextConfig)?.value }) == [
        "config.yaml isn't a valid configuration", "Fix it and save to reload",
      ])
  }
}

final class LoadConfigTests {
  @Test func testMinimalConfigReturnsNativeAppearance() throws {
    let yaml = try Yaml.load("height: 33\npadding: 10\n")
    let config = try #require(loadConfig(from: yaml))
    #expect(config.height == 33)
    #expect(config.padding == 10)
    #expect(config.isNativeAppearance)
    #expect(config.modules.isEmpty)
  }

  @Test func testReturnsNilWhenStyleIncompleteWithoutTheme() throws {
    let yaml = try Yaml.load(
      """
      height: 33
      padding: 10
      style:
        light:
          fg: "#000000"
      """)
    #expect(loadConfig(from: yaml) == nil)
  }

  @Test func testParsesTextModule() throws {
    let yaml = try Yaml.load(
      """
      height: 33
      padding: 10
      modules:
        - name: greeting
          placement: left
          type: text
          config:
            value: hello
      """)
    let config = try #require(loadConfig(from: yaml))
    #expect(config.modules.count == 1)
    #expect(config.modules.first?.name == "greeting")
    #expect(config.modules.first?.type == "text")
  }

  @Test func testSkipsModuleWithUnknownType() throws {
    let yaml = try Yaml.load(
      """
      height: 33
      padding: 10
      modules:
        - name: ghost
          placement: left
          type: nonsense
      """)
    let config = try #require(loadConfig(from: yaml))
    #expect(config.modules.isEmpty)
  }

  @Test func testBlurClampsAboveSixToSix() throws {
    let yaml = try Yaml.load("height: 33\npadding: 10\nblur: 100\n")
    #expect(loadConfig(from: yaml)?.blur == 6)
  }

  @Test func testAutohideParsesEnabledAndDelay() throws {
    let yaml = try Yaml.load(
      """
      height: 33
      padding: 10
      autohide:
        enabled: false
        delay: 0.5
      """)
    let config = try #require(loadConfig(from: yaml))
    #expect(config.autohide.enabled == false)
    #expect(config.autohide.delay == 0.5)
  }
}

// MARK: - ViewNode JSON decoding (plugin protocol)

final class ViewNodeJSONDecodingTests {
  private func decode(_ json: String) throws -> ViewNode {
    try JSONDecoder().decode(ViewNode.self, from: Data(json.utf8))
  }

  @Test func testVstackWithSpacingAndChildren() throws {
    let json = #"{"type":"vstack","spacing":4,"children":[{"type":"text","content":"a"}]}"#
    guard case .vstack(let spacing, _, let children, _) = try decode(json) else {
      Issue.record("expected vstack")
      return
    }
    #expect(spacing == 4)
    #expect(children.count == 1)
  }

  @Test func testCheckAcceptsBoolForChecked() throws {
    let json = #"{"type":"check","label":"Done","checked":true}"#
    guard case .check(_, let checked, _, _, _) = try decode(json) else {
      Issue.record("expected check")
      return
    }
    #expect(checked == "true")
  }

  @Test func testForeachDecodes() throws {
    let json = #"{"type":"foreach","items":"rows","child":{"type":"text","content":"{name}"}}"#
    guard case .foreach(let items, _, _) = try decode(json) else {
      Issue.record("expected foreach")
      return
    }
    #expect(items == "rows")
  }

  @Test func testIfDecodesWithElse() throws {
    let json = #"""
      {"type":"if","condition":"on","then":{"type":"text","content":"yes"},"else":{"type":"text","content":"no"}}
      """#
    guard case .if(let condition, _, let elseNode, _) = try decode(json) else {
      Issue.record("expected if")
      return
    }
    #expect(condition == "on")
    #expect(elseNode != nil)
  }

  @Test func testCommonPropertiesDecodeAlongsideNode() throws {
    let json = #"""
      {"type":"text","content":"x","padding":8,"opacity":0.5,"background":"#112233"}
      """#
    guard case .text(_, _, _, _, _, _, _, let common) = try decode(json) else {
      Issue.record("expected text")
      return
    }
    #expect(common.opacity == 0.5)
    #expect(common.background == "#112233")
    guard case .uniform(let value) = common.padding else {
      Issue.record("expected uniform padding")
      return
    }
    #expect(value == 8)
  }

  @Test func testPaddingArrayIsRejected() {
    let json = #"{"type":"text","content":"x","padding":[1,2,3,4]}"#
    #expect(throws: (any Error).self) { try decode(json) }
  }

  @Test func testUnknownTypeThrows() {
    #expect(throws: (any Error).self) { try decode(#"{"type":"flibbertigibbet"}"#) }
  }
}

// MARK: - parseViewNodeFromYaml

final class ParseViewNodeFromYamlTests {
  private func yaml(_ source: String) throws -> Yaml {
    try Yaml.load(source)
  }

  @Test func testVstackRecursesIntoChildren() throws {
    let y = try yaml(
      """
      type: vstack
      spacing: 4
      children:
        - type: text
          content: a
        - type: text
          content: b
      """)
    guard case .vstack(_, _, let children, _) = parseViewNodeFromYaml(y) else {
      Issue.record("expected vstack")
      return
    }
    #expect(children.count == 2)
  }

  @Test func testPaddingObjectFromYamlMapping() throws {
    let y = try yaml(
      """
      type: vstack
      padding:
        top: 1
        leading: 2
        bottom: 3
        trailing: 4
      children: []
      """)
    guard case .vstack(_, _, _, let common) = parseViewNodeFromYaml(y) else {
      Issue.record("expected vstack")
      return
    }
    guard case .edges(let top, let leading, let bottom, let trailing) = common.padding else {
      Issue.record("expected edges padding")
      return
    }
    #expect(top == 1)
    #expect(leading == 2)
    #expect(bottom == 3)
    #expect(trailing == 4)
  }

  @Test func testCheckCoercesYamlYesToCanonicalTrue() throws {
    let y = try yaml("type: check\nlabel: Done\nchecked: yes\n")
    guard case .check(_, let checked, _, _, _) = parseViewNodeFromYaml(y) else {
      Issue.record("expected check")
      return
    }
    #expect(checked == dslCanonicalBool(true))
  }

  @Test func testForeachReturnsNilWithoutChild() throws {
    let y = try yaml("type: foreach\nitems: rows\n")
    #expect(parseViewNodeFromYaml(y) == nil)
  }

  @Test func testIfRequiresThenBranch() throws {
    let y = try yaml("type: if\ncondition: x\n")
    #expect(parseViewNodeFromYaml(y) == nil)
  }

  @Test func testUnknownTypeReturnsNil() throws {
    let y = try yaml("type: snickerdoodle")
    #expect(parseViewNodeFromYaml(y) == nil)
  }
}

// MARK: - ModuleViewModel.update() generation guard

private final class CapturingModuleConfig: ModuleConfiguration, @unchecked Sendable {
  var type: String { "captureMock" }
  var redrawInterval: TimeInterval { noPoll }

  private let lock = NSLock()
  private var _completions: [@Sendable (String) -> Void] = []

  var completionCount: Int {
    lock.lock()
    defer { lock.unlock() }
    return _completions.count
  }

  func getValue(completion: @escaping @Sendable (String) -> Void) {
    lock.lock()
    _completions.append(completion)
    lock.unlock()
  }

  func fire(at index: Int, with value: String) {
    lock.lock()
    let comp = _completions[index]
    lock.unlock()
    comp(value)
  }
}

@MainActor
final class ModuleViewModelUpdateGenerationTests {
  private func drainMainQueue() async {
    let exp = Expectation()
    DispatchQueue.main.async { exp.fulfill() }
    #expect(await fulfillment(of: [exp], timeout: 1.0))
  }

  @Test func testResumingUpdatesOnce() {
    let mock = CapturingModuleConfig()
    let vm = ModuleViewModel(
      moduleConfig: ModuleConfig(
        name: "test", placement: PlacementSpec(raw: "left"), type: "test", config: mock))
    #expect(mock.completionCount == 1)
    vm.pause()
    vm.resume()
    #expect(mock.completionCount == 2, "resume should trigger one update()")
  }

  @Test func testStaleCompletionDoesNotOverwriteFreshValue() async {
    let mock = CapturingModuleConfig()
    let cfg = ModuleConfig(
      name: "test", placement: PlacementSpec(raw: "left"), type: "test", config: mock)
    let vm = ModuleViewModel(moduleConfig: cfg)

    #expect(mock.completionCount == 1, "init should trigger one update()")
    vm.update()
    #expect(mock.completionCount == 2)

    mock.fire(at: 1, with: "fresh")
    await drainMainQueue()
    #expect(vm.displayValue == "fresh")

    mock.fire(at: 0, with: "stale")
    await drainMainQueue()
    #expect(
      vm.displayValue == "fresh", "completion captured before the latest update() must be discarded"
    )
  }

  @Test func testInOrderCompletionsApplySequentially() async {
    let mock = CapturingModuleConfig()
    let cfg = ModuleConfig(
      name: "test", placement: PlacementSpec(raw: "left"), type: "test", config: mock)
    let vm = ModuleViewModel(moduleConfig: cfg)

    mock.fire(at: 0, with: "first")
    await drainMainQueue()
    #expect(vm.displayValue == "first")

    vm.update()
    mock.fire(at: 1, with: "second")
    await drainMainQueue()
    #expect(vm.displayValue == "second")
  }
}

// MARK: - Theme template resolution

final class ThemeTemplateResolutionTests {
  private let palette = ThemePalette(
    fg: "#ffffff",
    bg: "#000000",
    shape: "#222222",
    colors: ["accent": "#ff8800", "muted": "#888888"]
  )

  @Test func testResolvesNamedColor() {
    #expect(resolveThemeTemplate("{theme(accent)}", palette: palette) == "#ff8800")
  }

  @Test func testReturnsOriginalForUnknownColor() {
    let input = "{theme(missing)}"
    #expect(resolveThemeTemplate(input, palette: palette) == input)
  }

  @Test func testEmbeddedTemplatesResolvedInPlace() {
    let input = "fg={theme(fg)} bg={theme(bg)}"
    #expect(resolveAllThemeTemplates(input, palette: palette) == "fg=#ffffff bg=#000000")
  }
}

// MARK: - MenuBarItemDetector coordinate conversion

final class MenuBarItemDetectorCoordinateTests {
  @Test func testFlipsYAroundPrimaryHeight() {
    let cg = CGRect(x: 100, y: 0, width: 30, height: 24)
    let ns = MenuBarItemDetector.appKitRect(from: cg, primaryHeight: 900)
    #expect(ns.origin.x == 100)
    #expect(ns.origin.y == CGFloat(900 - 0 - 24))
    #expect(ns.width == 30)
    #expect(ns.height == 24)
  }

  @Test func testCGItemOnSecondaryScreenAbovePrimary() {
    // Secondary screen above primary → CG origin y is negative (above primary top).
    let cg = CGRect(x: -1440, y: -900, width: 30, height: 24)
    let ns = MenuBarItemDetector.appKitRect(from: cg, primaryHeight: 900)
    #expect(ns.origin.x == -1440)
    #expect(ns.origin.y == CGFloat(900 - (-900) - 24))
    #expect(ns.height == 24)
  }
}

// MARK: - WindowListCache

final class WindowListCacheTests {
  private func sample(_ tag: String) -> [[String: Any]] {
    [["tag": tag]]
  }

  @Test func testSecondGetWithinTTLReturnsCached() {
    var cache = WindowListCache()
    var calls = 0
    _ = cache.get(
      now: 100, ttl: 0.15,
      fetch: {
        calls += 1
        return self.sample("a")
      })
    let result = cache.get(
      now: 100.1, ttl: 0.15,
      fetch: {
        calls += 1
        return self.sample("b")
      })
    #expect(calls == 1)
    #expect((result.first?["tag"] as? String) == "a")
  }

  @Test func testGetAfterTTLRefetches() {
    var cache = WindowListCache()
    var calls = 0
    _ = cache.get(
      now: 100, ttl: 0.15,
      fetch: {
        calls += 1
        return self.sample("a")
      })
    let result = cache.get(
      now: 100.16, ttl: 0.15,
      fetch: {
        calls += 1
        return self.sample("b")
      })
    #expect(calls == 2)
    #expect((result.first?["tag"] as? String) == "b")
  }
}

// MARK: - MenuBarItemDetector filterMenuBarItems

final class MenuBarItemDetectorFilterTests {
  private static let statusLevel = Int(CGWindowLevelForKey(.statusWindow))

  private func window(
    owner: String, level: Int = statusLevel, x: CGFloat, y: CGFloat,
    w: CGFloat = 30, h: CGFloat = 24
  ) -> [String: Any] {
    let bounds: [String: CGFloat] = ["X": x, "Y": y, "Width": w, "Height": h]
    return [
      kCGWindowOwnerName as String: owner,
      kCGWindowLayer as String: level,
      kCGWindowBounds as String: bounds as NSDictionary,
    ]
  }

  @Test func testSortsRightToLeftAndIndexes() {
    let windows = [
      window(owner: "ControlCenter", x: 1000, y: 0),
      window(owner: "ControlCenter", x: 1100, y: 0),
      window(owner: "ControlCenter", x: 900, y: 0),
    ]
    let items = MenuBarItemDetector.filterMenuBarItems(
      from: windows, primaryHeight: 1080,
      screenFrame: NSRect(x: 0, y: 0, width: 1920, height: 1080))
    #expect(items.count == 3)
    #expect((items.map { $0.cgRect.origin.x }) == [1100, 1000, 900])
    #expect((items.map { $0.index }) == [0, 1, 2])
  }

  @Test func testDropsNonStatusLevelWindows() {
    let windows = [
      window(owner: "ControlCenter", x: 1000, y: 0),
      window(owner: "OtherApp", level: 0, x: 1100, y: 0),
    ]
    let items = MenuBarItemDetector.filterMenuBarItems(
      from: windows, primaryHeight: 1080,
      screenFrame: NSRect(x: 0, y: 0, width: 1920, height: 1080))
    #expect(items.count == 1)
    #expect(items.first?.owner == "ControlCenter")
  }

  @Test func testFiltersByScreenXRange() {
    // Two screens side-by-side: primary 0..1920, secondary 1920..3840.
    // An item at CG X >= 1920 belongs to the secondary screen, not primary.
    let windows = [
      window(owner: "ControlCenter", x: 1500, y: 0),
      window(owner: "ControlCenter", x: 2500, y: 0),
    ]
    let primary = MenuBarItemDetector.filterMenuBarItems(
      from: windows, primaryHeight: 1080,
      screenFrame: NSRect(x: 0, y: 0, width: 1920, height: 1080))
    #expect(primary.count == 1)
    #expect(primary.first?.cgRect.origin.x == 1500)

    let secondary = MenuBarItemDetector.filterMenuBarItems(
      from: windows, primaryHeight: 1080,
      screenFrame: NSRect(x: 1920, y: 0, width: 1920, height: 1080))
    #expect(secondary.count == 1)
    #expect(secondary.first?.cgRect.origin.x == 2500)
  }

  @Test func testSecondaryScreenAbovePrimary() {
    // Secondary screen above primary in NSScreen coords: screen.frame.maxY > primaryHeight.
    // CG Y of secondary's top = primaryHeight - screen.frame.maxY (negative).
    let primaryHeight: CGFloat = 1080
    let secondaryFrame = NSRect(x: 0, y: 1080, width: 1920, height: 1080)
    let cgTop = primaryHeight - secondaryFrame.maxY  // -1080
    let windows = [
      window(owner: "ControlCenter", x: 1000, y: cgTop),
      window(owner: "ControlCenter", x: 1100, y: 0),  // on primary
    ]
    let items = MenuBarItemDetector.filterMenuBarItems(
      from: windows, primaryHeight: primaryHeight, screenFrame: secondaryFrame)
    #expect(items.count == 1)
    #expect(items.first?.cgRect.origin.y == cgTop)
  }
}

// MARK: - PersistedMenuBarLayout

final class PersistedMenuBarLayoutTests {
  /// Control Centre module positions captured on macOS 27 with a 1512×982
  /// primary display. The frames asserted below are what Accessibility
  /// reported for the same layout.
  private let positions: [String: Double] = [
    "module:Clock": 0,
    "module:BentoBox-0": 36.5,
    "module:Battery": 62.5,
    "module:WiFi": 88.5,
    "module:Sound": 110.5,
    "module:Bluetooth": 132.5,
    "module:FocusModes": 148.5,
  ]
  private let screen = NSRect(x: 0, y: 0, width: 1512, height: 982)

  private func layout(_ positions: [String: Double], screenFrame: NSRect? = nil)
    -> [NativeMenuBarItem]
  {
    PersistedMenuBarLayout.items(
      from: positions, screenFrame: screenFrame ?? screen,
      primaryHeight: 982, menuBarHeight: 33)
  }

  private func item(_ id: String, in items: [NativeMenuBarItem]) -> NativeMenuBarItem? {
    items.first { $0.identifier == id }
  }

  @Test func testModuleContentMatchesMeasuredFrames() {
    let measured: [String: (x: CGFloat, width: CGFloat)] = [
      "Clock": (1455, 37), "BentoBox-0": (1413, 26), "Battery": (1371, 26),
      "WiFi": (1333, 22), "Sound": (1295, 22), "Bluetooth": (1263, 16),
      "FocusModes": (1225, 22),
    ]
    let items = layout(positions)
    for (id, frame) in measured {
      guard let found = item(id, in: items) else {
        Issue.record("missing \(id)")
        return
      }
      let content = found.cgRect.insetBy(dx: PersistedMenuBarLayout.moduleSpacing / 2, dy: 0)
      #expect(abs(content.minX - frame.x) <= 1, "\(id)")
      #expect(abs(content.maxX - (frame.x + frame.width)) <= 1, "\(id)")
    }
  }

  @Test func testModuleSlotsAbutLikeWindowBackedItems() {
    let items = layout(positions)
    #expect(items.first?.cgRect.maxX == (1512 - PersistedMenuBarLayout.trailingEdgeInset))
    for (right, left) in zip(items, items.dropFirst()) {
      #expect(left.cgRect.maxX == right.cgRect.minX)
    }
  }

  @Test func testSortsRightToLeftAndIndexes() {
    let items = layout(positions)
    #expect(
      (Array(items.prefix(7)).map { $0.identifier }) == [
        "Clock", "BentoBox-0", "Battery", "WiFi", "Sound", "Bluetooth", "FocusModes",
      ])
    #expect((items.map { $0.index }) == Array(0..<positions.count))
  }

  @Test func testLeftmostItemUsesDefaultWidth() {
    let items = layout(["module:Clock": 0, "module:WiFi": 36.5])
    #expect(
      item("WiFi", in: items)?.cgRect.width
        == (PersistedMenuBarLayout.defaultContentWidth + PersistedMenuBarLayout.moduleSpacing))
  }

  @Test func testLaysOutAgainstEachScreensRightEdgeAndTop() {
    let secondary = NSRect(x: 1512, y: -100, width: 1920, height: 1080)
    let items = layout(positions, screenFrame: secondary)
    #expect(items.first?.cgRect.maxX == (secondary.maxX - PersistedMenuBarLayout.trailingEdgeInset))
    #expect(items.first?.cgRect.origin.y == (982 - secondary.maxY))
  }

  @Test func testResolveItemMatchesIdentifiersThroughAliases() {
    let items = layout(positions)
    let resolve = { MenuBarItemDetector.resolveItem(for: MaskConfig(name: $0), from: items) }
    #expect(resolve("Clock")?.identifier == "Clock")
    #expect(resolve("ControlCenter")?.identifier == "BentoBox-0")
    #expect(resolve("Volume")?.identifier == "Sound")
    #expect(resolve("Focus")?.identifier == "FocusModes")
    #expect(resolve("WiFi")?.identifier == "WiFi")
    #expect(resolve("NowPlaying") == nil)
    #expect(
      MenuBarItemDetector.resolveItem(for: MaskConfig(index: 1), from: items)?.identifier
        == "BentoBox-0")
  }

  /// `com.apple.controlcenter` defaults from the machine the fixture above
  /// was captured on, including a stale key and a hidden module.
  private let controlCentreDefaults: [String: Any] = [
    "NSStatusItem Preferred Position BentoBox-0": 63,
    "NSStatusItem Preferred Position Battery": 105,
    "NSStatusItem Preferred Position WiFi": 147,
    "NSStatusItem Preferred Position Sound": 185,
    "NSStatusItem Preferred Position Bluetooth": 223,
    "NSStatusItem Preferred Position FocusModes": 255,
    "NSStatusItem Preferred Position StageManager": 326,
    "NSStatusItem Preferred Position BentoBox": 143,
    "NSStatusItem Visible StageManager": 0,
    "NSStatusItem VisibleCC Clock": 1,
  ]

  @Test func testLegacyPositionsMatchMenuBarAgentPositions() {
    let legacy = PersistedMenuBarLayout.legacyPositions { self.controlCentreDefaults[$0] }
    #expect(legacy == (positions.filter { $0.key.hasPrefix("module:") }))
  }

  @Test func testLegacyPositionsWithoutClockStartAtEdge() {
    var defaults = controlCentreDefaults
    defaults["NSStatusItem VisibleCC Clock"] = 0
    let legacy = PersistedMenuBarLayout.legacyPositions { defaults[$0] }
    #expect(legacy["module:Clock"] == nil)
    #expect(legacy["module:BentoBox-0"] == Double(63 + 1.5 - 12))
    #expect(legacy["module:Battery"] == Double(105 + 1.5 - 12 - 16))
  }
}

// MARK: - Menu bar Accessibility

final class MenuBarAccessibilityTests {
  private let screen = NSRect(x: 0, y: 0, width: 1512, height: 982)

  private func system(_ name: String, _ x: CGFloat, _ width: CGFloat) -> AccessibleMenuBarItem {
    AccessibleMenuBarItem(
      frame: CGRect(x: x, y: 0, width: width, height: 33),
      identifier: "com.apple.menuextra.\(name)", owner: "MenuBarAgent",
      appNames: ["com.apple.MenuBarAgent", "MenuBarAgent"], isMenuBarAgentItem: true)
  }

  private func app(_ names: [String], _ x: CGFloat, _ width: CGFloat) -> AccessibleMenuBarItem {
    AccessibleMenuBarItem(
      frame: CGRect(x: x, y: 4.5, width: width, height: 24), identifier: nil,
      owner: names[names.count > 1 ? 1 : 0], appNames: names, isMenuBarAgentItem: false)
  }

  /// What Accessibility reported on macOS 27 for the layout in
  /// `PersistedMenuBarLayoutTests`, plus the third-party items to its left.
  private var reported: [AccessibleMenuBarItem] {
    [
      system("focusmode", 1225, 22), system("bluetooth", 1263, 16), system("sound", 1295, 22),
      system("wifi", 1333, 22), system("battery", 1371, 26), system("controlcenter", 1413, 26),
      system("clock", 1455, 37),
      app(["io.tailscale.ipn.macos", "Tailscale", "Tailscale"], 1186, 24),
      app(["rift", "rift"], 1150, 22),
      app(["com.1password.1password", "1Password", "1Password"], 1110, 34),
      app(["org.pqrs.Karabiner-Menu", "Karabiner-Menu", "Karabiner-Menu"], 1081, 31),
    ]
  }

  private func layout(
    _ items: [AccessibleMenuBarItem], on screenFrame: NSRect? = nil,
    screens: [NSRect]? = nil
  ) -> [NativeMenuBarItem] {
    MenuBarAccessibility.items(
      from: items, screenFrame: screenFrame ?? screen, screenFrames: screens ?? [screen],
      primaryHeight: 982, menuBarHeight: 33)
  }

  private func resolve(_ name: String, in items: [NativeMenuBarItem]) -> NativeMenuBarItem? {
    MenuBarItemDetector.resolveItem(for: MaskConfig(name: name), from: items)
  }

  @Test func testSystemSlotsMatchControlCentreReconstruction() {
    let positions: [String: Double] = [
      "module:Clock": 0, "module:BentoBox-0": 36.5, "module:Battery": 62.5,
      "module:WiFi": 88.5, "module:Sound": 110.5, "module:Bluetooth": 132.5,
      "module:FocusModes": 148.5,
    ]
    let reconstructed = PersistedMenuBarLayout.items(
      from: positions, screenFrame: screen, primaryHeight: 982, menuBarHeight: 33)
    let live = layout(reported)
    for expected in reconstructed {
      guard let found = live.first(where: { $0.identifier == expected.identifier }) else {
        Issue.record("missing \(expected.identifier ?? "?")")
        return
      }
      #expect(abs(found.cgRect.minX - expected.cgRect.minX) <= 1)
      #expect(abs(found.cgRect.width - expected.cgRect.width) <= 1)
      #expect(found.cgRect.origin.y == 0)
      #expect(found.cgRect.height == 33)
    }
  }

  @Test func testThirdPartyItemsKeepTheirFrame() {
    let rift = resolve("rift", in: layout(reported))
    #expect(rift?.cgRect == CGRect(x: 1150, y: 0, width: 22, height: 33))
    #expect(rift?.identifier == nil)
  }

  @Test func testSortsRightToLeftAndIndexes() {
    let items = layout(reported)
    #expect(
      (items.prefix(8).map { $0.identifier ?? $0.owner }) == [
        "Clock", "BentoBox-0", "Battery", "WiFi", "Sound", "Bluetooth", "FocusModes", "Tailscale",
      ])
    #expect((items.map { $0.index }) == Array(0..<reported.count))
    #expect(
      MenuBarItemDetector.resolveItem(for: MaskConfig(index: 8), from: items)?.owner == "rift")
  }

  @Test func testMasksNameSystemItemsThroughAliasesAndIdentifiers() {
    let items = layout(reported)
    #expect(resolve("Focus", in: items)?.identifier == "FocusModes")
    #expect(resolve("Volume", in: items)?.identifier == "Sound")
    #expect(resolve("ControlCenter", in: items)?.identifier == "BentoBox-0")
    #expect(resolve("wifi", in: items)?.identifier == "WiFi")
    #expect(resolve("com.apple.menuextra.battery", in: items)?.identifier == "Battery")
    #expect(resolve("NowPlaying", in: items) == nil)
  }

  @Test func testMasksNameThirdPartyItemsByApp() {
    let items = layout(reported)
    #expect(resolve("RIFT", in: items)?.owner == "rift")
    #expect(resolve("com.1password.1password", in: items)?.owner == "1Password")
    #expect(resolve("1password", in: items)?.owner == "1Password")
    #expect(resolve("Karabiner-Menu", in: items)?.owner == "Karabiner-Menu")
    #expect(resolve("Raycast", in: items) == nil)
  }

  @Test func testRightmostItemOfAnAppWins() {
    let items = layout([
      app(["com.example.menus", "Menus"], 1000, 30), app(["com.example.menus", "Menus"], 1100, 30),
    ])
    #expect(resolve("Menus", in: items)?.cgRect.minX == 1100)
  }

  @Test func testItemsMoveAcrossToEachScreen() {
    let secondary = NSRect(x: 1512, y: -100, width: 1920, height: 1080)
    let items = layout(reported, on: secondary, screens: [screen, secondary])
    let clock = items.first { $0.identifier == "Clock" }
    #expect(clock?.cgRect.maxX == (secondary.maxX - PersistedMenuBarLayout.trailingEdgeInset))
    #expect(clock?.cgRect.origin.y == (982 - secondary.maxY))
    #expect(resolve("rift", in: items)?.cgRect.minX == (1150 + secondary.maxX - screen.maxX))
  }

  @Test func testItemsOffEveryScreenAreDropped() {
    let offscreen = AccessibleMenuBarItem(
      frame: CGRect(x: -500, y: 0, width: 22, height: 33), identifier: nil, owner: "Ghost",
      appNames: ["Ghost"], isMenuBarAgentItem: false)
    #expect(layout([offscreen]).isEmpty)
  }

  @Test func testControlCentreIdentifierForName() {
    #expect(MenuBarAccessibility.controlCentreIdentifier(forName: "focusmode") == "FocusModes")
    #expect(MenuBarAccessibility.controlCentreIdentifier(forName: "clock") == "Clock")
    #expect(MenuBarAccessibility.controlCentreIdentifier(forName: "nowplaying") == "NowPlaying")
    #expect(MenuBarAccessibility.controlCentreIdentifier(forName: "spotlight") == "spotlight")
  }

  @Test func testNeededOnlyForMasksOrFocusWithoutFullDiskAccess() {
    func module(_ type: String, mask: MaskConfig? = nil) -> ModuleConfig {
      ModuleConfig(name: type, placement: PlacementSpec(raw: "right"), type: type, mask: mask)
    }
    let plain = [module("clock"), module("bluetooth")]
    #expect(!MenuBarAccessibility.isNeeded(by: plain, fullDiskAccess: false))
    #expect(
      MenuBarAccessibility.isNeeded(
        by: plain + [module("text", mask: MaskConfig(name: "rift"))], fullDiskAccess: true))
    #expect(MenuBarAccessibility.isNeeded(by: [module("focus")], fullDiskAccess: false))
    #expect(!MenuBarAccessibility.isNeeded(by: [module("focus")], fullDiskAccess: true))
  }
}

// MARK: - Full Disk Access

final class FullDiskAccessTests {
  @Test(
    .enabled(
      if: FileManager.default.fileExists(atPath: "/Library/Application Support/com.apple.TCC"),
      "needs the host's TCC directory"))
  func testProbeFileExists() {
    // A missing probe file reads as "not granted" even with access granted.
    #expect(FileManager.default.fileExists(atPath: FullDiskAccess.probePath))
  }
}

// MARK: - Focus database

final class FocusDatabaseTests {
  private let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    // British Summer Time, London's offset all that week.
    calendar.timeZone = TimeZone(secondsFromGMT: 3600)!
    return calendar
  }()

  /// Local time on a day in the week of Monday 2026-09-21.
  private func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
    calendar.date(
      from: DateComponents(year: 2026, month: 9, day: day, hour: hour, minute: minute))!
  }

  /// Schedules mirroring a real `ModeConfigurations.json`: Mindfulness
  /// through the day, Do Not Disturb overnight, and a disabled Work schedule.
  private let modeConfigurations = """
    {"data": [{"modeConfigurations": {
      "com.apple.focus.mindfulness": {
        "mode": {"name": "Mindfulness", "modeIdentifier": "com.apple.focus.mindfulness"},
        "triggers": {"triggers": [
          {"class": "DNDModeConfigurationMindfulnessTrigger", "enabledSetting": 2},
          {"class": "DNDModeConfigurationScheduleTrigger", "enabledSetting": 2,
           "timePeriodStartTimeHour": 7, "timePeriodStartTimeMinute": 0,
           "timePeriodEndTimeHour": 21, "timePeriodEndTimeMinute": 30, "timePeriodWeekdays": 127}
        ]}
      },
      "com.apple.donotdisturb.mode.default": {
        "mode": {"name": "Do Not Disturb", "modeIdentifier": "com.apple.donotdisturb.mode.default"},
        "triggers": {"triggers": [
          {"class": "DNDModeConfigurationScheduleTrigger", "enabledSetting": 2,
           "timePeriodStartTimeHour": 21, "timePeriodStartTimeMinute": 30,
           "timePeriodEndTimeHour": 6, "timePeriodEndTimeMinute": 30, "timePeriodWeekdays": 127}
        ]}
      },
      "com.apple.focus.work": {
        "mode": {"name": "Work", "modeIdentifier": "com.apple.focus.work"},
        "triggers": {"triggers": [
          {"class": "DNDModeConfigurationScheduleTrigger", "enabledSetting": 1,
           "timePeriodStartTimeHour": 9, "timePeriodStartTimeMinute": 0,
           "timePeriodEndTimeHour": 17, "timePeriodEndTimeMinute": 0, "timePeriodWeekdays": 31}
        ]}
      },
      "com.apple.sleep.sleep-mode": {
        "mode": {"name": "Sleep", "modeIdentifier": "com.apple.sleep.sleep-mode"}
      }
    }}]}
    """

  /// `Assertions.json` with the given active assertions and invalidation
  /// requests, shaped like the file `donotdisturbd` writes.
  private func assertions(
    active: [(mode: String, start: Date)] = [],
    requests: [(predicate: String, date: Date)] = []
  ) -> String {
    let records = active.map {
      """
      {"assertionUUID": "\(UUID())",
       "assertionSource": {"assertionClientIdentifier": "com.apple.focus.activity-manager"},
       "assertionStartDateTimestamp": \($0.start.timeIntervalSinceReferenceDate),
       "assertionDetails": {"assertionDetailsIdentifier": "com.apple.focus.activity-manager",
         "assertionDetailsModeIdentifier": "\($0.mode)", "assertionDetailsReason": "user-action"}}
      """
    }
    let invalidations = requests.map {
      """
      {"invalidationRequestPredicate": {"invalidationPredicateType": "\($0.predicate)"},
       "invalidationRequestReason": "user-changed-state",
       "invalidationRequestDateTimestamp": \($0.date.timeIntervalSinceReferenceDate)}
      """
    }
    return """
      {"data": [{"storeAssertionRecords": [\(records.joined(separator: ","))],
                 "storeInvalidationRequestRecords": [\(invalidations.joined(separator: ","))],
                 "storeInvalidationRecords": []}]}
      """
  }

  private func database(_ assertionsJSON: String) -> FocusDatabase {
    FocusDatabase(
      assertionsJSON: Data(assertionsJSON.utf8),
      modeConfigurationsJSON: Data(modeConfigurations.utf8))!
  }

  private func activeName(_ assertionsJSON: String, at date: Date) -> String? {
    database(assertionsJSON).activeMode(at: date, calendar: calendar)?.name
  }

  @Test func testParsesModesAndOnlyEnabledSchedules() {
    let db = database(assertions())
    #expect(db.modes["com.apple.focus.mindfulness"]?.name == "Mindfulness")
    #expect(db.modes["com.apple.sleep.sleep-mode"]?.name == "Sleep")
    #expect(
      Set(db.schedules.map { $0.modeIdentifier }) == [
        "com.apple.focus.mindfulness", "com.apple.donotdisturb.mode.default",
      ])
  }

  @Test func testScheduledModeIsActiveWithoutAssertions() {
    #expect(activeName(assertions(), at: at(24, 15, 34)) == "Mindfulness")
    #expect(activeName(assertions(), at: at(24, 22)) == "Do Not Disturb")
  }

  @Test func testOvernightScheduleCarriesIntoNextMorning() {
    #expect(activeName(assertions(), at: at(25, 3)) == "Do Not Disturb")
    #expect(activeName(assertions(), at: at(25, 6, 45)) == nil)
  }

  @Test func testDisabledScheduleIsIgnored() {
    // Work's 09:00–17:00 weekday schedule is disabled; Mindfulness covers the day.
    #expect(activeName(assertions(), at: at(24, 10)) == "Mindfulness")
  }

  @Test func testAssertionNamesTheActiveMode() {
    let json = assertions(active: [("com.apple.donotdisturb.mode.default", at(24, 15, 34))])
    #expect(activeName(json, at: at(24, 15, 35)) == "Do Not Disturb")
  }

  @Test func testLaterScheduleWindowOverridesEarlierAssertion() {
    let json = assertions(active: [("com.apple.focus.mindfulness", at(24, 15, 34))])
    #expect(activeName(json, at: at(24, 22)) == "Do Not Disturb")
  }

  @Test func testStateChangeEndsScheduleUntilNextWindow() {
    let json = assertions(requests: [("any", at(24, 15, 34))])
    #expect(activeName(json, at: at(24, 15, 35)) == nil)
    #expect(activeName(json, at: at(24, 21, 31)) == "Do Not Disturb")
  }

  @Test func testTargetedInvalidationDoesNotEndSchedule() {
    let json = assertions(requests: [("uuid", at(24, 15, 34))])
    #expect(activeName(json, at: at(24, 15, 35)) == "Mindfulness")
  }

  @Test func testWeekdayBitsStartOnMonday() {
    // 31 = Monday–Friday, 96 = Saturday–Sunday.
    let weekdays = FocusSchedule(
      modeIdentifier: "m", startMinute: 6 * 60 + 30, endMinute: 9 * 60, weekdays: 31)
    let weekend = FocusSchedule(
      modeIdentifier: "m", startMinute: 6 * 60 + 30, endMinute: 21 * 60 + 30, weekdays: 96)
    #expect(weekdays.activeWindowStart(at: at(21, 8), calendar: calendar) != nil)  // Monday
    #expect(weekdays.activeWindowStart(at: at(25, 8), calendar: calendar) != nil)  // Friday
    #expect(weekdays.activeWindowStart(at: at(26, 8), calendar: calendar) == nil)  // Saturday
    #expect(weekend.activeWindowStart(at: at(27, 12), calendar: calendar) != nil)  // Sunday
    #expect(weekend.activeWindowStart(at: at(25, 12), calendar: calendar) == nil)  // Friday
  }

  @Test func testOvernightWindowBelongsToItsStartDay() {
    // Friday only (bit 4), 21:30–06:30.
    let friday = FocusSchedule(
      modeIdentifier: "m", startMinute: 21 * 60 + 30, endMinute: 6 * 60 + 30, weekdays: 1 << 4)
    #expect(friday.activeWindowStart(at: at(26, 3), calendar: calendar) == at(25, 21, 30))
    #expect(friday.activeWindowStart(at: at(25, 3), calendar: calendar) == nil)
  }

  @Test func testUnreadableDatabaseIsNil() {
    #expect(FocusDatabase(assertionsJSON: Data("{}".utf8), modeConfigurationsJSON: Data()) == nil)
    #expect(
      FocusDatabase.load(from: URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)")) == nil)
  }

  @Test func testEntryMatchesModeNameThenIdentifier() {
    let mindfulness = FocusMode(identifier: "com.apple.focus.mindfulness", name: "Mindfulness")
    let dnd = FocusMode(identifier: "com.apple.donotdisturb.mode.default", name: "Do Not Disturb")
    let icons = ["Mindfulness": "brain", "com.apple.donotdisturb.mode.default": "moon-filled"]
    #expect(FocusConfig.entry(for: mindfulness, in: icons) == "brain")
    #expect(FocusConfig.entry(for: dnd, in: icons) == "moon-filled")
    #expect(FocusConfig.entry(for: FocusMode(identifier: "x", name: "Work"), in: icons) == nil)
    #expect(FocusConfig.entry(for: nil, in: icons) == nil)
  }

  @Test func testFactoryParsesIconAndStyleMaps() throws {
    let yaml = try Yaml.load(
      """
      icons:
        Mindfulness: brain
        Do Not Disturb: moon-filled
      style:
        Mindfulness: '{theme(teal)}'
        com.apple.focus.work:
          icon:
            fg: '{theme(peach)}'
          bg: '#313244'
        Sleep: {}
      """)
    let config = try FocusConfigFactory().configuration(from: yaml, configDir: nil, theme: nil)
    let focus = try #require(config as? FocusConfig)
    #expect(focus.icons == ["Mindfulness": "brain", "Do Not Disturb": "moon-filled"])
    #expect(
      focus.styles == [
        "Mindfulness": StateStyle(fg: "{theme(teal)}", bg: nil, iconFg: nil, textFg: nil),
        "com.apple.focus.work": StateStyle(
          fg: nil, bg: "#313244", iconFg: "{theme(peach)}", textFg: nil),
      ])
    let defaults = try #require(FocusConfigFactory().defaultConfiguration() as? FocusConfig)
    #expect(defaults.icons == [:])
    #expect(defaults.styles == [:])
  }
}

// MARK: - State style

final class StateStyleTests {
  @Test func testStringShorthandSetsForeground() throws {
    #expect(
      StateStyle.parse(from: try Yaml.load("'{theme(red)}'"))
        == StateStyle(fg: "{theme(red)}", bg: nil, iconFg: nil, textFg: nil))
  }

  @Test func testExpandedFormReadsEachElement() throws {
    let yaml = try Yaml.load(
      """
      fg: '#ffffff'
      bg: '#000000'
      icon:
        fg: '{theme(peach)}'
      text:
        fg: '{theme(text)}'
      """)
    let style = try #require(StateStyle.parse(from: yaml))
    #expect(
      style
        == StateStyle(
          fg: "#ffffff", bg: "#000000", iconFg: "{theme(peach)}", textFg: "{theme(text)}"))
    #expect(style.toDynamicStyle().iconFg == "{theme(peach)}")
  }
}

// MARK: - Screen diff

final class ScreenDiffTests {
  @Test func testMixedAddAndRemove() {
    let diff = computeScreenDiff(existing: ["A", "B", "C"], target: ["B", "C", "D"])
    #expect(diff.toAdd == ["D"])
    #expect(diff.toRemove == ["A"])
  }

  @Test func testReorderingAloneProducesNoChanges() {
    let diff = computeScreenDiff(existing: ["A", "B", "C"], target: ["C", "B", "A"])
    #expect(diff.toAdd.isEmpty)
    #expect(diff.toRemove.isEmpty)
  }
}

// MARK: - ScreenLayout

final class ScreenLayoutTests {
  @Test func testSecondaryScreenOffsetToRight() {
    let frame = NSRect(x: 1920, y: 0, width: 1440, height: 900)
    let gaps = GapsConfig(top: 0, left: 0, right: 0)
    let layout = ScreenLayout(screenFrame: frame, gaps: gaps, height: 24)
    #expect(layout.screenLeft == 1920)
    #expect(layout.screenRight == 3360)
    #expect(layout.statusBarY == CGFloat(900 - 24))
    #expect(layout.barFrame == NSRect(x: 1920, y: 876, width: 1440, height: 24))
  }

  @Test func testTopGapPushesStatusBarDown() {
    let frame = NSRect(x: 0, y: 0, width: 1000, height: 800)
    let gaps = GapsConfig(top: 10, left: 0, right: 0)
    let layout = ScreenLayout(screenFrame: frame, gaps: gaps, height: 30)
    #expect(layout.statusBarY == CGFloat(800 - 30 - 10))
    #expect(layout.barFrame.origin.y == layout.statusBarY)
  }
}

// MARK: - Workspace rainbow memoisation

final class ShuffledRainbowTests {
  @Test func testIsDeterministicForSameInputs() {
    let a = WorkspaceConfig.shuffledRainbow(["r", "g", "b", "y"], spaceCount: 4)
    let b = WorkspaceConfig.shuffledRainbow(["r", "g", "b", "y"], spaceCount: 4)
    #expect(a == b)
  }

  @Test func testNoAdjacentRepeatsWhenCycling() {
    let result = WorkspaceConfig.shuffledRainbow(["r", "g", "b"], spaceCount: 10)
    for i in 1..<result.count {
      #expect(result[i] != result[i - 1])
    }
  }
}

// MARK: - Workspace providers

/// A temporary directory holding executables at the given relative paths.
private func makeExecutables(_ paths: [String]) throws -> URL {
  let root = FileManager.default.temporaryDirectory
    .appendingPathComponent("kantan-\(UUID().uuidString)")
  for path in paths {
    let file = root.appendingPathComponent(path)
    try FileManager.default.createDirectory(
      at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    FileManager.default.createFile(
      atPath: file.path, contents: Data(), attributes: [.posixPermissions: 0o755])
  }
  return root
}

final class WorkspaceProviderSelectionTests {
  @Test func testTypeSelectsProvider() throws {
    #expect(WorkspaceConfig(yaml: nil).provider is NativeWorkspaces)
    #expect(
      WorkspaceConfig(yaml: try Yaml.load("type: aerospace\n")).provider is AerospaceWorkspaces)
    #expect(WorkspaceConfig(yaml: try Yaml.load("type: rift\n")).provider is RiftWorkspaces)
  }

  @Test func testScrollingSubscribesRiftToScrollEvents() throws {
    let plain = try #require(
      WorkspaceConfig(yaml: try Yaml.load("type: rift\n")).provider as? RiftWorkspaces)
    #expect(!plain.scrolling)
    let scrolling = try #require(
      WorkspaceConfig(yaml: try Yaml.load("type: rift\nscrolling:\n  enabled: true\n")).provider
        as? RiftWorkspaces)
    #expect(scrolling.scrolling)
  }
}

// MARK: - Workspace scrolling

/// A provider whose first read is slow and reports workspace 1, and whose
/// later reads report workspace 2.
private final class SlowFirstReadWorkspaces: WorkspaceProvider, @unchecked Sendable {
  private let reads = OSAllocatedUnfairLock(initialState: 0)

  func workspaces() -> [Workspace] {
    let read = reads.withLock {
      $0 += 1
      return $0
    }
    if read == 1 { Thread.sleep(forTimeInterval: 0.3) }
    return [
      Workspace(index: 0, label: "1", isActive: read == 1),
      Workspace(index: 1, label: "2", isActive: read != 1),
    ]
  }
}

final class NativeWorkspacesTests {
  private func display(current: Int?, spaces: [(id: Int, type: Int)]) -> [String: Any] {
    var display: [String: Any] = ["Spaces": spaces.map { ["id64": $0.id, "type": $0.type] }]
    if let current { display["Current Space"] = ["id64": current] }
    return display
  }

  @Test func testEachDisplaysCurrentSpaceIsActive() {
    let workspaces = NativeWorkspaces.workspaces(
      of: [
        display(current: 2, spaces: [(1, 0), (2, 0)]),
        display(current: 3, spaces: [(3, 0), (4, 0)]),
      ], activeSpace: 2)
    #expect(workspaces.map(\.isActive) == [false, true, true, false])
  }

  @Test func testOnlyDesktopsAreShown() {
    let workspaces = NativeWorkspaces.workspaces(
      of: [display(current: 1, spaces: [(1, 0), (2, 4), (3, 0), (4, 2), (5, 0)])],
      activeSpace: 1)
    #expect(workspaces.map(\.label) == ["1", "3", "5"])
  }

  @Test func testADisplayNamingNoCurrentSpaceUsesTheActiveOne() {
    let workspaces = NativeWorkspaces.workspaces(
      of: [display(current: nil, spaces: [(1, 0), (2, 0)])], activeSpace: 2)
    #expect(workspaces.map(\.isActive) == [false, true])
  }
}

final class RunCommandSyncTests {
  @Test func testAHungCommandIsStoppedAtItsTimeout() {
    let start = Date()
    #expect(runCommandSync(path: "/bin/sleep", arguments: ["10"], timeout: 0.3) == nil)
    #expect(Date().timeIntervalSince(start) < 3)
  }
}

final class WorkspaceReadOrderTests {
  @Test func testASlowEarlierReadDoesntReplaceALaterOne() async {
    let config = WorkspaceConfig(yaml: nil, provider: SlowFirstReadWorkspaces())
    let done = [Expectation(), Expectation()]
    config.getValue { _ in done[0].fulfill() }
    try? await Task.sleep(for: .milliseconds(50))
    config.getValue { _ in done[1].fulfill() }
    #expect(await fulfillment(of: done, timeout: 2))
    #expect(config.display.segments.map(\.isActive) == [false, true])
  }
}

final class WorkspaceScrollingTests {
  private let scroll = [
    ScrollWindow(
      id: "1-1", app: "Ghostty", bundleIdentifier: "com.mitchellh.ghostty", isSelected: false),
    ScrollWindow(
      id: "2-1", app: "Arc", bundleIdentifier: "company.thebrowser.Browser", isSelected: true),
    ScrollWindow(id: "3-1", app: "Emacs", bundleIdentifier: "org.gnu.Emacs", isSelected: false),
  ]

  private func workspaces(activeScroll: [ScrollWindow]?) -> [Workspace] {
    [
      Workspace(index: 0, label: "1", isActive: false, hasWindows: true),
      Workspace(index: 1, label: "2", isActive: true, hasWindows: true, scroll: activeScroll),
      Workspace(index: 2, label: "3", isActive: false),
      Workspace(index: 3, label: "4", isActive: false, hasWindows: true),
    ]
  }

  private func config(_ yaml: String) throws -> WorkspaceConfig {
    WorkspaceConfig(yaml: try Yaml.load(yaml))
  }

  @Test func testParsesScrollingConfig() throws {
    let scrolling = try config(
      """
      scrolling:
        enabled: true
        icon: app-window
        workspaces: false
        icons:
          Ghostty: terminal-2
      """
    ).scrolling
    #expect(scrolling.enabled)
    #expect(scrolling.icon == "app-window")
    #expect(!scrolling.showsWorkspaces)
    #expect(scrolling.icons == ["ghostty": "terminal-2"])
  }

  @Test func testWindowIconsMatchBundleIdentifierThenNameIgnoringCase() {
    let scrolling = ScrollingConfig(
      enabled: true, icon: "fallback",
      icons: ["COM.MITCHELLH.GHOSTTY": "terminal-2", "arc": "world", "Browser": "unused"],
      showsWorkspaces: true)
    #expect(scroll.map(scrolling.icon(for:)) == ["terminal-2", "world", "fallback"])
  }

  @Test func testShowsTheActiveScrollsWindows() throws {
    let display = try config(
      """
      scrolling:
        enabled: true
        icons:
          Ghostty: terminal-2
      """
    ).display(of: workspaces(activeScroll: scroll))
    #expect(display.isScroll)
    #expect(display.slot?.id == "workspace-1")
    #expect(display.segments.map(\.id) == ["window-1-1", "window-2-1", "window-3-1"])
    #expect(display.segments.map(\.isActive) == [false, true, false])
    #expect(
      display.segments.map(\.label)
        == (["terminal-2", ScrollingConfig.defaultIcon, ScrollingConfig.defaultIcon].map {
          resolveIconName($0).glyph
        }))
  }

  @Test func testPipsShowWorkspacesWithWindowsAndTheActiveOne() throws {
    let display = try config("scrolling:\n  enabled: true\n").display(
      of: workspaces(activeScroll: scroll))
    #expect(display.pips.map(\.id) == ["workspace-0", "workspace-1", "workspace-3"])
    #expect(display.pips.map(\.isActive) == [false, true, false])
  }

  @Test func testWindowsTakeTheActiveWorkspacesRainbowColour() throws {
    let display = try config(
      """
      scrolling:
        enabled: true
      rainbow:
        enabled: true
        random: false
        colors: [red, green, blue]
      """
    ).display(of: workspaces(activeScroll: scroll))
    #expect(display.segments.map(\.colorOverride) == ["green", "green", "green"])
    #expect(display.pips.map(\.colorOverride) == ["red", "green", "red"])
  }

  @Test func testScrollRainbowColoursWindowsByApp() throws {
    let config = try config(
      """
      scrolling:
        enabled: true
        rainbow:
          enabled: true
      rainbow:
        enabled: true
        random: false
        colors: [red, green, blue, cyan, magenta, yellow]
      """)
    let second = ScrollWindow(
      id: "4-1", app: "Ghostty", bundleIdentifier: "com.mitchellh.ghostty", isSelected: false)
    let colors = config.display(of: workspaces(activeScroll: scroll + [second])).segments.map {
      $0.colorOverride
    }
    let palette = ["red", "green", "blue", "cyan", "magenta", "yellow"]
    #expect(colors.allSatisfy { $0.map(palette.contains) == true })
    #expect(colors[0] == colors[3])
    #expect(
      config.scrolling.color(for: scroll[0])
        == config.scrolling.color(
          for: ScrollWindow(
            id: "9-9", app: "ghostty", bundleIdentifier: "COM.MITCHELLH.GHOSTTY", isSelected: true))
    )
  }

  @Test func testSummaryChangesWithWhatIsShown() throws {
    let config = try config("scrolling:\n  enabled: true\n")
    let workspaces = config.display(of: workspaces(activeScroll: nil))
    let windows = config.display(of: self.workspaces(activeScroll: scroll))
    let moved = config.display(
      of: self.workspaces(
        activeScroll: scroll.map {
          ScrollWindow(
            id: $0.id, app: $0.app, bundleIdentifier: $0.bundleIdentifier,
            isSelected: $0.id == "1-1")
        }))
    #expect(Set([workspaces.summary, windows.summary, moved.summary]).count == 3)
  }
}

final class RiftWorkspacesTests {
  @Test func testParsesWorkspacesInIndexOrder() {
    let json = """
      [{"id":"VirtualWorkspaceId(2v1)","index":1,"is_active":true,"layout_mode":"bsp",
        "name":"code","window_count":0,"windows":[]},
       {"id":"VirtualWorkspaceId(1v1)","index":0,"is_active":false,"layout_mode":"scrolling",
        "name":"web","window_count":1,"windows":[{"app_name":"Arc","id":{"idx":1,"pid":2}}]},
       {"id":"VirtualWorkspaceId(3v1)","index":2,"is_active":false,"layout_mode":"traditional",
        "name":"chat","window_count":0,"windows":[]}]
      """
    #expect(
      RiftWorkspaces.parse(Data(json.utf8)) == [
        Workspace(index: 0, label: "web", isActive: false, hasWindows: true, scroll: []),
        Workspace(index: 1, label: "code", isActive: true),
        Workspace(index: 2, label: "chat", isActive: false),
      ])
  }

  @Test func testParsesScrollInStripOrderWithoutFloatingWindows() {
    let json = """
      [{"index":0,"is_active":true,"layout_mode":"scrolling","name":"1","window_count":5,
        "windows":[
          {"app_name":"Emacs","bundle_id":"org.gnu.Emacs","id":{"idx":4,"pid":40},
           "is_floating":false,"is_focused":false,"layout_position":{"column":1,"row":1}},
          {"app_name":"Ghostty","bundle_id":"com.mitchellh.ghostty","id":{"idx":1,"pid":10},
           "is_floating":false,"is_focused":true,"layout_position":{"column":0,"row":0}},
          {"app_name":"Finder","id":{"idx":5,"pid":50},"is_floating":true,"is_focused":false},
          {"app_name":"Arc","id":{"idx":2,"pid":20},"is_floating":false,"is_focused":false,
           "layout_position":{"column":1,"row":0}},
          {"app_name":"Mail","id":{"idx":6,"pid":60},"is_floating":false,"is_focused":false}]}]
      """
    #expect(
      RiftWorkspaces.parse(Data(json.utf8)).first?.scroll == [
        ScrollWindow(
          id: "10-1", app: "Ghostty", bundleIdentifier: "com.mitchellh.ghostty", isSelected: true),
        ScrollWindow(id: "20-2", app: "Arc", bundleIdentifier: nil, isSelected: false),
        ScrollWindow(
          id: "40-4", app: "Emacs", bundleIdentifier: "org.gnu.Emacs", isSelected: false),
      ])
  }

  @Test func testReadsTheLayoutsSelectedWindow() {
    let layout = #"{"mode":"scrolling","focused_window":null,"selected_window":{"idx":2,"pid":20}}"#
    #expect(RiftWorkspaces.selectedWindow(in: Data(layout.utf8)) == "20-2")
    #expect(RiftWorkspaces.selectedWindow(in: Data(#"{"selected_window":null}"#.utf8)) == nil)
    #expect(RiftWorkspaces.selectedWindow(in: Data("Failed to connect".utf8)) == nil)
  }

  @Test func testSelectingAWindowOutsideTheScrollKeepsItsSelection() {
    let focused = ScrollWindow(id: "1-1", app: "Ghostty", bundleIdentifier: nil, isSelected: true)
    let other = ScrollWindow(id: "2-1", app: "Arc", bundleIdentifier: nil, isSelected: false)
    var workspace = Workspace(index: 0, label: "1", isActive: true, scroll: [focused, other])

    workspace.selectWindow("9-9")
    #expect(workspace.scroll?.map(\.isSelected) == [true, false])
    workspace.selectWindow("2-1")
    #expect(workspace.scroll?.map(\.isSelected) == [false, true])
  }

  @Test func testScrollEventsExcludeTitlesStacksAndOtherLayouts() {
    let events = [
      #"{"type":"workspace_changed","space_id":1}"#: true,
      #"{"type":"windows_changed","windows":[]}"#: true,
      #"{"type":"focused_window_changed","window_id":{"idx":1,"pid":2}}"#: true,
      #"{"type":"layout_changed","layout":{"mode":"scrolling"}}"#: true,
      #"{"type":"selection_changed","layout":{"mode":"scrolling"}}"#: true,
      #"{"type":"layout_changed","layout":{"mode":"bsp"}}"#: false,
      #"{"type":"window_title_changed","new_title":"x"}"#: false,
      #"{"type":"stacks_changed","stacks":[]}"#: false,
      "not json": false,
    ]
    for (event, affects) in events {
      #expect(RiftWorkspaces.affectsScroll(Data(event.utf8)) == affects, "\(event)")
    }
  }

  @Test func testMalformedOutputYieldsNoWorkspaces() {
    #expect(RiftWorkspaces.parse(Data("Failed to connect".utf8)).isEmpty)
  }

  @Test func testFindsCLIBesideRunningRift() throws {
    let bin = try makeExecutables(["rift"])
    defer { try? FileManager.default.removeItem(at: bin) }
    let running = [nil, URL(fileURLWithPath: "/usr/bin/true"), bin.appendingPathComponent("rift")]
    #expect(RiftWorkspaces.cli(among: running) == nil)

    FileManager.default.createFile(
      atPath: bin.appendingPathComponent("rift-cli").path, contents: Data(),
      attributes: [.posixPermissions: 0o755])
    #expect(RiftWorkspaces.cli(among: running) == bin.appendingPathComponent("rift-cli").path)
    #expect(RiftWorkspaces.cli(among: [URL(fileURLWithPath: "/usr/bin/true")]) == nil)
  }
}

final class AerospaceWorkspacesTests {
  @Test func testParsesNumericWorkspacesFirstInNumericOrder() {
    let all = #"[{"workspace":"B"},{"workspace":"10"},{"workspace":"2"},{"workspace":"A"}]"#
    let focused = #"[{"workspace":"10"}]"#
    #expect(
      AerospaceWorkspaces.parse(all: Data(all.utf8), focused: Data(focused.utf8)) == [
        Workspace(index: 0, label: "2", isActive: false),
        Workspace(index: 1, label: "10", isActive: true),
        Workspace(index: 2, label: "A", isActive: false),
        Workspace(index: 3, label: "B", isActive: false),
      ])
  }

  @Test func testFindsCLIBesideReleaseArchiveApp() throws {
    let root = try makeExecutables(["AeroSpace-v1/bin/aerospace"])
    defer { try? FileManager.default.removeItem(at: root) }
    #expect(
      AerospaceWorkspaces.cli(
        forApp: root.appendingPathComponent("AeroSpace-v1/AeroSpace.app"), fallbacks: [])
        == root.appendingPathComponent("AeroSpace-v1/bin/aerospace").path)
  }

  @Test func testFindsCLIInNixPackageLayout() throws {
    let root = try makeExecutables(["out/bin/aerospace"])
    defer { try? FileManager.default.removeItem(at: root) }
    #expect(
      AerospaceWorkspaces.cli(
        forApp: root.appendingPathComponent("out/Applications/AeroSpace.app"), fallbacks: [])
        == root.appendingPathComponent("out/bin/aerospace").path)
  }

  @Test func testFallsBackWhenAppShipsNoCLI() throws {
    let root = try makeExecutables(["homebrew/bin/aerospace"])
    defer { try? FileManager.default.removeItem(at: root) }
    let homebrew = root.appendingPathComponent("homebrew/bin/aerospace").path
    #expect(
      AerospaceWorkspaces.cli(
        forApp: root.appendingPathComponent("Applications/AeroSpace.app"),
        fallbacks: [root.appendingPathComponent("missing/aerospace").path, homebrew]) == homebrew)
    #expect(
      AerospaceWorkspaces.cli(
        forApp: root.appendingPathComponent("Applications/AeroSpace.app"), fallbacks: []) == nil)
  }
}

// MARK: - Workspace activation

final class WorkspaceActivationTests {
  private let scroll = [
    ScrollWindow(id: "10-1", app: "Ghostty", bundleIdentifier: nil, isSelected: false),
    ScrollWindow(id: "20-2", app: "Arc", bundleIdentifier: nil, isSelected: true),
    ScrollWindow(id: "30-3", app: "Emacs", bundleIdentifier: nil, isSelected: false),
  ]

  private let spaces = [
    Workspace(index: 0, label: "web", isActive: false, hasWindows: true),
    Workspace(index: 1, label: "code", isActive: true),
    Workspace(index: 2, label: "chat", isActive: false),
  ]

  @Test func testWorkspaceSegmentsTargetTheirWorkspaceExceptTheActiveOne() {
    #expect(
      WorkspaceConfig(yaml: nil).display(of: spaces).segments.map(\.target) == [
        .workspace(index: 0, label: "web"), nil, .workspace(index: 2, label: "chat"),
      ])
  }

  @Test func testScrollSegmentsTargetTheirWindowsAndPipsTheirWorkspaces() throws {
    var spaces = self.spaces
    spaces[1].scroll = scroll
    let display = WorkspaceConfig(yaml: try Yaml.load("scrolling:\n  enabled: true\n"))
      .display(of: spaces)
    #expect(
      display.segments.map(\.target) == [
        .window(id: "10-1"), .window(id: "20-2"), .window(id: "30-3"),
      ])
    #expect(display.pips.map(\.target) == [.workspace(index: 0, label: "web"), nil])
  }

  @Test func testSteppingMovesFromTheActiveSegmentAndStopsAtTheEnds() {
    let display = WorkspaceConfig(yaml: nil).display(of: spaces)
    #expect(display.target(steppingBy: 1) == .workspace(index: 2, label: "chat"))
    #expect(display.target(steppingBy: -1) == .workspace(index: 0, label: "web"))
    #expect(display.target(steppingBy: 5) == .workspace(index: 2, label: "chat"))
    #expect(display.target(steppingBy: -5) == .workspace(index: 0, label: "web"))
    #expect(display.target(steppingBy: 0) == nil)
  }

  @Test func testSteppingPastTheLastSegmentOrWithoutAnActiveOneDoesNothing() {
    let display = WorkspaceConfig(yaml: nil).display(
      of: [
        Workspace(index: 0, label: "1", isActive: false),
        Workspace(index: 1, label: "2", isActive: true),
      ])
    #expect(display.target(steppingBy: 1) == nil)
    #expect(WorkspaceDisplay().target(steppingBy: 1) == nil)
  }

  @Test func testRiftSwitchesWorkspacesByIndexAndFocusesWindowsByID() {
    #expect(
      RiftWorkspaces.arguments(for: .workspace(index: 3, label: "chat")) == [
        "execute", "workspace", "switch", "3",
      ])
    #expect(
      RiftWorkspaces.arguments(for: .window(id: "96136-21335")) == [
        "execute", "window", "focus", "--window-id", #"{"pid":96136,"idx":21335}"#,
      ])
    #expect(RiftWorkspaces.arguments(for: .window(id: "not-a-window")) == nil)
  }

  @Test func testAerospaceSwitchesWorkspacesByName() {
    #expect(
      AerospaceWorkspaces.arguments(for: .workspace(index: 0, label: "web")) == [
        "workspace", "web",
      ])
    #expect(AerospaceWorkspaces.arguments(for: .window(id: "1-1")) == nil)
  }

  @Test func testSegmentsSwitchWithProvidersThatCanUnlessTheModuleHasAClick() throws {
    func module(_ type: String, click: String? = nil) throws -> ModuleConfig {
      ModuleConfig(
        name: "spaces", placement: PlacementSpec(raw: "left"), type: "workspace",
        config: WorkspaceConfig(yaml: try Yaml.load("type: \(type)\n")),
        interaction: click.map { InteractionConfig(hover: nil, click: ClickConfig(type: $0)) })
    }
    #expect(WorkspaceModuleView.activates(try module("rift")))
    #expect(WorkspaceModuleView.activates(try module("aerospace")))
    #expect(!WorkspaceModuleView.activates(try module("native")))
    #expect(!WorkspaceModuleView.activates(try module("rift", click: "menu")))
  }
}

// MARK: - Scroll stepping

final class ScrollStepperTests {
  private func scroll(
    _ delta: CGFloat, precise: Bool = true, begins: Bool = false, momentum: Bool = false
  ) -> ScrollWheelDelta {
    ScrollWheelDelta(delta: delta, isPrecise: precise, begins: begins, isMomentum: momentum)
  }

  @Test func testEachWheelNotchStepsOnce() {
    var stepper = ScrollStepper()
    #expect(stepper.steps(for: scroll(-3, precise: false)) == 1)
    #expect(stepper.steps(for: scroll(1, precise: false)) == -1)
    #expect(stepper.steps(for: scroll(0, precise: false)) == 0)
  }

  @Test func testTrackpadStepsOncePerDistanceScrolled() {
    var stepper = ScrollStepper()
    let half = ScrollStepper.distance / 2
    #expect(stepper.steps(for: scroll(-half, begins: true)) == 0)
    #expect(stepper.steps(for: scroll(-half)) == 1)
    #expect(stepper.steps(for: scroll(-ScrollStepper.distance * 2)) == 2)
    #expect(stepper.steps(for: scroll(ScrollStepper.distance)) == -1)
  }

  @Test func testANewGestureStartsAfresh() {
    var stepper = ScrollStepper()
    let most = ScrollStepper.distance * 0.75
    #expect(stepper.steps(for: scroll(-most, begins: true)) == 0)
    #expect(stepper.steps(for: scroll(-most, begins: true)) == 0)
  }

  @Test func testReversingDirectionStartsAfresh() {
    var stepper = ScrollStepper()
    let most = ScrollStepper.distance * 0.75
    #expect(stepper.steps(for: scroll(-most)) == 0)
    #expect(stepper.steps(for: scroll(most)) == 0)
    #expect(stepper.steps(for: scroll(most)) == -1)
  }

  @Test func testMomentumDoesNotStep() {
    var stepper = ScrollStepper()
    #expect(stepper.steps(for: scroll(-ScrollStepper.distance * 3, momentum: true)) == 0)
  }
}

// MARK: - Event stream process

final class EventStreamProcessTests {
  @Test func testRestartDelayDoublesToCap() {
    #expect(
      ((1...7).map { EventStreamProcess.restartDelay(afterFailures: $0) }) == [
        1, 2, 4, 8, 16, 16, 16,
      ])
  }

  @Test func testOutputFiresEvent() async {
    let event = Expectation()
    let stream = EventStreamProcess(
      command: { ["/bin/sh", "-c", "echo changed; sleep 5"] }
    ) { event.fulfill() }
    stream.start()
    #expect(await fulfillment(of: [event], timeout: 2))
    stream.stop()
  }

  @Test func testRelaunchAfterExitFiresEvent() async {
    let event = Expectation()
    let stream = EventStreamProcess(
      command: { ["/bin/sh", "-c", "exit 1"] }
    ) { event.fulfill() }
    stream.start()
    #expect(await fulfillment(of: [event], timeout: 3))
    stream.stop()
  }

  @Test func testLaunchesOnceCommandBecomesAvailable() async {
    let event = Expectation()
    let available = OSAllocatedUnfairLock(initialState: false)
    let stream = EventStreamProcess(
      command: {
        available.withLock { isAvailable in
          defer { isAvailable = true }
          return isAvailable ? ["/bin/sh", "-c", "sleep 5"] : nil
        }
      }
    ) { event.fulfill() }
    stream.start()
    #expect(await fulfillment(of: [event], timeout: 3))
    stream.stop()
  }

  @Test func testAcceptsFiltersLines() async {
    let event = Expectation()
    let stream = EventStreamProcess(
      command: { ["/bin/sh", "-c", "echo skip; printf 'ke'; sleep 0.1; echo ep; sleep 5"] },
      accepts: { $0 == Data("keep".utf8) }
    ) { event.fulfill() }
    stream.start()
    #expect(await fulfillment(of: [event], timeout: 2))
    stream.stop()
  }

  @Test func testRejectedLinesFireNoEvent() async {
    let event = Expectation()
    let stream = EventStreamProcess(
      command: { ["/bin/sh", "-c", "echo skip; echo skip; sleep 5"] },
      accepts: { $0 == Data("keep".utf8) }
    ) { event.fulfill() }
    stream.start()
    #expect(await !fulfillment(of: [event], timeout: 1))
    stream.stop()
  }

  @Test func testCoalescingFiresOncePerBurst() async {
    let events = OSAllocatedUnfairLock(initialState: 0)
    let stream = EventStreamProcess(
      command: { ["/bin/sh", "-c", "for i in 1 2 3 4 5; do echo $i; done; sleep 5"] },
      coalescing: 0.2
    ) { events.withLock { $0 += 1 } }
    stream.start()
    let burst = Expectation()
    DispatchQueue.global().asyncAfter(deadline: .now() + 0.8) { burst.fulfill() }
    #expect(await fulfillment(of: [burst], timeout: 2))
    stream.stop()
    #expect((events.withLock { $0 }) == 1)
  }

  @Test func testStopSilencesStream() async {
    let event = Expectation()
    let stream = EventStreamProcess(
      command: { ["/bin/sh", "-c", "sleep 0.3; echo late"] }
    ) { event.fulfill() }
    stream.start()
    stream.stop()
    #expect(await !fulfillment(of: [event], timeout: 1.5))
  }

  @Test func testStopKillsCommand() throws {
    let pidFile = FileManager.default.temporaryDirectory
      .appendingPathComponent("kantan-stream-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: pidFile) }
    let stream = EventStreamProcess(
      command: { ["/bin/sh", "-c", "echo $$ > \"$0\"; exec sleep 30", pidFile.path] }
    ) {}
    stream.start()

    var pid: pid_t?
    let started = Date()
    while pid == nil, Date().timeIntervalSince(started) < 2 {
      pid = (try? String(contentsOf: pidFile, encoding: .utf8))
        .flatMap { pid_t($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
      usleep(20_000)
    }
    let command = try #require(pid)
    #expect(kill(command, 0) == 0)

    stream.stop()
    let stopped = Date()
    while kill(command, 0) == 0, Date().timeIntervalSince(stopped) < 2 { usleep(20_000) }
    #expect(kill(command, 0) != 0)
  }
}

// MARK: - Command toggle

@MainActor
final class CommandToggleTests {
  init() {
    // handleToggle reads NSApp's appearance for KANTAN_APPEARANCE.
    _ = NSApplication.shared
  }

  private func config(_ yaml: String) throws -> CommandConfig {
    try CommandConfig(yaml: try Yaml.load(yaml))
  }

  @Test func testToggleReturnsBeforeCommandExits() async throws {
    let toggle = try config("command: 'true'\ntoggle: sleep 0.5\n")
    let exited = Expectation()
    let started = Date()
    toggle.handleToggle { exited.fulfill() }
    #expect(Date().timeIntervalSince(started) < 0.2)
    #expect(await fulfillment(of: [exited], timeout: 3))
    #expect(Date().timeIntervalSince(started) >= 0.4)
  }

  @Test func testMissingToggleCompletesImmediately() async throws {
    let toggle = try config("command: 'true'\n")
    let done = Expectation()
    toggle.handleToggle { done.fulfill() }
    #expect(await fulfillment(of: [done], timeout: 0.1))
  }

  @Test func testCommandsAndTogglesAreGivenTheirModuleName() async throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: file) }
    let module = try #require(
      parseModuleConfig(
        from: try Yaml.load(
          """
          name: todo
          type: command
          placement: right
          config:
            command: 'printf %s "$KANTAN_MODULE_NAME"'
            toggle: 'printf %s "$KANTAN_MODULE_NAME" > \(file.path)'
          """)))
    let command = try #require(module.config as? CommandConfig)

    let ran = Expectation()
    let value = OSAllocatedUnfairLock<String?>(initialState: nil)
    command.getValue { output in
      value.withLock { $0 = output }
      ran.fulfill()
    }
    let toggled = Expectation()
    command.handleToggle { toggled.fulfill() }
    #expect(await fulfillment(of: [ran, toggled], timeout: 5))
    #expect((value.withLock { $0 }) == "todo")
    #expect((try String(contentsOf: file, encoding: .utf8)) == "todo")
  }

  @Test func testUnlaunchableToggleStillCompletes() async throws {
    let toggle = try config(
      "command: 'true'\ntoggle: x\nlauncher:\n  path: /nonexistent/sh\n")
    let done = Expectation()
    toggle.handleToggle { done.fulfill() }
    #expect(await fulfillment(of: [done], timeout: 1))
  }
}

// MARK: - Command module icons

/// Runs the main run loop and main actor until `condition` holds or `timeout` passes.
@MainActor
func waitUntil(
  _ condition: () -> Bool, timeout: TimeInterval = 5,
  sourceLocation: SourceLocation = #_sourceLocation
) async {
  let deadline = Date().addingTimeInterval(timeout)
  while !condition() && Date() < deadline {
    await runMainLoop(for: 0.01)
  }
  #expect(condition(), sourceLocation: sourceLocation)
}

@MainActor
final class CommandIconTests {
  init() {
    // getValue reads NSApp's appearance for KANTAN_APPEARANCE.
    _ = NSApplication.shared
  }

  @Test func testIconComesFromTheRunThatProducedTheValue() async throws {
    let dir = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let iconFile = dir.appendingPathComponent("icon")
    let script = dir.appendingPathComponent("emit")
    try """
    #!/bin/sh
    icon=$(cat "\(iconFile.path)")
    printf '{"value":"%s","icon":"%s"}' "$icon" "$icon"
    """.write(to: script, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)

    let command = try CommandConfig(
      yaml: try Yaml.load("command: \(script.path)\noutput: json\ninterval: 0\n"))
    let vm = ModuleViewModel(
      moduleConfig: ModuleConfig(
        name: "icon-test", placement: PlacementSpec(raw: "right"), type: "command",
        config: command))

    try "arrow-up".write(to: iconFile, atomically: true, encoding: .utf8)
    vm.update()
    await waitUntil { vm.displayValue == "arrow-up" }
    #expect(vm.displayIcon == resolveIconName("arrow-up").glyph)

    try "arrow-down".write(to: iconFile, atomically: true, encoding: .utf8)
    vm.update()
    await waitUntil { vm.displayValue == "arrow-down" }
    #expect(vm.displayIcon == resolveIconName("arrow-down").glyph)
  }
}

// MARK: - Watch process restart backoff

final class WatchRestartDelayTests {
  @Test func testDoublesEachAttempt() {
    #expect(ModuleViewModel.watchRestartDelay(forAttempt: 2) == 2.0)
    #expect(ModuleViewModel.watchRestartDelay(forAttempt: 3) == 4.0)
    #expect(ModuleViewModel.watchRestartDelay(forAttempt: 4) == 8.0)
    #expect(ModuleViewModel.watchRestartDelay(forAttempt: 5) == 16.0)
  }

  @Test func testCapsAtSixteenSeconds() {
    #expect(ModuleViewModel.watchRestartDelay(forAttempt: 6) == 16.0)
    #expect(ModuleViewModel.watchRestartDelay(forAttempt: 10) == 16.0)
  }

  @Test func testReturnsNilOnceMaxRestartsExceeded() {
    #expect(
      ModuleViewModel.watchRestartDelay(forAttempt: ModuleViewModel.maxWatchRestarts + 1) == nil)
    #expect(ModuleViewModel.watchRestartDelay(forAttempt: 999) == nil)
  }

  @Test func testAStableRunStartsTheCountAfresh() {
    #expect(
      ModuleViewModel.watchRestartAttempt(after: 9, ranFor: ModuleViewModel.stableWatchRun) == 1)
    #expect(
      ModuleViewModel.watchRestartAttempt(after: 9, ranFor: ModuleViewModel.stableWatchRun - 1)
        == 10)
  }
}

// MARK: - Watch process output

final class LineBufferTests {
  @Test func testTakesCompleteLinesAndHoldsBackTheRest() {
    var buffer = LineBuffer()
    #expect(buffer.append(Data("one\ntw".utf8)) == [Data("one".utf8)])
    #expect(buffer.append(Data("o\n\nthree".utf8)) == [Data("two".utf8), Data()])
    #expect(buffer.append(Data("\n".utf8)) == [Data("three".utf8)])
    #expect(buffer.append(Data()) == [])
  }
}

@MainActor
final class DSLToggleTests {
  /// Shows `json` in a window and returns whether its command touched a file.
  private func ranCommandOnShow(_ on: String) async throws -> Bool {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: file) }
    let json = #"{"type":"toggle","label":"Focus","on":"\#(on)","command":"touch '\#(file.path)'"}"#
    let node = try JSONDecoder().decode(ViewNode.self, from: Data(json.utf8))
    var dismissed = false
    let view = DSLRendererView(
      node: node, resolver: TemplateResolver(variables: [:], data: [:]), isNative: false,
      dismissHandler: { dismissed = true }, depth: 0)
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 200, height: 40), styleMask: [.borderless],
      backing: .buffered, defer: false)
    window.contentView = NSHostingView(rootView: view)
    window.orderFront(nil)
    defer { window.orderOut(nil) }
    await runMainLoop(for: 0.5)
    return dismissed || FileManager.default.fileExists(atPath: file.path)
  }

  @Test func testAMenuToggleInAForeachRunsWithItsItem() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let json = #"""
      {"type":"foreach","items":"devices","child":
        {"type":"toggle","label":"{name}","command":"touch '\#(dir.path)'/{address}"}}
      """#
    let node = try JSONDecoder().decode(ViewNode.self, from: Data(json.utf8))
    let resolver = TemplateResolver(
      variables: [:], data: ["devices": [["name": "Headphones", "address": "aa-bb"]]])
    let menu = buildNativeMenu(from: node, resolver: resolver)
    let view = try #require(
      menu.items.first?.view as? NativeMenuHostedView<NativeMenuToggleView>)
    view.hosting.rootView.action()
    let file = dir.appendingPathComponent("aa-bb").path
    await waitUntil { FileManager.default.fileExists(atPath: file) }
  }

  @Test func testAPopupToggleFollowsItsRowsOn() async throws {
    let node = try JSONDecoder().decode(
      ViewNode.self, from: Data(#"{"type":"toggle","label":"Wi-Fi","on":"{on}"}"#.utf8))
    func view(on: String) -> DSLRendererView {
      DSLRendererView(
        node: node, resolver: TemplateResolver(variables: ["on": on], data: [:]),
        isNative: false, dismissHandler: {}, depth: 0)
    }
    let hosting = NSHostingView(rootView: view(on: "false"))
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 200, height: 40), styleMask: [.borderless],
      backing: .buffered, defer: false)
    window.contentView = hosting
    window.orderFront(nil)
    defer { window.orderOut(nil) }
    func switchState() -> NSControl.StateValue? {
      func find(_ view: NSView) -> NSSwitch? {
        (view as? NSSwitch) ?? view.subviews.lazy.compactMap(find).first
      }
      return find(hosting)?.state
    }
    await runMainLoop(for: 0.3)
    try #require(switchState() != nil)
    #expect(switchState() == .off)
    hosting.rootView = view(on: "true")
    await runMainLoop(for: 0.3)
    #expect(switchState() == .on)
  }

  @Test func testAToggleThatStartsOnDoesNotRunItsCommandWhenShown() async throws {
    #expect(!(try await ranCommandOnShow("true")))
    #expect(!(try await ranCommandOnShow("false")))
  }
}

@MainActor
final class ViewCommandEnvironmentTests {
  @Test func testAModulesViewsRunCommandsWithItsSettings() throws {
    let yaml = try Yaml.load(
      """
      name: pomo
      type: command
      placement: right
      config:
        command: kantan-plugin-pomodoro
        settings:
          work: 50
      """)
    let vm = ModuleViewModel(moduleConfig: try #require(parseModuleConfig(from: yaml)))
    let env = PopupManager().makeResolver(for: LiveContentProvider(viewModel: vm))
      .commandEnvironment
    #expect(env["KANTAN_SETTINGS"] == #"{"work":50}"#)
    #expect(env["KANTAN_MODULE_NAME"] == "pomo")
    #expect(env["KANTAN_APPEARANCE"] != nil)
  }

  @Test func testRunCommandAddsTheEnvironment() async throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: file) }
    runCommand(
      #"printf %s "$KANTAN_SETTINGS" > '\#(file.path)'"#,
      environment: ["KANTAN_SETTINGS": #"{"work":50}"#])
    await waitUntil { (try? String(contentsOf: file, encoding: .utf8)) == #"{"work":50}"# }
  }
}

@MainActor
final class LiveModuleViewTests {
  /// A module that runs nothing, showing `cpu` as its `{cpu}` variable.
  private func viewModel(cpu: String) async throws -> ModuleViewModel {
    let yaml = try Yaml.load(
      """
      name: system-monitor
      type: command
      placement: right
      config:
        command: kantan-plugin-system-monitor
      """)
    let vm = ModuleViewModel(moduleConfig: try #require(parseModuleConfig(from: yaml)))
    vm.suspend()
    // The command's first run, which would otherwise overwrite what the test
    // sets when it finishes.
    await waitUntil { vm.displayValue != nil }
    vm.templateVariables = ["cpu": cpu]
    return vm
  }

  private func node(_ json: String) throws -> ViewNode {
    try JSONDecoder().decode(ViewNode.self, from: Data(json.utf8))
  }

  @Test func testAnOpenMenuShowsTheModulesLatestValues() async throws {
    let vm = try await viewModel(cpu: "5%")
    let live = LiveContentProvider(viewModel: vm)
    let manager = PopupManager()
    let tree = try node(#"{"type":"vstack","children":[{"type":"action","label":"CPU {cpu}"}]}"#)
    let menu = buildNativeMenu(from: tree, resolver: manager.makeResolver(for: live))
    #expect(menu.items.map { $0.attributedTitle?.string } == ["CPU 5%"])
    let item = try #require(menu.items.first)

    var refreshes = 0
    let refresh = live.changes.sink {
      refreshes += 1
      refreshNativeMenu(menu, from: tree, resolver: manager.makeResolver(for: live))
    }
    vm.templateVariables = ["cpu": "42%"]
    vm.displayValue = "42%"
    await waitUntil { menu.items.first?.attributedTitle?.string == "CPU 42%" }
    await runMainLoop(for: 0.2)
    #expect(menu.items.count == 1)
    #expect(menu.items.first === item)
    #expect(refreshes == 1)
    withExtendedLifetime(refresh) {}
  }

  @Test func testAnOpenMenuKeepsItsItemsViewsAsValuesChange() async throws {
    let vm = try await viewModel(cpu: "5%")
    let live = LiveContentProvider(viewModel: vm)
    let manager = PopupManager()
    let tree = try node(
      #"""
      {"type":"vstack","children":[
        {"type":"header","content":"Overview"},
        {"type":"hstack","children":[
          {"type":"text","content":"CPU"},{"type":"spacer"},{"type":"text","content":"{cpu}"}]},
        {"type":"hstack","command":"true","children":[
          {"type":"text","content":"Load"},{"type":"spacer"},{"type":"text","content":"{cpu}"}]},
        {"type":"action","label":"Activity Monitor","command":"true"}]}
      """#)
    let menu = buildNativeMenu(from: tree, resolver: manager.makeResolver(for: live))
    let views = menu.items.map(\.view)
    let title = menu.items.last?.attributedTitle

    vm.templateVariables = ["cpu": "42%"]
    await waitUntil { live.templateVariables["cpu"] == "42%" }
    refreshNativeMenu(menu, from: tree, resolver: manager.makeResolver(for: live))

    #expect(zip(menu.items.map(\.view), views).allSatisfy { $0 === $1 })
    #expect(menu.items.last?.attributedTitle === title)
    let row = try #require(menu.items[1].view as? NativeMenuHostedView<AnyView>)
    var shown = ""
    dump(row.hosting.rootView, to: &shown)
    #expect(shown.contains("42%"))
  }

  @Test func testAnOpenMenuGainsRowsWhenTheModuleDoes() async throws {
    let vm = try await viewModel(cpu: "5%")
    vm.data = ["processes": [["name": "kernel_task"]]]
    let live = LiveContentProvider(viewModel: vm)
    let manager = PopupManager()
    let tree = try node(
      #"{"type":"foreach","items":"processes","child":{"type":"action","label":"{name}"}}"#)
    let menu = buildNativeMenu(from: tree, resolver: manager.makeResolver(for: live))
    #expect(menu.items.map { $0.attributedTitle?.string } == ["kernel_task"])

    let refresh = live.changes.sink {
      refreshNativeMenu(menu, from: tree, resolver: manager.makeResolver(for: live))
    }
    vm.data = ["processes": [["name": "kernel_task"], ["name": "WindowServer"]]]
    await waitUntil {
      menu.items.map { $0.attributedTitle?.string } == ["kernel_task", "WindowServer"]
    }
    withExtendedLifetime(refresh) {}
  }

  @Test func testAClickedMenuCheckHoldsUntilTheModuleReportsAChange() async throws {
    let vm = try await viewModel(cpu: "5%")
    vm.templateVariables = ["done": "false"]
    let live = LiveContentProvider(viewModel: vm)
    let manager = PopupManager()
    let tree = try node(#"{"type":"check","label":"Buy milk","checked":"{done}"}"#)
    let menu = buildNativeMenu(from: tree, resolver: manager.makeResolver(for: live))
    let clicked = try #require(menu.items.first?.view as? NativeMenuCheckItemView)
    let event = try #require(
      NSEvent.mouseEvent(
        with: .leftMouseUp, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
        context: nil, eventNumber: 0, clickCount: 1, pressure: 0))
    clicked.mouseUp(with: event)

    refreshNativeMenu(menu, from: tree, resolver: manager.makeResolver(for: live))
    #expect(menu.items.first?.view === clicked)

    vm.templateVariables = ["done": "true"]
    await waitUntil { live.templateVariables["done"] == "true" }
    refreshNativeMenu(menu, from: tree, resolver: manager.makeResolver(for: live))
    #expect(menu.items.first?.view !== clicked)
  }

  @Test func testAClickedPopupCheckHoldsUntilTheRowOrItsValueChanges() {
    let row = ["Buy milk", "reminders --complete 1", nil]
    let click = CheckFlip(row: row, reported: false)
    #expect(CheckFlip.isChecked(row: row, reported: false, flip: click))
    #expect(CheckFlip.isChecked(row: row, reported: true, flip: click))
    #expect(
      !CheckFlip.isChecked(
        row: ["Walk dog", "reminders --complete 2", nil], reported: false, flip: click))
    #expect(!CheckFlip.isChecked(row: row, reported: false, flip: nil))
  }

  @Test func testAPopupRendersTheModulesLatestValues() async throws {
    let vm = try await viewModel(cpu: "5%")
    let live = LiveContentProvider(viewModel: vm)
    let manager = PopupManager()
    let view = LiveDSLView(
      liveContent: live, configViewTree: try node(#"{"type":"text","content":"CPU {cpu}"}"#),
      makeResolver: { manager.makeResolver(for: $0) }, isNative: false, dismissHandler: {})
    let hosting = NSHostingView(rootView: view)
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 400, height: 40), styleMask: [.borderless],
      backing: .buffered, defer: false)
    window.contentView = hosting
    await runMainLoop(for: 0.1)
    let before = hosting.fittingSize.width

    vm.templateVariables = ["cpu": "42% across every core of this machine"]
    await waitUntil { hosting.fittingSize.width > before }
  }
}

final class CommandWatchOutputTests {
  private func config(_ yaml: String) throws -> CommandConfig {
    try CommandConfig(yaml: try Yaml.load(yaml))
  }

  @Test func testModulesRunningTheSameCommandKeepTheirOwnOutput() throws {
    var work = try config("command: shared-command\noutput: json\n")
    var home = work
    work.moduleName = "work"
    home.moduleName = "home"
    #expect(work.cacheWatchOutput(Data(#"{"value":"1","icon":"briefcase"}"#.utf8)) == "1")
    #expect(home.cacheWatchOutput(Data(#"{"value":"2","icon":"home"}"#.utf8)) == "2")
    #expect(work.getIcon() == "briefcase")
    #expect(home.getIcon() == "home")
  }

  @Test func testJSONObjectLinesBecomeTheCommandsOutput() throws {
    let command = try config("command: watch-output-object\noutput: json\n")
    let line = #"{"value":"3","icon":"bell","variables":{"count":"3"}}"#
    #expect(command.cacheWatchOutput(Data(line.utf8)) == "3")
    #expect(command.getIcon() == "bell")
    #expect(command.getTemplateVariables() == ["count": "3"])
  }

  @Test func testSegmentsColourTheValue() throws {
    let command = try config("command: output-segments\noutput: json\n")
    let segments =
      ##"[{"text":"Review","fg":"#89b4fa"},{"text":" in "},{"fg":"#f38ba8"},"##
      + ##"{"text":"5m","fg":"{theme(red)}"}]"##
    let line = ##"{"value":"Review in 5m","segments":"## + segments + "}"
    #expect(command.cacheWatchOutput(Data(line.utf8)) == "Review in 5m")
    #expect(
      command.getSegments() == [
        ValueSegment(text: "Review", fg: "#89b4fa"), ValueSegment(text: " in ", fg: nil),
        ValueSegment(text: "5m", fg: "{theme(red)}"),
      ])
    #expect(command.cacheWatchOutput(Data(#"{"value":"plain"}"#.utf8)) == "plain")
    #expect(command.getSegments() == [])
  }

  @Test func testOtherLinesAreIgnored() throws {
    let command = try config("command: watch-output-other\noutput: json\n")
    for line in ["starting up", "[1, 2]", "", #"{"value":"#] {
      #expect(command.cacheWatchOutput(Data(line.utf8)) == nil, "\(line)")
    }
    let text = try config("command: watch-output-text\n")
    #expect(text.cacheWatchOutput(Data(#"{"value":"x"}"#.utf8)) == nil)
  }
}

@MainActor
final class BarTeardownTests {
  private final class Module {}

  @Test func testADisplayAddedLaterShowsTheDrawersAsTheBarHasThem() throws {
    _ = NSApplication.shared
    let config = try #require(
      loadConfig(
        from: try Yaml.load(
          "modules:\n  - name: drawer\n    type: drawer\n    placement: right\n")))
    let bar = BarViewModel(config: config)
    let app = AppDelegate()
    app.config = config
    app.barViewModel = bar
    app.themeProvider = ThemeProvider(config: config)
    bar.toggleDrawer(side: "right")
    app.screenDidChange(Notification(name: NSApplication.didChangeScreenParametersNotification))
    defer { app.teardownBar() }
    let display = try #require(app.displayInstances.first)
    #expect(display.rightDrawerOpen)
    #expect(!display.leftDrawerOpen)
  }

  @Test func testTearingDownTheBarClosesItsPopupsAndTooltips() throws {
    _ = NSApplication.shared
    let config = try #require(loadConfig(from: try Yaml.load("modules: []")))
    let bar = BarViewModel(config: config)
    let app = AppDelegate()
    app.barViewModel = bar
    weak var module: Module?
    do {
      let held = Module()
      module = held
      bar.popupManager.showTooltip(
        text: "x", anchorPoint: .zero, refreshProvider: { withExtendedLifetime(held) { "x" } })
    }
    let vm = ModuleViewModel(
      moduleConfig: try #require(
        parseModuleConfig(
          from: try Yaml.load("name: t\ntype: text\nplacement: right\nconfig:\n  value: x\n"))))
    bar.popupManager.showDSLView(
      configViewTree: try JSONDecoder().decode(
        ViewNode.self, from: Data(#"{"type":"text","content":"x"}"#.utf8)),
      moduleName: "t", anchorPoint: .zero, liveContent: LiveContentProvider(viewModel: vm))
    #expect(bar.popupManager.isPopupActive)

    app.teardownBar()
    #expect(!bar.popupManager.isPopupActive)
    #expect(module == nil)
  }
}

@MainActor
final class HotReloadWatchTests {
  @Test func testWatchingResumesOnceAMissingConfigAndModulesDirAppear() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let config = dir.appendingPathComponent("config.yaml")
    let modules = dir.appendingPathComponent("modules.d")
    let app = AppDelegate()
    app.configFilePath = config.path
    app.modulesDirPath = modules.path
    app.startWatchingConfig(path: config.path)
    app.startWatchingModulesDir(path: modules.path)
    #expect(app.configFileSource == nil)
    #expect(app.modulesDirSource == nil)

    // Not a valid config, so the reload this starts keeps the current bar.
    try "[".write(to: config, atomically: true, encoding: .utf8)
    try FileManager.default.createDirectory(at: modules, withIntermediateDirectories: true)
    await waitUntil { app.configFileSource != nil && app.modulesDirSource != nil }
    app.configFilePath = nil
    app.modulesDirPath = nil
    app.configFileSource?.cancel()
    app.modulesDirSource?.cancel()
  }
}

final class CommandOutputDataTests {
  @Test func testABadByteDoesntBlankTheOutput() async throws {
    let config = try CommandConfig(yaml: try Yaml.load(#"command: "printf 'ok \\377'""#))
    let output = OSAllocatedUnfairLock(initialState: "")
    let done = Expectation()
    config.getValue { value in
      output.withLock { $0 = value }
      done.fulfill()
    }
    #expect(await fulfillment(of: [done], timeout: 5))
    #expect(output.withLock { $0 } == "ok \u{FFFD}")
  }

  @Test func testAViewNestedTooDeepIsIgnoredSafely() async throws {
    /// Whether output with a view `depth` stacks deep decodes, on a thread
    /// with a GCD worker's stack.
    func decodes(depth: Int) async throws -> Bool {
      var view = #"{"type":"text","content":"x"}"#
      for _ in 0..<depth { view = #"{"type":"vstack","children":["# + view + "]}" }
      let raw = #"{"value":"v","view":"# + view + "}"
      let json = try #require(
        try JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any])
      let decoded = OSAllocatedUnfairLock(initialState: false)
      let done = Expectation()
      let thread = Thread {
        let (data, _) = CommandConfig.parseOutput(json, raw: raw)
        decoded.withLock { $0 = data.viewTree != nil }
        done.fulfill()
      }
      thread.stackSize = 512 * 1024
      thread.start()
      #expect(await fulfillment(of: [done], timeout: 10))
      return decoded.withLock { $0 }
    }
    #expect(try await decodes(depth: 8))
    #expect(!(try await decodes(depth: 220)))
  }

  @Test func testStyleShapeOverridesTheModulesShape() throws {
    func shape(_ raw: String) throws -> ShapeOverride? {
      let json = try #require(
        try JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any])
      return CommandConfig.parseOutput(json, raw: raw).0.styleShape
    }
    #expect(try shape(#"{"value":"v","style":{"shape":"none"}}"#) == .unshaped)
    #expect(try shape(#"{"value":"v","style":{"shape":"pill"}}"#) == .shaped(.pill))
    #expect(try shape(#"{"value":"v","style":{"shape":"blob"}}"#) == nil)
    #expect(try shape(#"{"value":"v","style":{"fg":"FF0000"}}"#) == nil)
  }

  @Test func testANullDataFieldReadsAsMissing() throws {
    let raw = #"{"value":"v","data":{"items":[{"name":"a","due":null}]}}"#
    let json = try #require(
      try JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any])
    let (data, _) = CommandConfig.parseOutput(json, raw: raw)
    #expect(data.data["items"] == [["name": "a"]])
  }
}

final class CommandViewProblemTests {
  @Test func testABadViewNamesWhereItsWrong() throws {
    let json = #"{"type":"vstack","children":[{"type":"text","content":"x","weight":"extrabold"}]}"#
    do {
      _ = try JSONDecoder().decode(ViewNode.self, from: Data(json.utf8))
      Issue.record("the view decoded")
    } catch {
      #expect(CommandConfig.viewProblem(error).hasPrefix("view.children[0].weight: "))
    }
  }
}

@MainActor
final class CommandPollingTests {
  /// A polling module running `command` every `interval` seconds.
  private func module(_ name: String, command: String, interval: Double) throws
    -> ModuleViewModel
  {
    let config = try CommandConfig(
      yaml: try Yaml.load("command: '\(command) # \(name)'\ninterval: \(interval)\n"))
    return ModuleViewModel(
      moduleConfig: ModuleConfig(
        name: name, placement: PlacementSpec(raw: "right"), type: "command", config: config))
  }

  @Test func testACommandSlowerThanItsIntervalStillShows() async throws {
    let vm = try module("slow-poll", command: "sleep 0.3; echo done", interval: 0.1)
    defer { vm.pause() }
    await waitUntil({ vm.displayValue == "done" }, timeout: 3)
  }

  @Test func testResumingTwicePollsAtTheConfiguredRate() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let log = dir.appendingPathComponent("runs").path
    let vm = try module("resume-twice", command: "echo run >> \(log)", interval: 0.2)
    vm.resume()
    await runMainLoop(for: 0.05)
    vm.resume()
    try? FileManager.default.removeItem(atPath: log)
    await runMainLoop(for: 1.05)
    vm.pause()
    let runs = (try? String(contentsOfFile: log, encoding: .utf8))?.split(separator: "\n") ?? []
    // About 5 polls a second; two timers would make about 10.
    #expect(runs.count <= 7)
  }

  @Test func testASetWithADurationOutlastsARunInFlight() async throws {
    let vm = try module("set-in-flight", command: "sleep 0.3; echo command", interval: 0)
    defer { vm.pause() }
    vm.displayValue = "set"
    vm.scheduleDurationReset(5)
    await runMainLoop(for: 0.6)
    #expect(vm.displayValue == "set")
  }

  @Test func testPollsNeverOverlapARunStillInFlight() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let log = dir.appendingPathComponent("runs").path
    let vm = try module(
      "no-overlap",
      command: "echo start >> \(log); sleep 0.25; echo end >> \(log); echo ok", interval: 0.05)
    await runMainLoop(for: 1)
    vm.pause()
    await runMainLoop(for: 0.4)
    let runs = try String(contentsOfFile: log, encoding: .utf8).split(separator: "\n")
    #expect(runs.count >= 4)
    #expect(runs.enumerated().allSatisfy { $1 == ($0 % 2 == 0 ? "start" : "end") })
  }
}

// Serialized, as one test changes the appearance, which relaunches every
// watch process.
@MainActor @Suite(.serialized)
final class WatchOutputTests {
  private var teardowns: [@MainActor () -> Void] = []

  init() {
    // Watch processes are given NSApp's appearance.
    _ = NSApplication.shared
  }

  /// Runs `block` as the test ends, after any added later.
  private func addTeardownBlock(_ block: @escaping @MainActor () -> Void) {
    teardowns.append(block)
  }

  private func tearDown() {
    teardowns.reversed().forEach { $0() }
  }

  /// A module running `command` with a watch process running `watch`.
  private func module(_ name: String, command: String = "true", watch: String) throws
    -> ModuleViewModel
  {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
    let script = dir.appendingPathComponent("watch")
    try "#!/bin/sh\n\(watch)\n".write(to: script, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
    let config = try CommandConfig(
      yaml: try Yaml.load(
        "command: '\(command.replacingOccurrences(of: "'", with: "''")) # \(name)'\n"
          + "output: json\ninterval: 0\nwatch: \(script.path)\n"))
    let vm = ModuleViewModel(
      moduleConfig: ModuleConfig(
        name: name, placement: PlacementSpec(raw: "right"), type: "command", config: config))
    addTeardownBlock { @MainActor in vm.pause() }
    return vm
  }

  @Test func testAStoppedWatchFinishesOnStdinEOFBeforeBeingTerminated() async throws {
    defer { tearDown() }
    let done = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    addTeardownBlock { try? FileManager.default.removeItem(at: done) }
    let vm = try module(
      "watch-eof",
      watch: """
        echo '{"value":"up"}'
        read _
        sleep 0.2
        echo cleaned > '\(done.path)'
        """)
    await waitUntil { vm.displayValue == "up" }
    vm.pause()
    await waitUntil { FileManager.default.fileExists(atPath: done.path) }
  }

  @Test func testAStoppedWatchThatIgnoresEOFIsTerminated() async throws {
    defer { tearDown() }
    let pidFile = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    addTeardownBlock { try? FileManager.default.removeItem(at: pidFile) }
    let vm = try module(
      "watch-stubborn",
      watch: """
        echo $$ > '\(pidFile.path)'
        echo '{"value":"up"}'
        while :; do sleep 0.1; done
        """)
    await waitUntil { vm.displayValue == "up" }
    let pid = try #require(
      Int32(
        try String(contentsOf: pidFile, encoding: .utf8).trimmingCharacters(
          in: .whitespacesAndNewlines)))
    vm.pause()
    await waitUntil({ kill(pid, 0) != 0 }, timeout: ModuleViewModel.watchStopGrace + 3)
  }

  @Test func testEachLineTheWatchPrintsUpdatesTheModule() async throws {
    defer { tearDown() }
    let vm = try module(
      "watch-lines",
      watch: """
        echo starting
        echo '{"value":"first","icon":"bell","segments":[{"text":"first","fg":"#ff0000"}]}'
        sleep 0.3
        echo 'not json'
        echo '{"value":"second"}'
        cat
        """)
    await waitUntil { vm.displayValue == "first" }
    #expect(vm.displayIcon == resolveIconName("bell").glyph)
    #expect(vm.segments == [ValueSegment(text: "first", fg: "#ff0000")])
    await waitUntil { vm.displayValue == "second" }
    #expect(vm.segments == [])
  }

  @Test func testWatchOutputOutlivesACommandRunStillInFlight() async throws {
    defer { tearDown() }
    let vm = try module(
      "watch-in-flight", command: #"sleep 0.5; echo '{"value":"command"}'"#,
      watch: #"echo '{"value":"watch"}'; cat"#)
    await waitUntil { vm.displayValue == "watch" }
    await runMainLoop(for: 1)
    #expect(vm.displayValue == "watch")
  }

  @Test func testAWatchAndEverythingItStartedStopWhenKantanGoesAway() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let marker = dir.appendingPathComponent("survived").path
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/sh")
    process.arguments = [
      "-c", ModuleViewModel.watchScript, "sh", "(sleep 2.5; touch \(marker)) & sleep 30 | cat",
    ]
    let stdin = Pipe()
    process.standardInput = stdin
    process.standardOutput = FileHandle.nullDevice
    try process.run()
    try await Task.sleep(for: .milliseconds(200))
    // kantan's end of stdin closes however kantan exits, signals included.
    try stdin.fileHandleForWriting.close()
    try await Task.sleep(for: .seconds(3.3))
    #expect(!process.isRunning)
    #expect(!FileManager.default.fileExists(atPath: marker))
    if process.isRunning { process.terminate() }
  }

  @Test func testAWatchStartedDuringARestartsBackoffRunsOnce() async throws {
    defer { tearDown() }
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
    let log = dir.appendingPathComponent("runs").path
    let marker = dir.appendingPathComponent("ran").path
    // Exits the first time, starting a restart's backoff, then stays up.
    let vm = try module(
      "watch-backoff",
      watch: """
        echo run >> \(log)
        [ -e \(marker) ] && exec cat
        touch \(marker)
        """)
    await waitUntil { FileManager.default.fileExists(atPath: marker) }
    await runMainLoop(for: 0.2)
    // As on sleep and wake, inside the 1 s backoff.
    vm.pause()
    vm.resume()
    await runMainLoop(for: 1.5)
    let runs = try String(contentsOfFile: log, encoding: .utf8).split(separator: "\n")
    #expect(runs.count == 2)
  }

  @Test func testTheWatchRelaunchesWithTheNewAppearance() async throws {
    defer { tearDown() }
    NSApp.appearance = NSAppearance(named: .aqua)
    addTeardownBlock { @MainActor in NSApp.appearance = nil }
    let vm = try module(
      "watch-appearance", watch: #"echo "{\"value\":\"$KANTAN_APPEARANCE\"}"; cat"#)
    await waitUntil { vm.displayValue == "light" }
    NSApp.appearance = NSAppearance(named: .darkAqua)
    await waitUntil { vm.displayValue == "dark" }
  }
}

// MARK: - Reposition trigger debouncing

@MainActor
private final class RepositionTriggerSource: ObservableObject {
  @Published var shouldDisplay: Bool = true
  @Published var displayValue: String? = nil
  @Published var displayIcon: String? = nil
}

@MainActor
final class RepositionTriggerMergeTests {
  private func wait(milliseconds: Int) async {
    let exp = Expectation()
    DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(milliseconds)) {
      exp.fulfill()
    }
    #expect(await fulfillment(of: [exp], timeout: 2.0))
  }

  /// Burst changes across all three signals within one debounce window
  /// must fan out to exactly one downstream layout trigger — not three.
  @Test func testMergedPublishersCoalesceBurstIntoSingleTrigger() async {
    let src = RepositionTriggerSource()
    var triggers = 0
    var cancellables: [AnyCancellable] = []

    let shouldDisplay = src.$shouldDisplay.removeDuplicates().map { _ in () }
    let displayValue = src.$displayValue.removeDuplicates().map { _ in () }
    let displayIcon = src.$displayIcon.removeDuplicates().map { _ in () }
    Publishers.Merge3(shouldDisplay, displayValue, displayIcon)
      .debounce(for: .milliseconds(50), scheduler: RunLoop.main)
      .sink { _ in triggers += 1 }
      .store(in: &cancellables)

    // Drain the initial values emitted on subscription.
    await wait(milliseconds: 120)
    let baseline = triggers

    src.shouldDisplay = false
    src.displayValue = "v"
    src.displayIcon = "i"

    await wait(milliseconds: 120)
    #expect(
      (triggers - baseline) == 1,
      "three property changes within one debounce window must produce a single layout pass")
  }
}

// MARK: - ThemeProvider.elementFgColor precedence

@MainActor
final class ThemeProviderElementFgPrecedenceTests {
  init() {
    // Force NSApp to exist so ThemeProvider.init can query effectiveAppearance.
    _ = NSApplication.shared
  }

  private func makeConfig(
    light: StyleModeConfig? = nil,
    dark: StyleModeConfig? = StyleModeConfig(
      fg: "ABCDEF", bg: "000000", text: nil, icon: nil, shape: nil),
    theme: ThemeConfig? = nil
  ) -> Config {
    Config(
      theme: theme,
      style: StyleConfig(light: light, dark: dark),
      height: 33, padding: 10, iconTextSpacing: 4,
      iconFont: nil, textFont: nil, cornerRadius: 0, blur: 0,
      gaps: .default, autohide: .default,
      displays: .main, modules: []
    )
  }

  private func makeVM(style: StyleConfig? = nil) -> ModuleViewModel {
    let cfg = ModuleConfig(
      name: "t", placement: PlacementSpec(raw: "left"), type: "captureMock",
      style: style, config: CapturingModuleConfig())
    return ModuleViewModel(moduleConfig: cfg)
  }

  private func assertColor(_ color: Color, equalsHex hex: String) {
    let actual = NSColor(color).usingColorSpace(.deviceRGB)!
    let expected = NSColor(hex: hex).usingColorSpace(.deviceRGB)!
    #expect(abs(actual.redComponent - expected.redComponent) <= 0.01)
    #expect(abs(actual.greenComponent - expected.greenComponent) <= 0.01)
    #expect(abs(actual.blueComponent - expected.blueComponent) <= 0.01)
  }

  @Test func testColorResolvesHexAndThemeTemplatesButNotUnknownOnes() throws {
    let palette = ThemePalette(fg: "FFFFFF", bg: "000000", shape: nil, colors: ["red": "F38BA8"])
    let theme = ThemeProvider(
      config: makeConfig(theme: ThemeConfig(lightPalette: palette, darkPalette: palette)))
    assertColor(try #require(theme.color("{theme(red)}")), equalsHex: "F38BA8")
    assertColor(try #require(theme.color("#89B4FA")), equalsHex: "89B4FA")
    #expect(theme.color("{theme(absent)}") == nil)
    #expect(ThemeProvider(config: makeConfig()).color("{theme(red)}") == nil)
  }

  @Test func testFgOverrideBypassesAllOtherSources() {
    let theme = ThemeProvider(config: makeConfig())
    theme.isDarkMode = true
    let vm = makeVM(
      style: StyleConfig(
        light: nil,
        dark: StyleModeConfig(
          fg: "111111", bg: nil, text: ElementStyle(fg: "222222"), icon: nil, shape: nil)))
    vm.fgOverride = "FF0000"
    vm.dynamicStyle = DynamicStyleOverride(fg: "00FF00", bg: nil, iconFg: nil, textFg: "0000FF")
    assertColor(theme.textFgColor(for: vm), equalsHex: "FF0000")
  }

  @Test func testDynamicElementFgPrecedesDynamicGenericFg() {
    let theme = ThemeProvider(config: makeConfig())
    theme.isDarkMode = true
    let vm = makeVM()
    vm.dynamicStyle = DynamicStyleOverride(fg: "00FF00", bg: nil, iconFg: nil, textFg: "FF0000")
    assertColor(theme.textFgColor(for: vm), equalsHex: "FF0000")
    vm.dynamicStyle = DynamicStyleOverride(fg: "00FF00", bg: nil, iconFg: "0000FF", textFg: nil)
    assertColor(theme.iconFgColor(for: vm), equalsHex: "0000FF")
  }

  @Test func testModuleGenericFgPrecedesGlobalElementFg() {
    let config = makeConfig(
      dark: StyleModeConfig(
        fg: "111111", bg: "000000",
        text: ElementStyle(fg: "222222"), icon: nil, shape: nil))
    let theme = ThemeProvider(config: config)
    theme.isDarkMode = true
    let vm = makeVM(
      style: StyleConfig(
        light: nil,
        dark: StyleModeConfig(fg: "FF0000", bg: nil, text: nil, icon: nil, shape: nil)))
    assertColor(theme.textFgColor(for: vm), equalsHex: "FF0000")
  }

  @Test func testUnresolvableDynamicTemplateFallsThroughToStatic() {
    // No theme palette set; `{theme(accent)}` cannot resolve.
    let theme = ThemeProvider(config: makeConfig())
    theme.isDarkMode = true
    let vm = makeVM()
    vm.dynamicStyle = DynamicStyleOverride(
      fg: "{theme(accent)}", bg: nil, iconFg: nil, textFg: "{theme(missing)}")
    assertColor(theme.textFgColor(for: vm), equalsHex: "ABCDEF")
  }
}

// MARK: - BluetoothConfig status reads

final class BluetoothStatusReadTests {
  @Test func testIconRendersWithoutReadingStatus() {
    let reads = OSAllocatedUnfairLock(initialState: 0)
    let config = BluetoothConfig(icon: "bluetooth", disabledIcon: "bluetooth-off") {
      reads.withLock { $0 += 1 }
      return .unavailable
    }
    #expect(config.getIcon() == "bluetooth")
    #expect(!config.isActive())
    #expect((reads.withLock { $0 }) == 0)
  }

  @Test func testRefreshReadsOffMainThreadThenRendersResult() async {
    let readOnMain = OSAllocatedUnfairLock<Bool?>(initialState: nil)
    let config = BluetoothConfig(icon: "bluetooth", disabledIcon: "bluetooth-off") {
      readOnMain.withLock { $0 = Thread.isMainThread }
      return BluetoothStatus(
        isPoweredOn: true,
        pairedDevices: [BluetoothDeviceInfo(name: "Buds", address: "aa", isConnected: true)])
    }
    let done = Expectation()
    config.refresh {
      #expect(Thread.isMainThread)
      done.fulfill()
    }
    #expect(await fulfillment(of: [done], timeout: 2))
    #expect((readOnMain.withLock { $0 }) == false)
    #expect(config.getIcon() == "bluetooth")
    #expect(config.isActive())
  }

  @Test func testBlockedReadDoesNotBlockCaller() async {
    let prompt = DispatchSemaphore(value: 0)
    let config = BluetoothConfig(icon: "bluetooth", disabledIcon: "bluetooth-off") {
      prompt.wait()
      return BluetoothStatus(isPoweredOn: false, pairedDevices: [])
    }
    let done = Expectation()
    let started = Date()
    config.refresh { done.fulfill() }
    #expect(config.getIcon() == "bluetooth")
    #expect(Date().timeIntervalSince(started) < 0.5)

    prompt.signal()
    #expect(await fulfillment(of: [done], timeout: 2))
    #expect(config.getIcon() == "bluetooth-off")
  }
}

// MARK: - BluetoothConfig.parseSPBluetoothData

final class BluetoothSystemProfilerParserTests {
  private func parse(_ json: String) -> BluetoothStatus? {
    BluetoothConfig.parseSPBluetoothData(Data(json.utf8))
  }

  @Test func testReportsConnectedDevicesWhenPresent() throws {
    let json = """
      {
        "SPBluetoothDataType": [{
          "controller_properties": { "controller_state": "attrib_on" },
          "device_connected": [
            { "Magic Trackpad": { "device_address": "02:00:00:00:00:01" } }
          ],
          "device_not_connected": [
            { "AirPods Pro": { "device_address": "02:00:00:00:00:02" } }
          ]
        }]
      }
      """
    let status = try #require(parse(json))
    #expect(status.isPoweredOn)
    #expect(status.pairedDevices.count == 2)
    #expect(status.connectedDevices.map(\.name) == ["Magic Trackpad"])
  }

  @Test func testReportsPoweredOffWhenControllerStateIsOff() throws {
    let json = """
      {
        "SPBluetoothDataType": [{
          "controller_properties": { "controller_state": "attrib_off" }
        }]
      }
      """
    let status = try #require(parse(json))
    #expect(!status.isPoweredOn)
    #expect(status.pairedDevices.isEmpty)
  }

  @Test func testReturnsNilForMalformedRoot() {
    #expect(parse("{}") == nil)
    #expect(parse(#"{"SPBluetoothDataType": []}"#) == nil)
    #expect(parse("not json") == nil)
  }
}

// MARK: - Tooltip dismissal

@MainActor
final class TooltipClickTests {
  @Test func testHidingTheTooltipStopsWatchingClicks() {
    _ = NSApplication.shared
    let manager = PopupManager()
    manager.hideTooltipOnClickElsewhere()
    #expect(manager.isWatchingClicksForTooltip)
    manager.hideTooltip()
    #expect(!manager.isWatchingClicksForTooltip)
  }
}

// MARK: - Bundled assets

final class InstallPrefixTests {
  @Test func testAPrefixWithAssetsIsUsedUnresolved() throws {
    let root = try makeExecutables(["store/kantan/bin/kantan"])
    let prefix = root.appendingPathComponent("profile")
    try FileManager.default.createDirectory(
      at: prefix.appendingPathComponent("share/fonts"), withIntermediateDirectories: true)
    try FileManager.default.createDirectory(
      at: prefix.appendingPathComponent("bin"), withIntermediateDirectories: true)
    let link = prefix.appendingPathComponent("bin/kantan")
    try FileManager.default.createSymbolicLink(
      at: link, withDestinationURL: root.appendingPathComponent("store/kantan/bin/kantan"))
    #expect(installPrefix(of: link).path == prefix.path)
  }

  @Test func testAPrefixWithAnotherShareResolvesTheSymlink() throws {
    let root = try makeExecutables(["local/lib/kantan/bin/kantan"])
    let local = root.appendingPathComponent("local")
    try FileManager.default.createDirectory(
      at: local.appendingPathComponent("share/fish"), withIntermediateDirectories: true)
    try FileManager.default.createDirectory(
      at: local.appendingPathComponent("bin"), withIntermediateDirectories: true)
    let link = local.appendingPathComponent("bin/kantan")
    try FileManager.default.createSymbolicLink(
      at: link, withDestinationURL: local.appendingPathComponent("lib/kantan/bin/kantan"))
    #expect(
      installPrefix(of: link).path
        == local.appendingPathComponent("lib/kantan").resolvingSymlinksInPath().path)
  }
}

// MARK: - Tooltip template variables

final class ClockFormatTests {
  /// 2026-11-16 09:05 UTC, a Monday.
  private let date = Date(timeIntervalSince1970: 1_794_819_900)

  @Test func testOrdinalSuffixesFollowEnglishRules() {
    let cases = [
      1: "st", 2: "nd", 3: "rd", 4: "th", 11: "th", 12: "th", 13: "th", 21: "st",
      22: "nd", 23: "rd", 30: "th", 31: "st",
    ]
    for (day, suffix) in cases {
      #expect(ClockConfig.ordinalSuffix(for: day) == suffix, "day \(day)")
    }
  }

  @Test func testDoIsTheOrdinalDay() {
    #expect(ClockConfig.string(from: date, format: "do", timezone: "UTC") == "16th")
    #expect(
      ClockConfig.string(from: date, format: "M/do HH:mm", timezone: "UTC") == "11/16th 09:05")
  }

  @Test func testOrdinalDayFollowsTheTimezone() {
    #expect(ClockConfig.string(from: date, format: "do", timezone: "Pacific/Kiritimati") == "16th")
    #expect(ClockConfig.string(from: date, format: "do", timezone: "Pacific/Pago_Pago") == "15th")
  }

  @Test func testNamedFormatsBecomeTemplateVariables() throws {
    let yaml = try Yaml.load(
      "format: HH:mm\ntimezone: UTC\nformats:\n  date: do\n  year: yyyy\n  bad: [1]\n")
    let clock = try ClockConfig(yaml: yaml)
    let vars = clock.getTemplateVariables()
    #expect(Set(vars.keys) == ["date", "year"])
    #expect(vars["year"]?.count == 4)
  }
}

final class StatusTemplateVariableTests {
  @Test func testVolumeReportsItsLevelOrMuted() {
    let playing = VolumeStatus(volume: 0.64, isMuted: false, deviceName: "Speakers")
    #expect(
      VolumeConfig.templateVariables(for: playing)
        == ["level": "64", "state": "64%", "device": "Speakers"])
    let muted = VolumeStatus(volume: 0.64, isMuted: true, deviceName: "Speakers")
    #expect(VolumeConfig.templateVariables(for: muted)["state"] == "Muted")
    #expect(VolumeConfig.templateVariables(for: muted)["level"] == "64")
  }

  @Test func testWiFiReportsWhetherItIsConnected() {
    #expect(
      WiFiConfig.templateVariables(for: WiFiStatus(rssi: -50, isConnected: true))
        == ["state": "Connected"])
    #expect(WiFiConfig.templateVariables(for: .disconnected) == ["state": "Disconnected"])
  }

  @Test func testPowerReportsItsLevelAndState() {
    func vars(charging: Bool, plugged: Bool) -> [String: String] {
      PowerConfig.templateVariables(
        for: BatteryStatus(
          level: 78, isCharging: charging, isPluggedIn: plugged, isLowPowerMode: false))
    }
    #expect(vars(charging: false, plugged: false) == ["level": "78", "state": "Discharging"])
    #expect(vars(charging: false, plugged: true)["state"] == "Plugged")
    #expect(vars(charging: true, plugged: true)["state"] == "Charging")
    #expect(PowerConfig.templateVariables(for: .unavailable) == ["level": "", "state": ""])
  }

  private func bluetooth(_ status: BluetoothStatus) async -> [String: String] {
    let config = BluetoothConfig(icon: "bluetooth", disabledIcon: "bluetooth-off") { status }
    let done = Expectation()
    config.refresh { done.fulfill() }
    #expect(await fulfillment(of: [done], timeout: 2))
    return config.getTemplateVariables()
  }

  @Test func testBluetoothReportsItsStateAndConnectedDevices() async {
    let devices = [
      BluetoothDeviceInfo(name: "Buds", address: "aa", isConnected: true),
      BluetoothDeviceInfo(name: "Mouse", address: "bb", isConnected: true),
      BluetoothDeviceInfo(name: "Pad", address: "cc", isConnected: false),
    ]
    #expect(
      await bluetooth(BluetoothStatus(isPoweredOn: true, pairedDevices: devices))
        == ["state": "Connected", "devices": "Buds, Mouse"])
    #expect(
      await bluetooth(BluetoothStatus(isPoweredOn: true, pairedDevices: [devices[2]]))
        == ["state": "On", "devices": ""])
    #expect(
      await bluetooth(BluetoothStatus(isPoweredOn: false, pairedDevices: []))
        == ["state": "Off", "devices": ""])
  }
}

// MARK: - Theme directory watching

@MainActor
final class ThemeWatchingTests {
  private let dir: URL

  init() throws {
    // The path as the file system reports it, which a watched path is
    // compared against.
    dir = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
      .appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
  }

  deinit {
    try? FileManager.default.removeItem(at: dir)
  }

  private func write(_ contents: String, to name: String, atomically: Bool = false) throws {
    let file = dir.appendingPathComponent(name)
    try FileManager.default.createDirectory(
      at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try contents.write(to: file, atomically: atomically, encoding: .utf8)
  }

  /// Whether a watcher of `path` reports a change within two seconds of
  /// `change` being made.
  private func reports(
    watching path: String, retryInterval: TimeInterval = 0.05, _ change: () throws -> Void
  ) async rethrows -> Bool {
    let changed = Expectation()
    let watcher = YamlTreeWatcher(path: path, retryInterval: retryInterval) { changed.fulfill() }
    watcher.start()
    defer { watcher.stop() }
    try change()
    let deadline = Date(timeIntervalSinceNow: 2)
    while !changed.isFulfilled, Date() < deadline { await runMainLoop(for: 0.02) }
    return changed.isFulfilled
  }

  @Test func testThemesAreSoughtBesideTheConfigThenInTheXDGDirectory() {
    let environment = ["XDG_CONFIG_HOME": "/xdg"]
    #expect(
      userThemeDirectories(configDir: "/somewhere/kantan", environment: environment)
        == ["/somewhere/kantan/themes", "/xdg/kantan/themes"])
    #expect(
      userThemeDirectories(configDir: "/xdg/kantan/", environment: environment)
        == ["/xdg/kantan/themes"])
    #expect(
      userThemeDirectories(configDir: nil, environment: environment) == ["/xdg/kantan/themes"])
  }

  @Test func testAThemeWrittenInPlaceIsAChange() async throws {
    try write("fg: '#000000'", to: "plain.yaml")
    #expect(try await reports(watching: dir.path) { try write("fg: '#ffffff'", to: "plain.yaml") })
  }

  @Test func testAThemeReplacedByItsEditorIsAChange() async throws {
    try write("fg: '#000000'", to: "plain.yaml")
    #expect(
      try await reports(watching: dir.path) {
        try write("fg: '#ffffff'", to: "plain.yaml", atomically: true)
      })
  }
}
