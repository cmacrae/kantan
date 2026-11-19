import SwiftUI

/// Draws the sound: its bands as bars, or its wave as a line.
struct WaveformCanvas: View {
  let style: WaveformStyle
  let sound: Sound
  /// The colour of what is drawn, and each bar's own when they have them.
  let color: Color
  let colors: [Color]?
  let sensitivity: Double
  /// How many bars are drawn.
  var bars = 8
  var options = WaveOptions()
  /// Whether the waves just drawn are left out, as nothing is to move
  /// but the sound.
  var still = false

  static let barWidth: CGFloat = 2
  static let barSpacing: CGFloat = 2
  /// How far apart the wave's points are drawn.
  static let wavePointSpacing: CGFloat = 1.5
  /// How bright each older wave is beside the one drawn after it.
  static let glowFade = 0.5

  /// The width `count` bars take.
  static func width(ofBars count: Int) -> CGFloat {
    CGFloat(count) * (barWidth + barSpacing) - barSpacing
  }

  var body: some View {
    Canvas { context, size in
      switch style {
      case .bars: drawBars(in: &context, size: size)
      case .wave: drawWave(in: &context, size: size)
      }
    }
  }

  // MARK: - Colours

  /// The bars' colours from left to right across `size`, or the module's.
  private func shading(across size: CGSize) -> GraphicsContext.Shading {
    colors.map {
      .linearGradient(
        Gradient(colors: $0), startPoint: .zero, endPoint: CGPoint(x: size.width, y: 0))
    } ?? .color(color)
  }

  /// The colour `fraction` of the way along `colors`, passing from each to
  /// the next.
  private static func shade(_ colors: [Color], at fraction: Double) -> Color {
    guard colors.count > 1 else { return colors.first ?? .clear }
    let position = min(max(fraction, 0), 1) * Double(colors.count - 1)
    let lower = min(Int(position), colors.count - 2)
    let from = NSColor(colors[lower]).usingColorSpace(.sRGB)
    let to = NSColor(colors[lower + 1]).usingColorSpace(.sRGB)
    guard let from, let to,
      let mixed = from.blended(withFraction: position - Double(lower), of: to)
    else { return colors[lower] }
    return Color(nsColor: mixed)
  }

  // MARK: - Paths

  /// A line through `points`: straight from each to the next, or a curve
  /// that bends at each on its way between the middles of its neighbours.
  private static func line(through points: [CGPoint], curved: Bool) -> Path {
    var line = Path()
    guard let first = points.first, let last = points.last else { return line }
    line.move(to: first)
    guard curved, points.count > 2 else {
      points.dropFirst().forEach { line.addLine(to: $0) }
      return line
    }
    for index in 1..<(points.count - 1) {
      let (point, next) = (points[index], points[index + 1])
      line.addQuadCurve(
        to: CGPoint(x: (point.x + next.x) / 2, y: (point.y + next.y) / 2), control: point)
    }
    line.addLine(to: last)
    return line
  }

  /// `line` closed along the height `y` between its ends, to fill.
  private static func closed(_ line: Path, width: CGFloat, at y: CGFloat) -> Path {
    var area = line
    area.addLine(to: CGPoint(x: width, y: y))
    area.addLine(to: CGPoint(x: 0, y: y))
    area.closeSubpath()
    return area
  }

  // MARK: - Bars

  private func drawBars(in context: inout GraphicsContext, size: CGSize) {
    for (index, level) in AudioAnalysis.resampled(sound.bands, to: bars).enumerated() {
      let scaled = min(CGFloat(level) * sensitivity, 1)
      let height = max(Self.barWidth, scaled * size.height)
      let bar = CGRect(
        x: CGFloat(index) * (Self.barWidth + Self.barSpacing),
        y: (size.height - height) / 2, width: Self.barWidth, height: height)
      context.fill(
        Path(roundedRect: bar, cornerRadius: Self.barWidth / 2),
        with: .color(colors.map { $0[index % $0.count] } ?? color))
    }
  }

