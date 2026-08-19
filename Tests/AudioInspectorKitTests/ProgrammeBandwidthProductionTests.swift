import AVFoundation
import Foundation
import Testing

import AudioInspectorDomain
import FeatureImport

@testable import AudioInspectorApp

// Group 6 against production: the same fixtures group 2 measured with its oracle, now read by the real
// decoder through the shared pass and asserted on the outcome the composition publishes.
//
// **No expected value is taken from a previous run.** Each is written from the fixture's own
// specification, and every tolerance is expressed in resolutions rather than hertz so it means the same
// thing at all five rates.

// MARK: - Extents and rates

@Suite("App — programme bandwidth extents and rates, through production")
struct ProgrammeBandwidthProductionExtentTests {

    /// Task 6.1. A comb has no component above its top tone, so the edge is a property of the
    /// specification rather than of a filter this package would have to implement and then trust.
    @Test(
        "a known spectral edge reads back within the leakage the window explains, at every rate",
        arguments: [44_100.0, 48_000, 88_200, 96_000, 192_000], [8_000.0, 12_000, 16_000, 20_000]
    )
    func knownEdge(sampleRate: Double, edge: Double) async throws {
        try await withTemporaryDirectory { directory in
            let outcome = try await measureThroughProduction(
                productionSpec("edge-\(Int(sampleRate))-\(Int(edge))", productionProgramme(to: edge),
                               rate: sampleRate, frames: AVAudioFrameCount(sampleRate)),
                in: directory
            )
            try expectProductionEdge(outcome, at: edge, "\(Int(sampleRate)) Hz, edge \(Int(edge)) Hz")
        }
    }

    /// **The error is one-sided upward**, and that is a claim about the method rather than a tolerance.
    /// A bin below a hard edge cannot be lit by content that is not there, so no reading may fall under
    /// its edge — asserted across the whole matrix in one place, because a per-case bound of
    /// `>= −1 resolution` would let a systematic downward bias hide inside it.
    @Test("no reading falls below its edge, at any rate")
    func overshootIsOneSided() async throws {
        try await withTemporaryDirectory { directory in
            for sampleRate in [44_100.0, 48_000, 88_200, 96_000, 192_000] {
                for edge in [8_000.0, 12_000, 16_000, 20_000] {
                    let outcome = try await measureThroughProduction(
                        productionSpec("side-\(Int(sampleRate))-\(Int(edge))", productionProgramme(to: edge),
                                       rate: sampleRate, frames: AVAudioFrameCount(sampleRate)),
                        in: directory
                    )
                    let model = try productionModel(outcome, "\(Int(sampleRate)) Hz, edge \(Int(edge)) Hz")
                    let reading = try #require(model.overall)
                    #expect(
                        reading.frequency >= edge,
                        """
                        \(Int(sampleRate)) Hz read \(reading.frequency) Hz for a \(Int(edge)) Hz edge — \
                        below it, which the one-sided leakage argument does not allow
                        """
                    )
                }
            }
        }
    }

    /// Task 6.4. The same physical evidence at five rates. The raw hertz differ — each rate quantises
    /// the edge onto its own bin grid — so the claim is stated in resolutions, the only unit in which
    /// the rates are comparable.
    @Test("the same edge reads the same at every rate, once expressed in resolutions")
    func rateAgreement() async throws {
        try await withTemporaryDirectory { directory in
            var overshoots: [Double] = []
            for sampleRate in [44_100.0, 48_000, 88_200, 96_000, 192_000] {
                let outcome = try await measureThroughProduction(
                    productionSpec("agree-\(Int(sampleRate))", productionProgramme(to: 16_000),
                                   rate: sampleRate, frames: AVAudioFrameCount(sampleRate)),
                    in: directory
                )
                let model = try productionModel(outcome, "\(Int(sampleRate)) Hz")
                let reading = try #require(model.overall)
                overshoots.append((reading.frequency - 16_000) / reading.resolution)
            }
            let spread = overshoots.max()! - overshoots.min()!
            #expect(
                spread <= 1,
                "the overshoot varies by \(spread) resolutions across rates, which is more than the bin grid explains"
            )
        }
    }

    /// **The window is time-locked, and the identity says which one ran.** The lengths are the ones the
    /// method's own rule selects — the transform length closest in *duration* to 2048 frames at
    /// 48 kHz — and the non-powers of two are what make that reachable: 1920 at 44.1 kHz and 3840 at
    /// 88.2 kHz hold the window to within 2 % of the target where powers of two alone would force 8.8 %.
    ///
    /// A sample-locked implementation would report 2048 at every rate, which this fails on.
    @Test(
        "the published method identity is the time-locked one for the rate",
        arguments: [(44_100.0, 1_920), (48_000.0, 2_048), (88_200.0, 3_840), (96_000.0, 4_096), (192_000.0, 8_192)]
    )
    func methodIdentity(sampleRate: Double, windowFrames: Int) async throws {
        try await withTemporaryDirectory { directory in
            let outcome = try await measureThroughProduction(
                productionSpec("identity-\(Int(sampleRate))", productionProgramme(to: 16_000),
                               rate: sampleRate, frames: AVAudioFrameCount(sampleRate)),
                in: directory
            )
            let model = try productionModel(outcome, "\(Int(sampleRate)) Hz")
            #expect(model.method.identifier == SignificantBandwidthMethod.v1)
            #expect(model.method.sampleRate == sampleRate)
            #expect(model.method.windowFrames == windowFrames, "\(Int(sampleRate)) Hz ran a \(model.method.windowFrames)-frame window")
            #expect(model.method.hopFrames == windowFrames / 4, "the 75 % overlap changed")
            // Time-locked: every rate's window is within 3 % of the 42.67 ms target.
            let target = 2_048.0 / 48_000.0
            #expect(
                abs(model.method.windowSeconds - target) / target <= 0.03,
                "\(Int(sampleRate)) Hz analysed a \(model.method.windowSeconds * 1_000) ms window"
            )
            // The resolution the reading carries is the one the identity implies, not a separate claim.
            let reading = try #require(model.overall)
            #expect(reading.resolution == sampleRate / Double(windowFrames))
        }
    }
}

