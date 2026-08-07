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
    /// The even and odd halves of the current window, and the transform's two outputs.
    ///
    /// **These four exist because they used to be allocated per transform, and it was measured.** The
    /// previous version built `evens` and `odds` with `stride(...).map` and took the two arrays
    /// `transform(real:imaginary:)` returns — four 1024-element arrays for every transform, which for a
    /// seven-minute stereo file is **286 624 allocations and ≈293 M `Float`s**, roughly 32× the volume of
    /// the PCM copy an earlier audit spent its time on
    /// (`docs/spikes/2026-08-07-spectrogram-performance-presentation-diagnosis.md` §C). Release hid most
    /// of it; Debug did not, and Debug is what a developer runs.
    ///
    /// Held here, they are allocated **once per operation** and reused for every frame of every channel,
    /// so no allocation scales with the STFT frame count.
    private var evens: [Float]
    private var odds: [Float]
    private var outputReal: [Float]
    private var outputImaginary: [Float]

    /// Which bin each band takes on each pass of the band reduction, as **1-based** indices for
    /// `vDSP_vgathr`. One array per pass; `bandGather.count` is the widest band's bin count.
    ///
    /// A pure function of the mapping, so it is built once in `init` rather than recomputed 36.7 M times
    /// through an integer division inside the hot loop.
    private let bandGather: [[vDSP_Length]]
    private var bandMaxima: [Float]
    private var bandScratch: [Float]

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
        // Half-length: `.complexReal` treats the window's even and odd samples as one complex sequence.
        evens = [Float](repeating: 0, count: Self.fftSize / 2)
        odds = [Float](repeating: 0, count: Self.fftSize / 2)
        outputReal = [Float](repeating: 0, count: Self.fftSize / 2)
        outputImaginary = [Float](repeating: 0, count: Self.fftSize / 2)

        // Which bins each band covers, read from the mapping itself so this can never disagree with it.
        var binsPerBand = [[Int]](repeating: [], count: mapping.bandCount)
        for bin in 0 ..< Self.binCount {
            if let band = mapping.bandIndex(forBin: bin) { binsPerBand[band].append(bin) }
        }
        let widest = binsPerBand.map(\.count).max() ?? 0
        bandGather = (0 ..< widest).map { pass in
            binsPerBand.map { bins -> vDSP_Length in
                // A band with fewer bins repeats its last, which cannot change a maximum. An empty band
                // cannot occur while `bandCount <= binCount`, and reads bin 0 rather than out of bounds.
                guard let bin = bins.isEmpty ? nil : bins[min(pass, bins.count - 1)] else { return 1 }
                return vDSP_Length(bin + 1)   // `vDSP_vgathr` indices are 1-based
            }
        }
        bandMaxima = [Float](repeating: 0, count: mapping.bandCount)
        bandScratch = [Float](repeating: 0, count: mapping.bandCount)
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
        // Absolute dBFS, referenced to full scale. **No normalisation of any kind**: the user compares
        // copies of the same music, and scaling each file to its own peak would make two files
        // incomparable. The floor applies below; nothing is limited above, so a file that exceeds full
        // scale keeps its values above 0 dBFS.
        //
        // **This one stays scalar, deliberately.** `vDSP_vdbcon` computes the same thing far faster, but
        // its logarithm differs from `log10`'s in the last bit: measured across three real files, the
        // vectorised form moved **267 000 to 297 000 of 524 288 cells by up to 2.29 × 10⁻⁵ dB** — one to
        // three ULP, and far below anything a reader or a threshold could notice.
        //
        // It was reverted anyway, because the trade is poor. This pass is **one** sweep over the grid,
        // not one per window: 86 ms of an unoptimised build's 36 s, or 0.2 %. Paying that keeps the whole
        // optimisation **bit-identical** to the model it replaces, which is a far stronger claim than
        // "different by an amount we argue is small".
        var values = [Float](repeating: Spectrogram.floorDecibels, count: peak.count)
        for index in 0 ..< peak.count {
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
            //
            // The first channel is **copied** rather than maximised against a zeroed buffer: the clear
            // beforehand was a third of a scalar pass per window, and starting from the first channel's
            // own magnitudes gives the identical answer without it.
            if channel == 0 {
                combined.withUnsafeMutableBufferPointer { destination in
                    magnitudes.withUnsafeBufferPointer { source in
                        destination.baseAddress?.update(from: source.baseAddress!, count: Self.binCount)
                    }
                }
            } else {
                vDSP.maximum(combined, magnitudes, result: &combined)
            }
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
        //
        // Split with `vDSP_ctoz`, which is exactly this operation: it reads a buffer as interleaved
        // complex pairs and writes the two halves apart. It fills buffers this type already owns, so the
        // split costs no allocation — where `stride(...).map` built two fresh arrays every time.
        splitWindowIntoHalves()

        // The output goes into buffers this type owns too. `transform(real:imaginary:)` returns two new
        // arrays; this overload writes into existing ones and is the same transform otherwise.
        dft.transform(
            inputReal: evens,
            inputImaginary: odds,
            outputReal: &outputReal,
            outputImaginary: &outputImaginary
        )

        // **The interior bins are vectorised, and the arithmetic is kept in the same order.**
        //
        // This replaces a scalar loop of 1 023 square roots per transform — 73.3 M for a seven-minute
        // stereo file — measured at **11.5 s** where the vectorised form takes tens of milliseconds
        // (`docs/spikes/2026-08-07-spectrogram-performance-presentation-diagnosis.md` §I). Accelerate is
        // precompiled, so the saving lands in an unoptimised build too, which is the one a developer runs.
        //
        // **`zvmags` + `vvsqrtf`, not `zvabs`.** The obvious call is `vDSP_zvabs`, which computes the
        // same magnitude in one pass — but not with the same last bit: measured over three real files it
        // moved 31 068 of 524 288 cells by one ULP (7.6 × 10⁻⁶ dB), because it does not evaluate
        // `re² + im²` and then take a root. Splitting it into exactly those two steps reproduces the
        // scalar expression term for term and the result is **bit-identical**, at no measurable cost.
        //
        // The scale is applied to the interior bins **separately** from the two ends, so the arithmetic
        // of each stays exactly what it was: an end is `abs(x) * scale * 0.5`, an interior bin is
        // `sqrt(...) * scale`. Folding the ends into one multiply would reassociate their product.
        let interior = Self.binCount - 2
        var interiorCount = Int32(interior)
        outputReal.withUnsafeMutableBufferPointer { realBuffer in
            outputImaginary.withUnsafeMutableBufferPointer { imaginaryBuffer in
                guard let realBase = realBuffer.baseAddress, let imaginaryBase = imaginaryBuffer.baseAddress
                else { return }
                var split = DSPSplitComplex(realp: realBase + 1, imagp: imaginaryBase + 1)
                magnitudes.withUnsafeMutableBufferPointer { magnitudeBuffer in
                    guard let magnitudeBase = magnitudeBuffer.baseAddress else { return }
                    vDSP_zvmags(&split, 1, magnitudeBase + 1, 1, vDSP_Length(interior))
                    vvsqrtf(magnitudeBase + 1, magnitudeBase + 1, &interiorCount)
                    var scale = magnitudeScale
                    vDSP_vsmul(magnitudeBase + 1, 1, &scale, magnitudeBase + 1, 1, vDSP_Length(interior))
                }
            }
        }

        // DC and Nyquist come back packed into element 0 — `real[0]` and `imaginary[0]` — so they are
        // unpacked into the first and last bins rather than summed into one. Their amplitudes carry no
        // mirrored twin, so they are halved to sit on the same scale as every other bin: measured, DC at
        // 0.5 then reads −6.02 dBFS exactly as a tone at 0.5 does.
        magnitudes[0] = abs(outputReal[0]) * magnitudeScale * 0.5
        magnitudes[Self.binCount - 1] = abs(outputImaginary[0]) * magnitudeScale * 0.5
    }

    /// Deinterleaves `windowed` into `evens` and `odds` in place.
    ///
    /// The pointers live only inside this call: `DSPSplitComplex` is built, used and dropped within the
    /// nested scopes, and nothing it refers to outlives them.
    mutating func splitWindowIntoHalves() {
        let half = Self.fftSize / 2
        windowed.withUnsafeBufferPointer { source in
            guard let base = source.baseAddress else { return }
            evens.withUnsafeMutableBufferPointer { evensBuffer in
                odds.withUnsafeMutableBufferPointer { oddsBuffer in
                    guard let realp = evensBuffer.baseAddress, let imagp = oddsBuffer.baseAddress else {
                        return
                    }
                    var split = DSPSplitComplex(realp: realp, imagp: imagp)
                    base.withMemoryRebound(to: DSPComplex.self, capacity: half) { interleaved in
                        vDSP_ctoz(interleaved, 2, &split, 1, vDSP_Length(half))
                    }
                }
            }
        }
    }

    /// Folds the combined magnitudes of one transform frame into its column, reducing by maximum.
    ///
    /// **Maximum in both axes, never the mean.** The mean buried a 20 ms transient by 8.74 dB, and a
    /// brief burst of high-frequency content is exactly what a user is looking for. The risk was
    /// checked rather than assumed: an isolated click lights 3 columns of 1024 under either strategy,
    /// so the maximum does not smear one artefact into a surface.
    ///
    /// **The reduction is a gather, not a loop.** Which bins belong to a band is a function of the
    /// mapping alone, so the indices are computed once in `init` and reused for every window. Each pass
    /// gathers one bin per band with `vDSP_vgathr`, the passes are combined by `vDSP_vmax`, and the
    /// result folds into the column with one more `vDSP_vmax`. The scalar version ran 1 025 integer
    /// divisions and 1 025 indexed maxima per window — 36.7 M for a seven-minute file, measured at
    /// **6.1 s** in an unoptimised build.
    ///
    /// A band with fewer bins than the widest one repeats its last bin, which cannot change a maximum.
    mutating func foldIntoGrid() {
        guard let column = mapping.columnIndex(forFrame: framesTransformed), !bandGather.isEmpty else {
            return
        }
        let bands = mapping.bandCount
        let columnStart = column * bands

        combined.withUnsafeBufferPointer { source in
            guard let sourceBase = source.baseAddress else { return }
            bandMaxima.withUnsafeMutableBufferPointer { maxima in
                guard let maximaBase = maxima.baseAddress else { return }
                for pass in bandGather.indices {
                    bandGather[pass].withUnsafeBufferPointer { indices in
                        guard let indexBase = indices.baseAddress else { return }
                        if pass == 0 {
                            vDSP_vgathr(sourceBase, indexBase, 1, maximaBase, 1, vDSP_Length(bands))
                        } else {
                            bandScratch.withUnsafeMutableBufferPointer { scratch in
                                guard let scratchBase = scratch.baseAddress else { return }
                                vDSP_vgathr(sourceBase, indexBase, 1, scratchBase, 1, vDSP_Length(bands))
                                vDSP_vmax(maximaBase, 1, scratchBase, 1, maximaBase, 1, vDSP_Length(bands))
                            }
                        }
                    }
                }
                peak.withUnsafeMutableBufferPointer { destination in
                    guard let destinationBase = destination.baseAddress else { return }
                    vDSP_vmax(
                        destinationBase + columnStart, 1, maximaBase, 1,
                        destinationBase + columnStart, 1, vDSP_Length(bands)
                    )
                }
            }
        }
    }
}
