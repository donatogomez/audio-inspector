import AVFoundation
import Foundation
import Testing

// Group 2 of `add-significant-bandwidth-measurement`: the methodology stops being arrays in memory and
// becomes real files, read by the production decoder, in real chunks.
//
// **There is no production accumulator yet, and nothing here asserts against one.** The subject is
// `ProgrammeBandwidthReference`, which implements the method group 1 decided. What these suites
// establish is that the *fact* survives the transport: containers, sample rates, chunk boundaries and
// file edges must not change it. When the accumulator exists, it inherits these fixtures and these
// expected values, and the reference becomes what it is checked against.
//
// Every expected value is written from the fixture's own specification, not from a previous run.

// MARK: - The resolution contract

/// How far above a known edge a reading may sit, in multiples of the analysis resolution.
///
/// Not a tolerance chosen to make fixtures pass. A Hann window's skirt stays above a relative
/// threshold `T` out to `d(T) = (1 / (π · 10^(T/20)))^(1/3)` bins, which is **4.72 bins at −50 dB**
/// (spike §12.2), and the overshoot is one-sided upward because a bin below the edge cannot be lit by
/// content that is not there. Measured across four edges and five sample rates the worst case was
/// **4.55**; five leaves margin for the grid without admitting a sixth bin.
private let maximumOvershootInResolutions = 5.0

/// The bandwidth reading must sit at or above a known edge, and within the leakage reach of it.
private func expectEdge(
    _ reading: ProgrammeBandwidthReading?, at edge: Double,
    _ comment: Comment, sourceLocation: SourceLocation = #_sourceLocation
) throws {
    let reading = try #require(reading, comment, sourceLocation: sourceLocation)
    let error = reading.frequency - edge
    #expect(
        error >= -reading.resolution,
        "\(comment): read \(reading.frequency) Hz, below the \(edge) Hz edge by more than one bin",
        sourceLocation: sourceLocation
    )
    #expect(
        error <= maximumOvershootInResolutions * reading.resolution,
        """
        \(comment): read \(reading.frequency) Hz for a \(edge) Hz edge — \
        \(error / reading.resolution) resolutions above it, past the \(maximumOvershootInResolutions) \
        the Hann skirt explains
        """,
        sourceLocation: sourceLocation
    )
}

// MARK: - Fixture vocabulary

/// A comb up to `edge`, at a per-component amplitude that keeps a 32-component comb well inside full
/// scale. Clipping is broadband, so a fixture that clips measures the clipping and not the comb.
private func programme(to edge: Double, level: Float = 0.01) -> AudioFixtureSignal {
    .tones(highest: edge, spacing: 500, lowest: 500, perComponentAmplitude: level)
}

/// A 19–20 kHz band at a stated level **relative to the programme's per-component amplitude**, which
/// is what a per-bin measurement compares.
private func highBand(relativeDB: Double, programmeLevel: Float = 0.01) -> AudioFixtureSignal {
    .tones(
        highest: 20_000, spacing: 500, lowest: 19_000,
        perComponentAmplitude: programmeLevel * Float(pow(10.0, relativeDB / 20))
    )
}

private func measure(
    _ signal: AudioFixtureSignal, name: String, format: AudioFixtureFormat = .wavFloat,
    sampleRate: Double = 48_000, channels: AVAudioChannelCount = 1, seconds: Double = 1,
    chunkFrames: Int = 4_096, in directory: URL
) async throws -> [ProgrammeBandwidthReading?] {
    let url = try writeAudioFixture(
        AudioFixtureSpec(
            name: name, format: format, signal: signal, sampleRate: sampleRate,
            channels: channels, frames: AVAudioFrameCount(sampleRate * seconds)
        ),
        in: directory
    )
    return try await measureProgrammeBandwidth(of: url, chunkFrames: chunkFrames).readings
}

// MARK: - Analytical extents, across the rate matrix

@Suite("Analysis — programme bandwidth: analytical extents (reference method)")
struct ProgrammeBandwidthExtentTests {