// MARK: - The three layers

@Suite("App — programme bandwidth's three layers, through production")
struct ProgrammeBandwidthProductionCriterionTests {

    /// Task 6.3, first half: **persistence**. A contiguous block must occupy slightly more than the
    /// nominal fraction because its ramped edges do not reach the threshold, so the cases sit on either
    /// side of the flip rather than on it.
    @Test("a band present for a tenth of the file or more is reported", arguments: [0.10, 0.25, 1.0])
    func persistentBandIsReported(share: Double) async throws {
        try await withTemporaryDirectory { directory in
            try await expectProductionEdge(
                measureThroughProduction(burst(share: share, name: "persist-\(Int(share * 100))"), in: directory),
                at: 20_000, "a band present \(Int(share * 100)) % of the file"
            )
        }
    }

    /// The other side: a band present a twentieth of the time is a transient, and the reading stays at
    /// the programme's own edge.
    @Test("a band present for a twentieth of the file is not reported")
    func rareBandIsNotReported() async throws {
        try await withTemporaryDirectory { directory in
            try await expectProductionEdge(
                measureThroughProduction(burst(share: 0.05, name: "persist-5"), in: directory),
                at: 16_000, "a band present 5 % of the file"
            )
        }
    }

    private func burst(share: Double, name: String) -> AudioFixtureSpec {
        let frames = 48_000
        let on = Int(Double(frames) * share)
        return productionSpec(
            name,
            .sum([
                productionProgramme(to: 16_000),
                .enveloped(
                    productionHighBand(relativeDB: -30),
                    segments: [.init(amplitude: 1, frames: on), .init(amplitude: 0, frames: frames - on)],
                    rampFrames: 256
                ),
            ]),
            frames: AVAudioFrameCount(frames)
        )
    }

    /// Task 6.3, second half: **the programme budget**, and its declared cost. A passage within 60 dB
    /// of the programme's peak takes part; one below it does not, whether it is music or a noise floor.
    /// −60 dB is the boundary and is **inclusive**, and the 0.25 dB stratification is conservative in
    /// that direction by construction — which these three anchors confirm it does not disturb.
    @Test("a quiet passage inside the budget is measured, and one below it is not",
          arguments: [(-50.0, 20_000.0), (-60.0, 20_000.0), (-70.0, 16_000.0)])
    func programmeBudget(down: Double, expected: Double) async throws {
        try await withTemporaryDirectory { directory in
            let half = 24_000
            let gain = Float(pow(10.0, down / 20))
            let signal = AudioFixtureSignal.sum([
                .enveloped(productionProgramme(to: 16_000), segments: [.init(amplitude: 1, frames: half)], rampFrames: 256),
                .enveloped(
                    .sum([
                        productionProgramme(to: 16_000, level: 0.01 * gain),
                        productionHighBand(relativeDB: -30, programmeLevel: 0.01 * gain),
                    ]),
                    segments: [.init(amplitude: 0, frames: half), .init(amplitude: 1, frames: half)],
                    rampFrames: 256
                ),
            ])
            try await expectProductionEdge(
                measureThroughProduction(
                    productionSpec("budget-\(Int(-down))", signal, frames: 48_000), in: directory
                ),
                at: expected, "a passage \(Int(down)) dB below the programme"
            )
        }
    }

