import Accelerate
import Foundation

// The candidate reduction, written the way it would live in `AudioInspectorAnalysis`: pure, fed in
// chunks, holding no file and exposing no framework type. Nothing here is production code — it exists
// to be measured, and the numbers it produces are what `docs/spikes/` records.

/// The fixed shape of the model. Independent of any view: resizing a window re-maps this, it never
/// recomputes it.
struct SpectrogramSpec: Sendable, Equatable {
    var fftSize = 2_048
    var hop = 512
    var maxColumns = 1_024
    var maxBands = 512
    var floorDB: Float = -120

    /// Useful bins of a real-to-complex transform.
    var bins: Int { fftSize / 2 }
}

/// The reduced model: `columns × bands` of dBFS on an absolute scale, plus what is needed to read the
/// axes. Never normalised per file.
struct SpectrogramModel: Sendable, Equatable {
    let values: [Float] // row-major: column * bands + band
    let columns: Int
    let bands: Int
    let sampleRate: Double
    let frameCount: Int
    let channelCount: Int

    var nyquist: Double { sampleRate / 2 }
    func value(column: Int, band: Int) -> Float { values[column * bands + band] }

    /// Centre frequency of a reduced band.
    func frequency(ofBand band: Int) -> Double { (Double(band) + 0.5) * nyquist / Double(bands) }

    /// The highest band rising above `threshold` dBFS anywhere in the file. This is an *observation*,
    /// not a verdict: it says where energy stops, never why.
    func highestBand(above threshold: Float) -> Int? {
        for band in stride(from: bands - 1, through: 0, by: -1) {
            for column in 0 ..< columns where value(column: column, band: band) > threshold {
                return band
            }
        }
        return nil
    }

    func highestFrequency(above threshold: Float) -> Double? {
        highestBand(above: threshold).map { frequency(ofBand: $0) }
    }

    /// Peak dBFS at a frequency, across the whole file.
    func peak(atFrequency frequency: Double) -> Float? {
        let band = Int(frequency / (nyquist / Double(bands)))
        guard band >= 0, band < bands else { return nil }
        var best = -Float.infinity
        for column in 0 ..< columns { best = max(best, value(column: column, band: band)) }
        return best
    }

    /// The loudest point anywhere, with where it is.
    func loudest() -> (band: Int, db: Float) {
        var best = (band: 0, db: -Float.infinity)
        for band in 0 ..< bands {
            for column in 0 ..< columns where value(column: column, band: band) > best.db {
                best = (band, value(column: column, band: band))
            }
        }
        return best
    }
}

/// How several STFT frames fold into one column, and several bins into one band.
enum Reduction: String, Sendable {
    case maximum
    case mean
}

/// Folds PCM chunks into a bounded spectrogram.
///
/// **Not `Sendable`, on purpose.** It owns a `vDSP.DiscreteFourierTransform`, which is not `Sendable`
/// either (measured — see the report). It is created and consumed inside one `nonisolated async`
/// function, never shared across an isolation boundary, and never annotated `@unchecked Sendable`.
/// That this file compiles under `-swift-language-mode 6` **is** the evidence for that claim.
///
/// **Channels are transformed separately and combined by maximum per bin, in the frequency domain.**
/// Combining samples in the time domain was measured to synthesise spectral content present in
/// neither channel; the negative control in `GateChannels.swift` reproduces that failure.
final class SpectrogramAccumulator {
    private let spec: SpectrogramSpec
    private let sampleRate: Double
    private let channelCount: Int
    private let totalFrames: Int
    private let reduction: Reduction

    /// One transform, created once per operation and reused for every frame of every channel.
    /// Recreating it per frame was measured at 10× the cost.
    private let dft: vDSP.DiscreteFourierTransform<Float>
    private let window: [Float]
    private let windowSum: Float

    private var accumulator: [Float]
    private var counts: [Int]
    private let columns: Int
    private let bands: Int
    private let binsPerBand: Int
    private let stftFrames: Int

    /// Samples not yet consumed by a window, one buffer per channel.
    private var pending: [[Float]]
    private var framesConsumed = 0