    /// A comb has no component above its top tone, so the edge is a property of the specification
    /// rather than of a filter this package would have to implement and then trust.
    @Test(
        "a known spectral edge reads back within the leakage the window explains, at every rate",
        arguments: [44_100.0, 48_000, 88_200, 96_000, 192_000], [8_000.0, 12_000, 16_000, 20_000]
    )
    func knownEdge(sampleRate: Double, edge: Double) async throws {
        try await withTemporaryDirectory { directory in
            let readings = try await measure(
                programme(to: edge), name: "edge-\(Int(sampleRate))-\(Int(edge))",
                sampleRate: sampleRate, in: directory
            )
            try expectEdge(readings.first ?? nil, at: edge, "\(Int(sampleRate)) Hz, edge \(Int(edge)) Hz")
        }
    }

    /// The same physical evidence at five rates. The raw hertz differ — each rate quantises the edge
    /// onto its own bin grid — so the claim is stated in resolutions, which is the only unit in which
    /// the rates are comparable.
    @Test("the same edge reads the same at every rate, once expressed in resolutions")
    func rateAgreement() async throws {
        try await withTemporaryDirectory { directory in
            var overshoots: [Double] = []
            for sampleRate in [44_100.0, 48_000, 88_200, 96_000, 192_000] {
                let readings = try await measure(
                    programme(to: 16_000), name: "agree-\(Int(sampleRate))",
                    sampleRate: sampleRate, in: directory
                )
                let reading = try #require(readings.first ?? nil)
                overshoots.append((reading.frequency - 16_000) / reading.resolution)
            }
            let spread = overshoots.max()! - overshoots.min()!
            #expect(
                spread <= 1,
                "the overshoot varies by \(spread) resolutions across rates, which is more than the bin grid explains"
            )
        }
    }
}

// MARK: - The three layers, on real files

@Suite("Analysis — programme bandwidth: threshold, persistence and budget (reference method)")
struct ProgrammeBandwidthCriterionTests {

    /// The threshold is a **sensitivity**, not a discriminator: it says how far below the loudest bin
    /// in the same window content still counts. −45 dB is reported in full, −55 dB is not, and −50 dB
    /// is the transition, so the assertions are on the two sides rather than on the boundary itself.
    @Test("a high band is kept while it is within the threshold of the programme", arguments: [-30.0, -40])
    func prominentBandIsKept(relativeDB: Double) async throws {
        try await withTemporaryDirectory { directory in
            let readings = try await measure(
                .sum([programme(to: 16_000), highBand(relativeDB: relativeDB)]),
                name: "prominent-\(Int(-relativeDB))", in: directory
            )
            try expectEdge(readings.first ?? nil, at: 20_000, "a band \(Int(relativeDB)) dB down")
        }
    }

    @Test("a high band below the threshold is not reported", arguments: [-60.0, -70])
    func quietBandIsNotKept(relativeDB: Double) async throws {
        try await withTemporaryDirectory { directory in
            let readings = try await measure(
                .sum([programme(to: 16_000), highBand(relativeDB: relativeDB)]),
                name: "quiet-\(Int(-relativeDB))", in: directory
            )
            try expectEdge(readings.first ?? nil, at: 16_000, "a band \(Int(relativeDB)) dB down")
        }
    }

    /// A contiguous block must occupy slightly more than the nominal fraction, because its ramped
    /// edges do not reach the threshold: measured, the flip sits between 10 % and 12 %. The cases
    /// below are on either side of that, not on it.
    @Test("a band present for a quarter of the file or more is reported", arguments: [0.25, 0.5, 1.0])
    func persistentBandIsKept(share: Double) async throws {
        try await withTemporaryDirectory { directory in
            let frames = 48_000
            let on = Int(Double(frames) * share)
            try await expectEdge(
                measure(
                    .sum([
                        programme(to: 16_000),
                        .enveloped(
                            highBand(relativeDB: -30),
                            segments: [.init(amplitude: 1, frames: on), .init(amplitude: 0, frames: frames - on)],
                            rampFrames: 256
                        ),
                    ]),
                    name: "persist-\(Int(share * 100))", in: directory
                ).first ?? nil,
                at: 20_000, "a band present \(Int(share * 100)) % of the file"
            )
        }
    }