    /// Task 6.3, third half — **prominence**, the −50 dB threshold against each window's own peak.
    /// −40 is comfortably inside it and −60 comfortably outside; −50 is the boundary, and a band sitting
    /// exactly on it is reported but not to its full extent, because its topmost components are the ones
    /// closest to the threshold. That partial reading is the honest one and is asserted as such rather
    /// than rounded to either neighbour.
    @Test("a high band is kept while it is within the threshold of its window's peak", arguments: [-40.0, -50.0])
    func prominentBandIsKept(relativeDB: Double) async throws {
        try await withTemporaryDirectory { directory in
            let outcome = try await measureThroughProduction(
                productionSpec("prom-\(Int(-relativeDB))",
                               .sum([productionProgramme(to: 16_000), productionHighBand(relativeDB: relativeDB)]),
                               frames: 48_000),
                in: directory
            )
            let model = try productionModel(outcome, "a band \(Int(relativeDB)) dB down")
            let reading = try #require(model.overall)
            #expect(
                reading.frequency >= 19_000,
                "a band \(Int(relativeDB)) dB down read \(reading.frequency) Hz, below the 19–20 kHz band itself"
            )
            #expect(reading.frequency <= 20_000 + productionOvershootInResolutions * reading.resolution)
        }
    }

    @Test("a high band below the threshold is not reported", arguments: [-60.0, -70.0])
    func quietBandIsNotKept(relativeDB: Double) async throws {
        try await withTemporaryDirectory { directory in
            try await expectProductionEdge(
                measureThroughProduction(
                    productionSpec("prom-out-\(Int(-relativeDB))",
                                   .sum([productionProgramme(to: 16_000), productionHighBand(relativeDB: relativeDB)]),
                                   frames: 48_000),
                    in: directory
                ),
                at: 16_000, "a band \(Int(relativeDB)) dB below its window's peak"
            )
        }
    }
}

// MARK: - The file's edges

@Suite("App — programme bandwidth at the file's edges, through production")
struct ProgrammeBandwidthProductionEdgeTests {

    /// Task 6.5. Each of these is an **absence caused by the file**, published as `.unavailable` and
    /// never as a floor, a zero or a substituted Nyquist.
    @Test("a file with no audio, or shorter than one window, publishes no measurement",
          arguments: [0, 1, 1_000, 2_047])
    func tooLittleAudio(frames: Int) async throws {
        try await withTemporaryDirectory { directory in
            let outcome = try await measureThroughProduction(
                productionSpec("short-\(frames)", productionProgramme(to: 16_000),
                               frames: AVAudioFrameCount(frames)),
                in: directory
            )
            #expect(outcome == .unavailable, "\(frames) frames published \(outcome)")
        }
    }

    @Test("a long digital silence publishes no measurement")
    func longSilence() async throws {
        try await withTemporaryDirectory { directory in
            let outcome = try await measureThroughProduction(
                productionSpec("silence-long", .silence, frames: 240_000), in: directory
            )
            #expect(outcome == .unavailable, "five seconds of digital silence published \(outcome)")
        }
    }

    /// **Exactly one window is enough**, and the partial tail after it changes nothing — the final
    /// incomplete window is discarded rather than zero-padded, because padding invents samples the file
    /// does not contain. Asserted as equality between the two files, so a tail that leaked in would
    /// have to move the reading to pass.
    @Test("one whole window measures, and a partial tail after it is discarded")
    func oneWindowAndItsTail() async throws {
        try await withTemporaryDirectory { directory in
            let exact = try await measureThroughProduction(
                productionSpec("one-window", productionProgramme(to: 16_000), frames: 2_048), in: directory
            )
            let withTail = try await measureThroughProduction(
                productionSpec("one-window-tail", productionProgramme(to: 16_000), frames: 2_048 + 700), in: directory
            )
            try expectProductionEdge(exact, at: 16_000, "exactly one analysis window")
            #expect(withTail == exact, "the partial final window changed the reading")
        }
    }
}

// MARK: - Transport

@Suite("App — programme bandwidth through every lossless container")
struct ProgrammeBandwidthProductionTransportTests {

