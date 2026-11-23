import AppKit
import Testing

@testable import kantan

@Suite struct AppMenusTests {
  private func menus(_ spans: (x: CGFloat, width: CGFloat)..., y: CGFloat = 0) -> AppMenus {
    AppMenus(
      titles: spans.map {
        AppMenuTitle(
          title: "Menu", frame: CGRect(x: $0.x, y: y, width: $0.width, height: 33),
          isApple: false, isAppName: false)
      })
  }

  @Test func testTitlesArePlacedOnEachDisplayUnlessANotchSplitsThem() {
    let laptop = CGRect(x: 0, y: 0, width: 1512, height: 982)
    let external = CGRect(x: 1512, y: -200, width: 2560, height: 1440)
    let screens = [laptop, external]
    let notch: CGFloat = 663.5

    let short = menus((1522, 34), (1555, 62), y: -200)
    let onLaptop = short.titles(on: laptop, screens: screens, notchMinX: notch)
    #expect(onLaptop.map(\.frame.minX) == [10, 43])
    #expect(onLaptop.map(\.frame.minY) == [0, 0])
    #expect(AppMenus.runs(of: onLaptop) == [0...105])

    let split = menus((10, 34), (43, 600), (848.5, 80))
    let placed = split.titles(on: laptop, screens: screens, notchMinX: notch)
    #expect(AppMenus.runs(of: placed) == [0...643, 848.5...928.5])
    #expect(split.titles(on: external, screens: screens, notchMinX: nil).isEmpty)

    let long = menus((1522, 34), (1555, 700), y: -200)
    #expect(long.titles(on: laptop, screens: screens, notchMinX: notch).isEmpty)
  }

  @Test func testATitleLeftOfTheScreenStartsARunAtItsEdge() {
    let titles = menus((-300, 34), (10, 34)).titles
    #expect(AppMenus.runs(of: titles) == [0...44])
  }

  @Test func testAFrameNoDisplayCouldHoldIsImplausible() {
    #expect(CGRect(x: -1512, y: -200, width: 34, height: 24).isPlausibleScreenFrame)
    #expect(!CGRect(x: CGFloat.nan, y: 0, width: 34, height: 24).isPlausibleScreenFrame)
    #expect(!CGRect(x: 0, y: 0, width: 1e30, height: 24).isPlausibleScreenFrame)
  }

  @MainActor @Test func testPanelsUnderTheMenusGetTheirClicksBack() {
    _ = NSApplication.shared
    let panels = [(x: 0, ignores: false), (x: 100, ignores: true), (x: 500, ignores: false)].map {
      let panel = NSPanel(
        contentRect: NSRect(x: $0.x, y: 0, width: 90, height: 33),
        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
      panel.ignoresMouseEvents = $0.ignores
      return panel
    }
    let cover = PanelCover()

    #expect(cover.update(panels, spans: [0...365]) == Array(panels.prefix(2)))
    #expect(panels.map(\.ignoresMouseEvents) == [true, true, false])
    #expect(cover.update(panels, spans: [0...365]).isEmpty)

    cover.update([], spans: [])
    #expect(panels.map(\.ignoresMouseEvents) == [false, true, false])
  }
}
