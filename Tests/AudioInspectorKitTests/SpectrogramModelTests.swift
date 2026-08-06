import AudioInspectorDomain
import Testing

// The spectrogram's grid arithmetic and its model, over plain numbers. No transform, no Accelerate, no
// file: the resolution rules are a property of integer arithmetic, and are proved exhaustively here.

@Suite("Domain — spectrogram grid mapping")
struct SpectrogramGridMappingTests {

    // MARK: Shape

    @Test("the production caps are 1024 columns and 512 bands")
    func productionCaps() throws {
        #expect(SpectrogramGridMapping.defaultMaximumColumnCount == 1_024)
        #expect(SpectrogramGridMapping.defaultMaximumBandCount == 512)
        let mapping = try #require(SpectrogramGridMapping(stftFrameCount: 100_000, binCount: 1_024))
        #expect(mapping.columnCount == 1_024)
        #expect(mapping.bandCount == 512)
    }

    /// A file with no audio, or one shorter than a single window, yields no transform frames — and must
    /// therefore yield no columns. Inventing one would draw a moment the file does not have.
    @Test("no transform frames means no columns")
    func zeroFramesMeansZeroColumns() throws {
        let mapping = try #require(SpectrogramGridMapping(stftFrameCount: 0, binCount: 1_024))
        #expect(mapping.columnCount == 0)
        #expect(mapping.bandIndex(forBin: 0) != nil, "the spectrum is still described")
        #expect(mapping.columnIndex(forFrame: 0) == nil)
    }

    @Test("no bins means no bands")
    func zeroBinsMeansZeroBands() throws {
        let mapping = try #require(SpectrogramGridMapping(stftFrameCount: 100, binCount: 0))
        #expect(mapping.bandCount == 0)
        #expect(mapping.bandIndex(forBin: 0) == nil)
    }

    @Test("a single window is a single column")
    func oneFrameOneColumn() throws {
        let mapping = try #require(SpectrogramGridMapping(stftFrameCount: 1, binCount: 1_024))
        #expect(mapping.columnCount == 1)
        #expect(mapping.columnIndex(forFrame: 0) == 0)
        #expect(mapping.columnIndex(forFrame: 1) == nil)
    }

    @Test("a single bin is a single band")
    func oneBinOneBand() throws {
        let mapping = try #require(SpectrogramGridMapping(stftFrameCount: 100, binCount: 1))
        #expect(mapping.bandCount == 1)
        #expect(mapping.bandIndex(forBin: 0) == 0)
    }

    /// Below the cap there is one output per input, so nothing is folded and no column or band is left
    /// describing nothing.
    @Test("fewer inputs than the cap gives one output each", arguments: [1, 2, 7, 511, 1_023])
    func fewerInputsThanCap(count: Int) throws {
        let mapping = try #require(SpectrogramGridMapping(stftFrameCount: count, binCount: count))
        #expect(mapping.columnCount == count)
        #expect(mapping.bandCount == min(count, 512))
    }

    @Test("an impossible description is refused", arguments: [(-1, 1_024), (100, -1), (-5, -5)])
    func refusesImpossibleDescriptions(stftFrameCount: Int, binCount: Int) {
        #expect(SpectrogramGridMapping(stftFrameCount: stftFrameCount, binCount: binCount) == nil)
    }

