import AVFoundation
import Foundation
import Testing

import AudioInspectorDomain
@testable import AudioInspectorApp

// Two matrices over the **production path**: sample rate, and container.
//
// Task 6.4 is already closed by "Analysis — integrated loudness across sample rates", which proves
// rate-invariance and the derivation's round-trip on the accumulator. This suite does not repeat that
// evidence — it confirms the *whole path* preserves it, which is a different claim: between the
// accumulator and the number a user sees sit a file format, a decoder, and a chunk size nobody chose
// for loudness. A rate-dependent bug in any of those would leave the accumulator suite green.

@Suite("Analysis — loudness across rates through the production path")
struct LoudnessProductionRateMatrixTests {

    static let rates = [44_100.0, 48_000.0, 88_200.0, 96_000.0, 192_000.0]

    /// **The identity must follow the rate, and it is production that has to get this right.** 48 kHz is
    /// the one rate whose coefficients are published and transcribed; everything else runs coefficients
    /// this project derived. Nothing infers the identity from the rate downstream — the accumulator
    /// records what it ran, and the measurement carries it out through the composition unchanged.
    @Test("the weighting identity that reaches the outcome is the one the rate calls for", arguments: rates)
    func theIdentityFollowsTheRateThroughTheWholePath(_ rate: Double) async throws {
        try await withTemporaryDirectory { directory in
            let run = try await LoudnessProductionHarness.run(.calibration, at: rate, in: directory)
            let method = try #require(run.measurement).method

            #expect(method.algorithm == .integratedBS1770v1, "the algorithm changed with the rate")
            #expect(
                method.weighting == (rate == 48_000 ? .publishedAt48kHz : .derivedFrom48kHz),
                "\(Int(rate)) Hz reported \(method.weighting.rawValue)"
            )
        }
    }

    /// Tech 3341's calibration signal, resynthesised at each rate and written as a real file. **The
    /// published expectation does not change with the rate**, because the signal the document describes
    /// is the same signal — so each run is measured against −18.0 ±0.1 exactly as at 48 kHz.
    ///
    /// A resynthesis is labelled `derived` in the catalogue and is not itself compliance evidence; what
    /// it demonstrates is that the derivation carries the published result across rates rather than only
    /// reproducing a response curve.
    @Test("the published calibration reading survives the whole path at every supported rate", arguments: rates)
    func theCalibrationReadingSurvivesEveryRate(_ rate: Double) async throws {
        let expected = try #require(LoudnessTestVector.calibration.expectedLUFS)
        let tolerance = try #require(LoudnessTestVector.calibration.expectedTolerance)

        try await withTemporaryDirectory { directory in
            let measured = try #require(
                try await LoudnessProductionHarness.run(.calibration, at: rate, in: directory).integratedLoudness
            )
            #expect(
                abs(measured - expected) <= tolerance,
                "\(Int(rate)) Hz: production \(measured), published \(expected) ±\(tolerance)"
            )
        }
    }

    /// **Rate-invariance of the product**, not of the accumulator: the same described signal, written and
    /// decoded at five rates, must read the same.
    ///
    /// The bound is **0.03 LU**, and it is not new. It is FFmpeg's own drift across these same rates,
    /// recorded in the spike (§B5) and already used as the reasoning behind `KWeightingResponseTests`'s
    /// 0.02 dB: a bound tighter than the reference implementation's own agreement with itself would be
    /// claiming more than anyone can demonstrate. What production actually achieves is far inside it.
    @Test("the same signal reads the same at every rate, through the whole path")
    func theReadingIsRateInvariantThroughTheWholePath() async throws {
        try await withTemporaryDirectory { directory in
            var readings: [(rate: Double, value: Double)] = []
            for rate in Self.rates {
                let value = try #require(
                    try await LoudnessProductionHarness.run(.table1Test1, at: rate, in: directory).integratedLoudness
                )
                readings.append((rate, value))
            }
            let values = readings.map(\.value)
            let highest = try #require(values.max())
            let lowest = try #require(values.min())
            let spread = highest - lowest
            #expect(spread <= 0.03, "spread \(spread) across \(readings)")
        }
    }

    /// The same, at the two ends of the weighting's own response. A rate-dependent derivation error
    /// would most likely appear where the filter is doing the most work — the roll-off and the shelf —
    /// and a 1 kHz signal alone could not see it.
    @Test(
        "a low and a high tone are rate-invariant too, where the filter does the most work",
        arguments: [40.0, 12_000.0]
    )
    func theReadingIsRateInvariantAtTheEndsOfTheResponse(_ frequency: Double) async throws {
        try await withTemporaryDirectory { directory in
            var values: [Double] = []
            for rate in Self.rates {
                let spec = AudioFixtureSpec(
                    name: "rate-\(Int(rate))-tone-\(Int(frequency))",
                    format: .wavFloat,
                    signal: .sine(frequency: frequency, amplitude: 0.1),
                    sampleRate: rate,
                    channels: 2,
                    frames: AVAudioFrameCount(rate * 5)
                )
                let run = try await LoudnessProductionHarness.run(
                    fileAt: try writeFloatPCMFixture(spec, in: directory)
                )
                values.append(try #require(run.integratedLoudness))
            }
            let highest = try #require(values.max())
            let lowest = try #require(values.min())
            let spread = highest - lowest
            #expect(spread <= 0.03, "\(Int(frequency)) Hz: spread \(spread) across \(values)")
        }
    }
}

