import Accelerate
import Foundation

/// Turns samples of sound into what a waveform module draws.
enum AudioAnalysis {
  /// How many samples are analysed at a time.
  static let window = 4096
  /// How many of the newest samples say whether there is sound now.
  static let recent = 256
  /// How many bands the spectrum is measured in.
  static let bandCount = 256
  /// How many points of the wave are drawn.
  static let wavePoints = 512
  /// The loudest sample that still counts as silence.
  static let silenceThreshold: Float = 0.0005
  /// The frequencies the bands span, in hertz.
  static let frequencies: ClosedRange<Double> = 50...16000
  /// The levels, in decibels below full scale, drawn as nothing and as full.
  static let decibels: ClosedRange<Float> = -60...(-12)
  /// The levels, in decibels below full scale, that count as no loudness
  /// and as full.
  static let loudnessDecibels: ClosedRange<Float> = -40...(-6)
  /// The least of the way along the bands that the recent tones are spread
  /// over to tell them apart.
  static let toneSpan: Float = 0.06
  /// How many samples the sound is averaged over to find where it rises
  /// through zero.
  static let lockSmoothing = 64

  private static let log2Window = vDSP_Length(12)
  nonisolated(unsafe) private static let fft = vDSP.FFT(
    log2n: log2Window, radix: .radix2, ofType: DSPSplitComplex.self)
  private static let hann = vDSP.window(
    ofType: Float.self, usingSequence: .hanningDenormalized, count: window, isHalfWindow: false)

  static func peak(_ samples: [Float]) -> Float {
    samples.isEmpty ? 0 : vDSP.maximumMagnitude(samples)
  }

  /// The level of each band of `samples`' spectrum, 0 to 1, the lowest
  /// frequencies first. The bands are spaced evenly in pitch, and a level
  /// is its band's loudest frequency in decibels, scaled over `decibels`.
  static func bands(of samples: [Float], sampleRate: Double) -> [Float] {
    guard samples.count == window, let fft else {
      return [Float](repeating: 0, count: bandCount)
    }
    let half = window / 2
    var windowed = vDSP.multiply(samples, hann)
    var real = [Float](repeating: 0, count: half)
    var imaginary = [Float](repeating: 0, count: half)
    var outReal = [Float](repeating: 0, count: half)
    var outImaginary = [Float](repeating: 0, count: half)
    var magnitudes = [Float](repeating: 0, count: half)
    real.withUnsafeMutableBufferPointer { real in
      imaginary.withUnsafeMutableBufferPointer { imaginary in
        outReal.withUnsafeMutableBufferPointer { outReal in
          outImaginary.withUnsafeMutableBufferPointer { outImaginary in
            var input = DSPSplitComplex(realp: real.baseAddress!, imagp: imaginary.baseAddress!)
            var output = DSPSplitComplex(
              realp: outReal.baseAddress!, imagp: outImaginary.baseAddress!)
            windowed.withUnsafeMutableBytes {
              vDSP_ctoz(
                $0.bindMemory(to: DSPComplex.self).baseAddress!, 2, &input, 1, vDSP_Length(half))
            }
            fft.forward(input: input, output: &output)
            vDSP.absolute(output, result: &magnitudes)
          }
        }
      }
    }

    // A full-scale tone's magnitude, which a level of 0 dB stands for.
    let fullScale = Float(window) / 2
    let binWidth = sampleRate / Double(window)
    let ratio = frequencies.upperBound / frequencies.lowerBound
    return (0..<bandCount).map { band in
      let low = frequencies.lowerBound * pow(ratio, Double(band) / Double(bandCount))
      let high = frequencies.lowerBound * pow(ratio, Double(band + 1) / Double(bandCount))
      let loudest: Float
      if high - low < binWidth {
        // A band narrower than the spectrum's steps takes the level between
        // the two steps its middle lies between.
        let middle = min(max((low + high) / 2 / binWidth, 1), Double(half - 1))
        let below = Int(middle)
        let above = min(below + 1, half - 1)
        loudest =
          magnitudes[below] + (magnitudes[above] - magnitudes[below])
          * Float(middle - Double(below))
      } else {
        let first = min(max(Int(low / binWidth), 1), half - 1)
        let last = min(max(Int(high / binWidth), first), half - 1)
        loudest = magnitudes[first...last].max() ?? 0
      }
      let level = 20 * log10(max(loudest / fullScale, 1e-9))
      return min(
        max((level - decibels.lowerBound) / (decibels.upperBound - decibels.lowerBound), 0), 1)
    }
  }

  /// `levels` following `previous`: rising at once, falling a little at a
  /// time so the bars settle rather than flicker.
  static func smoothed(_ levels: [Float], over previous: [Float]) -> [Float] {
    zip(levels, previous).map { max($0, $1 - 0.07) }
  }

  /// How loud `samples` are, 0 to 1: their level in decibels below full
  /// scale, scaled over `loudnessDecibels`.
  static func loudness(of samples: [Float]) -> Float {
    guard !samples.isEmpty else { return 0 }
    let level = 20 * log10(max(vDSP.rootMeanSquare(samples), 1e-9))
    let range = loudnessDecibels
    return min(max((level - range.lowerBound) / (range.upperBound - range.lowerBound), 0), 1)
  }

