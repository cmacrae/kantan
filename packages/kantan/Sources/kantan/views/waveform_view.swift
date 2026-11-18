import SwiftUI

/// Draws the sound: its bands as bars, or its wave as a line.
struct WaveformCanvas: View {
  let style: WaveformStyle
  /// The level of each bar, 0 to 1, or the wave's points, -1 to 1.
  let levels: [Float]
  /// The colour of what is drawn, and each bar's own when they have them.
  let color: Color
  let colors: [Color]?
  let sensitivity: Double

  static let barWidth: CGFloat = 2
  static let barSpacing: CGFloat = 2
  /// How far apart the wave's points are drawn.
  static let wavePointSpacing: CGFloat = 1.5

  /// How many bars fit `width`.
  static func barCount(fitting width: CGFloat) -> Int {
    max(Int((width + barSpacing) / (barWidth + barSpacing)), 1)
  }

  /// The width `count` bars take.
  static func width(ofBars count: Int) -> CGFloat {
    CGFloat(count) * (barWidth + barSpacing) - barSpacing
  }

  var body: some View {
    Canvas { context, size in
      switch style {
      case .bars:
        for (index, level) in levels.enumerated() {
          let scaled = min(CGFloat(level) * sensitivity, 1)
          let height = max(Self.barWidth, scaled * size.height)
          let bar = CGRect(
            x: CGFloat(index) * (Self.barWidth + Self.barSpacing),
            y: (size.height - height) / 2, width: Self.barWidth, height: height)
          context.fill(
            Path(roundedRect: bar, cornerRadius: Self.barWidth / 2),
            with: .color(colors.map { $0[index % $0.count] } ?? color))
        }
      case .wave:
        var line = Path()
        for (index, point) in levels.enumerated() {
          let scaled = min(max(CGFloat(point) * sensitivity, -1), 1)
          let position = CGPoint(
            x: size.width * CGFloat(index) / CGFloat(max(levels.count - 1, 1)),
            y: size.height / 2 * (1 - scaled))
          if index == 0 { line.move(to: position) } else { line.addLine(to: position) }
        }
        // The wave passes through the bars' colours from left to right.
        let shading: GraphicsContext.Shading =
          colors.map {
            .linearGradient(
              Gradient(colors: $0), startPoint: .zero, endPoint: CGPoint(x: size.width, y: 0))
          } ?? .color(color)
        context.stroke(line, with: shading, style: StrokeStyle(lineWidth: 1.2, lineJoin: .round))
      }
    }
  }
}

extension WaveformConfig {
  /// Each of `count` bars' own colour, or nil for the module's: with the
  /// native appearance, or without colours of its own.
  @MainActor
  func barColors(count: Int, theme: ThemeProvider) -> [Color]? {
    guard !theme.isNative else { return nil }
    return colors.colors(count: count, resolve: theme.resolveColorString)?
      .map { Color(nsColor: NSColor(hex: $0)) }
  }
}

/// Draws a waveform module: the sound's bands as bars, or its wave as a
/// line, in the colour of the module's icon.
struct WaveformModuleView: View {
  @ObservedObject var viewModel: ModuleViewModel
  @ObservedObject private var levels = AudioLevels.shared
  @ObservedObject private var widths = ModuleWidths.shared
  @EnvironmentObject var themeProvider: ThemeProvider

  /// How much of the wave's width fades out at each end.
  private static let waveFade: CGFloat = 0.2

  var body: some View {
    if let config = viewModel.moduleConfig.config as? WaveformConfig {
      let color = themeProvider.iconFgColor(for: viewModel)
      // The width of the module this one follows, while it is in the bar.
      let matched = config.matchWidth.flatMap { widths.widths[$0] }.flatMap { $0 > 0 ? $0 : nil }
      let barCount = config.barCount(
        matching: matched, barWidth: WaveformCanvas.barWidth, spacing: WaveformCanvas.barSpacing)
      let waveWidth = max(CGFloat(config.width), matched ?? 0)
      let resizing =
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        ? nil : ModuleAnimation.content
      let own = config.barColors(count: barCount, theme: themeProvider)
      let sensitivity = config.sensitivity(bars: config.style == .bars ? barCount : nil)
      switch config.style {
      case .bars:
        WaveformCanvas(
          style: .bars, levels: AudioAnalysis.resampled(levels.bands, to: barCount),
          color: color, colors: own, sensitivity: sensitivity
        )
        .frame(width: WaveformCanvas.width(ofBars: barCount), height: config.height)
        .animation(resizing, value: barCount)
      case .wave:
        WaveformCanvas(
          style: .wave,
          levels: AudioAnalysis.resampledWave(
            levels.wave, to: max(Int(waveWidth / WaveformCanvas.wavePointSpacing), 2)),
          color: color, colors: own, sensitivity: sensitivity
        )
        .frame(width: waveWidth, height: config.height)
        .animation(resizing, value: waveWidth)
        // The line fades out toward each end rather than stopping short.
        .mask(
          LinearGradient(
            stops: [
              .init(color: .clear, location: 0), .init(color: .black, location: Self.waveFade),
              .init(color: .black, location: 1 - Self.waveFade), .init(color: .clear, location: 1),
            ], startPoint: .leading, endPoint: .trailing))
      }
    }
  }
}
