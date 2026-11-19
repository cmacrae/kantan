import SwiftUI

/// Draws the sound in one of the waveform module's styles.
struct WaveformCanvas: View {
  let style: WaveformStyle
  let sound: Sound
  /// The colour of what is drawn, and each bar's own when they have them.
  let color: Color
  let colors: [Color]?
  let sensitivity: Double
  /// How many bars or columns of dots are drawn.
  var bars = 8
  var options = WaveOptions()
  /// How fast what the sound has been scrolls, in points a second.
  var speed = WaveformConfig.defaultSpeed
  /// Whether what moves between one measurement and the next is held still.
  var still = false

  static let barWidth: CGFloat = 2
  static let barSpacing: CGFloat = 2
  static let dotSize: CGFloat = 2
  static let dotSpacing: CGFloat = 1
  /// How far apart the wave's points are drawn.
  static let wavePointSpacing: CGFloat = 1.5
  /// How far apart the bars of the sound's loudness scroll past.
  static let scrollPitch: CGFloat = 3
  /// How bright each older wave is beside the one drawn after it.
  static let glowFade = 0.5

  /// The width of a bar and the space between two, for a style with bars.
  static func barGeometry(of style: WaveformStyle) -> (width: CGFloat, spacing: CGFloat) {
    style == .dots ? (dotSize, dotSpacing) : (barWidth, barSpacing)
  }

  /// The width `count` bars of `style` take.
  static func width(ofBars count: Int, style: WaveformStyle = .bars) -> CGFloat {
    let bar = barGeometry(of: style)
    return CGFloat(count) * (bar.width + bar.spacing) - bar.spacing
  }