    @Test("a band present for a twentieth of the file is not reported")
    func rareBandIsNotKept() async throws {
        try await withTemporaryDirectory { directory in
            let frames = 48_000, on = frames / 20
            try await expectEdge(
                measure(
                    .sum([
                        programme(to: 16_000),
                        .enveloped(
                            highBand(relativeDB: -30),
                            segments: [.init(amplitude: 1, frames: on), .init(amplitude: 0, frames: frames - on)],
                            rampFrames: 256
                        ),
                    ]),
                    name: "persist-5", in: directory
                ).first ?? nil,
                at: 16_000, "a band present 5 % of the file"
            )
        }
    }

    /// The declared 60 dB budget, and its declared cost. Both halves are the same rule: a passage
    /// within the budget is measured, and one below it is not — whether it is music or a noise floor.
    @Test("a quiet passage inside the budget is measured", arguments: [-40.0, -50, -60])
    func quietPassageInsideBudget(down: Double) async throws {
        try await withTemporaryDirectory { directory in
            try await expectEdge(
                measure(programmeThenQuietPassage(down: down), name: "budget-in-\(Int(-down))", in: directory).first ?? nil,
                at: 20_000, "a passage \(Int(down)) dB below the programme"
            )
        }
    }

    @Test("a passage below the budget is not measured, and the record says so", arguments: [-70.0, -80])
    func quietPassageBelowBudget(down: Double) async throws {
        try await withTemporaryDirectory { directory in
            try await expectEdge(
                measure(programmeThenQuietPassage(down: down), name: "budget-out-\(Int(-down))", in: directory).first ?? nil,
                at: 16_000,
                "a passage \(Int(down)) dB below the programme carries a real band, and the budget excludes it"
            )
        }
    }

    /// Half a second of programme, then half a second of the same programme `down` dB lower carrying a
    /// real 19–20 kHz band 30 dB under its own body.
    private func programmeThenQuietPassage(down: Double) -> AudioFixtureSignal {
        let half = 24_000
        let gain = Float(pow(10.0, down / 20))
        return .sum([
            .enveloped(programme(to: 16_000), segments: [.init(amplitude: 1, frames: half)], rampFrames: 256),
            .enveloped(
                .sum([programme(to: 16_000, level: 0.01 * gain), highBand(relativeDB: -30, programmeLevel: 0.01 * gain)]),
                segments: [.init(amplitude: 0, frames: half), .init(amplitude: 1, frames: half)],
                rampFrames: 256
            ),
        ])
    }
}

// MARK: - Transport

@Suite("Analysis — programme bandwidth: containers and chunking (reference method)")
struct ProgrammeBandwidthTransportTests {

    /// Lossless containers must agree **exactly**, not within a tolerance: they carry the same samples,
    /// and the measurement is a pure function of the samples. A tolerance here would hide a decoder
    /// difference rather than reveal one.
    @Test(
        "every lossless container reads the same bin",
        arguments: [AudioFixtureFormat.wav, .wavFloat, .aiff, .alac, .flac]
    )
    func losslessContainers(format: AudioFixtureFormat) async throws {
        try await withTemporaryDirectory { directory in
            let signal = AudioFixtureSignal.sum([programme(to: 16_000), highBand(relativeDB: -30)])
            let reference = try #require(
                try await measure(signal, name: "container-reference", format: .wavFloat, in: directory).first ?? nil
            )
            let candidate = try #require(
                try await measure(signal, name: "container-\(format.fileExtension)", format: format, in: directory).first ?? nil
            )
            #expect(candidate.bin == reference.bin, "\(format) read bin \(candidate.bin) where float WAV read \(reference.bin)")
            #expect(candidate.resolution == reference.resolution)
        }
    }

    /// The port's own contract: "the result of any correct consumer must not depend on this value".
    /// One frame at a time and the whole file in one call must produce the identical reading, with no
    /// tolerance — the windows are cut from frame zero at a fixed stride, so a chunk boundary has
    /// nowhere to enter the arithmetic.
    @Test(
        "the reading does not depend on the chunk size",
        arguments: [1, 3, 127, 512, 4_096, 65_536, 24_000]
    )
    func chunkIndependence(chunkFrames: Int) async throws {
        try await withTemporaryDirectory { directory in
            let signal = AudioFixtureSignal.sum([programme(to: 16_000), highBand(relativeDB: -30)])
            let url = try writeAudioFixture(
                AudioFixtureSpec(
                    name: "chunks", format: .wavFloat, signal: signal,
                    sampleRate: 48_000, channels: 1, frames: 24_000
                ),
                in: directory
            )
            let whole = try #require(try await measureProgrammeBandwidth(of: url, chunkFrames: 1 << 20).readings.first ?? nil)
            let chunked = try #require(try await measureProgrammeBandwidth(of: url, chunkFrames: chunkFrames).readings.first ?? nil)
            #expect(chunked == whole, "reading at \(chunkFrames)-frame chunks differs from the single-call read")
        }
    }

    /// Two channels carrying different content are measured separately. **This is not a decision about
    /// how the shipped measurement treats channels** — that is task 3.4 and is undecided — only a
    /// demonstration that the reference does not fold them together behind anyone's back.
    @Test("each channel is measured on its own content")
    func channelsAreMeasuredSeparately() async throws {
        try await withTemporaryDirectory { directory in
            let readings = try await measure(
                .perChannelSine(frequencies: [1_000, 15_000], amplitude: 0.2),
                name: "channels", channels: 2, in: directory
            )
            #expect(readings.count == 2)
            try expectEdge(readings[0], at: 1_000, "channel 0 carries a 1 kHz tone")
            try expectEdge(readings[1], at: 15_000, "channel 1 carries a 15 kHz tone")
        }
    }
}

