import AppKit
import Combine
import CoreGraphics
import SwiftUI
import XCTest

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