    @Test("a cap below one is refused", arguments: [(0, 512), (1_024, 0), (-1, 512)])
    func refusesImpossibleCaps(maximumColumnCount: Int, maximumBandCount: Int) {
        #expect(SpectrogramGridMapping(
            stftFrameCount: 100, binCount: 1_024,
            maximumColumnCount: maximumColumnCount, maximumBandCount: maximumBandCount
        ) == nil)
    }

    @Test("a size large enough to overflow the mapping is refused")
    func refusesOverflowingSizes() {
        #expect(SpectrogramGridMapping(stftFrameCount: .max, binCount: 1_024) == nil)
        #expect(SpectrogramGridMapping(stftFrameCount: 100, binCount: .max) == nil)
        #expect(SpectrogramGridMapping(stftFrameCount: Int.max / 1_024, binCount: 1_024) != nil)
    }

    // MARK: Coverage — the property everything else rests on

    /// The map is total and single-valued over the analysis, so no frame is lost and none is counted
    /// twice, including at sizes that do not divide evenly.
    @Test(
        "every frame lands in exactly one column, and every column receives at least one frame",
        arguments: [
            (1, 1_024), (2, 1_024), (7, 4), (10, 4), (100, 7), (1_024, 1_024),
            (2_048, 1_024), (5_164, 1_024), (25_836, 1_024), (44_101, 1_024), (99_991, 1_024),
        ]
    )
    func columnMappingIsTotalAndCovering(stftFrameCount: Int, maximumColumnCount: Int) throws {
        let mapping = try #require(SpectrogramGridMapping(
            stftFrameCount: stftFrameCount, binCount: 1_024, maximumColumnCount: maximumColumnCount
        ))
        #expect(mapping.columnCount == min(stftFrameCount, maximumColumnCount))

        var perColumn = [Int](repeating: 0, count: mapping.columnCount)
        for frame in 0 ..< stftFrameCount {
            let column = try #require(mapping.columnIndex(forFrame: frame))
            #expect(column >= 0 && column < mapping.columnCount)
            perColumn[column] += 1
        }
        #expect(perColumn.reduce(0, +) == stftFrameCount, "every frame counted exactly once")
        #expect(perColumn.allSatisfy { $0 >= 1 }, "no column left empty")
    }

    @Test(
        "every bin lands in exactly one band, and every band receives at least one bin",
        arguments: [(1, 512), (2, 512), (7, 4), (512, 512), (1_024, 512), (1_025, 512), (4_096, 512)]
    )
    func bandMappingIsTotalAndCovering(binCount: Int, maximumBandCount: Int) throws {
        let mapping = try #require(SpectrogramGridMapping(
            stftFrameCount: 100, binCount: binCount, maximumBandCount: maximumBandCount
        ))
        #expect(mapping.bandCount == min(binCount, maximumBandCount))

        var perBand = [Int](repeating: 0, count: mapping.bandCount)
        for bin in 0 ..< binCount {
            let band = try #require(mapping.bandIndex(forBin: bin))
            perBand[band] += 1
        }
        #expect(perBand.reduce(0, +) == binCount)
        #expect(perBand.allSatisfy { $0 >= 1 })
    }

    @Test("the column mapping is monotonic, so time never runs backwards")
    func columnMappingIsMonotonic() throws {
        let mapping = try #require(SpectrogramGridMapping(stftFrameCount: 25_836, binCount: 1_024))
        var previous = 0
        for frame in 0 ..< mapping.stftFrameCount {
            let column = try #require(mapping.columnIndex(forFrame: frame))
            #expect(column >= previous)
            previous = column
        }
        #expect(previous == mapping.columnCount - 1, "the last frame lands in the last column")
        #expect(mapping.columnIndex(forFrame: 0) == 0, "the first frame lands in the first column")
    }

    @Test("the band mapping is monotonic, so frequency never runs backwards")
    func bandMappingIsMonotonic() throws {
        let mapping = try #require(SpectrogramGridMapping(stftFrameCount: 100, binCount: 1_024))
        var previous = 0
        for bin in 0 ..< mapping.binCount {
            let band = try #require(mapping.bandIndex(forBin: bin))
            #expect(band >= previous)
            previous = band
        }
        #expect(previous == mapping.bandCount - 1, "the highest bin lands in the highest band")
        #expect(mapping.bandIndex(forBin: 0) == 0, "the lowest bin lands in the lowest band")
    }

    @Test("indices outside the analysis map to nothing")
    func outOfRangeMapsToNothing() throws {
        let mapping = try #require(SpectrogramGridMapping(stftFrameCount: 10, binCount: 8))
        #expect(mapping.columnIndex(forFrame: -1) == nil)
        #expect(mapping.columnIndex(forFrame: 10) == nil)
        #expect(mapping.columnIndex(forFrame: 9) != nil)
        #expect(mapping.bandIndex(forBin: -1) == nil)
        #expect(mapping.bandIndex(forBin: 8) == nil)
        #expect(mapping.bandIndex(forBin: 7) != nil)
    }
}

@Suite("Domain — spectrogram model")
struct SpectrogramTests {