  // MARK: - Wave

  /// `wave` as points across `size`, `spacing` apart.
  private func points(of wave: [Float], size: CGSize, spacing: CGFloat) -> [CGPoint] {
    let levels = AudioAnalysis.resampledWave(wave, to: max(Int(size.width / spacing), 2))
    return levels.enumerated().map { index, point in
      let scaled = min(max(CGFloat(point) * sensitivity, -1), 1)
      return CGPoint(
        x: size.width * CGFloat(index) / CGFloat(max(levels.count - 1, 1)),
        y: size.height / 2 * (1 - scaled))
    }
  }

  /// What one of the wave's lines is drawn in: the left and right sides in
  /// the first and last of the bars' colours, a line following the sound's
  /// tone in the colour that far along them, and otherwise all of them from
  /// left to right.
  private func waveShading(channel: Int, size: CGSize) -> GraphicsContext.Shading {
    if options.stereo {
      guard let colors, let low = colors.first, let high = colors.last else {
        return .color(channel == 0 ? color : color.opacity(0.55))
      }
      return .color(channel == 0 ? low : high)
    }
    if options.tone, let colors { return .color(Self.shade(colors, at: Double(sound.tone))) }
    return shading(across: size)
  }

  private func drawWave(in context: inout GraphicsContext, size: CGSize) {
    let frames = options.lock ? sound.lockedWaves : sound.waves
    let spacing = options.curve ? Self.wavePointSpacing * 2 : Self.wavePointSpacing
    let lineWidth = options.loudness ? 0.7 + 1.5 * CGFloat(sound.loudness) : 1.2
    let drawn = Array(frames.prefix(options.glow && !still ? Sound.trail : 1))
    // The oldest first, so that each newer wave lies over those before it.
    for (age, frame) in drawn.enumerated().reversed() {
      var layer = context
      layer.opacity = pow(Self.glowFade, Double(age))
      let channels = options.stereo ? [frame.left, frame.right] : [frame.mono]
      for (channel, wave) in channels.enumerated() {
        let line = Self.line(
          through: points(of: wave, size: size, spacing: spacing), curved: options.curve)
        let shading = waveShading(channel: channel, size: size)
        if options.fill, age == 0 {
          var area = layer
          area.opacity = 0.22
          area.fill(Self.closed(line, width: size.width, at: size.height / 2), with: shading)
        }
        layer.stroke(
          line, with: shading,
          style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
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
      let style = config.style
      // The width of the module this one follows, while it is in the bar.
      let matched = config.matchWidth.flatMap { widths.widths[$0] }.flatMap { $0 > 0 ? $0 : nil }
      let barCount = config.barCount(
        matching: matched, barWidth: WaveformCanvas.barWidth, spacing: WaveformCanvas.barSpacing)
      let width =
        style == .bars
        ? WaveformCanvas.width(ofBars: barCount) : max(CGFloat(config.width), matched ?? 0)
      let still = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
      // The line fades out toward each end rather than stopping short.
      let edge: Color = style == .wave ? .clear : .black
      WaveformCanvas(
        style: style, sound: levels.sound, color: themeProvider.iconFgColor(for: viewModel),
        colors: config.barColors(
          count: style == .wave && config.wave.tone
            ? config.colors.toneCount(bars: barCount) : barCount,
          theme: themeProvider),
        sensitivity: config.sensitivity(bars: style == .bars ? barCount : nil),
        bars: barCount, options: config.wave, still: still
      )
      .frame(width: width, height: config.height)
      .animation(still ? nil : ModuleAnimation.content, value: width)
      .mask(
        LinearGradient(
          stops: [
            .init(color: edge, location: 0), .init(color: .black, location: Self.waveFade),
            .init(color: .black, location: 1 - Self.waveFade), .init(color: edge, location: 1),
          ], startPoint: .leading, endPoint: .trailing))
    }
  }
}