// MARK: - Containers

@Suite("Analysis — loudness across containers through the production path")
struct LoudnessProductionContainerMatrixTests {

    /// The signal every container carries: 997 Hz at −23 dBFS, stereo, 48 kHz, 20 s. A steady tone
    /// because the question is what the *container and codec* do to the reading, and a complex programme
    /// would confound that with the gate's own behaviour.
    private static func spec(_ format: AudioFixtureFormat) -> AudioFixtureSpec {
        AudioFixtureSpec(
            name: "container-\(format)",
            format: format,
            signal: .sine(frequency: 997, amplitude: Float(pow(10.0, -23.0 / 20.0))),
            sampleRate: 48_000,
            channels: 2,
            frames: 960_000
        )
    }

    private func measure(_ format: AudioFixtureFormat, in directory: URL) async throws -> Double {
        let url = try writeAudioFixture(Self.spec(format), in: directory)
        let run = try await LoudnessProductionHarness.run(fileAt: url)
        return try #require(run.integratedLoudness, "\(format): no measurement")
    }

    /// Every container the fixture writer can produce yields a measurement at all — the first thing a
    /// container-specific decode fault would break.
    ///
    /// MP3 is absent because CoreAudio provides no encoder for it (`AudioFixtureFormat`'s own note), so
    /// it cannot be produced natively. That gap belongs to the fixture writer, not to this measurement.
    @Test("every writable container produces a measurement", arguments: AudioFixtureFormat.allCases)
    func everyContainerMeasures(_ format: AudioFixtureFormat) async throws {
        try await withTemporaryDirectory { directory in
            let measured = try await measure(format, in: directory)
            #expect(measured.isFinite)
            #expect(abs(measured - (-23.0)) <= LoudnessTestVector.publishedTolerance, "\(format): \(measured)")
        }
    }

    /// **The lossless containers must agree with each other, and the bound is stated from measurement.**
    ///
    /// WAV, AIFF and ALAC store 16-bit integers; float WAV and FLAC carry more. The two groups therefore
    /// differ by quantisation noise and nothing else, and the observed spread across all five is
    /// **1.4 × 10⁻⁵ LU**. The bound asserted is **0.001 LU** — roughly seventy times the observed value,
    /// so it is not fitted to today's measurement, and four orders of magnitude under the published
    /// ±0.1, so a failure here could never be a compliance question. It would mean a decode path had
    /// started changing samples.
    @Test("every lossless container reads the same, to quantisation noise")
    func losslessContainersAgree() async throws {
        let lossless: [AudioFixtureFormat] = [.wav, .wavFloat, .aiff, .alac, .flac]
        try await withTemporaryDirectory { directory in
            var readings: [(AudioFixtureFormat, Double)] = []
            for format in lossless {
                readings.append((format, try await measure(format, in: directory)))
            }
            let values = readings.map(\.1)
            let highest = try #require(values.max())
            let lowest = try #require(values.min())
            let spread = highest - lowest
            #expect(spread <= 0.001, "spread \(spread) across \(readings)")
        }
    }

    /// **AAC separately, because a lossy codec is a different question**, and the tolerance was set after
    /// measuring rather than before.
    ///
    /// The encoder does not reproduce the samples, so some movement is expected and is a property of the
    /// *codec*, not an error of the meter. Measured: **6.7 × 10⁻⁴ LU** from the float reference — about
    /// fifty times the whole lossless spread, which is what separates the two effects, and still more
    /// than a hundred times inside the published ±0.1.
    ///
    /// The bound is **0.01 LU**: fifteen times the observed value, so a real codec regression or an
    /// encoder change would have room to appear without this failing on noise. It is deliberately not
    /// the lossless bound — claiming a lossy round-trip is bit-transparent would be false — and
    /// deliberately not ±0.1, which would be too loose to notice anything.
    @Test("AAC moves the reading only by the codec's own error, not the meter's")
    func aacMovesOnlyByTheCodecsOwnError() async throws {
        try await withTemporaryDirectory { directory in
            let reference = try await measure(.wavFloat, in: directory)
            let lossy = try await measure(.aac, in: directory)
            let delta = abs(lossy - reference)

            #expect(delta <= 0.01, "AAC \(lossy), float reference \(reference), delta \(delta)")
            // And the separation itself: whatever AAC moved, it is a codec effect rather than the
            // meter drifting, because the lossless containers agree with the reference far more closely.
            let alac = try await measure(.alac, in: directory)
            #expect(
                abs(alac - reference) < delta,
                "a lossless container disagreed with the reference by more than the lossy one did"
            )
        }
    }
}
