import Accelerate

import AudioInspectorDomain

/// Folds decoded PCM into a bounded spectral model: short-time Fourier transform, then reduction by
/// maximum in both axes.
///
/// ## Not `Sendable`, deliberately
///
/// It owns a `vDSP.DiscreteFourierTransform`, which is not `Sendable` — and neither is `vDSP.FFT`. That
/// is not worked around: the accumulator is created and consumed inside **one** `nonisolated async`
/// operation, never stored on a `Sendable` type, never cached, never shared. No `@unchecked Sendable`
/// exists anywhere in this package, and that is the evidence for the claim rather than this comment.
///
/// ## What crosses its surface
///
/// `PCMChunk` in, `Spectrogram` out. No `DSPSplitComplex`, no `vDSP.*` and no transform setup appears
/// in any signature: Accelerate stops here, and a caller cannot tell which library did the arithmetic.
///
/// ## The constants are measured, not conventional
///
/// FFT 2048, hop 512, Hann denormalised, magnitude scaled by `1 / windowSum`, floor −120 dBFS, and
/// reduction by **maximum** in both axes. Every one of them comes from
/// `docs/spikes/2026-08-06-static-spectrogram-validation.md`; the reasons are recorded beside each use
/// rather than gathered here.
public struct SpectrogramAccumulator {
    /// Frames per transform. 2048 at 44.1 kHz is a 43.1 Hz reduced band, which the spike measured as
    /// sufficient to separate every cutoff pair at every sample rate — narrowest margin five bands at
    /// 192 kHz.
    public static let fftSize = 2_048
    /// Frames advanced between transforms: a quarter of the window, so successive frames overlap by 75 %
    /// and a transient cannot fall entirely between two of them.
    public static let hop = 512

    /// Useful bins of a real-to-complex transform, **including both ends**: DC and Nyquist.
    ///
    /// `fftSize / 2 + 1`, not `fftSize / 2`. vDSP's real-to-complex output packs DC into `real[0]` and
    /// Nyquist into `imaginary[0]`, so taking the magnitude of that element sums two frequencies at
    /// opposite ends of the spectrum into one value. Measured: DC at 0.5 together with Nyquist at 0.5
    /// read **+3.01 dBFS in the lowest bin**, and Nyquist alone lit the lowest bin at −0.00 dBFS. For an
    /// instrument whose subject is where high-frequency energy stops, energy at Nyquist appearing in the
    /// bass is exactly the wrong failure. They are unpacked into their own bins below.
    public static let binCount = fftSize / 2 + 1

    private let dft: vDSP.DiscreteFourierTransform<Float>
    private let window: [Float]
    /// `1 / windowSum`, precomputed. **`2 / windowSum` is the natural mistake and reads 6 dB high** —
    /// the real-to-complex packing invites it. Pinned by tones at three amplitudes reading exactly
    /// 0.00, −6.02 and −20.00 dBFS.
    private let magnitudeScale: Float

    private let mapping: SpectrogramGridMapping
    private let sampleRate: Double
    private let channelCount: Int
    private let frameCount: Int
    private let stftFrameCount: Int

    // MARK: Mutable state, all confined to one operation

    /// Samples not yet consumed by a window, one buffer per channel.
    private var pending: [[Float]]
    /// How many frames at the front of `pending` have already been advanced past. Kept as an index
    /// rather than removing from the front, so feeding a file in small chunks stays linear.
    private var consumedFromPending = 0
    private var framesTransformed = 0
    /// The running maximum per cell, in **linear** amplitude. Converted to dBFS once, in `finish()`:
    /// taking the maximum of logarithms and of amplitudes gives the same answer, and doing it once is
    /// both cheaper and free of repeated rounding.
    private var peak: [Float]

    // Scratch, allocated once per operation rather than per frame.
    private var windowed: [Float]
    private var magnitudes: [Float]
    private var combined: [Float]