    private func grid(columns: Int, bands: Int, value: Float = -60) -> [Float] {
        [Float](repeating: value, count: columns * bands)
    }

    @Test("a model keeps its grid and the facts its axes need")
    func keepsItsParts() throws {
        let model = try #require(Spectrogram(
            values: grid(columns: 4, bands: 8), columnCount: 4, bandCount: 8,
            sampleRate: 44_100, frameCount: 44_100, channelCount: 2
        ))
        #expect(model.columnCount == 4)
        #expect(model.bandCount == 8)
        #expect(model.nyquist == 22_050)
        #expect(model.value(column: 0, band: 0) == -60)
        #expect(model.value(column: 3, band: 7) == -60)
    }

    /// A file with no audio. Valid and complete — not an absence, not an error, and with no invented
    /// column sitting at the floor.
    @Test("a file with no audio yields a model with no columns")
    func emptyIsValid() throws {
        let model = try #require(Spectrogram.empty(sampleRate: 44_100, channelCount: 2))
        #expect(model.columnCount == 0)
        #expect(model.bandCount == 0)
        #expect(model.values.isEmpty)
        #expect(model.frameCount == 0)
        #expect(model.value(column: 0, band: 0) == nil)
    }

    @Test("a column for a file with no frames is not representable")
    func columnsRequireFrames() {
        #expect(Spectrogram(
            values: grid(columns: 1, bands: 4), columnCount: 1, bandCount: 4,
            sampleRate: 44_100, frameCount: 0, channelCount: 1
        ) == nil)
    }

    /// The converse is **not** an invariant, and treating it as one left a real file unrepresentable.
    /// A file shorter than one analysis window has frames and yields no complete window, so it has
    /// audio and no columns — the honest answer, and the only alternatives would be to invent a column
    /// or to pad the window.
    @Test(
        "a file shorter than one analysis window has frames and no columns",
        arguments: [1, 512, 2_047]
    )
    func framesWithoutColumnsAreRepresentable(frameCount: Int) throws {
        let model = try #require(Spectrogram(
            values: [], columnCount: 0, bandCount: 0,
            sampleRate: 44_100, frameCount: frameCount, channelCount: 1
        ))
        #expect(model.columnCount == 0)
        #expect(model.frameCount == frameCount, "the file's real length is still stated")
    }

    /// A column exists to say what the spectrum was during a slice of time. One with no band to say it
    /// in describes nothing, and the empty grid it produces would be indistinguishable from the model of
    /// a file with no audio — two answers that must never arrive as the same value.
    @Test("columns with no bands are not representable", arguments: [1, 2, 1_024])
    func refusesColumnsWithoutBands(columnCount: Int) {
        #expect(Spectrogram(
            values: [], columnCount: columnCount, bandCount: 0,
            sampleRate: 44_100, frameCount: 1_000, channelCount: 1
        ) == nil)
    }

    /// The smallest model that says something: one moment, one band. The floor for what the invariant
    /// allows, and it must stay allowed.
    @Test("one column and one band is a valid model")
    func oneColumnOneBandIsValid() throws {
        let model = try #require(Spectrogram(
            values: [-42], columnCount: 1, bandCount: 1,
            sampleRate: 44_100, frameCount: 1_000, channelCount: 1
        ))
        #expect(model.value(column: 0, band: 0) == -42)
        #expect(model.frequency(ofBand: 0) == 11_025)
    }

    /// The empty model is the *only* place a zero band count belongs, and it stays `0 × 0`: no band is
    /// invented to make it well-formed.
    @Test("the empty model has no bands and needs none")
    func emptyModelInventsNoBand() throws {
        let model = try #require(Spectrogram.empty(sampleRate: 44_100, channelCount: 1))
        #expect(model.columnCount == 0)
        #expect(model.bandCount == 0)
        #expect(model.values.isEmpty)
    }

    @Test("the grid must match the dimensions it claims")
    func refusesIncoherentDimensions() {
        #expect(Spectrogram(
            values: grid(columns: 4, bands: 8), columnCount: 4, bandCount: 7,
            sampleRate: 44_100, frameCount: 1_000, channelCount: 1
        ) == nil)
        #expect(Spectrogram(
            values: grid(columns: 3, bands: 8), columnCount: 4, bandCount: 8,
            sampleRate: 44_100, frameCount: 1_000, channelCount: 1
        ) == nil)
    }

    @Test("dimensions beyond the production caps are refused")
    func refusesOversizedGrids() {
        #expect(Spectrogram(
            values: grid(columns: 1_025, bands: 1), columnCount: 1_025, bandCount: 1,
            sampleRate: 44_100, frameCount: 1_000, channelCount: 1
        ) == nil)
        #expect(Spectrogram(
            values: grid(columns: 1, bands: 513), columnCount: 1, bandCount: 513,
            sampleRate: 44_100, frameCount: 1_000, channelCount: 1
        ) == nil)
        #expect(Spectrogram(
            values: grid(columns: 1_024, bands: 512), columnCount: 1_024, bandCount: 512,
            sampleRate: 44_100, frameCount: 1_000, channelCount: 1
        ) != nil, "the caps themselves are allowed")
    }

    @Test("an impossible stream is refused", arguments: [(0.0, 1), (-44_100.0, 1), (44_100.0, 0), (44_100.0, -1)])
    func refusesImpossibleStreams(sampleRate: Double, channelCount: Int) {
        #expect(Spectrogram(
            values: grid(columns: 2, bands: 2), columnCount: 2, bandCount: 2,
            sampleRate: sampleRate, frameCount: 1_000, channelCount: channelCount
        ) == nil)
    }

    @Test("a sample rate that is not a number is refused", arguments: [Double.nan, .infinity, -.infinity])
    func refusesNonFiniteSampleRate(sampleRate: Double) {
        #expect(Spectrogram(
            values: grid(columns: 2, bands: 2), columnCount: 2, bandCount: 2,
            sampleRate: sampleRate, frameCount: 1_000, channelCount: 1
        ) == nil)
    }

    // MARK: The scale — a floor, and deliberately no ceiling

    @Test("a value that is not finite is refused", arguments: [Float.nan, .infinity, -.infinity])
    func refusesNonFiniteValues(value: Float) {
        #expect(Spectrogram(
            values: [value, -60, -60, -60], columnCount: 2, bandCount: 2,
            sampleRate: 44_100, frameCount: 1_000, channelCount: 1
        ) == nil)
    }

    /// The floor is a genuine invariant: everything quieter is represented *as* the floor, so a value
    /// below it means the producer skipped the flooring it is required to apply.
    @Test("a value below the floor is refused", arguments: [Float(-120.1), -150, -1_000])
    func refusesValuesBelowTheFloor(value: Float) {
        #expect(Spectrogram(
            values: [value, -60, -60, -60], columnCount: 2, bandCount: 2,
            sampleRate: 44_100, frameCount: 1_000, channelCount: 1
        ) == nil)
        #expect(Spectrogram.floorDecibels == -120)
    }

    @Test("the floor itself is a valid value")
    func floorIsValid() throws {
        let model = try #require(Spectrogram(
            values: grid(columns: 2, bands: 2, value: Spectrogram.floorDecibels),
            columnCount: 2, bandCount: 2, sampleRate: 44_100, frameCount: 1_000, channelCount: 1
        ))
        #expect(model.value(column: 0, band: 0) == -120)
    }

    /// **There is no ceiling, and that is deliberate.** A file whose samples exceed full scale produces
    /// values above 0 dBFS; the spike measured +3.52 for a sample at 1.5. Limiting them belongs to
    /// drawing, which has edges, not to the data — exactly as `WaveformBucket` keeps samples beyond
    /// `-1...1`. The −120…0 range the interface shows is the legend's, not the model's.
    @Test("values above 0 dBFS are kept, not clamped", arguments: [Float(0.1), 3.52, 12, 60])
    func keepsValuesAboveFullScale(value: Float) throws {
        let model = try #require(Spectrogram(
            values: [value, -60, -60, -60], columnCount: 2, bandCount: 2,
            sampleRate: 44_100, frameCount: 1_000, channelCount: 1
        ))
        #expect(model.value(column: 0, band: 0) == value)
    }

    /// Two files at different levels stay different in the model. Nothing rescales either to its own
    /// peak, which is what makes copies of the same music comparable.
    @Test("nothing is normalised: two models 20 dB apart stay 20 dB apart")
    func noImplicitNormalisation() throws {
        let loud = try #require(Spectrogram(
            values: [-6, -6, -6, -6], columnCount: 2, bandCount: 2,
            sampleRate: 44_100, frameCount: 1_000, channelCount: 1
        ))
        let quiet = try #require(Spectrogram(
            values: [-26, -26, -26, -26], columnCount: 2, bandCount: 2,
            sampleRate: 44_100, frameCount: 1_000, channelCount: 1
        ))
        let difference = try #require(loud.value(column: 0, band: 0))
            - #require(quiet.value(column: 0, band: 0))
        #expect(difference == 20)
        #expect(loud != quiet)
    }

    // MARK: The frequency axis

    /// Linear from zero to the file's own Nyquist, at every sample rate. Nothing crops the top: an empty
    /// upper range in a file that declares a high rate is itself something to see.
    @Test("bands are linear and span the whole of Nyquist", arguments: [44_100.0, 48_000, 96_000, 192_000])
    func bandsAreLinearToNyquist(sampleRate: Double) throws {
        let bands = 512
        let model = try #require(Spectrogram(
            values: grid(columns: 1, bands: bands), columnCount: 1, bandCount: bands,
            sampleRate: sampleRate, frameCount: 1_000, channelCount: 1
        ))
        let first = try #require(model.frequency(ofBand: 0))
        let last = try #require(model.frequency(ofBand: bands - 1))
        let width = model.nyquist / Double(bands)

        #expect(abs(first - width / 2) < 1e-9, "the first band is centred half a band above zero")
        #expect(abs(last - (model.nyquist - width / 2)) < 1e-9, "the last band reaches Nyquist")

        // Equal spacing is what makes the axis linear.
        for band in 1 ..< bands {
            let step = try #require(model.frequency(ofBand: band)) - #require(model.frequency(ofBand: band - 1))
            #expect(abs(step - width) < 1e-9)
        }
    }

    /// The margin the spike measured at the worst sample rate: 18 and 19 kHz sit five bands apart at
    /// 192 kHz, which is what makes a cutoff readable there at all.
    @Test("the bands relevant to a cutoff stay separable, even at 192 kHz")
    func cutoffBandsAreSeparable() throws {
        for sampleRate in [44_100.0, 48_000, 96_000, 192_000] {
            let model = try #require(Spectrogram(
                values: grid(columns: 1, bands: 512), columnCount: 1, bandCount: 512,
                sampleRate: sampleRate, frameCount: 1_000, channelCount: 1
            ))
            let width = model.nyquist / 512
            for (lower, upper) in [(16_000.0, 18_000.0), (18_000.0, 19_000.0), (19_000.0, 20_000.0), (20_000.0, 22_000.0)] {
                let separation = (upper - lower) / width
                #expect(separation >= 2, "\(Int(lower))–\(Int(upper)) Hz at \(Int(sampleRate)) Hz is \(separation) bands apart")
            }
        }
    }

    @Test("a band outside the spectrum has no frequency")
    func outOfRangeBandHasNoFrequency() throws {
        let model = try #require(Spectrogram(
            values: grid(columns: 1, bands: 4), columnCount: 1, bandCount: 4,
            sampleRate: 44_100, frameCount: 1_000, channelCount: 1
        ))
        #expect(model.frequency(ofBand: -1) == nil)
        #expect(model.frequency(ofBand: 4) == nil)
        #expect(model.frequency(ofBand: 3) != nil)
    }

    @Test("models compare by value")
    func comparesByValue() throws {
        let one = try #require(Spectrogram(
            values: [-60, -60], columnCount: 1, bandCount: 2,
            sampleRate: 44_100, frameCount: 1_000, channelCount: 1
        ))
        let same = try #require(Spectrogram(
            values: [-60, -60], columnCount: 1, bandCount: 2,
            sampleRate: 44_100, frameCount: 1_000, channelCount: 1
        ))
        let other = try #require(Spectrogram(
            values: [-60, -60], columnCount: 1, bandCount: 2,
            sampleRate: 44_100, frameCount: 1_000, channelCount: 2
        ))
        #expect(one == same)
        #expect(one != other)
    }
}