// MARK: - Edges

@Suite("Analysis — programme bandwidth: file edges (reference method)")
struct ProgrammeBandwidthEdgeTests {

    @Test("digital silence carries no eligible window and yields no value")
    func digitalSilence() async throws {
        try await withTemporaryDirectory { directory in
            let readings = try await measure(.silence, name: "silence", in: directory)
            #expect((readings.first ?? nil) == nil, "silence produced a reading")
        }
    }

    /// A *valid* file that holds no audio — not a zero-byte one, which is a different fault and
    /// already covered by the decoder's own suites. The port calls this a complete answer rather than
    /// a missing one, and the measurement has to agree: no frames, no windows, no value.
    @Test("a valid file holding no audio yields no value")
    func fileWithNoFrames() async throws {
        try await withTemporaryDirectory { directory in
            let url = try writeAudioFixture(
                AudioFixtureSpec(
                    name: "no-frames", format: .wav, signal: .silence,
                    sampleRate: 48_000, channels: 1, frames: 0
                ),
                in: directory
            )
            let (readings, description) = try await measureProgrammeBandwidth(of: url)
            #expect(description?.frameCount == 0)
            #expect(readings.first.flatMap { $0 } == nil)
        }
    }

    @Test("a file shorter than one analysis window yields no value", arguments: [1, 1_000, 2_047])
    func shorterThanAWindow(frames: AVAudioFrameCount) async throws {
        try await withTemporaryDirectory { directory in
            let url = try writeAudioFixture(
                AudioFixtureSpec(
                    name: "short-\(frames)", format: .wavFloat,
                    signal: .sine(frequency: 1_000, amplitude: 0.5),
                    sampleRate: 48_000, channels: 1, frames: frames
                ),
                in: directory
            )
            #expect((try await measureProgrammeBandwidth(of: url).readings.first ?? nil) == nil)
        }
    }

    @Test("exactly one window is enough to produce a value")
    func exactlyOneWindow() async throws {
        try await withTemporaryDirectory { directory in
            let url = try writeAudioFixture(
                AudioFixtureSpec(
                    name: "one-window", format: .wavFloat,
                    signal: .sine(frequency: 1_000, amplitude: 0.5),
                    sampleRate: 48_000, channels: 1, frames: 2_048
                ),
                in: directory
            )
            let reading = try #require(try await measureProgrammeBandwidth(of: url).readings.first ?? nil)
            #expect(reading.windowCount == 1)
            try expectEdge(reading, at: 1_000, "a single window holding a 1 kHz tone")
        }
    }

