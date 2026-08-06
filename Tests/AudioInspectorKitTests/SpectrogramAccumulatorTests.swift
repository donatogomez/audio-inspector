import AudioInspectorAnalysis
import AudioInspectorDomain
import Foundation
import Testing

// The STFT and its reduction, over synthetic signals whose correct answer is known in advance. Nothing
// here re-implements the transform: every assertion is about the model the accumulator returns.
//
// The amplitudes are the ones that pin the scale. A tone at 1.0 must read 0 dBFS, at 0.5 −6.02 and at
// 0.1 −20.00; `2 / windowSum` is the natural mistake and reads every one of them 6 dB high.

/// Builds a signal as a pure function of `(channel, frame)` and feeds it through the accumulator in
/// chunks of `chunkFrames`, exactly as the decoding port would.
private func model(
    frames: Int,
    channels: Int = 1,
    sampleRate: Double = 44_100,
    chunkFrames: Int = 4_096,
    sample: (Int, Int) -> Float
) throws -> Spectrogram {
    var accumulator = try #require(
        SpectrogramAccumulator(sampleRate: sampleRate, channelCount: channels, frameCount: frames)
    )
    var start = 0
    while start < frames {
        let count = min(chunkFrames, frames - start)
        let data = (0 ..< channels).map { channel in
            (0 ..< count).map { sample(channel, start + $0) }
        }
        accumulator.accumulate(try PCMChunk(startFrame: start, channels: data))
        start += count
    }
    return try #require(accumulator.finish())
}

private func tone(_ frequency: Double, amplitude: Float, sampleRate: Double = 44_100) -> (Int, Int) -> Float {
    { _, frame in amplitude * Float(sin(2 * .pi * frequency * Double(frame) / sampleRate)) }
}

/// The exact centre frequency of transform bin `bin` — a tone placed here falls on a bin and suffers
/// no scalloping, which is what lets the amplitude assertions be exact.
private func binFrequency(_ bin: Int, sampleRate: Double = 44_100) -> Double {
    Double(bin) * sampleRate / Double(SpectrogramAccumulator.fftSize)
}

/// One sample of a sine, spelled out so the type checker never has to solve a long mixed expression.
private func sine(_ frequency: Double, _ amplitude: Float, _ frame: Int, _ sampleRate: Double = 44_100) -> Float {
    let phase = 2 * Double.pi * frequency * Double(frame) / sampleRate
    return amplitude * Float(sin(phase))
}

/// The loudest cell of a model, and the band it sits in.
private func peak(_ spectrogram: Spectrogram) -> (value: Float, band: Int, column: Int) {
    var best = (value: -Float.infinity, band: 0, column: 0)
    for column in 0 ..< spectrogram.columnCount {
        for band in 0 ..< spectrogram.bandCount {
            let value = spectrogram.value(column: column, band: band)!
            if value > best.value { best = (value, band, column) }
        }
    }
    return best
}

@Suite("Analysis — spectrogram STFT scale")
struct SpectrogramAccumulatorScaleTests {
    /// The three readings that pin `1 / windowSum`. A tone placed exactly on a bin must read its own
    /// amplitude in dBFS, with no scale factor of 2 anywhere.
    @Test(
        "a tone on a bin reads its own amplitude, exactly",
        arguments: [(Float(1.0), Float(0)), (0.5, -6.02), (0.1, -20.0)]
    )
    func tonesReadTheirAmplitude(amplitude: Float, expected: Float) throws {
        // 1000 bins up at 44 100 Hz with a 2048-point transform: exactly on a bin, so no scalloping.
        let frequency = binFrequency(1_000)
        let spectrogram = try model(frames: 44_100, sample: tone(frequency, amplitude: amplitude))

        let loudest = peak(spectrogram)
        #expect(abs(loudest.value - expected) < 0.05, "read \(loudest.value) dBFS, expected \(expected)")
    }

    @Test("silence sits at the floor, everywhere")
    func silenceIsAtTheFloor() throws {
        let spectrogram = try model(frames: 44_100) { _, _ in 0 }
        #expect(spectrogram.values.allSatisfy { $0 == Spectrogram.floorDecibels })
    }

    /// Nothing is normalised: two files at different levels stay exactly that far apart in the model.
    @Test("two signals 20 dB apart stay 20 dB apart")
    func nothingIsNormalised() throws {
        let frequency = binFrequency(1_000)
        let loud = try model(frames: 44_100, sample: tone(frequency, amplitude: 0.5))
        let quiet = try model(frames: 44_100, sample: tone(frequency, amplitude: 0.05))

        #expect(abs((peak(loud).value - peak(quiet).value) - 20) < 0.05)
    }