    /// Scratch reused across frames so the per-frame cost is transform-bound, not allocation-bound.
    private var windowed: [Float]
    private var magnitudes: [Float]
    private var combined: [Float]

    init?(
        sampleRate: Double,
        channelCount: Int,
        totalFrames: Int,
        spec: SpectrogramSpec = .init(),
        reduction: Reduction = .maximum
    ) {
        guard sampleRate > 0, channelCount >= 1, totalFrames >= 0 else { return nil }
        guard let dft = try? vDSP.DiscreteFourierTransform(
            previous: nil,
            count: spec.fftSize,
            direction: .forward,
            transformType: .complexReal,
            ofType: Float.self
        ) else { return nil }

        self.spec = spec
        self.sampleRate = sampleRate
        self.channelCount = channelCount
        self.totalFrames = totalFrames
        self.reduction = reduction
        self.dft = dft

        window = vDSP.window(ofType: Float.self, usingSequence: .hanningDenormalized, count: spec.fftSize, isHalfWindow: false)
        windowSum = window.reduce(0, +)

        // **The final incomplete frame is discarded, never zero-padded.** Padding invents samples the
        // file does not contain and reads the level low — measured at −12.87 dBFS for a tone that
        // should read −6.02. At most `fftSize - 1` frames (46 ms at 44.1 kHz) are left undrawn.
        stftFrames = totalFrames >= spec.fftSize ? (totalFrames - spec.fftSize) / spec.hop + 1 : 0
        columns = max(1, min(spec.maxColumns, max(stftFrames, 1)))
        binsPerBand = max(1, spec.bins / spec.maxBands)
        bands = spec.bins / binsPerBand

        accumulator = [Float](repeating: 0, count: columns * bands)
        counts = [Int](repeating: 0, count: columns)
        pending = Array(repeating: [], count: channelCount)
        windowed = [Float](repeating: 0, count: spec.fftSize)
        magnitudes = [Float](repeating: 0, count: spec.bins)
        combined = [Float](repeating: 0, count: spec.bins)
    }

    /// Feeds one chunk: `chunk[channel]` holds that channel's samples, every channel the same length.
    ///
    /// The result is independent of how the caller chunks the file — verified down to one frame per
    /// call — because the frame→column mapping is a function of the file alone.
    func accumulate(_ chunk: [[Float]]) {
        guard chunk.count == channelCount else { return }
        for channel in 0 ..< channelCount { pending[channel].append(contentsOf: chunk[channel]) }
        drain()
    }

    func finish() -> SpectrogramModel {
        var out = [Float](repeating: spec.floorDB, count: columns * bands)
        for index in 0 ..< accumulator.count {
            let column = index / bands
            let linear: Float
            switch reduction {
            case .maximum:
                linear = accumulator[index]
            case .mean:
                linear = counts[column] > 0 ? accumulator[index] / Float(counts[column]) : 0
            }
            // Absolute dBFS, referenced to full scale. No per-file normalisation, ever: the user
            // compares copies of the same music, and scaling each file to its own peak would make two
            // files incomparable.
            out[index] = max(spec.floorDB, 20 * log10(max(linear, 1e-12)))
        }
        return SpectrogramModel(
            values: out, columns: columns, bands: bands,
            sampleRate: sampleRate, frameCount: totalFrames, channelCount: channelCount
        )
    }

    private func drain() {
        while pending[0].count >= spec.fftSize {
            processFrame()
            for channel in 0 ..< channelCount { pending[channel].removeFirst(spec.hop) }
        }
    }