    /// Fails on a description no analysis can be sized against.
    public init?(sampleRate: Double, channelCount: Int, frameCount: Int) {
        guard sampleRate.isFinite, sampleRate > 0, channelCount >= 1, frameCount >= 0 else { return nil }
        guard let dft = try? vDSP.DiscreteFourierTransform(
            previous: nil,
            count: Self.fftSize,
            direction: .forward,
            transformType: .complexReal,
            ofType: Float.self
        ) else { return nil }

        // **The final incomplete window is discarded, never zero-padded.** Padding invents samples the
        // file does not contain and reads the level low: the spike measured a 0.5 tone at −12.47 dBFS
        // where it should read −6.02. At most `fftSize - 1` frames — 46 ms at 44.1 kHz — go undrawn,
        // which is preferable to drawing something the file does not say. A file shorter than one
        // window therefore yields **no** windows, and no column is invented for it.
        let stftFrameCount = frameCount >= Self.fftSize
            ? (frameCount - Self.fftSize) / Self.hop + 1
            : 0
        guard let mapping = SpectrogramGridMapping(
            stftFrameCount: stftFrameCount,
            binCount: Self.binCount
        ) else { return nil }

        self.dft = dft
        self.mapping = mapping
        self.sampleRate = sampleRate
        self.channelCount = channelCount
        self.frameCount = frameCount
        self.stftFrameCount = stftFrameCount

        window = vDSP.window(
            ofType: Float.self,
            usingSequence: .hanningDenormalized,
            count: Self.fftSize,
            isHalfWindow: false
        )
        magnitudeScale = 1 / window.reduce(0, +)

        peak = [Float](repeating: 0, count: mapping.columnCount * mapping.bandCount)
        pending = Array(repeating: [], count: channelCount)
        windowed = [Float](repeating: 0, count: Self.fftSize)
        magnitudes = [Float](repeating: 0, count: Self.binCount)
        combined = [Float](repeating: 0, count: Self.binCount)
    }

    /// Feeds one chunk of decoded audio.
    ///
    /// The result does not depend on how the caller chunks the file — down to one frame per call —
    /// because the window boundaries are counted from the start of the file and the frame→column
    /// mapping is a function of the file alone. A chunk whose channel count disagrees with the stream's
    /// is ignored rather than folded into the wrong channel.
    public mutating func accumulate(_ chunk: PCMChunk) {
        guard chunk.channelCount == channelCount else { return }
        for channel in 0 ..< channelCount {
            pending[channel].append(contentsOf: chunk.channels[channel])
        }
        drainCompleteWindows()
    }

    /// The model, in absolute dBFS.
    public func finish() -> Spectrogram? {
        var values = [Float](repeating: Spectrogram.floorDecibels, count: peak.count)
        for index in 0 ..< peak.count {
            // Absolute dBFS, referenced to full scale. **No normalisation of any kind**: the user
            // compares copies of the same music, and scaling each file to its own peak would make two
            // files incomparable. The floor applies below; nothing is limited above, so a file that
            // exceeds full scale keeps its values above 0 dBFS.
            values[index] = max(
                Spectrogram.floorDecibels,
                20 * log10(max(peak[index], 1e-12))
            )
        }
        return Spectrogram(
            values: values,
            columnCount: mapping.columnCount,
            bandCount: mapping.bandCount,
            sampleRate: sampleRate,
            frameCount: frameCount,
            channelCount: channelCount
        )
    }
}

// MARK: - The transform

private extension SpectrogramAccumulator {
    /// Transforms every window that `pending` now holds in full, advancing by `hop` after each.
    mutating func drainCompleteWindows() {
        while pending[0].count - consumedFromPending >= Self.fftSize, framesTransformed < stftFrameCount {
            transformOneWindow()
            framesTransformed += 1
            consumedFromPending += Self.hop
        }
        compactPending()
    }