    /// A file that exceeds full scale keeps its values above 0 dBFS. Limiting belongs to drawing, which
    /// has edges, not to the data.
    @Test("a signal beyond full scale reads above 0 dBFS, unclamped")
    func valuesAboveFullScaleSurvive() throws {
        let frequency = binFrequency(1_000)
        let spectrogram = try model(frames: 44_100, sample: tone(frequency, amplitude: 1.5))
        #expect(peak(spectrogram).value > 0, "read \(peak(spectrogram).value) dBFS")
        #expect(abs(peak(spectrogram).value - 3.52) < 0.1, "the spike measured +3.52 dBFS for 1.5")
    }

    /// DC and Nyquist are packed into one element by the real-to-complex transform. Unpacked, each
    /// lands in its own end of the spectrum and reads on the same scale as any other bin.
    @Test("direct current lands in the lowest band, on the same scale as a tone")
    func directCurrentIsNotDoubled() throws {
        let spectrogram = try model(frames: 44_100) { _, _ in 0.5 }
        let loudest = peak(spectrogram)
        #expect(loudest.band == 0, "DC belongs in the lowest band")
        #expect(abs(loudest.value - -6.02) < 0.05, "DC at 0.5 read \(loudest.value), not −6.02")
    }

    @Test("energy at Nyquist lands in the highest band, not the lowest")
    func nyquistIsNotFoldedIntoTheBass() throws {
        // Alternating ±0.5 is exactly Nyquist.
        let spectrogram = try model(frames: 44_100) { _, frame in frame.isMultiple(of: 2) ? 0.5 : -0.5 }
        let loudest = peak(spectrogram)
        #expect(loudest.band == spectrogram.bandCount - 1, "Nyquist appeared in band \(loudest.band)")
        #expect(spectrogram.value(column: 0, band: 0) == Spectrogram.floorDecibels, "and not in the bass")
    }

    /// The failure the unpacking exists to prevent: both ends present at once must read as two separate
    /// bands, not as one summed value in the bass.
    @Test("direct current and Nyquist together stay apart")
    func bothEndsStayApart() throws {
        let spectrogram = try model(frames: 44_100) { _, frame in
            0.5 + (frame.isMultiple(of: 2) ? 0.5 : -0.5)
        }
        let lowest = try #require(spectrogram.value(column: 0, band: 0))
        let highest = try #require(spectrogram.value(column: 0, band: spectrogram.bandCount - 1))

        #expect(abs(lowest - -6.02) < 0.05, "the lowest band read \(lowest)")
        #expect(abs(highest - -6.02) < 0.05, "the highest band read \(highest)")
    }
}

@Suite("Analysis — spectrogram reduction and channels")
struct SpectrogramAccumulatorReductionTests {
    /// The deciding measurement of the spike: a 20 ms transient in a long silence survives the maximum
    /// and is buried by the mean. Here the transient must remain clearly visible, which only a maximum
    /// reduction achieves once several frames fold into one column.
    @Test("a short transient survives the reduction instead of being averaged away")
    func maximumPreservesATransient() throws {
        let frames = 44_100 * 4 // four seconds, so many frames fold into each column
        let burstStart = frames / 2
        let burstLength = 44_100 / 50 // 20 ms
        let frequency = binFrequency(700)

        let spectrogram = try model(frames: frames) { _, frame in
            guard frame >= burstStart, frame < burstStart + burstLength else { return 0 }
            return sine(frequency, 0.5, frame)
        }

        let loudest = peak(spectrogram)
        // A mean over the frames folded into that column would drop this by roughly 9 dB (measured:
        // 8.74). Requiring it within 3 dB of the true level rules the mean out without asserting a
        // number this test did not measure.
        #expect(loudest.value > -9, "the transient read \(loudest.value) dBFS; a mean would bury it")
    }

    /// Reduction by maximum in the frequency axis too: a single loud bin must not be diluted by the
    /// quiet bins folded into the same band.
    @Test("a lone loud bin is not diluted by its band's quiet neighbours")
    func maximumInTheFrequencyAxis() throws {
        let frequency = binFrequency(1_000)
        let spectrogram = try model(frames: 44_100, sample: tone(frequency, amplitude: 0.5))
        // Two bins fold into each band. A mean would halve the amplitude — 6 dB down.
        #expect(abs(peak(spectrogram).value - -6.02) < 0.05)
    }

