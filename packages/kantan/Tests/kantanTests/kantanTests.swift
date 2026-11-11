import AppKit
import Combine
import CoreGraphics
import SwiftUI
import XCTest
import os

@testable import kantan

final class FontConfigTests: XCTestCase {
  func testNameWeightSizeDescriptorParsesBoth() {
    let font = FontConfig(descriptor: "HelveticaNeue:medium:20")
    XCTAssertEqual(font.name, "HelveticaNeue")
    XCTAssertEqual(font.weight, .medium)
    XCTAssertEqual(font.size, 20)
  }

  func testWeightAliases() {
    XCTAssertEqual(FontConfig(descriptor: "Foo:ultralight").weight, .ultraLight)
    XCTAssertEqual(FontConfig(descriptor: "Foo:semibold").weight, .semibold)
    XCTAssertEqual(FontConfig(descriptor: "Foo:demi-bold").weight, .semibold)
    XCTAssertEqual(FontConfig(descriptor: "Foo:heavy").weight, .heavy)
    XCTAssertEqual(FontConfig(descriptor: "Foo:extrabold").weight, .heavy)
    XCTAssertEqual(FontConfig(descriptor: "Foo:black").weight, .black)
  }
}

final class NSColorHexTests: XCTestCase {
  func testInvalidHexFallsBackToDefault() {
    let fallback = NSColor.red
    let color = NSColor(hex: "not-hex", defaultColor: fallback).usingColorSpace(.deviceRGB)!
    let expected = fallback.usingColorSpace(.deviceRGB)!
    XCTAssertEqual(color.redComponent, expected.redComponent, accuracy: 0.01)
    XCTAssertEqual(color.greenComponent, expected.greenComponent, accuracy: 0.01)
    XCTAssertEqual(color.blueComponent, expected.blueComponent, accuracy: 0.01)
  }
}

final class PlacementSpecTests: XCTestCase {
  func testOrPairPicksNotchVariantOnNotchedScreens() {
    let spec = PlacementSpec(raw: "notchleft|left")
    XCTAssertEqual(spec.resolve(hasNotch: true), "notchleft")
    XCTAssertEqual(spec.resolve(hasNotch: false), "left")
  }
}

final class StyleParsingTests: XCTestCase {
  func testParseStyleConfigWithNestedLightAndDark() {
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
    XCTAssertEqual(style?.light?.fg, "#000000")
    XCTAssertEqual(style?.light?.bg, "#ffffff")
    XCTAssertEqual(style?.dark?.fg, "#ffffff")
    XCTAssertEqual(style?.dark?.bg, "#000000")
  }

  func testParseStyleConfigFlatAppliesToBothModes() {
    let yaml: Yaml = .dictionary([
      .string("fg"): .string("#abcdef"),
      .string("bg"): .string("#012345"),
    ])
    let style = parseStyleConfig(from: yaml)
    XCTAssertEqual(style?.light?.fg, "#abcdef")
    XCTAssertEqual(style?.dark?.fg, "#abcdef")
    XCTAssertEqual(style?.light?.bg, "#012345")
    XCTAssertEqual(style?.dark?.bg, "#012345")
  }
}

final class ModuleMergeTests: XCTestCase {
  private func mod(_ name: String, _ placement: String) -> ModuleConfig {
    ModuleConfig(name: name, placement: PlacementSpec(raw: placement), type: "text")
  }

  func testMergeAppendsExtrasLeftAndPrependsExtrasRight() {
    let base = [mod("L1", "left"), mod("L2", "left"), mod("R1", "right"), mod("R2", "right")]
    let extra = [mod("EL", "left"), mod("ER", "right")]
    let result = mergeModules(base: base, extra: extra).map(\.name)
    XCTAssertEqual(result, ["L1", "L2", "EL", "ER", "R1", "R2"])
  }
}

final class IconForLevelTests: XCTestCase {
  func testFirstBucketForLowLevel() {
    let icons = ["empty", "quarter", "half", "three-quarter", "full"]
    XCTAssertEqual(iconForLevel(0, icons: icons), "empty")
    XCTAssertEqual(iconForLevel(10, icons: icons), "empty")
  }

  func testClampsAboveMax() {
    let icons = ["a", "b", "c"]
    XCTAssertEqual(iconForLevel(500, icons: icons), "c")
  }
}

final class YamlTests: XCTestCase {
  func testLoadParsesScalarsAndCollections() throws {
    let source = """
      height: 33
      padding: 10
      modules:
        - name: clock
          enabled: true
      """
    let yaml = try Yaml.load(source)
    XCTAssertEqual(yaml["height"].int, 33)
    XCTAssertEqual(yaml["padding"].int, 10)
    XCTAssertEqual(yaml["modules"].array?.count, 1)
    XCTAssertEqual(yaml["modules"][0]["name"].string, "clock")
    XCTAssertEqual(yaml["modules"][0]["enabled"].bool, true)
  }
}

final class ConfigShapeTests: XCTestCase {
  func testNeedsBundledIconFontsTrueWhenAnyModuleUsesBundled() {
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
    XCTAssertTrue(cfg.needsBundledIconFonts)
  }
}

final class DSLColorFromHexTests: XCTestCase {
  private func components(_ color: Color) -> (r: Double, g: Double, b: Double, a: Double)? {
    guard let ns = NSColor(color).usingColorSpace(.deviceRGB) else { return nil }
    return (
      Double(ns.redComponent), Double(ns.greenComponent),
      Double(ns.blueComponent), Double(ns.alphaComponent)
    )
  }

  func testParses8CharRGBAExtractsAlpha() {
    guard let c = dslColorFromHex("ff000080"), let comps = components(c) else {
      return XCTFail("expected non-nil color")
    }
    XCTAssertEqual(comps.r, 1.0, accuracy: 0.01)
    XCTAssertEqual(comps.g, 0.0, accuracy: 0.01)
    XCTAssertEqual(comps.b, 0.0, accuracy: 0.01)
    XCTAssertEqual(comps.a, 128.0 / 255.0, accuracy: 0.01)
  }

  func testRejectsNonHexString() {
    XCTAssertNil(dslColorFromHex("not-a-color"))
  }
}

final class TemplateResolverTests: XCTestCase {
  func testScopeStackOverridesVariables() {
    let r = TemplateResolver(variables: ["v": "outer"], data: [:])
    r.pushScope(["v": "inner"])
    XCTAssertEqual(r.resolve("{v}"), "inner")
    r.popScope()
    XCTAssertEqual(r.resolve("{v}"), "outer")
  }
}

final class DSLCanonicalNormalisationTests: XCTestCase {
  func testCanonicalBoolRoundTripsThroughResolveBool() {
    let r = TemplateResolver(
      variables: ["t": dslCanonicalBool(true), "f": dslCanonicalBool(false)],
      data: [:])
    XCTAssertTrue(r.resolveBool("{t}"))
    XCTAssertFalse(r.resolveBool("{f}"))
  }

  func testCanonicalNumberRoundTripsThroughDouble() {
    for value in [0.0, 1.0, 75.0, -3.0, 3.5, 0.125, 1e6] {
      XCTAssertEqual(Double(dslCanonicalNumber(value)), value)
    }
  }
}

final class CachedStatusTests: XCTestCase {
  func testConcurrentSetAndGetDoesNotCrash() {
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
    XCTAssertEqual(group.wait(timeout: .now() + 5), .success)
  }
}

// MARK: - loadConfig() end-to-end

final class LoadConfigTests: XCTestCase {
  func testMinimalConfigReturnsNativeAppearance() throws {
    let yaml = try Yaml.load("height: 33\npadding: 10\n")
    let config = try XCTUnwrap(loadConfig(from: yaml))
    XCTAssertEqual(config.height, 33)
    XCTAssertEqual(config.padding, 10)
    XCTAssertTrue(config.isNativeAppearance)
    XCTAssertTrue(config.modules.isEmpty)
  }

  func testReturnsNilWhenStyleIncompleteWithoutTheme() throws {
    let yaml = try Yaml.load(
      """
      height: 33
      padding: 10
      style:
        light:
          fg: "#000000"
      """)
    XCTAssertNil(loadConfig(from: yaml))
  }

  func testParsesTextModule() throws {
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
    let config = try XCTUnwrap(loadConfig(from: yaml))
    XCTAssertEqual(config.modules.count, 1)
    XCTAssertEqual(config.modules.first?.name, "greeting")
    XCTAssertEqual(config.modules.first?.type, "text")
  }

  func testSkipsModuleWithUnknownType() throws {
    let yaml = try Yaml.load(
      """
      height: 33
      padding: 10
      modules:
        - name: ghost
          placement: left
          type: nonsense
      """)
    let config = try XCTUnwrap(loadConfig(from: yaml))
    XCTAssertTrue(config.modules.isEmpty)
  }

  func testBlurClampsAboveSixToSix() throws {
    let yaml = try Yaml.load("height: 33\npadding: 10\nblur: 100\n")
    XCTAssertEqual(loadConfig(from: yaml)?.blur, 6)
  }

  func testAutohideParsesEnabledAndDelay() throws {
    let yaml = try Yaml.load(
      """
      height: 33
      padding: 10
      autohide:
        enabled: false
        delay: 0.5
      """)
    let config = try XCTUnwrap(loadConfig(from: yaml))
    XCTAssertEqual(config.autohide.enabled, false)
    XCTAssertEqual(config.autohide.delay, 0.5)
  }
}