    /// Drops the samples no future window can reach. Amortised: only when the dead prefix is worth more
    /// than the copy it costs.
    mutating func compactPending() {
        guard consumedFromPending >= Self.fftSize else { return }
        for channel in 0 ..< channelCount {
            pending[channel].removeFirst(consumedFromPending)
        }
        consumedFromPending = 0
    }

    /// One STFT frame across every channel: transform each separately, combine magnitudes by maximum
    /// per bin, then fold into that frame's column and bands.
    mutating func transformOneWindow() {
        for bin in 0 ..< Self.binCount { combined[bin] = 0 }

        // **Channels are processed sequentially, sharing the one transform.** Not an optimisation left
        // undone: the setup is not `Sendable`, so per-channel parallelism would need one setup each, and
        // recreating a setup costs 10× what a transform does. Stereo costs 1.6–1.7× mono, accepted.
        for channel in 0 ..< channelCount {
            transformChannel(channel)
            // **Maximum per bin, in the frequency domain.** Combining samples in the *time* domain was
            // measured to invent 247 spurious bands — energy present in neither channel — because
            // taking the louder sample synthesises a waveform that exists in no channel. For an
            // instrument whose subject is where energy stops, invented energy could hide a real cutoff.
            // Here: a tone in one channel alone survives, and opposite polarity cannot cancel.
            //
            // The result is a **combined** spectral envelope across channels. It is not a mono mix and
            // not a downmix, and is not named as one anywhere.
            for bin in 0 ..< Self.binCount { combined[bin] = max(combined[bin], magnitudes[bin]) }
        }

        foldIntoGrid()
    }

    /// Windows one channel's current frame, transforms it, and leaves its per-bin amplitudes in
    /// `magnitudes`.
    mutating func transformChannel(_ channel: Int) {
        let start = consumedFromPending
        pending[channel].withUnsafeBufferPointer { source in
            let frame = UnsafeBufferPointer(rebasing: source[start ..< start + Self.fftSize])
            vDSP.multiply(frame, window, result: &windowed)
        }

        // `.complexReal` takes the even and odd samples as the real and imaginary halves of a
        // half-length complex sequence — the standard real-to-complex split.
        let evens = stride(from: 0, to: Self.fftSize, by: 2).map { windowed[$0] }
        let odds = stride(from: 1, to: Self.fftSize, by: 2).map { windowed[$0] }
        let transformed = dft.transform(real: evens, imaginary: odds)

        // DC and Nyquist come back packed into element 0 — `real[0]` and `imaginary[0]` — so they are
        // unpacked into the first and last bins rather than summed into one. Their amplitudes carry no
        // mirrored twin, so they are halved to sit on the same scale as every other bin: measured, DC at
        // 0.5 then reads −6.02 dBFS exactly as a tone at 0.5 does.
        magnitudes[0] = abs(transformed.real[0]) * magnitudeScale * 0.5
        magnitudes[Self.binCount - 1] = abs(transformed.imaginary[0]) * magnitudeScale * 0.5
        for bin in 1 ..< Self.binCount - 1 {
            let real = transformed.real[bin]
            let imaginary = transformed.imaginary[bin]
            magnitudes[bin] = (real * real + imaginary * imaginary).squareRoot() * magnitudeScale
        }
    }

    /// Folds the combined magnitudes of one transform frame into its column, reducing by maximum.
    mutating func foldIntoGrid() {
        guard let column = mapping.columnIndex(forFrame: framesTransformed) else { return }

        // **Maximum in both axes, never the mean.** The mean buried a 20 ms transient by 8.74 dB, and a
        // brief burst of high-frequency content is exactly what a user is looking for. The risk was
        // checked rather than assumed: an isolated click lights 3 columns of 1024 under either strategy,
        // so the maximum does not smear one artefact into a surface.
        for bin in 0 ..< Self.binCount {
            guard let band = mapping.bandIndex(forBin: bin) else { continue }
            let index = column * mapping.bandCount + band
            peak[index] = max(peak[index], combined[bin])
        }
    }
}
