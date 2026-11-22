import AppKit
import SwiftUI

/// Fades panels out and lets the mouse through them, and puts them back.
///
/// A panel's content fades rather than the panel, whose own opacity the
/// drawer and autohide animate. The panel has to ignore the mouse itself:
/// neither an overlay that ignores it nor an opacity of zero lets a click
/// through to the menu bar.
@MainActor
final class PanelCover {
  private struct Covered {
    let panel: NSPanel
    let ignoredMouse: Bool
  }

  private var covered: [Covered] = []

  /// Covers the panels reaching into `spans`, given in screen coordinates,
  /// uncovers any others, and returns those newly covered.
  @discardableResult
  func update(_ panels: [NSPanel], spans: [ClosedRange<CGFloat>]) -> [NSPanel] {
    let wanted = panels.filter { panel in
      spans.contains { $0.lowerBound < panel.frame.maxX && $0.upperBound > panel.frame.minX }
    }
    covered.removeAll { entry in
      guard !wanted.contains(entry.panel) else { return false }
      entry.panel.ignoresMouseEvents = entry.ignoredMouse
      Self.fade(entry.panel.contentView, to: 1)
      return true
    }
    let added = wanted.filter { panel in !covered.contains { $0.panel === panel } }
    for panel in added {
      covered.append(Covered(panel: panel, ignoredMouse: panel.ignoresMouseEvents))
      panel.ignoresMouseEvents = true
      Self.fade(panel.contentView, to: 0)
    }
    return added
  }

  private static func fade(_ view: NSView?, to alpha: CGFloat) {
    NSAnimationContext.runAnimationGroup { context in
      context.duration = AppMenusReveal.fadeDuration
      view?.animator().alphaValue = alpha
    }
  }
}

/// One display's app menus: draws them over the bar in place of the modules
/// there, which let clicks through to the native menus beneath, until the
/// pointer leaves and no menu is open.
@MainActor
final class AppMenusReveal {
  /// How often the pointer and open menu are checked while the menus show.
  /// A menu's tracking loop keeps mouse moves from global monitors.
  static let pollInterval: TimeInterval = 0.05
  /// How long the menus outlast the pointer. An app takes a moment to report
  /// the menu a click opened, and none is open between one and the next.
  static let linger: TimeInterval = 0.25

  static var fadeDuration: TimeInterval {
    NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.15
  }

  private(set) var isShowing = false
  private let reader: AppMenuReader
  private let model = AppMenusModel()
  private let cover = PanelCover()
  private let panel: NSPanel
  private let screen: () -> NSScreen?
  private let barFrame: () -> NSRect?
  private let coverable: () -> [NSPanel]
  private let onCover: ([NSPanel]) -> Void
  private let onHide: () -> Void
  private var timer: Timer?
  private var lastHeld = Date()

  /// `coverable` gives the panels that can be in the menus' way, `onCover`
  /// takes those just covered, and `onHide` runs as the menus go.
  init(
    reader: AppMenuReader, theme: ThemeProvider, level: NSWindow.Level,
    screen: @escaping () -> NSScreen?, barFrame: @escaping () -> NSRect?,
    coverable: @escaping () -> [NSPanel], onCover: @escaping ([NSPanel]) -> Void,
    onHide: @escaping () -> Void
  ) {
    self.reader = reader
    self.screen = screen
    self.barFrame = barFrame
    self.coverable = coverable
    self.onCover = onCover
    self.onHide = onHide
    panel = NSPanel(
      contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered,
      defer: false)
    panel.level = level
    panel.collectionBehavior = .canJoinAllSpaces
    panel.isOpaque = false
    panel.hasShadow = false
    panel.backgroundColor = .clear
    panel.ignoresMouseEvents = true
    panel.contentView = NSHostingView(rootView: AppMenusView(model: model, theme: theme))
  }

  /// The menus as they lie on this display.
  private struct Layout {
    let titles: [AppMenuTitle]
    let runs: [ClosedRange<CGFloat>]
    let screen: NSRect
    /// The part of the bar over the native menu bar.
    let band: NSRect
    let menuBarHeight: CGFloat
  }