    /// Lossless containers must agree **exactly**, not within a tolerance: they carry the same samples,
    /// and the measurement is a pure function of the samples. A tolerance here would hide a decoder
    /// difference rather than reveal one.
    @Test("every lossless container publishes the identical measurement",
          arguments: [AudioFixtureFormat.wav, .wavFloat, .aiff, .alac, .flac])
    func losslessContainers(format: AudioFixtureFormat) async throws {
        try await withTemporaryDirectory { directory in
            let signal = AudioFixtureSignal.sum([productionProgramme(to: 16_000), productionHighBand(relativeDB: -30)])
            let reference = try await measureThroughProduction(
                productionSpec("container-reference", signal, format: .wavFloat, frames: 48_000), in: directory
            )
            let candidate = try await measureThroughProduction(
                productionSpec("container-\(format.fileExtension)", signal, format: format, frames: 48_000), in: directory
            )
            try expectProductionEdge(reference, at: 20_000, "float WAV")
            #expect(candidate == reference, "\(format) published a different measurement from float WAV")
        }
    }
}

// MARK: - Channels

@Suite("App — programme bandwidth measures channels apart, through production")
struct ProgrammeBandwidthProductionChannelTests {

    private func measureChannels(
        _ signal: AudioFixtureSignal, name: String, channels: AVAudioChannelCount, in directory: URL
    ) async throws -> SignificantBandwidth {
        let outcome = try await measureThroughProduction(
            productionSpec(name, signal, channels: channels, frames: 48_000), in: directory
        )
        return try productionModel(outcome, Comment(rawValue: name))
    }

    @Test("mono publishes one reading and an overall equal to it")
    func mono() async throws {
        try await withTemporaryDirectory { directory in
            let model = try await measureChannels(productionProgramme(to: 16_000), name: "mono", channels: 1, in: directory)
            #expect(model.channels.count == 1)
            #expect(model.overall == model.channels[0])
        }
    }

    @Test("two identical channels read identically")
    func identicalChannels() async throws {
        try await withTemporaryDirectory { directory in
            let model = try await measureChannels(productionProgramme(to: 16_000), name: "identical", channels: 2, in: directory)
            #expect(model.channels.count == 2)
            #expect(model.channels[0] == model.channels[1])
            #expect(model.overall == model.channels[0])
        }
    }

    /// **Channels are indices, and `overall` is the higher of them.** No layout is asserted anywhere:
    /// the pipeline reads channel counts and never labels, so nothing here says "left" or "right".
    @Test("channels with different extents are published separately, and overall is the higher")
    func differentExtents() async throws {
        try await withTemporaryDirectory { directory in
            let model = try await measureChannels(
                .perChannel([productionProgramme(to: 16_000), productionProgramme(to: 20_000)]),
                name: "extents", channels: 2, in: directory
            )
            #expect(model.channels.count == 2)
            let low = try #require(model.channels[0]), high = try #require(model.channels[1])
            #expect(low.frequency < high.frequency, "the two channels published the same extent")
            #expect(model.overall == high, "overall is not the higher of the two channels")
            #expect(abs(low.frequency - 16_000) <= productionOvershootInResolutions * low.resolution)
            #expect(abs(high.frequency - 20_000) <= productionOvershootInResolutions * high.resolution)
        }
    }

    /// The fixture that decided the question: identical content with the sign flipped on odd channels
    /// cancels to a flat line under any reduction that sums. A measurement of where energy stops must
    /// not be able to lose energy the file carries.
    @Test("opposite polarity does not cancel, because the channels are never summed")
    func oppositePolarity() async throws {
        try await withTemporaryDirectory { directory in
            let model = try await measureChannels(
                .oppositePolarity(frequency: 15_000, amplitude: 0.4), name: "polarity", channels: 2, in: directory
            )
            #expect(model.channels.count == 2)
            for (index, channel) in model.channels.enumerated() {
                let reading = try #require(channel, "channel \(index) cancelled away")
                #expect(abs(reading.frequency - 15_000) <= productionOvershootInResolutions * reading.resolution)
            }
        }
    }

    /// A band present in one channel only survives in that channel and in `overall`, which is what
    /// makes `overall` a summary of the per-channel facts rather than a claim about "the programme".
    @Test("a high band in one channel only survives in that channel and in overall")
    func bandInOneChannel() async throws {
        try await withTemporaryDirectory { directory in
            let model = try await measureChannels(
                .perChannel([
                    productionProgramme(to: 16_000),
                    .sum([productionProgramme(to: 16_000), productionHighBand(relativeDB: -30)]),
                ]),
                name: "one-channel-band", channels: 2, in: directory
            )
            let plain = try #require(model.channels[0]), banded = try #require(model.channels[1])
            #expect(abs(plain.frequency - 16_000) <= productionOvershootInResolutions * plain.resolution)
            #expect(abs(banded.frequency - 20_000) <= productionOvershootInResolutions * banded.resolution)
            #expect(model.overall == banded)
        }
    }
}

