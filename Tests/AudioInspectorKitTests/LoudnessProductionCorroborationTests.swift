import AVFoundation
import Foundation
import Testing

import AudioInspectorDomain
@testable import AudioInspectorApp

// Task 6.5 — corroboration, and **explicitly ranked below** the published vectors.
//
// Everything here is compared against a table in
// `docs/spikes/2026-08-18-loudness-measurement-validation.md` §B4 and §B6, which was **measured from
// FFmpeg** during the spike rather than published by anyone. The spike itself demotes it: "This table
// remains useful but is demoted. It is now a *corroborating* target measured from an implementation;
// the *primary* acceptance targets are A9's published values."
//
// So a failure here is not a compliance failure — it is a signal that the filter's *shape* moved, which
// the published vectors alone would not localise: tests 1, 2 and §2.9 are all 1 kHz, so a weighting
// error at 40 Hz or 12 kHz passes every one of them. That is what this suite is for, and it is why it
// exists despite being weaker evidence.
//
// **The subject is production**: real files through `AVFoundationAudioDecoder` and
// `SharedPCMAnalysisGeneration`, not the filter's coefficients. `KWeightingResponseTests` already proves
// the coefficients reproduce the published response to 0.0077 dB; this proves the *measurement* built on
// them has the shape the spike observed end to end.

@Suite("Analysis — loudness corroboration through the production path")
struct LoudnessProductionCorroborationTests {

    /// The spike's own §B4 table, transcribed: frequency, the **absolute** reading it printed, and the
    /// reading **relative to 1 kHz** it derived from that column.
    private static let spikeResponse: [(frequency: Double, absoluteLUFS: Double, relativeDB: Double)] = [
        (40, -26.3, -6.3), (100, -21.8, -1.8), (200, -21.0, -1.0), (400, -20.7, -0.7),
        (1_000, -20.0, 0.0),
        (2_000, -17.6, 2.4), (4_000, -16.7, 3.3), (8_000, -16.7, 3.3),
        (12_000, -16.6, 3.4), (16_000, -16.6, 3.4),
    ]

    /// **±0.05 dB against the absolute column, and it is not a new tolerance.** The spike prints one
    /// decimal place, so half of its last digit is the whole width a value can differ by while still
    /// being the same printed number.
    ///
    /// Nothing here is loosened: the published compliance tolerance (±0.1 LUFS) and the response-matching
    /// tolerance (0.02 dB, `KWeightingResponseTests`) are untouched and describe different magnitudes.
    private static let spikeRounding = 0.05

    /// **±0.1 dB against the relative column**, because that column is a *difference of two values the
    /// spike had already rounded*: each carries ±0.05, so their difference carries twice that. It is
    /// arithmetic about the table's precision, not a wider tolerance — and it is why the absolute
    /// comparison below is asserted too, at half this width, rather than being replaced by this one.
    private static let spikeRelativeRounding = 0.1

    /// The spike's stereo, amplitude-0.1 signal at 48 kHz, 5 s — long enough to settle far past the
    /// gating block, short enough that ten of them stay cheap.
    private func measure(frequency: Double, in directory: URL) async throws -> Double {
        let spec = AudioFixtureSpec(
            name: "k-curve-\(Int(frequency))",
            format: .wavFloat,
            signal: .sine(frequency: frequency, amplitude: 0.1),
            sampleRate: 48_000,
            channels: 2,
            frames: 240_000
        )
        let run = try await LoudnessProductionHarness.run(
            fileAt: try writeFloatPCMFixture(spec, in: directory)
        )
        return try #require(run.integratedLoudness, "no measurement at \(frequency) Hz")
    }