  /// Where the sound of `bands` sits between its lowest frequencies, 0, and
  /// its highest, 1: the middle of the bands by how loud each is, its
  /// loudest counting the most. Nil for a sound without any level.
  static func tone(of bands: [Float]) -> Float? {
    var weight: Float = 0
    var weighted: Float = 0
    for (index, level) in bands.enumerated() {
      let cubed = level * level * level
      weight += cubed
      weighted += cubed * Float(index)
    }
    guard weight > 0, bands.count > 1 else { return nil }
    return weighted / weight / Float(bands.count - 1)
  }

  /// Where `tone` lies among the `recent` tones, from 0 at the lowest of
  /// them to 1 at the highest, leaving out the twentieth furthest each way.
  /// Tones closer together than `toneSpan` are told apart over that span.
  static func placed(_ tone: Float, among recent: [Float]) -> Float {
    guard !recent.isEmpty else { return 0.5 }
    let sorted = recent.sorted()
    let low = sorted[Int(Float(sorted.count - 1) * 0.05)]
    let high = sorted[Int((Float(sorted.count - 1) * 0.95).rounded(.up))]
    let span = max(high - low, toneSpan)
    return min(max((tone - ((low + high) / 2 - span / 2)) / span, 0), 1)
  }

  /// How many of `samples`' newest a wave leaves undrawn to begin where the
  /// sound last rose through zero, so that a steady sound's wave stands
  /// still from one drawing to the next. The sound is smoothed first, so it
  /// is its lowest tones that are followed, and it has to dip below a tenth
  /// of its peak before a rise counts. 0 when it never does.
  static func lockOffset(of samples: [Float]) -> Int {
    let drawn = waveStride(of: samples) * wavePoints
    let latestStart = samples.count - drawn
    guard latestStart > 0, samples.count > lockSmoothing else { return 0 }
    let smooth = vDSP.slidingWindowSum(samples, usingWindowLength: lockSmoothing)
    let threshold = peak(smooth) * 0.1
    guard threshold > 0 else { return 0 }
    var armed = false
    var start: Int?
    for (index, value) in smooth.enumerated() {
      // A smoothed value stands for the sample at its window's middle.
      let sample = index + lockSmoothing / 2
      guard sample <= latestStart else { break }
      if value < -threshold {
        armed = true
      } else if armed, value >= 0 {
        armed = false
        start = sample
      }
    }
    return start.map { latestStart - $0 } ?? 0
  }

  /// The stretch of `samples` ending `offset` before the newest as
  /// `wavePoints` points, each the mean of the samples it covers.
  private static func points(of samples: [Float], leaving offset: Int) -> [Float] {
    let stride = waveStride(of: samples)
    let end = samples.count - offset
    let start = end - stride * wavePoints
    guard start >= 0, end <= samples.count else {
      return [Float](repeating: 0, count: wavePoints)
    }
    return (0..<wavePoints).map { point in
      vDSP.mean(Array(samples[(start + point * stride)..<(start + (point + 1) * stride)]))
    }
  }

  /// How many samples each of a wave's points covers: a quarter of
  /// `samples` is drawn.
  private static func waveStride(of samples: [Float]) -> Int {
    max(samples.count / 4 / wavePoints, 1)
  }

  /// The latest stretch of `samples` as `wavePoints` points, -1 to 1, each
  /// the mean of the samples it covers, ending `offset` samples before the
  /// newest. A quiet wave is drawn larger, up to four times.
  static func wave(of samples: [Float], leaving offset: Int = 0) -> [Float] {
    let points = points(of: samples, leaving: offset)
    let gain = 1 / max(peak(points), 0.25)
    return points.map { $0 * gain }
  }

  /// The waves of `samples`: the two sides together, and each side's own,
  /// drawn as large as each other so one louder than the other stays so.
  static func waves(of samples: AudioSamples, leaving offset: Int = 0) -> Waves {
    let left = points(of: samples.left, leaving: offset)
    let right = points(of: samples.right, leaving: offset)
    let gain = 1 / max(peak(left), peak(right), 0.25)
    return Waves(
      mono: wave(of: samples.mono, leaving: offset),
      left: left.map { $0 * gain }, right: right.map { $0 * gain })
  }

  /// `wave` as `count` points, each the mean of the points it covers, or
  /// with more to make than there are, a point between its neighbours.
  static func resampledWave(_ wave: [Float], to count: Int) -> [Float] {
    guard count > 0, !wave.isEmpty else { return [] }
    if count >= wave.count { return resampled(wave, to: count) }
    return (0..<count).map { index in
      let first = index * wave.count / count
      let last = max((index + 1) * wave.count / count, first + 1)
      return vDSP.mean(Array(wave[first..<min(last, wave.count)]))
    }
  }

  /// `levels` as `count` levels: each the highest of the levels it covers,
  /// or with more to make than there are, a level between its neighbours.
  static func resampled(_ levels: [Float], to count: Int) -> [Float] {
    guard count > 0, !levels.isEmpty else { return [] }
    if count >= levels.count {
      return (0..<count).map { index in
        let position = Float(index) * Float(levels.count - 1) / Float(max(count - 1, 1))
        let lower = Int(position)
        let upper = min(lower + 1, levels.count - 1)
        return levels[lower] + (levels[upper] - levels[lower]) * (position - Float(lower))
      }
    }
    return (0..<count).map { index in
      let first = index * levels.count / count
      let last = max((index + 1) * levels.count / count, first + 1)
      return levels[first..<min(last, levels.count)].max() ?? 0
    }
  }
}
