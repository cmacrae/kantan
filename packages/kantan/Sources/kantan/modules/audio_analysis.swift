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

  /// The latest stretch of `samples` as `wavePoints` points, -1 to 1, each
  /// the mean of the samples it covers. A quiet wave is drawn larger, up to
  /// four times.
  static func wave(of samples: [Float]) -> [Float] {
    let stride = max(samples.count / 4 / wavePoints, 1)
    let recent = samples.suffix(stride * wavePoints)
    guard recent.count == stride * wavePoints else {
      return [Float](repeating: 0, count: wavePoints)
    }
    let points = (0..<wavePoints).map { point in
      vDSP.mean(Array(recent.dropFirst(point * stride).prefix(stride)))
    }
    let gain = 1 / max(peak(points), 0.25)
    return points.map { $0 * gain }
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
