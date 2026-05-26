import AppKit
import CoreGraphics
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