// MARK: - Numeric extremes, as far as a real file can carry them

/// The two extremes `SignificantBandwidthNumericExtremeTests` pins at the PCM level, carried through a
/// written file and the real decoder — as far as the transport actually carries them.
///
/// **One of the two cannot be reproduced end-to-end, and that is recorded rather than faked.** The
/// denormal amplitudes the underflow case needs do not survive the write-and-decode round trip: the
/// samples come back as zeros, so the file the decoder hands over is silence and the honest answer is
/// an absence. That is a limitation of the fixture path, not of the measurement, and the evidence for
/// the arithmetic stays where it can actually be exercised. Asserting an end-to-end underflow here would
/// be asserting something the transport makes impossible.
@Suite("App — programme bandwidth's numeric extremes through a real file")
struct ProgrammeBandwidthProductionExtremeTests {

    /// A quiet programme that the transport *can* carry is measured honestly, and its answer is the bin
    /// the signal genuinely occupies. 10⁻³⁰ is thirty orders of magnitude down and still normal `Float`.
    @Test("an extremely quiet programme survives the file and is measured, not floored")
    func quietProgrammeThroughAFile() async throws {
        try await withTemporaryDirectory { directory in
            let outcome = try await measureThroughProduction(
                productionSpec("quiet-nyquist", .sine(frequency: 24_000, amplitude: 1e-30), frames: 48_000),
                in: directory
            )
            let model = try productionModel(outcome, "a 10⁻³⁰ programme at Nyquist")
            let reading = try #require(model.overall)
            #expect(reading.frequency == 24_000, "read \(reading.frequency) Hz for a signal at Nyquist")
            #expect(reading.frequency.isFinite && reading.resolution > 0)
        }
    }

    /// **The limitation, evidenced rather than claimed.** The signal level metrics from the same shared
    /// read report what the decoder actually delivered: a peak of zero means the denormal amplitudes
    /// were flushed on the way through, so the absence below is the correct answer to the file that
    /// arrived and says nothing about the arithmetic.
    @Test("a denormal amplitude does not survive the transport, so the end-to-end case is not available")
    func denormalDoesNotSurviveTheTransport() async throws {
        try await withTemporaryDirectory { directory in
            let outcome = try await measureEveryAnalysisThroughProduction(
                productionSpec("denormal-nyquist", .sine(frequency: 24_000, amplitude: 5e-43), frames: 48_000),
                in: directory
            )
            guard case let .available(metrics) = outcome.signalLevelMetrics else {
                Issue.record("the shared read published no signal level metrics: \(outcome.signalLevelMetrics)")
                return
            }
            #expect(
                metrics.overallPeakSample == 0,
                """
                the transport now carries denormals — peak \(String(describing: metrics.overallPeakSample)) — \
                so the end-to-end underflow case has become reachable and should be asserted here
                """
            )
            #expect(
                outcome.significantBandwidth == .unavailable,
                "a file that decoded to silence published \(outcome.significantBandwidth)"
            )
        }
    }

    /// Enormous-but-finite samples through the whole path: whatever the transport makes of them, the
    /// published answer is finite, inside the band, and never a trap.
    @Test("enormous samples publish a finite in-range answer, never a trap",
          arguments: [1e20, 1e30, Double(Float.greatestFiniteMagnitude)])
    func enormousSamplesThroughAFile(amplitude: Double) async throws {
        try await withTemporaryDirectory { directory in
            let outcome = try await measureThroughProduction(
                productionSpec("huge-\(amplitude)", .sine(frequency: 5_000, amplitude: Float(amplitude)),
                               frames: 48_000),
                in: directory
            )
            switch outcome {
            case let .available(model):
                let reading = try #require(model.overall)
                #expect(reading.frequency.isFinite, "published a non-finite frequency")
                #expect(reading.frequency >= 0 && reading.frequency <= 24_000, "published \(reading.frequency) Hz, outside the band")
                #expect(reading.resolution == 48_000.0 / 2_048.0)
            case .unavailable:
                break // an honest absence for material the transform cannot represent
            case let .failed(message):
                Issue.record("an enormous but finite input failed the production path: \(message)")
            case .cancelled:
                Issue.record("an enormous but finite input reported cancellation")
            }
        }
    }
}