    /// One STFT frame across every channel: transform each separately, combine magnitudes by maximum,
    /// then fold into the frame's column and bands.
    private func processFrame() {
        guard framesConsumed < stftFrames else {
            framesConsumed += 1
            return
        }
        for index in 0 ..< spec.bins { combined[index] = 0 }

        // Channels are processed **sequentially**, sharing the one transform. No parallelism: the
        // transform is not `Sendable`, so a per-channel task would need a setup each.
        for channel in 0 ..< channelCount {
            pending[channel].withUnsafeBufferPointer { source in
                let frame = UnsafeBufferPointer(rebasing: source[0 ..< spec.fftSize])
                vDSP.multiply(frame, window, result: &windowed)
            }
            let evens = stride(from: 0, to: spec.fftSize, by: 2).map { windowed[$0] }
            let odds = stride(from: 1, to: spec.fftSize, by: 2).map { windowed[$0] }
            let transformed = dft.transform(real: evens, imaginary: odds)

            transformed.real.withUnsafeBufferPointer { real in
                transformed.imaginary.withUnsafeBufferPointer { imaginary in
                    let split = DSPSplitComplex(
                        realp: .init(mutating: real.baseAddress!),
                        imagp: .init(mutating: imaginary.baseAddress!)
                    )
                    vDSP.absolute(split, result: &magnitudes)
                }
            }
            // Amplitude referenced to full scale. `1 / windowSum` — verified exact against pure tones
            // at three amplitudes; `2 / windowSum` is the natural mistake and reads +6 dB.
            vDSP.multiply(1 / windowSum, magnitudes, result: &magnitudes)
            // Maximum per bin, in the frequency domain: energy present in a single channel survives,
            // opposite polarity cannot cancel, and nothing absent from every channel is invented.
            for bin in 0 ..< spec.bins { combined[bin] = max(combined[bin], magnitudes[bin]) }
        }

        // Which reduced column this frame belongs to — a function of the file, not of the chunking.
        let column = stftFrames <= 1 ? 0 : min(columns - 1, framesConsumed * columns / stftFrames)
        counts[column] += 1
        for band in 0 ..< bands {
            let lower = band * binsPerBand
            var value: Float = 0
            for bin in lower ..< (lower + binsPerBand) {
                switch reduction {
                case .maximum: value = max(value, combined[bin])
                case .mean: value += combined[bin] / Float(binsPerBand)
                }
            }
            let index = column * bands + band
            switch reduction {
            case .maximum: accumulator[index] = max(accumulator[index], value)
            case .mean: accumulator[index] += value
            }
        }
        framesConsumed += 1
    }
}

// MARK: - Driving the accumulator

/// Runs the accumulator over in-memory channels.
///
/// `nonisolated` and `async` on purpose: this is the shape the production adapter would take, and it
/// is what confines the non-`Sendable` transform to a single call. Cancellation is honoured between
/// chunks, and a cancelled run returns `nil` rather than a partial model presented as complete.
nonisolated func makeSpectrogram(
    channels: [[Float]],
    sampleRate: Double,
    spec: SpectrogramSpec = .init(),
    reduction: Reduction = .maximum,
    chunk: Int? = nil
) async -> SpectrogramModel? {
    let frames = channels.first?.count ?? 0
    guard let accumulator = SpectrogramAccumulator(
        sampleRate: sampleRate, channelCount: channels.count,
        totalFrames: frames, spec: spec, reduction: reduction
    ) else { return nil }

    let step = chunk ?? max(frames, 1)
    var start = 0
    while start < frames {
        if Task.isCancelled { return nil }
        let end = min(start + step, frames)
        accumulator.accumulate(channels.map { Array($0[start ..< end]) })
        start = end
    }
    return accumulator.finish()
}

/// Synchronous convenience for the gates that are not about cancellation.
func spectrogram(
    channels: [[Float]],
    sampleRate: Double,
    spec: SpectrogramSpec = .init(),
    reduction: Reduction = .maximum,
    chunk: Int? = nil
) -> SpectrogramModel? {
    let frames = channels.first?.count ?? 0
    guard let accumulator = SpectrogramAccumulator(
        sampleRate: sampleRate, channelCount: channels.count,
        totalFrames: frames, spec: spec, reduction: reduction
    ) else { return nil }
    let step = chunk ?? max(frames, 1)
    var start = 0
    while start < frames {
        let end = min(start + step, frames)
        accumulator.accumulate(channels.map { Array($0[start ..< end]) })
        start = end
    }
    return accumulator.finish()
}