    /// The measured curve against the spike's own table, at every frequency it lists — **both columns**.
    ///
    /// The absolute reading is the tighter claim and the one the spike actually measured; the relative
    /// one is what the table is *evidence about*, since a shape is a set of differences and an absolute
    /// comparison folds in the conversion offset the BS.1770-5 anchor already pins far more sharply.
    /// Asserting both means the looser bound is never the only thing standing.
    @Test("the production measurement reproduces the K-weighting curve the spike observed")
    func theMeasuredResponseMatchesTheSpikeTable() async throws {
        try await withTemporaryDirectory { directory in
            var readings: [Double: Double] = [:]
            for entry in Self.spikeResponse {
                readings[entry.frequency] = try await measure(frequency: entry.frequency, in: directory)
            }
            let reference = try #require(readings[1_000])

            for entry in Self.spikeResponse {
                let absolute = try #require(readings[entry.frequency])
                #expect(
                    abs(absolute - entry.absoluteLUFS) <= Self.spikeRounding,
                    "\(Int(entry.frequency)) Hz: production \(absolute) LUFS, spike \(entry.absoluteLUFS)"
                )
                guard entry.frequency != 1_000 else { continue }
                let relative = absolute - reference
                #expect(
                    abs(relative - entry.relativeDB) <= Self.spikeRelativeRounding,
                    "\(Int(entry.frequency)) Hz: production \(relative) dB relative to 1 kHz, spike \(entry.relativeDB)"
                )
            }
        }
    }

    /// The two ends of the curve, asserted as **shape** rather than as points: a high-pass roll-off at
    /// the bottom and a shelf at the top, with the shelf settled by 4 kHz. This is what would survive a
    /// re-measurement of the table, and it is the property a weighting error actually breaks.
    @Test("the response is a low-frequency roll-off under a settled high-frequency shelf")
    func theResponseHasTheShapeTheTwoFilterStagesPredict() async throws {
        try await withTemporaryDirectory { directory in
            let reference = try await measure(frequency: 1_000, in: directory)
            func relative(_ frequency: Double) async throws -> Double {
                try await measure(frequency: frequency, in: directory) - reference
            }

            let low = try await relative(40)
            let mid = try await relative(400)
            let shelfStart = try await relative(4_000)
            let shelfEnd = try await relative(16_000)

            // Monotonic through the roll-off: 40 Hz is well below 400 Hz, which is below 1 kHz.
            #expect(low < mid, "40 Hz did not sit below 400 Hz")
            #expect(mid < 0, "400 Hz did not sit below 1 kHz")
            // The shelf has settled: 4 kHz and 16 kHz are the same height to a tenth of a decibel.
            #expect(abs(shelfEnd - shelfStart) <= 0.1, "the shelf had not settled by 4 kHz")
            #expect(shelfStart > 3.0, "there is no high-frequency shelf")
        }
    }

    /// §B6's 40 dB gating fixture: 10 s at amplitude 0.5 followed by 10 s at 0.005, stereo, 48 kHz.
    /// The spike's FFmpeg reading was **−6.1 LUFS**.
    ///
    /// A blunter instrument than Tech 3341 tests 3 and 4 — its step is 40 dB rather than 13 — and the
    /// spike says exactly that: "Superseded as an acceptance target by A9 tests #3 and #4 … retained
    /// because its 40 dB step is a blunter, easier-to-debug first signal." Kept here for the same
    /// reason: when the published gating vectors fail, this says in one number whether gating ran at all.
    @Test("the 40 dB gating fixture reads what the spike observed")
    func theGatingFixtureReadsWhatTheSpikeObserved() async throws {
        try await withTemporaryDirectory { directory in
            let spec = AudioFixtureSpec(
                name: "gating-40db",
                format: .wavFloat,
                signal: .segmentedSine(frequency: 1_000, segments: [
                    AudioFixtureSegment(amplitude: 0.5, frames: 480_000),
                    AudioFixtureSegment(amplitude: 0.005, frames: 480_000),
                ]),
                sampleRate: 48_000,
                channels: 2,
                frames: 960_000
            )
            let run = try await LoudnessProductionHarness.run(
                fileAt: try writeFloatPCMFixture(spec, in: directory)
            )
            let measured = try #require(run.integratedLoudness)
            #expect(
                abs(measured - (-6.1)) <= Self.spikeRounding,
                "production \(measured), spike −6.1"
            )

            // And it discriminates: an ungated mean over both halves would sit far lower, because the
            // quiet half is half the file. The gate excluding it is the whole point of the fixture.
            #expect(measured > -7.0, "the quiet half was not excluded")
        }
    }
}