  var body: some View {
    Canvas { context, size in
      switch style {
      case .bars: drawBars(in: &context, size: size)
      case .dots: drawDots(in: &context, size: size)
      case .wave: drawWave(in: &context, size: size)
      case .flow: drawFlow(in: &context, size: size)
      case .scroll: drawScroll(in: &context, size: size)
      case .spectrogram: drawSpectrogram(in: &context, size: size)
      case .line: drawLine(in: &context, size: size)
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

  // MARK: - Bars and dots

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

  /// Each band as a column of dots, as many lit from the bottom as the
  /// band is loud and the rest dim.
  private func drawDots(in context: inout GraphicsContext, size: CGSize) {
    let pitch = Self.dotSize + Self.dotSpacing
    let rows = max(Int((size.height + Self.dotSpacing) / pitch), 1)
    let top = (size.height - (CGFloat(rows) * pitch - Self.dotSpacing)) / 2
    for (index, level) in AudioAnalysis.resampled(sound.bands, to: bars).enumerated() {
      let scaled = min(CGFloat(level) * sensitivity, 1)
      let lit = max(Int((scaled * CGFloat(rows)).rounded()), 1)
      let shade = colors.map { $0[index % $0.count] } ?? color
      for row in 0..<rows {
        let dot = CGRect(
          x: CGFloat(index) * pitch, y: top + CGFloat(rows - 1 - row) * pitch,
          width: Self.dotSize, height: Self.dotSize)
        context.fill(Path(ellipseIn: dot), with: .color(shade.opacity(row < lit ? 1 : 0.18)))
      }
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

  // MARK: - Flow

  /// A ribbon of the flow: how many times it swings across the module, how
  /// fast it moves along in radians a second, and how bright it is.
  private static let ribbons: [(cycles: Double, speed: Double, opacity: Double)] = [
    (1.0, 1.6, 0.95), (1.7, -2.4, 0.65), (2.6, 3.5, 0.45),
  ]

  /// A ribbon each for the sound's low, middle and high frequencies, as
  /// tall as they are loud, swelling toward the middle and moving along.
  private func drawFlow(in context: inout GraphicsContext, size: CGSize) {
    let third = max(sound.bands.count / Self.ribbons.count, 1)
    let time = still ? 0 : Double(sound.tick) / Sound.rate
    let count = max(Int(size.width / Self.wavePointSpacing), 2)
    for (index, ribbon) in Self.ribbons.enumerated().reversed() {
      let part = sound.bands.dropFirst(index * third).prefix(third)
      let level = part.isEmpty ? 0 : Double(part.reduce(0, +)) / Double(part.count)
      let reach = min(level * sensitivity * 1.3, 1) * size.height / 2
      let swings = (0..<count).map { point -> (x: CGFloat, y: CGFloat) in
        let along = Double(point) / Double(count - 1)
        let swell = pow(sin(.pi * along), 2)
        let swing = sin(
          2 * .pi * ribbon.cycles * along + time * ribbon.speed + Double(index) * 1.9)
        return (size.width * along, reach * swell * swing)
      }
      let middle = size.height / 2
      let upper = Self.line(
        through: swings.map { CGPoint(x: $0.x, y: middle - $0.y) }, curved: false)
      var lens = upper
      swings.reversed().forEach { lens.addLine(to: CGPoint(x: $0.x, y: middle + $0.y)) }
      lens.closeSubpath()
      let shade =
        colors.map {
          Self.shade($0, at: Double(index) / Double(Self.ribbons.count - 1))
        } ?? color
      var layer = context
      layer.opacity = ribbon.opacity
      layer.fill(lens, with: .color(shade.opacity(0.3)))
      layer.stroke(
        upper, with: .color(shade), style: StrokeStyle(lineWidth: 1, lineJoin: .round))
    }
  }

  // MARK: - Scrolling

  /// The columns of what the sound has been that fit `width`, the newest
  /// first: where each one's left edge is, and the measurements it covers
  /// as places in `Sound.history`. Each column covers as many measurements
  /// as pass while the sound scrolls `pitch` points, and the newest slides
  /// in as its measurements are made.
  private func columns(pitch: CGFloat, width: CGFloat) -> [(x: CGFloat, ticks: Range<Int>)] {
    let stored = sound.history.count
    guard sound.tick > 0, stored > 0 else { return [] }
    let each = max(Int((Double(pitch) / speed * Sound.rate).rounded()), 1)
    let newest = (sound.tick - 1) / each
    let shown = still ? 1 : CGFloat((sound.tick - 1) % each + 1) / CGFloat(each)
    // The measurement number of the oldest still kept.
    let oldest = sound.tick - stored
    var columns: [(x: CGFloat, ticks: Range<Int>)] = []
    for back in 0...newest {
      let x = width - pitch * shown - CGFloat(back) * pitch
      guard x + pitch > 0 else { break }
      let column = newest - back
      let first = max(column * each, oldest)
      let last = min((column + 1) * each, sound.tick)
      guard first < last else { break }
      columns.append((x, (first - oldest)..<(last - oldest)))
    }
    return columns
  }

  /// How loud the sound has been as bars about the middle, the newest at
  /// the right.
  private func drawScroll(in context: inout GraphicsContext, size: CGSize) {
    var bars = Path()
    for column in columns(pitch: Self.scrollPitch, width: size.width) {
      let level = sound.history[column.ticks].max() ?? 0
      let height = max(min(CGFloat(level) * sensitivity, 1) * size.height, 1)
      bars.addRoundedRect(
        in: CGRect(
          x: column.x, y: (size.height - height) / 2, width: Self.scrollPitch - 1,
          height: height),
        cornerSize: CGSize(width: 0.5, height: 0.5))
    }
    context.fill(bars, with: shading(across: size))
  }

  /// The sound's spectrum over time: a column a point wide for each moment,
  /// the lowest frequencies at the bottom, each cell brighter and further
  /// along the bars' colours the louder its frequencies were.
  private func drawSpectrogram(in context: inout GraphicsContext, size: CGSize) {
    let kept = Sound.spectrumRows
    let rows = min(max(Int(size.height), 1), kept)
    let cell = size.height / CGFloat(rows)
    let steps = 16
    let ramp = colors.map { own in
      (0...steps).map { Self.shade(own, at: Double($0) / Double(steps)) }
    }
    for column in columns(pitch: 1, width: size.width) {
      for row in 0..<rows {
        let bands = (row * kept / rows)..<max((row + 1) * kept / rows, row * kept / rows + 1)
        var level: Float = 0
        for tick in column.ticks {
          let moment = tick * kept
          level = max(
            level,
            sound.spectra[(moment + bands.lowerBound)..<(moment + bands.upperBound)].max() ?? 0)
        }
        let scaled = min(Double(level) * sensitivity, 1)
        guard scaled > 0.04 else { continue }
        let shade = ramp.map { $0[Int(scaled * Double(steps))] } ?? color
        context.fill(
          Path(
            CGRect(
              x: column.x, y: size.height - CGFloat(row + 1) * cell, width: 1, height: cell)),
          with: .color(shade.opacity(pow(scaled, 1.5))))
      }
    }
  }

  // MARK: - Line

  /// The sound's spectrum as one curve standing on the module's bottom
  /// edge, filled faintly beneath.
  private func drawLine(in context: inout GraphicsContext, size: CGSize) {
    let levels = AudioAnalysis.resampled(sound.bands, to: max(Int(size.width / 3), 2))
    let points = levels.enumerated().map { index, level in
      CGPoint(
        x: size.width * CGFloat(index) / CGFloat(levels.count - 1),
        y: size.height - max(min(CGFloat(level) * sensitivity, 1) * (size.height - 1), 0.6))
    }
    let line = Self.line(through: points, curved: true)
    let shading = shading(across: size)
    var area = context
    area.opacity = 0.25
    area.fill(Self.closed(line, width: size.width, at: size.height), with: shading)
    context.stroke(
      line, with: shading, style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))
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

/// Draws a waveform module in its style, in the colour of the module's
/// icon.
struct WaveformModuleView: View {
  @ObservedObject var viewModel: ModuleViewModel
  @ObservedObject private var levels = AudioLevels.shared
  @ObservedObject private var widths = ModuleWidths.shared
  @EnvironmentObject var themeProvider: ThemeProvider

  /// How much of a style's width fades out at an end.
  private static let fade: CGFloat = 0.2

  /// How much of the `line` style's height fades out at the bottom.
  private static let bottomFade: CGFloat = 0.35

  /// Where a style fades out: the `wave` and `flow` toward each end rather
  /// than stopping short, the `line` toward each end and the edge it stands
  /// on, and what scrolls past toward the end it leaves by.
  private static func fades(of style: WaveformStyle) -> (
    leading: Bool, trailing: Bool, bottom: Bool
  ) {
    switch style {
    case .wave, .flow: (true, true, false)
    case .line: (true, true, true)
    case .scroll, .spectrogram: (true, false, false)
    case .bars, .dots: (false, false, false)
    }
  }

  var body: some View {
    if let config = viewModel.moduleConfig.config as? WaveformConfig {
      let style = config.style
      // The width of the module this one follows, while it is in the bar.
      let matched = config.matchWidth.flatMap { widths.widths[$0] }.flatMap { $0 > 0 ? $0 : nil }
      let bar = WaveformCanvas.barGeometry(of: style)
      let barCount = config.barCount(matching: matched, barWidth: bar.width, spacing: bar.spacing)
      let width: CGFloat =
        switch style {
        case .bars, .dots: WaveformCanvas.width(ofBars: barCount, style: style)
        case .wave, .flow, .scroll, .spectrogram, .line: max(CGFloat(config.width), matched ?? 0)
        }
      let still = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
      let fades = Self.fades(of: style)
      WaveformCanvas(
        style: style, sound: levels.sound, color: themeProvider.iconFgColor(for: viewModel),
        colors: config.barColors(
          count: style == .wave && config.wave.tone
            ? config.colors.toneCount(bars: barCount) : barCount,
          theme: themeProvider),
        sensitivity: config.sensitivity(bars: style.hasBars ? barCount : nil),
        bars: barCount, options: config.wave, speed: config.speed, still: still
      )
      .frame(width: width, height: config.height)
      .animation(still ? nil : ModuleAnimation.content, value: width)
      .mask(
        LinearGradient(
          stops: [
            .init(color: fades.leading ? .clear : .black, location: 0),
            .init(color: .black, location: Self.fade),
            .init(color: .black, location: 1 - Self.fade),
            .init(color: fades.trailing ? .clear : .black, location: 1),
          ], startPoint: .leading, endPoint: .trailing)
      )
      .mask(
        LinearGradient(
          stops: [
            .init(color: .black, location: 1 - Self.bottomFade),
            .init(color: fades.bottom ? .clear : .black, location: 1),
          ], startPoint: .top, endPoint: .bottom))
    }
  }
}