    /// The negative control from the spike, as a property of the result. Two channels carrying
    /// *different* tones at 0.5 must both read −6.02 dBFS, and nothing may appear at a frequency
    /// present in neither. Combining samples in the time domain invented 247 spurious bands.
    @Test("channels are combined in the frequency domain, inventing nothing")
    func channelsCombineWithoutInventingEnergy() throws {
        let low = binFrequency(200)
        let high = binFrequency(800)
        let spectrogram = try model(frames: 44_100, channels: 2) { channel, frame in
            let frequency = channel == 0 ? low : high
            return sine(frequency, 0.5, frame)
        }

        let lowBand: Int = 200 * spectrogram.bandCount / SpectrogramAccumulator.binCount
        let highBand: Int = 800 * spectrogram.bandCount / SpectrogramAccumulator.binCount

        #expect(abs(try #require(spectrogram.value(column: 0, band: lowBand)) - -6.02) < 0.2)
        #expect(abs(try #require(spectrogram.value(column: 0, band: highBand)) - -6.02) < 0.2)

        // Nothing loud anywhere else: exactly two bands carry the tones, the rest stay far below.
        let loudBands = (0 ..< spectrogram.bandCount).filter {
            (spectrogram.value(column: 0, band: $0) ?? -120) > -40
        }
        #expect(loudBands.count <= 4, "energy appeared in \(loudBands.count) bands; two tones were fed")
    }

    /// Opposite polarity cannot cancel, because the channels are never summed as samples.
    @Test("channels in opposing polarity do not cancel")
    func oppositePolarityDoesNotCancel() throws {
        let frequency = binFrequency(1_000)
        let spectrogram = try model(frames: 44_100, channels: 2) { channel, frame in
            let sign: Float = channel == 0 ? 1 : -1
            return sign * sine(frequency, 0.5, frame)
        }
        #expect(abs(peak(spectrogram).value - -6.02) < 0.05, "the channels cancelled to \(peak(spectrogram).value)")
    }

    @Test("a tone present in one channel alone survives")
    func aToneInOneChannelSurvives() throws {
        let frequency = binFrequency(1_000)
        let spectrogram = try model(frames: 44_100, channels: 2) { channel, frame in
            channel == 0 ? sine(frequency, 0.5, frame) : 0
        }
        #expect(abs(peak(spectrogram).value - -6.02) < 0.05)
    }

    /// Left-only and right-only must be indistinguishable: the model says what energy is present, not
    /// which channel carried it.
    @Test("left-only and right-only produce the same model")
    func channelOrderDoesNotMatter() throws {
        let frequency = binFrequency(1_000)
        let left = try model(frames: 20_000, channels: 2) { channel, frame in
            channel == 0 ? sine(frequency, 0.5, frame) : 0
        }
        let right = try model(frames: 20_000, channels: 2) { channel, frame in
            channel == 1 ? sine(frequency, 0.5, frame) : 0
        }
        #expect(left == right)
    }
}

@Suite("Analysis — spectrogram windowing and chunking")
struct SpectrogramAccumulatorWindowingTests {
    /// The property that makes the seam trustworthy: the model is a function of the file, never of how
    /// the caller happened to read it. Down to one frame per call.
    @Test(
        "the model is identical at every chunk size",
        arguments: [1, 3, 127, 512, 2_048, 4_096, 65_536]
    )
    func chunkSizeDoesNotChangeTheModel(chunkFrames: Int) throws {
        let frequency = binFrequency(1_000)
        // A prime frame count, so the final window is incomplete at every chunk size.
        let frames = 44_101
        let whole = try model(frames: frames, chunkFrames: 200_000, sample: tone(frequency, amplitude: 0.6))
        let chunked = try model(frames: frames, chunkFrames: chunkFrames, sample: tone(frequency, amplitude: 0.6))

        #expect(chunked == whole, "chunk size \(chunkFrames) changed the model")
    }

    @Test("the same input twice produces the same model")
    func theTransformIsDeterministic() throws {
        let frequency = binFrequency(1_000)
        let once = try model(frames: 30_000, channels: 2, sample: tone(frequency, amplitude: 0.4))
        let twice = try model(frames: 30_000, channels: 2, sample: tone(frequency, amplitude: 0.4))
        #expect(once == twice)
    }

    /// The final incomplete window is discarded, never padded. The column count is therefore a function
    /// of how many **complete** windows the file yields, and adding frames that do not complete another
    /// window adds no column.
    @Test("the final incomplete window is discarded rather than padded")
    func theFinalPartialWindowIsDiscarded() throws {
        let exact = 2_048 + 512 * 9 // ten complete windows, nothing left over
        let plusABit = exact + 511 // not enough for another window

        let a = try model(frames: exact) { _, _ in 0.25 }
        let b = try model(frames: plusABit) { _, _ in 0.25 }

        #expect(a.columnCount == 10)
        #expect(b.columnCount == 10, "a partial window created a column")
        #expect(b.frameCount == plusABit, "the file's real length is still reported")
    }