  private func currentLayout() -> Layout? {
    guard let menus = reader.menus, let screen = screen(), let bar = barFrame(),
      let primary = NSScreen.screens.first
    else { return nil }
    let cgFrame = { (frame: NSRect) in
      CGRect(
        x: frame.minX, y: primary.frame.maxY - frame.maxY, width: frame.width,
        height: frame.height)
    }
    let titles = menus.titles(
      on: cgFrame(screen.frame), screens: NSScreen.screens.map { cgFrame($0.frame) },
      notchMinX: screen.hasNotch ? screen.auxiliaryTopLeftArea?.width : nil)
    guard let first = titles.first else { return nil }

    let reserved = screen.frame.maxY - screen.visibleFrame.maxY
    let height = reserved > 0 ? reserved : first.frame.height
    let menuBar = NSRect(
      x: screen.frame.minX, y: screen.frame.maxY - height, width: screen.frame.width,
      height: height)
    let band = bar.intersection(menuBar)
    // A bar lowered from the top has no room over the menus to draw them.
    guard band.height >= height / 2 else { return nil }
    return Layout(
      titles: titles, runs: AppMenus.runs(of: titles), screen: screen.frame, band: band,
      menuBarHeight: height)
  }

  /// What the pointer resting at the top edge brings out.
  enum Outcome {
    case menus, menuBar
    /// The menus are still being read.
    case pending
  }

  /// Shows the menus when `point` is over them.
  func reveal(at point: NSPoint) -> Outcome {
    reader.refresh()
    guard let layout = currentLayout() else { return reader.isPending ? .pending : .menuBar }
    let x = point.x - layout.screen.minX
    guard layout.runs.contains(where: { $0.contains(x) }) else { return .menuBar }
    show(layout)
    return .menus
  }

  private func show(_ layout: Layout) {
    guard !isShowing else { return }
    isShowing = true
    lastHeld = Date()
    apply(layout)
    model.hovered = nil
    panel.alphaValue = 0
    panel.orderFrontRegardless()
    NSAnimationContext.runAnimationGroup { context in
      context.duration = Self.fadeDuration
      panel.animator().alphaValue = 1
    }
    let timer = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated { self?.poll() }
    }
    RunLoop.main.add(timer, forMode: .common)
    self.timer = timer
  }

  private func apply(_ layout: Layout) {
    if panel.frame != layout.band { panel.setFrame(layout.band, display: true) }
    let inset = layout.band.minX - layout.screen.minX
    if model.inset != inset { model.inset = inset }
    if model.titles != layout.titles { model.titles = layout.titles }
    let spans = layout.runs.map {
      ($0.lowerBound + layout.screen.minX)...($0.upperBound + layout.screen.minX)
    }
    let added = cover.update(coverable(), spans: spans)
    if !added.isEmpty { onCover(added) }
  }

  /// Follows the menus and the bar's panels as either changes.
  func update() {
    guard isShowing, let layout = currentLayout() else { return }
    apply(layout)
  }

  private func poll() {
    reader.refresh()
    guard let layout = currentLayout() else {
      // The app coming to the front has its menus read in a moment.
      if !reader.isPending { hide() }
      return
    }
    apply(layout)

    let point = NSEvent.mouseLocation
    let x = point.x - layout.screen.minX
    let depth = layout.screen.maxY - point.y
    let inMenuBar = depth >= -1 && depth <= layout.menuBarHeight
    let hovered =
      inMenuBar
      ? layout.titles.firstIndex { $0.frame.minX <= x && x < $0.frame.maxX } : nil
    if model.hovered != hovered { model.hovered = hovered }

    // The notch between two runs is part of the way from one to the other.
    let overMenus =
      inMenuBar
      && x >= (layout.runs.first?.lowerBound ?? 0) && x <= (layout.runs.last?.upperBound ?? 0)
    if overMenus || NSEvent.pressedMouseButtons != 0 || layout.titles.contains(where: \.isOpen) {
      lastHeld = Date()
    } else if Date().timeIntervalSince(lastHeld) > Self.linger {
      hide()
    }
  }

  private func hide() {
    guard isShowing else { return }
    stopShowing()
    NSAnimationContext.runAnimationGroup(
      { context in
        context.duration = Self.fadeDuration
        panel.animator().alphaValue = 0
      },
      completionHandler: {
        DispatchQueue.main.async {
          MainActor.assumeIsolated { [weak self] in
            guard let self, !self.isShowing else { return }
            self.panel.orderOut(nil)
          }
        }
      })
    onHide()
  }

  private func stopShowing() {
    isShowing = false
    timer?.invalidate()
    timer = nil
    cover.update([], spans: [])
  }

  func teardown() {
    stopShowing()
    panel.orderOut(nil)
  }
}