    /// A prime frame count leaves a short final chunk at every chunk size above one, so the partial
    /// window at the end of a file is genuinely exercised rather than assumed away.
    @Test("a short final chunk changes nothing")
    func shortFinalChunk() async throws {
        try await withTemporaryDirectory { directory in
            let url = try writeAudioFixture(
                AudioFixtureSpec(
                    name: "prime", format: .wavFloat,
                    signal: .sum([programme(to: 16_000), highBand(relativeDB: -30)]),
                    sampleRate: 48_000, channels: 1, frames: framesWithShortFinalChunkAtAnyChunkSize
                ),
                in: directory
            )
            let a = try #require(try await measureProgrammeBandwidth(of: url, chunkFrames: 4_096).readings.first ?? nil)
            let b = try #require(try await measureProgrammeBandwidth(of: url, chunkFrames: 997).readings.first ?? nil)
            #expect(a == b)
            try expectEdge(a, at: 20_000, "a prime-length file")
        }
    }

    /// **A limitation, asserted so it cannot be discovered later.** Eligibility removes windows that
    /// carry no energy, which raises the share of the windows that remain. In a file that is silence
    /// plus one impulse, the impulse is not a transient *within* a programme — it **is** the whole
    /// programme, and a click is broadband. Measured, a programme must occupy about a quarter of the
    /// file before an isolated impulse stops setting the answer.
    @Test("an impulse alone in silence is the programme, and reads as broadband")
    func impulseAloneInSilence() async throws {
        try await withTemporaryDirectory { directory in
            let readings = try await measure(
                .impulse(amplitude: 0.9, frameIndex: 24_000), name: "impulse-alone", in: directory
            )
            let reading = try #require(readings.first ?? nil)
            #expect(
                reading.frequency > 20_000,
                "an impulse in silence read \(reading.frequency) Hz; the limitation this pins has changed"
            )
            #expect(reading.eligibleWindowCount < 10, "only the windows the impulse touches carry energy")
        }
    }

    @Test("an impulse inside a programme does not widen the reported band")
    func impulseInsideProgramme() async throws {
        try await withTemporaryDirectory { directory in
            let readings = try await measure(
                .sum([programme(to: 16_000), .impulse(amplitude: 0.9, frameIndex: 24_000)]),
                name: "impulse-in-programme", in: directory
            )
            try expectEdge(readings.first ?? nil, at: 16_000, "one full-scale impulse inside a 16 kHz programme")
        }
    }
}

// MARK: - Roll-off

@Suite("Analysis — programme bandwidth is not a cut-off frequency (reference method)")
struct ProgrammeBandwidthRollOffTests {

    /// The reading is where content stops crossing the threshold, which for a graded roll-off is not
    /// the filter's corner: it is `knee · 2^(|T| / slope)`. At 48 kHz with an 8 kHz knee, anything
    /// gentler than about 43 dB/octave has no edge below Nyquist at all.
    @Test("a graded roll-off reads its threshold crossing, not its knee", arguments: [96.0, 192, 480])
    func rollOffReadsTheCrossing(slope: Double) async throws {
        try await withTemporaryDirectory { directory in
            let knee = 8_000.0
            let predicted = knee * pow(2.0, 50.0 / slope)
            let readings = try await measure(
                .slopedTones(
                    highest: 23_500, spacing: 500, lowest: 500, perComponentAmplitude: 0.01,
                    knee: knee, dBPerOctave: slope
                ),
                name: "rolloff-\(Int(slope))", in: directory
            )
            let reading = try #require(readings.first ?? nil)
            #expect(
                abs(reading.frequency - predicted) <= 600,
                """
                a \(Int(slope)) dB/octave roll-off above \(Int(knee)) Hz read \(reading.frequency) Hz \
                where the -50 dB crossing is \(predicted) Hz
                """
            )
            #expect(reading.frequency > knee + 500, "the reading is not the knee, and must not be mistaken for it")
        }
    }

    @Test("a gentle roll-off has no edge below Nyquist and reads the top of the band")
    func gentleRollOffReachesTheTop() async throws {
        try await withTemporaryDirectory { directory in
            let readings = try await measure(
                .slopedTones(
                    highest: 23_500, spacing: 500, lowest: 500, perComponentAmplitude: 0.01,
                    knee: 8_000, dBPerOctave: 12
                ),
                name: "rolloff-gentle", in: directory
            )
            try expectEdge(readings.first ?? nil, at: 23_500, "a 12 dB/octave roll-off above 8 kHz")
        }
    }
}