    /// A file shorter than one window yields no complete window, so no column — and no invented one.
    /// It still reports the frames it has.
    @Test("a file shorter than one window yields no columns and no invented data", arguments: [1, 512, 2_047])
    func aFileShorterThanOneWindowHasNoColumns(frames: Int) throws {
        let spectrogram = try model(frames: frames) { _, _ in 0.5 }
        #expect(spectrogram.columnCount == 0)
        #expect(spectrogram.values.isEmpty)
        #expect(spectrogram.frameCount == frames)
    }

    @Test("exactly one window is exactly one column")
    func oneWindowIsOneColumn() throws {
        let spectrogram = try model(frames: 2_048) { _, _ in 0.25 }
        #expect(spectrogram.columnCount == 1)
        #expect(spectrogram.bandCount == 512)
    }

    /// The caps hold whatever the file's length: a long file folds into 1024 columns, never more.
    @Test("the model never exceeds 1024 columns by 512 bands")
    func theModelStaysBounded() throws {
        let spectrogram = try model(frames: 44_100 * 30, chunkFrames: 8_192) { _, _ in 0.1 }
        #expect(spectrogram.columnCount == 1_024)
        #expect(spectrogram.bandCount == 512)
        #expect(spectrogram.values.count == 1_024 * 512)
    }

    /// A file with no audio: a valid, empty model rather than an absence or a fabricated column.
    @Test("a file with no frames yields an empty model")
    func zeroFramesYieldsAnEmptyModel() throws {
        var accumulator = try #require(
            SpectrogramAccumulator(sampleRate: 44_100, channelCount: 2, frameCount: 0)
        )
        let spectrogram = try #require(accumulator.finish())
        #expect(spectrogram.columnCount == 0)
        #expect(spectrogram.frameCount == 0)
        #expect(spectrogram.channelCount == 2)
    }

    @Test("an impossible stream is refused", arguments: [(0.0, 1, 100), (44_100.0, 0, 100), (44_100.0, 1, -1)])
    func refusesImpossibleStreams(sampleRate: Double, channels: Int, frames: Int) {
        #expect(SpectrogramAccumulator(sampleRate: sampleRate, channelCount: channels, frameCount: frames) == nil)
    }

    /// A chunk whose channel count disagrees with the stream is ignored rather than folded into the
    /// wrong channel — which would silently attribute one channel's energy to another.
    @Test("a chunk with the wrong channel count is not folded in")
    func aMismatchedChunkIsIgnored() throws {
        var accumulator = try #require(
            SpectrogramAccumulator(sampleRate: 44_100, channelCount: 2, frameCount: 4_096)
        )
        let wrong = try PCMChunk(startFrame: 0, channels: [[Float](repeating: 0.5, count: 4_096)])
        accumulator.accumulate(wrong)
        let spectrogram = try #require(accumulator.finish())
        #expect(spectrogram.values.allSatisfy { $0 == Spectrogram.floorDecibels })
    }

    /// The frequency axis is linear to the file's own Nyquist at every sample rate, and a tone lands in
    /// the band whose stated frequency matches it.
    @Test("a tone lands in the band the model says holds its frequency", arguments: [44_100.0, 48_000, 96_000])
    func aToneLandsAtItsStatedFrequency(sampleRate: Double) throws {
        let frequency = binFrequency(300, sampleRate: sampleRate)
        let spectrogram = try model(
            frames: Int(sampleRate), sampleRate: sampleRate, sample: tone(frequency, amplitude: 0.5, sampleRate: sampleRate)
        )
        let band = peak(spectrogram).band
        let stated = try #require(spectrogram.frequency(ofBand: band))
        let bandWidth = spectrogram.nyquist / Double(spectrogram.bandCount)

        #expect(abs(stated - frequency) <= bandWidth, "band \(band) states \(stated) Hz for a \(frequency) Hz tone")
    }

    /// A brick-wall cutoff is visible as a step, which is the whole point of the slice.
    @Test("a band-limited signal shows where its energy stops")
    func aCutoffIsVisible() throws {
        // Two tones well below 8 kHz, nothing above.
        let low = binFrequency(200)
        let mid = binFrequency(350)
        let spectrogram = try model(frames: 44_100) { _, frame in
            sine(low, 0.3, frame) + sine(mid, 0.3, frame)
        }

        let topBand = spectrogram.bandCount - 1
        let quietTop = try #require(spectrogram.value(column: 0, band: topBand))
        #expect(quietTop < -80, "the empty upper range read \(quietTop) dBFS")
        #expect(peak(spectrogram).value > -20, "the content below the cutoff survived")
    }
}