// MARK: - ViewNode JSON decoding (plugin protocol)

final class ViewNodeJSONDecodingTests: XCTestCase {
  private func decode(_ json: String) throws -> ViewNode {
    try JSONDecoder().decode(ViewNode.self, from: Data(json.utf8))
  }

  func testVstackWithSpacingAndChildren() throws {
    let json = #"{"type":"vstack","spacing":4,"children":[{"type":"text","content":"a"}]}"#
    guard case .vstack(let spacing, _, let children, _) = try decode(json) else {
      return XCTFail("expected vstack")
    }
    XCTAssertEqual(spacing, 4)
    XCTAssertEqual(children.count, 1)
  }

  func testCheckAcceptsBoolForChecked() throws {
    let json = #"{"type":"check","label":"Done","checked":true}"#
    guard case .check(_, let checked, _, _, _) = try decode(json) else {
      return XCTFail("expected check")
    }
    XCTAssertEqual(checked, "true")
  }

  func testForeachDecodes() throws {
    let json = #"{"type":"foreach","items":"rows","child":{"type":"text","content":"{name}"}}"#
    guard case .foreach(let items, _, _) = try decode(json) else {
      return XCTFail("expected foreach")
    }
    XCTAssertEqual(items, "rows")
  }

  func testIfDecodesWithElse() throws {
    let json = #"""
      {"type":"if","condition":"on","then":{"type":"text","content":"yes"},"else":{"type":"text","content":"no"}}
      """#
    guard case .if(let condition, _, let elseNode, _) = try decode(json) else {
      return XCTFail("expected if")
    }
    XCTAssertEqual(condition, "on")
    XCTAssertNotNil(elseNode)
  }

  func testCommonPropertiesDecodeAlongsideNode() throws {
    let json = #"""
      {"type":"text","content":"x","padding":8,"opacity":0.5,"background":"#112233"}
      """#
    guard case .text(_, _, _, _, _, _, _, let common) = try decode(json) else {
      return XCTFail("expected text")
    }
    XCTAssertEqual(common.opacity, 0.5)
    XCTAssertEqual(common.background, "#112233")
    guard case .uniform(let value) = common.padding else {
      return XCTFail("expected uniform padding")
    }
    XCTAssertEqual(value, 8)
  }

  func testPaddingArrayIsRejected() {
    let json = #"{"type":"text","content":"x","padding":[1,2,3,4]}"#
    XCTAssertThrowsError(try decode(json))
  }

  func testUnknownTypeThrows() {
    XCTAssertThrowsError(try decode(#"{"type":"flibbertigibbet"}"#))
  }
}

// MARK: - parseViewNodeFromYaml

final class ParseViewNodeFromYamlTests: XCTestCase {
  private func yaml(_ source: String) throws -> Yaml {
    try Yaml.load(source)
  }

  func testVstackRecursesIntoChildren() throws {
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
      return XCTFail("expected vstack")
    }
    XCTAssertEqual(children.count, 2)
  }

  func testPaddingObjectFromYamlMapping() throws {
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
      return XCTFail("expected vstack")
    }
    guard case .edges(let top, let leading, let bottom, let trailing) = common.padding else {
      return XCTFail("expected edges padding")
    }
    XCTAssertEqual(top, 1)
    XCTAssertEqual(leading, 2)
    XCTAssertEqual(bottom, 3)
    XCTAssertEqual(trailing, 4)
  }

  func testCheckCoercesYamlYesToCanonicalTrue() throws {
    let y = try yaml("type: check\nlabel: Done\nchecked: yes\n")
    guard case .check(_, let checked, _, _, _) = parseViewNodeFromYaml(y) else {
      return XCTFail("expected check")
    }
    XCTAssertEqual(checked, dslCanonicalBool(true))
  }

  func testForeachReturnsNilWithoutChild() throws {
    let y = try yaml("type: foreach\nitems: rows\n")
    XCTAssertNil(parseViewNodeFromYaml(y))
  }

  func testIfRequiresThenBranch() throws {
    let y = try yaml("type: if\ncondition: x\n")
    XCTAssertNil(parseViewNodeFromYaml(y))
  }

  func testUnknownTypeReturnsNil() throws {
    let y = try yaml("type: snickerdoodle")
    XCTAssertNil(parseViewNodeFromYaml(y))
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
final class ModuleViewModelUpdateGenerationTests: XCTestCase {
  private func drainMainQueue() {
    let exp = expectation(description: "drain")
    DispatchQueue.main.async { exp.fulfill() }
    wait(for: [exp], timeout: 1.0)
  }

  func testStaleCompletionDoesNotOverwriteFreshValue() {
    let mock = CapturingModuleConfig()
    let cfg = ModuleConfig(
      name: "test", placement: PlacementSpec(raw: "left"), type: "test", config: mock)
    let vm = ModuleViewModel(moduleConfig: cfg)

    XCTAssertEqual(mock.completionCount, 1, "init should trigger one update()")
    vm.update()
    XCTAssertEqual(mock.completionCount, 2)

    mock.fire(at: 1, with: "fresh")
    drainMainQueue()
    XCTAssertEqual(vm.displayValue, "fresh")

    mock.fire(at: 0, with: "stale")
    drainMainQueue()
    XCTAssertEqual(
      vm.displayValue, "fresh",
      "completion captured before the latest update() must be discarded")
  }

  func testInOrderCompletionsApplySequentially() {
    let mock = CapturingModuleConfig()
    let cfg = ModuleConfig(
      name: "test", placement: PlacementSpec(raw: "left"), type: "test", config: mock)
    let vm = ModuleViewModel(moduleConfig: cfg)

    mock.fire(at: 0, with: "first")
    drainMainQueue()
    XCTAssertEqual(vm.displayValue, "first")

    vm.update()
    mock.fire(at: 1, with: "second")
    drainMainQueue()
    XCTAssertEqual(vm.displayValue, "second")
  }
}

// MARK: - Theme template resolution

final class ThemeTemplateResolutionTests: XCTestCase {
  private let palette = ThemePalette(
    fg: "#ffffff",
    bg: "#000000",
    shape: "#222222",
    colors: ["accent": "#ff8800", "muted": "#888888"]
  )

  func testResolvesNamedColor() {
    XCTAssertEqual(resolveThemeTemplate("{theme(accent)}", palette: palette), "#ff8800")
  }

  func testReturnsOriginalForUnknownColor() {
    let input = "{theme(missing)}"
    XCTAssertEqual(resolveThemeTemplate(input, palette: palette), input)
  }

  func testEmbeddedTemplatesResolvedInPlace() {
    let input = "fg={theme(fg)} bg={theme(bg)}"
    XCTAssertEqual(
      resolveAllThemeTemplates(input, palette: palette),
      "fg=#ffffff bg=#000000")
  }
}

// MARK: - MenuBarItemDetector coordinate conversion

final class MenuBarItemDetectorCoordinateTests: XCTestCase {
  func testFlipsYAroundPrimaryHeight() {
    let cg = CGRect(x: 100, y: 0, width: 30, height: 24)
    let ns = MenuBarItemDetector.appKitRect(from: cg, primaryHeight: 900)
    XCTAssertEqual(ns.origin.x, 100)
    XCTAssertEqual(ns.origin.y, 900 - 0 - 24)
    XCTAssertEqual(ns.width, 30)
    XCTAssertEqual(ns.height, 24)
  }

  func testCGItemOnSecondaryScreenAbovePrimary() {
    // Secondary screen above primary → CG origin y is negative (above primary top).
    let cg = CGRect(x: -1440, y: -900, width: 30, height: 24)
    let ns = MenuBarItemDetector.appKitRect(from: cg, primaryHeight: 900)
    XCTAssertEqual(ns.origin.x, -1440)
    XCTAssertEqual(ns.origin.y, 900 - (-900) - 24)
    XCTAssertEqual(ns.height, 24)
  }
}

// MARK: - WindowListCache

final class WindowListCacheTests: XCTestCase {
  private func sample(_ tag: String) -> [[String: Any]] {
    [["tag": tag]]
  }

  func testSecondGetWithinTTLReturnsCached() {
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
    XCTAssertEqual(calls, 1)
    XCTAssertEqual(result.first?["tag"] as? String, "a")
  }

  func testGetAfterTTLRefetches() {
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
    XCTAssertEqual(calls, 2)
    XCTAssertEqual(result.first?["tag"] as? String, "b")
  }
}

// MARK: - MenuBarItemDetector filterMenuBarItems

final class MenuBarItemDetectorFilterTests: XCTestCase {
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

  func testSortsRightToLeftAndIndexes() {
    let windows = [
      window(owner: "ControlCenter", x: 1000, y: 0),
      window(owner: "ControlCenter", x: 1100, y: 0),
      window(owner: "ControlCenter", x: 900, y: 0),
    ]
    let items = MenuBarItemDetector.filterMenuBarItems(
      from: windows, primaryHeight: 1080,
      screenFrame: NSRect(x: 0, y: 0, width: 1920, height: 1080))
    XCTAssertEqual(items.count, 3)
    XCTAssertEqual(items.map { $0.cgRect.origin.x }, [1100, 1000, 900])
    XCTAssertEqual(items.map { $0.index }, [0, 1, 2])
  }

  func testDropsNonStatusLevelWindows() {
    let windows = [
      window(owner: "ControlCenter", x: 1000, y: 0),
      window(owner: "OtherApp", level: 0, x: 1100, y: 0),
    ]
    let items = MenuBarItemDetector.filterMenuBarItems(
      from: windows, primaryHeight: 1080,
      screenFrame: NSRect(x: 0, y: 0, width: 1920, height: 1080))
    XCTAssertEqual(items.count, 1)
    XCTAssertEqual(items.first?.owner, "ControlCenter")
  }

  func testFiltersByScreenXRange() {
    // Two screens side-by-side: primary 0..1920, secondary 1920..3840.
    // An item at CG X >= 1920 belongs to the secondary screen, not primary.
    let windows = [
      window(owner: "ControlCenter", x: 1500, y: 0),
      window(owner: "ControlCenter", x: 2500, y: 0),
    ]
    let primary = MenuBarItemDetector.filterMenuBarItems(
      from: windows, primaryHeight: 1080,
      screenFrame: NSRect(x: 0, y: 0, width: 1920, height: 1080))
    XCTAssertEqual(primary.count, 1)
    XCTAssertEqual(primary.first?.cgRect.origin.x, 1500)

    let secondary = MenuBarItemDetector.filterMenuBarItems(
      from: windows, primaryHeight: 1080,
      screenFrame: NSRect(x: 1920, y: 0, width: 1920, height: 1080))
    XCTAssertEqual(secondary.count, 1)
    XCTAssertEqual(secondary.first?.cgRect.origin.x, 2500)
  }

  func testSecondaryScreenAbovePrimary() {
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
    XCTAssertEqual(items.count, 1)
    XCTAssertEqual(items.first?.cgRect.origin.y, cgTop)
  }
}

// MARK: - PersistedMenuBarLayout

final class PersistedMenuBarLayoutTests: XCTestCase {
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

  func testModuleContentMatchesMeasuredFrames() {
    let measured: [String: (x: CGFloat, width: CGFloat)] = [
      "Clock": (1455, 37), "BentoBox-0": (1413, 26), "Battery": (1371, 26),
      "WiFi": (1333, 22), "Sound": (1295, 22), "Bluetooth": (1263, 16),
      "FocusModes": (1225, 22),
    ]
    let items = layout(positions)
    for (id, frame) in measured {
      guard let found = item(id, in: items) else { return XCTFail("missing \(id)") }
      let content = found.cgRect.insetBy(dx: PersistedMenuBarLayout.moduleSpacing / 2, dy: 0)
      XCTAssertEqual(content.minX, frame.x, accuracy: 1, id)
      XCTAssertEqual(content.maxX, frame.x + frame.width, accuracy: 1, id)
    }
  }

  func testModuleSlotsAbutLikeWindowBackedItems() {
    let items = layout(positions)
    XCTAssertEqual(items.first?.cgRect.maxX, 1512 - PersistedMenuBarLayout.trailingEdgeInset)
    for (right, left) in zip(items, items.dropFirst()) {
      XCTAssertEqual(left.cgRect.maxX, right.cgRect.minX)
    }
  }

  func testSortsRightToLeftAndIndexes() {
    let items = layout(positions)
    XCTAssertEqual(
      Array(items.prefix(7)).map { $0.identifier },
      ["Clock", "BentoBox-0", "Battery", "WiFi", "Sound", "Bluetooth", "FocusModes"])
    XCTAssertEqual(items.map { $0.index }, Array(0..<positions.count))
  }

  func testLeftmostItemUsesDefaultWidth() {
    let items = layout(["module:Clock": 0, "module:WiFi": 36.5])
    XCTAssertEqual(
      item("WiFi", in: items)?.cgRect.width,
      PersistedMenuBarLayout.defaultContentWidth + PersistedMenuBarLayout.moduleSpacing)
  }

  func testLaysOutAgainstEachScreensRightEdgeAndTop() {
    let secondary = NSRect(x: 1512, y: -100, width: 1920, height: 1080)
    let items = layout(positions, screenFrame: secondary)
    XCTAssertEqual(
      items.first?.cgRect.maxX, secondary.maxX - PersistedMenuBarLayout.trailingEdgeInset)
    XCTAssertEqual(items.first?.cgRect.origin.y, 982 - secondary.maxY)
  }

  func testResolveItemMatchesIdentifiersThroughAliases() {
    let items = layout(positions)
    let resolve = { MenuBarItemDetector.resolveItem(for: MaskConfig(name: $0), from: items) }
    XCTAssertEqual(resolve("Clock")?.identifier, "Clock")
    XCTAssertEqual(resolve("ControlCenter")?.identifier, "BentoBox-0")
    XCTAssertEqual(resolve("Volume")?.identifier, "Sound")
    XCTAssertEqual(resolve("Focus")?.identifier, "FocusModes")
    XCTAssertEqual(resolve("WiFi")?.identifier, "WiFi")
    XCTAssertNil(resolve("NowPlaying"))
    XCTAssertEqual(
      MenuBarItemDetector.resolveItem(for: MaskConfig(index: 1), from: items)?.identifier,
      "BentoBox-0")
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

  func testLegacyPositionsMatchMenuBarAgentPositions() {
    let legacy = PersistedMenuBarLayout.legacyPositions { self.controlCentreDefaults[$0] }
    XCTAssertEqual(legacy, positions.filter { $0.key.hasPrefix("module:") })
  }

  func testLegacyPositionsWithoutClockStartAtEdge() {
    var defaults = controlCentreDefaults
    defaults["NSStatusItem VisibleCC Clock"] = 0
    let legacy = PersistedMenuBarLayout.legacyPositions { defaults[$0] }
    XCTAssertNil(legacy["module:Clock"])
    XCTAssertEqual(legacy["module:BentoBox-0"], 63 + 1.5 - 12)
    XCTAssertEqual(legacy["module:Battery"], 105 + 1.5 - 12 - 16)
  }
}

// MARK: - Menu bar Accessibility

final class MenuBarAccessibilityTests: XCTestCase {
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

  func testSystemSlotsMatchControlCentreReconstruction() {
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
        return XCTFail("missing \(expected.identifier ?? "?")")
      }
      XCTAssertEqual(found.cgRect.minX, expected.cgRect.minX, accuracy: 1)
      XCTAssertEqual(found.cgRect.width, expected.cgRect.width, accuracy: 1)
      XCTAssertEqual(found.cgRect.origin.y, 0)
      XCTAssertEqual(found.cgRect.height, 33)
    }
  }

  func testThirdPartyItemsKeepTheirFrame() {
    let rift = resolve("rift", in: layout(reported))
    XCTAssertEqual(rift?.cgRect, CGRect(x: 1150, y: 0, width: 22, height: 33))
    XCTAssertNil(rift?.identifier)
  }

  func testSortsRightToLeftAndIndexes() {
    let items = layout(reported)
    XCTAssertEqual(
      items.prefix(8).map { $0.identifier ?? $0.owner },
      ["Clock", "BentoBox-0", "Battery", "WiFi", "Sound", "Bluetooth", "FocusModes", "Tailscale"])
    XCTAssertEqual(items.map { $0.index }, Array(0..<reported.count))
    XCTAssertEqual(
      MenuBarItemDetector.resolveItem(for: MaskConfig(index: 8), from: items)?.owner, "rift")
  }

  func testMasksNameSystemItemsThroughAliasesAndIdentifiers() {
    let items = layout(reported)
    XCTAssertEqual(resolve("Focus", in: items)?.identifier, "FocusModes")
    XCTAssertEqual(resolve("Volume", in: items)?.identifier, "Sound")
    XCTAssertEqual(resolve("ControlCenter", in: items)?.identifier, "BentoBox-0")
    XCTAssertEqual(resolve("wifi", in: items)?.identifier, "WiFi")
    XCTAssertEqual(resolve("com.apple.menuextra.battery", in: items)?.identifier, "Battery")
    XCTAssertNil(resolve("NowPlaying", in: items))
  }

  func testMasksNameThirdPartyItemsByApp() {
    let items = layout(reported)
    XCTAssertEqual(resolve("RIFT", in: items)?.owner, "rift")
    XCTAssertEqual(resolve("com.1password.1password", in: items)?.owner, "1Password")
    XCTAssertEqual(resolve("1password", in: items)?.owner, "1Password")
    XCTAssertEqual(resolve("Karabiner-Menu", in: items)?.owner, "Karabiner-Menu")
    XCTAssertNil(resolve("Raycast", in: items))
  }

  func testRightmostItemOfAnAppWins() {
    let items = layout([
      app(["com.example.menus", "Menus"], 1000, 30), app(["com.example.menus", "Menus"], 1100, 30),
    ])
    XCTAssertEqual(resolve("Menus", in: items)?.cgRect.minX, 1100)
  }

  func testItemsMoveAcrossToEachScreen() {
    let secondary = NSRect(x: 1512, y: -100, width: 1920, height: 1080)
    let items = layout(reported, on: secondary, screens: [screen, secondary])
    let clock = items.first { $0.identifier == "Clock" }
    XCTAssertEqual(clock?.cgRect.maxX, secondary.maxX - PersistedMenuBarLayout.trailingEdgeInset)
    XCTAssertEqual(clock?.cgRect.origin.y, 982 - secondary.maxY)
    XCTAssertEqual(resolve("rift", in: items)?.cgRect.minX, 1150 + secondary.maxX - screen.maxX)
  }

  func testItemsOffEveryScreenAreDropped() {
    let offscreen = AccessibleMenuBarItem(
      frame: CGRect(x: -500, y: 0, width: 22, height: 33), identifier: nil, owner: "Ghost",
      appNames: ["Ghost"], isMenuBarAgentItem: false)
    XCTAssertTrue(layout([offscreen]).isEmpty)
  }

  func testControlCentreIdentifierForName() {
    XCTAssertEqual(MenuBarAccessibility.controlCentreIdentifier(forName: "focusmode"), "FocusModes")
    XCTAssertEqual(MenuBarAccessibility.controlCentreIdentifier(forName: "clock"), "Clock")
    XCTAssertEqual(
      MenuBarAccessibility.controlCentreIdentifier(forName: "nowplaying"), "NowPlaying")
    XCTAssertEqual(MenuBarAccessibility.controlCentreIdentifier(forName: "spotlight"), "spotlight")
  }

  func testNeededOnlyForMasksOrFocusWithoutFullDiskAccess() {
    func module(_ type: String, mask: MaskConfig? = nil) -> ModuleConfig {
      ModuleConfig(name: type, placement: PlacementSpec(raw: "right"), type: type, mask: mask)
    }
    let plain = [module("clock"), module("bluetooth")]
    XCTAssertFalse(MenuBarAccessibility.isNeeded(by: plain, fullDiskAccess: false))
    XCTAssertTrue(
      MenuBarAccessibility.isNeeded(
        by: plain + [module("text", mask: MaskConfig(name: "rift"))], fullDiskAccess: true))
    XCTAssertTrue(MenuBarAccessibility.isNeeded(by: [module("focus")], fullDiskAccess: false))
    XCTAssertFalse(MenuBarAccessibility.isNeeded(by: [module("focus")], fullDiskAccess: true))
  }
}

// MARK: - Full Disk Access

final class FullDiskAccessTests: XCTestCase {
  func testProbeFileExists() {
    // A missing probe file reads as "not granted" even with access granted.
    XCTAssertTrue(FileManager.default.fileExists(atPath: FullDiskAccess.probePath))
  }
}

// MARK: - Focus database

final class FocusDatabaseTests: XCTestCase {
  private let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/London")!
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

  func testParsesModesAndOnlyEnabledSchedules() {
    let db = database(assertions())
    XCTAssertEqual(db.modes["com.apple.focus.mindfulness"]?.name, "Mindfulness")
    XCTAssertEqual(db.modes["com.apple.sleep.sleep-mode"]?.name, "Sleep")
    XCTAssertEqual(
      Set(db.schedules.map { $0.modeIdentifier }),
      ["com.apple.focus.mindfulness", "com.apple.donotdisturb.mode.default"])
  }

  func testScheduledModeIsActiveWithoutAssertions() {
    XCTAssertEqual(activeName(assertions(), at: at(24, 15, 34)), "Mindfulness")
    XCTAssertEqual(activeName(assertions(), at: at(24, 22)), "Do Not Disturb")
  }

  func testOvernightScheduleCarriesIntoNextMorning() {
    XCTAssertEqual(activeName(assertions(), at: at(25, 3)), "Do Not Disturb")
    XCTAssertNil(activeName(assertions(), at: at(25, 6, 45)))
  }

  func testDisabledScheduleIsIgnored() {
    // Work's 09:00–17:00 weekday schedule is disabled; Mindfulness covers the day.
    XCTAssertEqual(activeName(assertions(), at: at(24, 10)), "Mindfulness")
  }

  func testAssertionNamesTheActiveMode() {
    let json = assertions(active: [("com.apple.donotdisturb.mode.default", at(24, 15, 34))])
    XCTAssertEqual(activeName(json, at: at(24, 15, 35)), "Do Not Disturb")
  }

  func testLaterScheduleWindowOverridesEarlierAssertion() {
    let json = assertions(active: [("com.apple.focus.mindfulness", at(24, 15, 34))])
    XCTAssertEqual(activeName(json, at: at(24, 22)), "Do Not Disturb")
  }

  func testStateChangeEndsScheduleUntilNextWindow() {
    let json = assertions(requests: [("any", at(24, 15, 34))])
    XCTAssertNil(activeName(json, at: at(24, 15, 35)))
    XCTAssertEqual(activeName(json, at: at(24, 21, 31)), "Do Not Disturb")
  }

  func testTargetedInvalidationDoesNotEndSchedule() {
    let json = assertions(requests: [("uuid", at(24, 15, 34))])
    XCTAssertEqual(activeName(json, at: at(24, 15, 35)), "Mindfulness")
  }

  func testWeekdayBitsStartOnMonday() {
    // 31 = Monday–Friday, 96 = Saturday–Sunday.
    let weekdays = FocusSchedule(
      modeIdentifier: "m", startMinute: 6 * 60 + 30, endMinute: 9 * 60, weekdays: 31)
    let weekend = FocusSchedule(
      modeIdentifier: "m", startMinute: 6 * 60 + 30, endMinute: 21 * 60 + 30, weekdays: 96)
    XCTAssertNotNil(weekdays.activeWindowStart(at: at(21, 8), calendar: calendar))  // Monday
    XCTAssertNotNil(weekdays.activeWindowStart(at: at(25, 8), calendar: calendar))  // Friday
    XCTAssertNil(weekdays.activeWindowStart(at: at(26, 8), calendar: calendar))  // Saturday
    XCTAssertNotNil(weekend.activeWindowStart(at: at(27, 12), calendar: calendar))  // Sunday
    XCTAssertNil(weekend.activeWindowStart(at: at(25, 12), calendar: calendar))  // Friday
  }

  func testOvernightWindowBelongsToItsStartDay() {
    // Friday only (bit 4), 21:30–06:30.
    let friday = FocusSchedule(
      modeIdentifier: "m", startMinute: 21 * 60 + 30, endMinute: 6 * 60 + 30, weekdays: 1 << 4)
    XCTAssertEqual(
      friday.activeWindowStart(at: at(26, 3), calendar: calendar), at(25, 21, 30))
    XCTAssertNil(friday.activeWindowStart(at: at(25, 3), calendar: calendar))
  }

  func testUnreadableDatabaseIsNil() {
    XCTAssertNil(
      FocusDatabase(assertionsJSON: Data("{}".utf8), modeConfigurationsJSON: Data()))
    XCTAssertNil(
      FocusDatabase.load(from: URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)")))
  }

  func testEntryMatchesModeNameThenIdentifier() {
    let mindfulness = FocusMode(identifier: "com.apple.focus.mindfulness", name: "Mindfulness")
    let dnd = FocusMode(identifier: "com.apple.donotdisturb.mode.default", name: "Do Not Disturb")
    let icons = ["Mindfulness": "brain", "com.apple.donotdisturb.mode.default": "moon-filled"]
    XCTAssertEqual(FocusConfig.entry(for: mindfulness, in: icons), "brain")
    XCTAssertEqual(FocusConfig.entry(for: dnd, in: icons), "moon-filled")
    XCTAssertNil(FocusConfig.entry(for: FocusMode(identifier: "x", name: "Work"), in: icons))
    XCTAssertNil(FocusConfig.entry(for: nil, in: icons))
  }

  func testFactoryParsesIconAndStyleMaps() throws {
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
    let focus = try XCTUnwrap(config as? FocusConfig)
    XCTAssertEqual(focus.icons, ["Mindfulness": "brain", "Do Not Disturb": "moon-filled"])
    XCTAssertEqual(
      focus.styles,
      [
        "Mindfulness": StateStyle(fg: "{theme(teal)}", bg: nil, iconFg: nil, textFg: nil),
        "com.apple.focus.work": StateStyle(
          fg: nil, bg: "#313244", iconFg: "{theme(peach)}", textFg: nil),
      ])
    let defaults = try XCTUnwrap(FocusConfigFactory().defaultConfiguration() as? FocusConfig)
    XCTAssertEqual(defaults.icons, [:])
    XCTAssertEqual(defaults.styles, [:])
  }
}

// MARK: - State style

final class StateStyleTests: XCTestCase {
  func testStringShorthandSetsForeground() throws {
    XCTAssertEqual(
      StateStyle.parse(from: try Yaml.load("'{theme(red)}'")),
      StateStyle(fg: "{theme(red)}", bg: nil, iconFg: nil, textFg: nil))
  }

  func testExpandedFormReadsEachElement() throws {
    let yaml = try Yaml.load(
      """
      fg: '#ffffff'
      bg: '#000000'
      icon:
        fg: '{theme(peach)}'
      text:
        fg: '{theme(text)}'
      """)
    let style = try XCTUnwrap(StateStyle.parse(from: yaml))
    XCTAssertEqual(
      style,
      StateStyle(fg: "#ffffff", bg: "#000000", iconFg: "{theme(peach)}", textFg: "{theme(text)}"))
    XCTAssertEqual(style.toDynamicStyle().iconFg, "{theme(peach)}")
  }
}

// MARK: - Screen diff

final class ScreenDiffTests: XCTestCase {
  func testMixedAddAndRemove() {
    let diff = computeScreenDiff(existing: ["A", "B", "C"], target: ["B", "C", "D"])
    XCTAssertEqual(diff.toAdd, ["D"])
    XCTAssertEqual(diff.toRemove, ["A"])
  }

  func testReorderingAloneProducesNoChanges() {
    let diff = computeScreenDiff(existing: ["A", "B", "C"], target: ["C", "B", "A"])
    XCTAssertTrue(diff.toAdd.isEmpty)
    XCTAssertTrue(diff.toRemove.isEmpty)
  }
}

// MARK: - ScreenLayout

final class ScreenLayoutTests: XCTestCase {
  func testSecondaryScreenOffsetToRight() {
    let frame = NSRect(x: 1920, y: 0, width: 1440, height: 900)
    let gaps = GapsConfig(top: 0, bottom: 0, left: 0, right: 0)
    let layout = ScreenLayout(screenFrame: frame, gaps: gaps, height: 24)
    XCTAssertEqual(layout.screenLeft, 1920)
    XCTAssertEqual(layout.screenRight, 3360)
    XCTAssertEqual(layout.statusBarY, 900 - 24)
    XCTAssertEqual(layout.barFrame, NSRect(x: 1920, y: 876, width: 1440, height: 24))
  }

  func testTopGapPushesStatusBarDown() {
    let frame = NSRect(x: 0, y: 0, width: 1000, height: 800)
    let gaps = GapsConfig(top: 10, bottom: 0, left: 0, right: 0)
    let layout = ScreenLayout(screenFrame: frame, gaps: gaps, height: 30)
    XCTAssertEqual(layout.statusBarY, 800 - 30 - 10)
    XCTAssertEqual(layout.barFrame.origin.y, layout.statusBarY)
  }
}

// MARK: - Workspace rainbow memoisation

final class ShuffledRainbowTests: XCTestCase {
  func testIsDeterministicForSameInputs() {
    let a = WorkspaceConfig.shuffledRainbow(["r", "g", "b", "y"], spaceCount: 4)
    let b = WorkspaceConfig.shuffledRainbow(["r", "g", "b", "y"], spaceCount: 4)
    XCTAssertEqual(a, b)
  }

  func testNoAdjacentRepeatsWhenCycling() {
    let result = WorkspaceConfig.shuffledRainbow(["r", "g", "b"], spaceCount: 10)
    for i in 1..<result.count {
      XCTAssertNotEqual(result[i], result[i - 1])
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

final class WorkspaceProviderSelectionTests: XCTestCase {
  func testTypeSelectsProvider() throws {
    XCTAssertTrue(WorkspaceConfig(yaml: nil).provider is NativeWorkspaces)
    XCTAssertTrue(
      WorkspaceConfig(yaml: try Yaml.load("type: aerospace\n")).provider is AerospaceWorkspaces)
    XCTAssertTrue(WorkspaceConfig(yaml: try Yaml.load("type: rift\n")).provider is RiftWorkspaces)
  }

  func testScrollingSubscribesRiftToScrollEvents() throws {
    let plain = try XCTUnwrap(
      WorkspaceConfig(yaml: try Yaml.load("type: rift\n")).provider as? RiftWorkspaces)
    XCTAssertFalse(plain.scrolling)
    let scrolling = try XCTUnwrap(
      WorkspaceConfig(yaml: try Yaml.load("type: rift\nscrolling:\n  enabled: true\n")).provider
        as? RiftWorkspaces)
    XCTAssertTrue(scrolling.scrolling)
  }
}

// MARK: - Workspace scrolling

final class WorkspaceScrollingTests: XCTestCase {
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

  func testParsesScrollingConfig() throws {
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
    XCTAssertTrue(scrolling.enabled)
    XCTAssertEqual(scrolling.icon, "app-window")
    XCTAssertFalse(scrolling.showsWorkspaces)
    XCTAssertEqual(scrolling.icons, ["ghostty": "terminal-2"])
  }

  func testWindowIconsMatchBundleIdentifierThenNameIgnoringCase() {
    let scrolling = ScrollingConfig(
      enabled: true, icon: "fallback",
      icons: ["COM.MITCHELLH.GHOSTTY": "terminal-2", "arc": "world", "Browser": "unused"],
      showsWorkspaces: true)
    XCTAssertEqual(scroll.map(scrolling.icon(for:)), ["terminal-2", "world", "fallback"])
  }

  func testShowsTheActiveScrollsWindows() throws {
    let display = try config(
      """
      scrolling:
        enabled: true
        icons:
          Ghostty: terminal-2
      """
    ).display(of: workspaces(activeScroll: scroll))
    XCTAssertTrue(display.isScroll)
    XCTAssertEqual(display.slot?.id, "workspace-1")
    XCTAssertEqual(display.segments.map(\.id), ["window-1-1", "window-2-1", "window-3-1"])
    XCTAssertEqual(display.segments.map(\.isActive), [false, true, false])
    XCTAssertEqual(
      display.segments.map(\.label),
      ["terminal-2", ScrollingConfig.defaultIcon, ScrollingConfig.defaultIcon].map {
        resolveIconName($0).glyph
      })
  }

  func testPipsShowWorkspacesWithWindowsAndTheActiveOne() throws {
    let display = try config("scrolling:\n  enabled: true\n").display(
      of: workspaces(activeScroll: scroll))
    XCTAssertEqual(display.pips.map(\.id), ["workspace-0", "workspace-1", "workspace-3"])
    XCTAssertEqual(display.pips.map(\.isActive), [false, true, false])
  }

  func testWindowsTakeTheActiveWorkspacesRainbowColour() throws {
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
    XCTAssertEqual(display.segments.map(\.colorOverride), ["green", "green", "green"])
    XCTAssertEqual(display.pips.map(\.colorOverride), ["red", "green", "red"])
  }

  func testScrollRainbowColoursWindowsByApp() throws {
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
    XCTAssertTrue(colors.allSatisfy { $0.map(palette.contains) == true })
    XCTAssertEqual(colors[0], colors[3])
    XCTAssertEqual(
      config.scrolling.color(for: scroll[0]),
      config.scrolling.color(
        for: ScrollWindow(
          id: "9-9", app: "ghostty", bundleIdentifier: "COM.MITCHELLH.GHOSTTY", isSelected: true)))
  }

  func testSummaryChangesWithWhatIsShown() throws {
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
    XCTAssertEqual(Set([workspaces.summary, windows.summary, moved.summary]).count, 3)
  }
}

final class RiftWorkspacesTests: XCTestCase {
  func testParsesWorkspacesInIndexOrder() {
    let json = """
      [{"id":"VirtualWorkspaceId(2v1)","index":1,"is_active":true,"layout_mode":"bsp",
        "name":"code","window_count":0,"windows":[]},
       {"id":"VirtualWorkspaceId(1v1)","index":0,"is_active":false,"layout_mode":"scrolling",
        "name":"web","window_count":1,"windows":[{"app_name":"Arc","id":{"idx":1,"pid":2}}]},
       {"id":"VirtualWorkspaceId(3v1)","index":2,"is_active":false,"layout_mode":"traditional",
        "name":"chat","window_count":0,"windows":[]}]
      """
    XCTAssertEqual(
      RiftWorkspaces.parse(Data(json.utf8)),
      [
        Workspace(index: 0, label: "web", isActive: false, hasWindows: true, scroll: []),
        Workspace(index: 1, label: "code", isActive: true),
        Workspace(index: 2, label: "chat", isActive: false),
      ])
  }

  func testParsesScrollInStripOrderWithoutFloatingWindows() {
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
    XCTAssertEqual(
      RiftWorkspaces.parse(Data(json.utf8)).first?.scroll,
      [
        ScrollWindow(
          id: "10-1", app: "Ghostty", bundleIdentifier: "com.mitchellh.ghostty", isSelected: true),
        ScrollWindow(id: "20-2", app: "Arc", bundleIdentifier: nil, isSelected: false),
        ScrollWindow(
          id: "40-4", app: "Emacs", bundleIdentifier: "org.gnu.Emacs", isSelected: false),
      ])
  }

  func testReadsTheLayoutsSelectedWindow() {
    let layout = #"{"mode":"scrolling","focused_window":null,"selected_window":{"idx":2,"pid":20}}"#
    XCTAssertEqual(RiftWorkspaces.selectedWindow(in: Data(layout.utf8)), "20-2")
    XCTAssertNil(RiftWorkspaces.selectedWindow(in: Data(#"{"selected_window":null}"#.utf8)))
    XCTAssertNil(RiftWorkspaces.selectedWindow(in: Data("Failed to connect".utf8)))
  }

  func testSelectingAWindowOutsideTheScrollKeepsItsSelection() {
    let focused = ScrollWindow(id: "1-1", app: "Ghostty", bundleIdentifier: nil, isSelected: true)
    let other = ScrollWindow(id: "2-1", app: "Arc", bundleIdentifier: nil, isSelected: false)
    var workspace = Workspace(index: 0, label: "1", isActive: true, scroll: [focused, other])

    workspace.selectWindow("9-9")
    XCTAssertEqual(workspace.scroll?.map(\.isSelected), [true, false])
    workspace.selectWindow("2-1")
    XCTAssertEqual(workspace.scroll?.map(\.isSelected), [false, true])
  }

  func testScrollEventsExcludeTitlesStacksAndOtherLayouts() {
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
      XCTAssertEqual(RiftWorkspaces.affectsScroll(Data(event.utf8)), affects, event)
    }
  }

  func testMalformedOutputYieldsNoWorkspaces() {
    XCTAssertTrue(RiftWorkspaces.parse(Data("Failed to connect".utf8)).isEmpty)
  }

  func testFindsCLIBesideRunningRift() throws {
    let bin = try makeExecutables(["rift"])
    defer { try? FileManager.default.removeItem(at: bin) }
    let running = [nil, URL(fileURLWithPath: "/usr/bin/true"), bin.appendingPathComponent("rift")]
    XCTAssertNil(RiftWorkspaces.cli(among: running))

    FileManager.default.createFile(
      atPath: bin.appendingPathComponent("rift-cli").path, contents: Data(),
      attributes: [.posixPermissions: 0o755])
    XCTAssertEqual(RiftWorkspaces.cli(among: running), bin.appendingPathComponent("rift-cli").path)
    XCTAssertNil(RiftWorkspaces.cli(among: [URL(fileURLWithPath: "/usr/bin/true")]))
  }
}

final class AerospaceWorkspacesTests: XCTestCase {
  func testParsesNumericWorkspacesFirstInNumericOrder() {
    let all = #"[{"workspace":"B"},{"workspace":"10"},{"workspace":"2"},{"workspace":"A"}]"#
    let focused = #"[{"workspace":"10"}]"#
    XCTAssertEqual(
      AerospaceWorkspaces.parse(all: Data(all.utf8), focused: Data(focused.utf8)),
      [
        Workspace(index: 0, label: "2", isActive: false),
        Workspace(index: 1, label: "10", isActive: true),
        Workspace(index: 2, label: "A", isActive: false),
        Workspace(index: 3, label: "B", isActive: false),
      ])
  }

  func testFindsCLIBesideReleaseArchiveApp() throws {
    let root = try makeExecutables(["AeroSpace-v1/bin/aerospace"])
    defer { try? FileManager.default.removeItem(at: root) }
    XCTAssertEqual(
      AerospaceWorkspaces.cli(
        forApp: root.appendingPathComponent("AeroSpace-v1/AeroSpace.app"), fallbacks: []),
      root.appendingPathComponent("AeroSpace-v1/bin/aerospace").path)
  }

  func testFindsCLIInNixPackageLayout() throws {
    let root = try makeExecutables(["out/bin/aerospace"])
    defer { try? FileManager.default.removeItem(at: root) }
    XCTAssertEqual(
      AerospaceWorkspaces.cli(
        forApp: root.appendingPathComponent("out/Applications/AeroSpace.app"), fallbacks: []),
      root.appendingPathComponent("out/bin/aerospace").path)
  }

  func testFallsBackWhenAppShipsNoCLI() throws {
    let root = try makeExecutables(["homebrew/bin/aerospace"])
    defer { try? FileManager.default.removeItem(at: root) }
    let homebrew = root.appendingPathComponent("homebrew/bin/aerospace").path
    XCTAssertEqual(
      AerospaceWorkspaces.cli(
        forApp: root.appendingPathComponent("Applications/AeroSpace.app"),
        fallbacks: [root.appendingPathComponent("missing/aerospace").path, homebrew]),
      homebrew)
    XCTAssertNil(
      AerospaceWorkspaces.cli(
        forApp: root.appendingPathComponent("Applications/AeroSpace.app"), fallbacks: []))
  }
}

// MARK: - Workspace activation

final class WorkspaceActivationTests: XCTestCase {
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

  func testWorkspaceSegmentsTargetTheirWorkspaceExceptTheActiveOne() {
    XCTAssertEqual(
      WorkspaceConfig(yaml: nil).display(of: spaces).segments.map(\.target),
      [.workspace(index: 0, label: "web"), nil, .workspace(index: 2, label: "chat")])
  }

  func testScrollSegmentsTargetTheirWindowsAndPipsTheirWorkspaces() throws {
    var spaces = self.spaces
    spaces[1].scroll = scroll
    let display = WorkspaceConfig(yaml: try Yaml.load("scrolling:\n  enabled: true\n"))
      .display(of: spaces)
    XCTAssertEqual(
      display.segments.map(\.target),
      [.window(id: "10-1"), .window(id: "20-2"), .window(id: "30-3")])
    XCTAssertEqual(display.pips.map(\.target), [.workspace(index: 0, label: "web"), nil])
  }

  func testSteppingMovesFromTheActiveSegmentAndStopsAtTheEnds() {
    let display = WorkspaceConfig(yaml: nil).display(of: spaces)
    XCTAssertEqual(display.target(steppingBy: 1), .workspace(index: 2, label: "chat"))
    XCTAssertEqual(display.target(steppingBy: -1), .workspace(index: 0, label: "web"))
    XCTAssertEqual(display.target(steppingBy: 5), .workspace(index: 2, label: "chat"))
    XCTAssertEqual(display.target(steppingBy: -5), .workspace(index: 0, label: "web"))
    XCTAssertNil(display.target(steppingBy: 0))
  }

  func testSteppingPastTheLastSegmentOrWithoutAnActiveOneDoesNothing() {
    let display = WorkspaceConfig(yaml: nil).display(
      of: [
        Workspace(index: 0, label: "1", isActive: false),
        Workspace(index: 1, label: "2", isActive: true),
      ])
    XCTAssertNil(display.target(steppingBy: 1))
    XCTAssertNil(WorkspaceDisplay().target(steppingBy: 1))
  }

  func testRiftSwitchesWorkspacesByIndexAndFocusesWindowsByID() {
    XCTAssertEqual(
      RiftWorkspaces.arguments(for: .workspace(index: 3, label: "chat")),
      ["execute", "workspace", "switch", "3"])
    XCTAssertEqual(
      RiftWorkspaces.arguments(for: .window(id: "96136-21335")),
      ["execute", "window", "focus", "--window-id", #"{"pid":96136,"idx":21335}"#])
    XCTAssertNil(RiftWorkspaces.arguments(for: .window(id: "not-a-window")))
  }

  func testAerospaceSwitchesWorkspacesByName() {
    XCTAssertEqual(
      AerospaceWorkspaces.arguments(for: .workspace(index: 0, label: "web")),
      ["workspace", "web"])
    XCTAssertNil(AerospaceWorkspaces.arguments(for: .window(id: "1-1")))
  }

  func testSegmentsSwitchWithProvidersThatCanUnlessTheModuleHasAClick() throws {
    func module(_ type: String, click: String? = nil) throws -> ModuleConfig {
      ModuleConfig(
        name: "spaces", placement: PlacementSpec(raw: "left"), type: "workspace",
        config: WorkspaceConfig(yaml: try Yaml.load("type: \(type)\n")),
        interaction: click.map { InteractionConfig(hover: nil, click: ClickConfig(type: $0)) })
    }
    XCTAssertTrue(WorkspaceModuleView.activates(try module("rift")))
    XCTAssertTrue(WorkspaceModuleView.activates(try module("aerospace")))
    XCTAssertFalse(WorkspaceModuleView.activates(try module("native")))
    XCTAssertFalse(WorkspaceModuleView.activates(try module("rift", click: "menu")))
  }
}

// MARK: - Scroll stepping

final class ScrollStepperTests: XCTestCase {
  private func scroll(
    _ delta: CGFloat, precise: Bool = true, begins: Bool = false, momentum: Bool = false
  ) -> ScrollWheelDelta {
    ScrollWheelDelta(delta: delta, isPrecise: precise, begins: begins, isMomentum: momentum)
  }

  func testEachWheelNotchStepsOnce() {
    var stepper = ScrollStepper()
    XCTAssertEqual(stepper.steps(for: scroll(-3, precise: false)), 1)
    XCTAssertEqual(stepper.steps(for: scroll(1, precise: false)), -1)
    XCTAssertEqual(stepper.steps(for: scroll(0, precise: false)), 0)
  }

  func testTrackpadStepsOncePerDistanceScrolled() {
    var stepper = ScrollStepper()
    let half = ScrollStepper.distance / 2
    XCTAssertEqual(stepper.steps(for: scroll(-half, begins: true)), 0)
    XCTAssertEqual(stepper.steps(for: scroll(-half)), 1)
    XCTAssertEqual(stepper.steps(for: scroll(-ScrollStepper.distance * 2)), 2)
    XCTAssertEqual(stepper.steps(for: scroll(ScrollStepper.distance)), -1)
  }

  func testANewGestureStartsAfresh() {
    var stepper = ScrollStepper()
    let most = ScrollStepper.distance * 0.75
    XCTAssertEqual(stepper.steps(for: scroll(-most, begins: true)), 0)
    XCTAssertEqual(stepper.steps(for: scroll(-most, begins: true)), 0)
  }

  func testReversingDirectionStartsAfresh() {
    var stepper = ScrollStepper()
    let most = ScrollStepper.distance * 0.75
    XCTAssertEqual(stepper.steps(for: scroll(-most)), 0)
    XCTAssertEqual(stepper.steps(for: scroll(most)), 0)
    XCTAssertEqual(stepper.steps(for: scroll(most)), -1)
  }

  func testMomentumDoesNotStep() {
    var stepper = ScrollStepper()
    XCTAssertEqual(stepper.steps(for: scroll(-ScrollStepper.distance * 3, momentum: true)), 0)
  }
}

// MARK: - Event stream process

final class EventStreamProcessTests: XCTestCase {
  func testRestartDelayDoublesToCap() {
    XCTAssertEqual(
      (1...7).map { EventStreamProcess.restartDelay(afterFailures: $0) },
      [1, 2, 4, 8, 16, 16, 16])
  }

  func testOutputFiresEvent() {
    let event = expectation(description: "event")
    event.assertForOverFulfill = false
    let stream = EventStreamProcess(
      command: { ["/bin/sh", "-c", "echo changed; sleep 5"] }
    ) { event.fulfill() }
    stream.start()
    wait(for: [event], timeout: 2)
    stream.stop()
  }

  func testRelaunchAfterExitFiresEvent() {
    let event = expectation(description: "resync after relaunch")
    event.assertForOverFulfill = false
    let stream = EventStreamProcess(
      command: { ["/bin/sh", "-c", "exit 1"] }
    ) { event.fulfill() }
    stream.start()
    wait(for: [event], timeout: 3)
    stream.stop()
  }

  func testLaunchesOnceCommandBecomesAvailable() {
    let event = expectation(description: "event once available")
    event.assertForOverFulfill = false
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
    wait(for: [event], timeout: 3)
    stream.stop()
  }

  func testAcceptsFiltersLines() {
    let event = expectation(description: "accepted line")
    event.assertForOverFulfill = false
    let stream = EventStreamProcess(
      command: { ["/bin/sh", "-c", "echo skip; printf 'ke'; sleep 0.1; echo ep; sleep 5"] },
      accepts: { $0 == Data("keep".utf8) }
    ) { event.fulfill() }
    stream.start()
    wait(for: [event], timeout: 2)
    stream.stop()
  }

  func testRejectedLinesFireNoEvent() {
    let event = expectation(description: "no event for rejected lines")
    event.isInverted = true
    let stream = EventStreamProcess(
      command: { ["/bin/sh", "-c", "echo skip; echo skip; sleep 5"] },
      accepts: { $0 == Data("keep".utf8) }
    ) { event.fulfill() }
    stream.start()
    wait(for: [event], timeout: 1)
    stream.stop()
  }

  func testCoalescingFiresOncePerBurst() {
    let events = OSAllocatedUnfairLock(initialState: 0)
    let stream = EventStreamProcess(
      command: { ["/bin/sh", "-c", "for i in 1 2 3 4 5; do echo $i; done; sleep 5"] },
      coalescing: 0.2
    ) { events.withLock { $0 += 1 } }
    stream.start()
    let burst = expectation(description: "burst delivered")
    DispatchQueue.global().asyncAfter(deadline: .now() + 0.8) { burst.fulfill() }
    wait(for: [burst], timeout: 2)
    stream.stop()
    XCTAssertEqual(events.withLock { $0 }, 1)
  }

  func testStopSilencesStream() {
    let event = expectation(description: "no event after stop")
    event.isInverted = true
    let stream = EventStreamProcess(
      command: { ["/bin/sh", "-c", "sleep 0.3; echo late"] }
    ) { event.fulfill() }
    stream.start()
    stream.stop()
    wait(for: [event], timeout: 1.5)
  }

  func testStopKillsCommand() throws {
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
    let command = try XCTUnwrap(pid)
    XCTAssertEqual(kill(command, 0), 0)

    stream.stop()
    let stopped = Date()
    while kill(command, 0) == 0, Date().timeIntervalSince(stopped) < 2 { usleep(20_000) }
    XCTAssertNotEqual(kill(command, 0), 0)
  }
}

// MARK: - Command toggle

final class CommandToggleTests: XCTestCase {
  override func setUp() {
    super.setUp()
    // handleToggle reads NSApp's appearance for KANTAN_APPEARANCE.
    MainActor.assumeIsolated { _ = NSApplication.shared }
  }

  private func config(_ yaml: String) throws -> CommandConfig {
    try CommandConfig(yaml: try Yaml.load(yaml))
  }

  func testToggleReturnsBeforeCommandExits() throws {
    let toggle = try config("command: 'true'\ntoggle: sleep 0.5\n")
    let exited = expectation(description: "toggle exited")
    let started = Date()
    toggle.handleToggle { exited.fulfill() }
    XCTAssertLessThan(Date().timeIntervalSince(started), 0.2)
    wait(for: [exited], timeout: 3)
    XCTAssertGreaterThanOrEqual(Date().timeIntervalSince(started), 0.4)
  }

  func testMissingToggleCompletesImmediately() throws {
    let toggle = try config("command: 'true'\n")
    let done = expectation(description: "completed")
    toggle.handleToggle { done.fulfill() }
    wait(for: [done], timeout: 0.1)
  }

  func testCommandsAndTogglesAreGivenTheirModuleName() throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: file) }
    let module = try XCTUnwrap(
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
    let command = try XCTUnwrap(module.config as? CommandConfig)

    let ran = expectation(description: "command ran")
    let value = OSAllocatedUnfairLock<String?>(initialState: nil)
    command.getValue { output in
      value.withLock { $0 = output }
      ran.fulfill()
    }
    let toggled = expectation(description: "toggle ran")
    command.handleToggle { toggled.fulfill() }
    wait(for: [ran, toggled], timeout: 5)
    XCTAssertEqual(value.withLock { $0 }, "todo")
    XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "todo")
  }

  func testUnlaunchableToggleStillCompletes() throws {
    let toggle = try config(
      "command: 'true'\ntoggle: x\nlauncher:\n  path: /nonexistent/sh\n")
    let done = expectation(description: "completed")
    toggle.handleToggle { done.fulfill() }
    wait(for: [done], timeout: 1)
  }
}

// MARK: - Command module icons

/// Runs the main run loop until `condition` holds or `timeout` passes.
@MainActor
func waitUntil(
  _ condition: () -> Bool, timeout: TimeInterval = 5, file: StaticString = #filePath,
  line: UInt = #line
) {
  let deadline = Date().addingTimeInterval(timeout)
  while !condition() && Date() < deadline {
    RunLoop.main.run(until: Date().addingTimeInterval(0.01))
  }
  XCTAssertTrue(condition(), file: file, line: line)
}

@MainActor
final class CommandIconTests: XCTestCase {
  override func setUp() {
    super.setUp()
    // getValue reads NSApp's appearance for KANTAN_APPEARANCE.
    _ = NSApplication.shared
  }

  func testIconComesFromTheRunThatProducedTheValue() throws {
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
    waitUntil { vm.displayValue == "arrow-up" }
    XCTAssertEqual(vm.displayIcon, resolveIconName("arrow-up").glyph)

    try "arrow-down".write(to: iconFile, atomically: true, encoding: .utf8)
    vm.update()
    waitUntil { vm.displayValue == "arrow-down" }
    XCTAssertEqual(vm.displayIcon, resolveIconName("arrow-down").glyph)
  }
}

// MARK: - Watch process restart backoff

final class WatchRestartDelayTests: XCTestCase {
  func testDoublesEachAttempt() {
    XCTAssertEqual(ModuleViewModel.watchRestartDelay(forAttempt: 2), 2.0)
    XCTAssertEqual(ModuleViewModel.watchRestartDelay(forAttempt: 3), 4.0)
    XCTAssertEqual(ModuleViewModel.watchRestartDelay(forAttempt: 4), 8.0)
    XCTAssertEqual(ModuleViewModel.watchRestartDelay(forAttempt: 5), 16.0)
  }

  func testCapsAtSixteenSeconds() {
    XCTAssertEqual(ModuleViewModel.watchRestartDelay(forAttempt: 6), 16.0)
    XCTAssertEqual(ModuleViewModel.watchRestartDelay(forAttempt: 10), 16.0)
  }

  func testReturnsNilOnceMaxRestartsExceeded() {
    XCTAssertNil(
      ModuleViewModel.watchRestartDelay(forAttempt: ModuleViewModel.maxWatchRestarts + 1))
    XCTAssertNil(ModuleViewModel.watchRestartDelay(forAttempt: 999))
  }

  func testAStableRunStartsTheCountAfresh() {
    XCTAssertEqual(
      ModuleViewModel.watchRestartAttempt(after: 9, ranFor: ModuleViewModel.stableWatchRun), 1)
    XCTAssertEqual(
      ModuleViewModel.watchRestartAttempt(after: 9, ranFor: ModuleViewModel.stableWatchRun - 1),
      10)
  }
}

// MARK: - Watch process output

final class LineBufferTests: XCTestCase {
  func testTakesCompleteLinesAndHoldsBackTheRest() {
    var buffer = LineBuffer()
    XCTAssertEqual(buffer.append(Data("one\ntw".utf8)), [Data("one".utf8)])
    XCTAssertEqual(buffer.append(Data("o\n\nthree".utf8)), [Data("two".utf8), Data()])
    XCTAssertEqual(buffer.append(Data("\n".utf8)), [Data("three".utf8)])
    XCTAssertEqual(buffer.append(Data()), [])
  }
}

final class CommandWatchOutputTests: XCTestCase {
  private func config(_ yaml: String) throws -> CommandConfig {
    try CommandConfig(yaml: try Yaml.load(yaml))
  }

  func testJSONObjectLinesBecomeTheCommandsOutput() throws {
    let command = try config("command: watch-output-object\noutput: json\n")
    let line = #"{"value":"3","icon":"bell","variables":{"count":"3"}}"#
    XCTAssertEqual(command.cacheWatchOutput(Data(line.utf8)), "3")
    XCTAssertEqual(command.getIcon(), "bell")
    XCTAssertEqual(command.getTemplateVariables(), ["count": "3"])
  }

  func testSegmentsColourTheValue() throws {
    let command = try config("command: output-segments\noutput: json\n")
    let segments =
      ##"[{"text":"Review","fg":"#89b4fa"},{"text":" in "},{"fg":"#f38ba8"},"##
      + ##"{"text":"5m","fg":"{theme(red)}"}]"##
    let line = ##"{"value":"Review in 5m","segments":"## + segments + "}"
    XCTAssertEqual(command.cacheWatchOutput(Data(line.utf8)), "Review in 5m")
    XCTAssertEqual(
      command.getSegments(),
      [
        ValueSegment(text: "Review", fg: "#89b4fa"), ValueSegment(text: " in ", fg: nil),
        ValueSegment(text: "5m", fg: "{theme(red)}"),
      ])
    XCTAssertEqual(command.cacheWatchOutput(Data(#"{"value":"plain"}"#.utf8)), "plain")
    XCTAssertEqual(command.getSegments(), [])
  }

  func testOtherLinesAreIgnored() throws {
    let command = try config("command: watch-output-other\noutput: json\n")
    for line in ["starting up", "[1, 2]", "", #"{"value":"#] {
      XCTAssertNil(command.cacheWatchOutput(Data(line.utf8)), line)
    }
    let text = try config("command: watch-output-text\n")
    XCTAssertNil(text.cacheWatchOutput(Data(#"{"value":"x"}"#.utf8)))
  }
}

@MainActor
final class WatchOutputTests: XCTestCase {
  override func setUp() {
    super.setUp()
    // Watch processes are given NSApp's appearance.
    _ = NSApplication.shared
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

  func testEachLineTheWatchPrintsUpdatesTheModule() throws {
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
    waitUntil { vm.displayValue == "first" }
    XCTAssertEqual(vm.displayIcon, resolveIconName("bell").glyph)
    XCTAssertEqual(vm.segments, [ValueSegment(text: "first", fg: "#ff0000")])
    waitUntil { vm.displayValue == "second" }
    XCTAssertEqual(vm.segments, [])
  }

  func testWatchOutputOutlivesACommandRunStillInFlight() throws {
    let vm = try module(
      "watch-in-flight", command: #"sleep 0.5; echo '{"value":"command"}'"#,
      watch: #"echo '{"value":"watch"}'; cat"#)
    waitUntil { vm.displayValue == "watch" }
    RunLoop.main.run(until: Date().addingTimeInterval(1))
    XCTAssertEqual(vm.displayValue, "watch")
  }

  func testTheWatchRelaunchesWithTheNewAppearance() throws {
    NSApp.appearance = NSAppearance(named: .aqua)
    addTeardownBlock { @MainActor in NSApp.appearance = nil }
    let vm = try module(
      "watch-appearance", watch: #"echo "{\"value\":\"$KANTAN_APPEARANCE\"}"; cat"#)
    waitUntil { vm.displayValue == "light" }
    NSApp.appearance = NSAppearance(named: .darkAqua)
    waitUntil { vm.displayValue == "dark" }
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
final class RepositionTriggerMergeTests: XCTestCase {
  private func wait(milliseconds: Int) {
    let exp = expectation(description: "wait\(milliseconds)")
    DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(milliseconds)) {
      exp.fulfill()
    }
    wait(for: [exp], timeout: 2.0)
  }

  /// Burst changes across all three signals within one debounce window
  /// must fan out to exactly one downstream layout trigger — not three.
  func testMergedPublishersCoalesceBurstIntoSingleTrigger() {
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
    wait(milliseconds: 120)
    let baseline = triggers

    src.shouldDisplay = false
    src.displayValue = "v"
    src.displayIcon = "i"

    wait(milliseconds: 120)
    XCTAssertEqual(
      triggers - baseline, 1,
      "three property changes within one debounce window must produce a single layout pass")
  }
}

// MARK: - ThemeProvider.elementFgColor precedence

@MainActor
final class ThemeProviderElementFgPrecedenceTests: XCTestCase {
  override func setUp() {
    super.setUp()
    // Force NSApp to exist so ThemeProvider.init can query effectiveAppearance.
    MainActor.assumeIsolated { _ = NSApplication.shared }
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
    XCTAssertEqual(actual.redComponent, expected.redComponent, accuracy: 0.01)
    XCTAssertEqual(actual.greenComponent, expected.greenComponent, accuracy: 0.01)
    XCTAssertEqual(actual.blueComponent, expected.blueComponent, accuracy: 0.01)
  }

  func testFgOverrideBypassesAllOtherSources() {
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

  func testDynamicElementFgPrecedesDynamicGenericFg() {
    let theme = ThemeProvider(config: makeConfig())
    theme.isDarkMode = true
    let vm = makeVM()
    vm.dynamicStyle = DynamicStyleOverride(fg: "00FF00", bg: nil, iconFg: nil, textFg: "FF0000")
    assertColor(theme.textFgColor(for: vm), equalsHex: "FF0000")
    vm.dynamicStyle = DynamicStyleOverride(fg: "00FF00", bg: nil, iconFg: "0000FF", textFg: nil)
    assertColor(theme.iconFgColor(for: vm), equalsHex: "0000FF")
  }

  func testModuleGenericFgPrecedesGlobalElementFg() {
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

  func testUnresolvableDynamicTemplateFallsThroughToStatic() {
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

final class BluetoothStatusReadTests: XCTestCase {
  func testIconRendersWithoutReadingStatus() {
    let reads = OSAllocatedUnfairLock(initialState: 0)
    let config = BluetoothConfig(icon: "bluetooth", disabledIcon: "bluetooth-off") {
      reads.withLock { $0 += 1 }
      return .unavailable
    }
    XCTAssertEqual(config.getIcon(), "bluetooth")
    XCTAssertFalse(config.isActive())
    XCTAssertEqual(reads.withLock { $0 }, 0)
  }

  func testRefreshReadsOffMainThreadThenRendersResult() {
    let readOnMain = OSAllocatedUnfairLock<Bool?>(initialState: nil)
    let config = BluetoothConfig(icon: "bluetooth", disabledIcon: "bluetooth-off") {
      readOnMain.withLock { $0 = Thread.isMainThread }
      return BluetoothStatus(
        isPoweredOn: true,
        pairedDevices: [BluetoothDeviceInfo(name: "Buds", address: "aa", isConnected: true)])
    }
    let done = expectation(description: "refreshed")
    config.refresh {
      XCTAssertTrue(Thread.isMainThread)
      done.fulfill()
    }
    wait(for: [done], timeout: 2)
    XCTAssertEqual(readOnMain.withLock { $0 }, false)
    XCTAssertEqual(config.getIcon(), "bluetooth")
    XCTAssertTrue(config.isActive())
  }

  func testBlockedReadDoesNotBlockCaller() {
    let prompt = DispatchSemaphore(value: 0)
    let config = BluetoothConfig(icon: "bluetooth", disabledIcon: "bluetooth-off") {
      prompt.wait()
      return BluetoothStatus(isPoweredOn: false, pairedDevices: [])
    }
    let done = expectation(description: "refreshed after prompt")
    let started = Date()
    config.refresh { done.fulfill() }
    XCTAssertEqual(config.getIcon(), "bluetooth")
    XCTAssertLessThan(Date().timeIntervalSince(started), 0.5)

    prompt.signal()
    wait(for: [done], timeout: 2)
    XCTAssertEqual(config.getIcon(), "bluetooth-off")
  }
}

// MARK: - BluetoothConfig.parseSPBluetoothData

final class BluetoothSystemProfilerParserTests: XCTestCase {
  private func parse(_ json: String) -> BluetoothStatus? {
    BluetoothConfig.parseSPBluetoothData(Data(json.utf8))
  }

  func testReportsConnectedDevicesWhenPresent() throws {
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
    let status = try XCTUnwrap(parse(json))
    XCTAssertTrue(status.isPoweredOn)
    XCTAssertEqual(status.pairedDevices.count, 2)
    XCTAssertEqual(status.connectedDevices.map(\.name), ["Magic Trackpad"])
  }

  func testReportsPoweredOffWhenControllerStateIsOff() throws {
    let json = """
      {
        "SPBluetoothDataType": [{
          "controller_properties": { "controller_state": "attrib_off" }
        }]
      }
      """
    let status = try XCTUnwrap(parse(json))
    XCTAssertFalse(status.isPoweredOn)
    XCTAssertTrue(status.pairedDevices.isEmpty)
  }

  func testReturnsNilForMalformedRoot() {
    XCTAssertNil(parse("{}"))
    XCTAssertNil(parse(#"{"SPBluetoothDataType": []}"#))
    XCTAssertNil(parse("not json"))
  }
}

// MARK: - Tooltip dismissal

@MainActor
final class TooltipClickTests: XCTestCase {
  func testHidingTheTooltipStopsWatchingClicks() {
    _ = NSApplication.shared
    let manager = PopupManager()
    manager.hideTooltipOnClickElsewhere()
    XCTAssertTrue(manager.isWatchingClicksForTooltip)
    manager.hideTooltip()
    XCTAssertFalse(manager.isWatchingClicksForTooltip)
  }
}
