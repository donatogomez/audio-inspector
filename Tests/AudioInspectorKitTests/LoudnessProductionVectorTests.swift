import AVFoundation
import Foundation
import Testing

import AudioInspectorDomain
@testable import AudioInspectorApp
@testable import FeatureAnalysis
import FeatureImport

// The published acceptance targets, measured through the **production path**.
//
// Every expected value comes from `LoudnessTestVector`, transcribed from EBU Tech 3341 and ITU-R
// BS.1770-5 before any of this existed and **not touched since**. Nothing here computes what the answer
// ought to be, and nothing here widens a tolerance: the published ±0.1 is used as published.
//
// **What separates this suite from "Analysis — integrated loudness (48 kHz)"** is the subject, not the
// targets. That suite feeds `PCMChunk`s into `LoudnessAccumulator`; this one writes a real file and runs
// it through `AVFoundationAudioDecoder` and `SharedPCMAnalysisGeneration` — the composition the app
// itself runs. The accumulator meeting its targets in isolation and the *product* meeting them are two
// different claims, and only the second is what a user gets.

@Suite("Analysis — published loudness targets through the production path")
struct LoudnessProductionVectorTests {

    // MARK: - Tech 3341 §2.9 and Table 1 tests 1–5

    /// Each vector against **its own published expected reading and its own published tolerance**, at
    /// the 48 kHz Tech 3341 publishes them at. Both numbers come from the document; neither moves.
    @Test(
        "every published expectation is reproduced through the production path within the published tolerance",
        arguments: LoudnessTestVector.normativeVectors
    )
    func productionReproducesPublishedTargets(_ vector: LoudnessTestVector) async throws {
        let expected = try #require(vector.expectedLUFS)
        let tolerance = try #require(vector.expectedTolerance)
        #expect(tolerance == LoudnessTestVector.publishedTolerance, "the published tolerance was replaced")
        #expect(vector.authority.isNormative, "\(vector.name) is not published evidence")
        #expect(vector.sampleRate == 48_000, "the published vectors are published at 48 kHz")

        try await withTemporaryDirectory { directory in
            let run = try await LoudnessProductionHarness.run(vector, in: directory)
            let measured = try #require(
                run.integratedLoudness,
                "\(vector.name): the production path produced no measurement at all — \(run.loudness)"
            )
            #expect(
                abs(measured - expected) <= tolerance,
                "\(vector.name): production \(measured), published \(expected) ±\(tolerance), delta \(measured - expected)"
            )
            // The methodology the document describes is the one that ran, named by the measurement
            // rather than assumed by this test.
            let method = try #require(run.measurement).method
            #expect(method.algorithm == .integratedBS1770v1)
            #expect(method.weighting == .publishedAt48kHz, "48 kHz must use the transcribed coefficients")
        }
    }

    // MARK: - BS.1770-5's own anchor

    /// 997 Hz, mono, 48 kHz — the frequency Annex 1 names, and the one where the −0.691 offset exactly
    /// cancels the K-weighting gain. It pins the offset more sharply than any 1 kHz signal can, because
    /// 1 kHz sits on a filter slope (Tech 3341 §2.9's own warning).
    ///
    /// The tolerance is the one already decided and recorded: ±0.1 borrowed from BS.2217-2, because
    /// BS.1770-5 states the anchor as a consequence of its algorithm rather than as a compliance test.
    @Test(
        "BS.1770-5's own calibration anchor is reproduced through the production path",
        arguments: [LoudnessTestVector.bs1770Anchor, LoudnessTestVector.bs1770AnchorAttenuated]
    )
    func productionReproducesTheITUAnchor(_ vector: LoudnessTestVector) async throws {
        let expected = try #require(vector.expectedLUFS)
        let tolerance = try #require(vector.expectedTolerance)
        #expect(vector.frequency == 997, "the anchor is stated at 997 Hz, not at the nominal 1 kHz")
        #expect(vector.channels == 1, "the anchor is stated for a single channel")

        try await withTemporaryDirectory { directory in
            let run = try await LoudnessProductionHarness.run(vector, in: directory)
            let measured = try #require(run.integratedLoudness, "\(vector.name): no measurement")
            #expect(
                abs(measured - expected) <= tolerance,
                "\(vector.name): production \(measured), published \(expected) ±\(tolerance), delta \(measured - expected)"
            )
        }
    }

    /// Attenuating the input attenuates the reading identically, which BS.1770-5 states outright. Read
    /// through production, the two anchors must therefore sit **exactly 23 LU apart** — a relationship
    /// far tighter than either vector's own ±0.1, and one no absolute offset error can satisfy by
    /// accident.
    @Test("the two anchors are exactly their own attenuation apart")
    func theAnchorsDifferByTheirStatedAttenuation() async throws {
        try await withTemporaryDirectory { directory in
            let loud = try #require(
                try await LoudnessProductionHarness.run(.bs1770Anchor, in: directory).integratedLoudness
            )
            let quiet = try #require(
                try await LoudnessProductionHarness.run(.bs1770AnchorAttenuated, in: directory).integratedLoudness
            )
            #expect(abs((loud - quiet) - 23.0) <= 0.01, "difference \(loud - quiet), stated 23")
        }
    }

    /// **What the reading alone can show about the absolute gate.** Test 4 is test 3 wrapped in 10 s of
    /// −72 dBFS at each end; if the absolute gate did not run, those passages would enter the relative
    /// threshold and pull the reading with them. Through production the two files must read **identically**
    /// — not merely both within ±0.1 of −23, which each would be even with a gate error of half a unit.
    ///
    /// The sharper intermediate — the derived relative threshold itself — is deliberately **not** observable
    /// here. `LoudnessMeasurement` carries a value and a methodology, and `LoudnessAccumulator.relativeThreshold()`
    /// is internal, reached only through `@testable`. Publishing it so this suite could read it would widen
    /// production for the convenience of a test. That evidence therefore stays where it already is —
    /// `LoudnessAccumulatorTests`, "the absolute gate is visible in the threshold, which the reading alone
    /// does not prove", and the oracle suite's own threshold comparison — and this test asserts the
    /// consequence that *is* visible from outside.
    @Test("tests 3 and 4 read identically through production, which a missing absolute gate would break")
    func theAbsoluteGateMakesTestsThreeAndFourIdentical() async throws {
        try await withTemporaryDirectory { directory in
            let three = try #require(
                try await LoudnessProductionHarness.run(.table1Test3, in: directory).integratedLoudness
            )
            let four = try #require(
                try await LoudnessProductionHarness.run(.table1Test4, in: directory).integratedLoudness
            )
            #expect(abs(three - four) <= 0.0005, "test 3 \(three), test 4 \(four)")
        }
    }

    /// **The file round-trip and the shared read are transparent**, and this is what lets every
    /// accumulator-level result in "Analysis — integrated loudness (48 kHz)" count as evidence about the
    /// product rather than only about a type.
    ///
    /// The same vector measured two ways — written to disk, decoded by AVFoundation and folded through
    /// four other consumers, against fed straight into a fresh accumulator — must agree to floating-point
    /// noise. If it did not, the intermediates that suite pins (the derived threshold, the block set, the
    /// chunk-independence matrix) would describe a path the user never takes.
    @Test(
        "production and the accumulator agree to floating-point noise on the published vectors",
        arguments: LoudnessTestVector.normativeVectors
    )
    func productionAgreesWithTheAccumulatorItRuns(_ vector: LoudnessTestVector) async throws {
        let direct = try #require(try LoudnessAccumulatorHarness.measureLoudness(vector))
        try await withTemporaryDirectory { directory in
            let viaProduction = try #require(
                try await LoudnessProductionHarness.run(vector, in: directory).integratedLoudness
            )
            #expect(
                abs(viaProduction - direct) <= 1e-9,
                "\(vector.name): production \(viaProduction), accumulator \(direct)"
            )
        }
    }

    // MARK: - The undefined cases

    /// 400 ms measures and 399 ms does not, through the real decode. The edge is one frame wide, and
    /// **neither side is −70**: below the boundary the standard defines no value, and the composition
    /// reports an absence rather than the reference implementation's display floor.
    @Test(
        "the measurement boundary sits exactly at one gating block, through the production path",
        arguments: LoudnessTestVector.blockBoundaryVectors
    )
    func productionHonoursTheBlockBoundary(_ vector: LoudnessTestVector) async throws {
        try await withTemporaryDirectory { directory in
            let run = try await LoudnessProductionHarness.run(vector, in: directory)
            switch vector.expectation {
            case let .measured(expected, tolerance):
                let measured = try #require(run.integratedLoudness, "\(vector.name): expected a value")
                #expect(abs(measured - expected) <= tolerance, "\(vector.name): production \(measured)")
            case .notComputable:
                #expect(run.loudness == .unavailable, "\(vector.name): got \(run.loudness)")
                #expect(run.measurement == nil)
            }
        }
    }

    /// Digital silence long enough to form blocks. Every block falls below the absolute gate, so
    /// BS.1770-5 eq. (7) divides by an empty set and there is no value — an **absence**, never a
    /// failure, and never the floor a meter displays.
    @Test(
        "digital silence yields an absence through the production path, never a floor",
        arguments: LoudnessTestVector.silenceVectors
    )
    func productionReportsSilenceAsAnAbsence(_ vector: LoudnessTestVector) async throws {
        try await withTemporaryDirectory { directory in
            let run = try await LoudnessProductionHarness.run(vector, in: directory)
            #expect(run.loudness == .unavailable, "\(vector.name): got \(run.loudness)")
            #expect(run.measurement == nil)
        }
    }

    /// A file that opens and holds no audio at all. Distinct from silence in cause and identical in
    /// consequence: no block, no value, an absence.
    @Test("a file with no audio frames yields an absence through the production path")
    func productionReportsAnEmptyFileAsAnAbsence() async throws {
        try await withTemporaryDirectory { directory in
            let empty = AudioFixtureSpec(
                name: "loudness-zero-frames", format: .wavFloat,
                signal: .silence, sampleRate: 48_000, channels: 2, frames: 0
            )
            let url = try writeFloatPCMFixture(empty, in: directory)
            let run = try await LoudnessProductionHarness.run(fileAt: url)
            #expect(run.loudness == .unavailable)
            #expect(run.measurement == nil)
        }
    }

    /// **The sweep the whole absence rule exists for.** Not one undefined case is allowed to become
    /// −70, −∞ or a zero anywhere in the production outcome — the reference implementation's −70.000 is
    /// a display convention this project does not copy (ADR-0022 §6).
    @Test("no undefined case is turned into a value anywhere on the production path")
    func noUndefinedCaseBecomesAFloor() async throws {
        let undefined = LoudnessTestVector.silenceVectors
            + LoudnessTestVector.blockBoundaryVectors.filter { $0.expectedLUFS == nil }
        try #require(!undefined.isEmpty)

        try await withTemporaryDirectory { directory in
            for vector in undefined {
                let run = try await LoudnessProductionHarness.run(vector, in: directory)
                guard case .unavailable = run.loudness else {
                    Issue.record("\(vector.name): expected an absence, got \(run.loudness)")
                    continue
                }
                // An absence carries no number to be wrong, which is the structural half of the claim.
                #expect(run.measurement == nil, "\(vector.name) carried a measurement")
            }
        }
    }

    // MARK: - An undefined loudness disturbs nothing beside it

    /// Loudness is the only consumer that declines perfectly valid streams, so its absence is the one
    /// most likely to be mistaken for a fault of the read. It is not: the four analyses beside it settle
    /// exactly as their own contracts say, from the same chunks, in the same pass.
    @Test("an absent loudness leaves the other four analyses answering for themselves")
    func anAbsentLoudnessDoesNotDisturbItsSiblings() async throws {
        try await withTemporaryDirectory { directory in
            let silent = try #require(LoudnessTestVector.silenceVectors.first)
            let run = try await LoudnessProductionHarness.run(silent, in: directory)
            #expect(run.loudness == .unavailable)

            // Each of the four produced a complete model of its own from the same read.
            guard case .available = run.outcome.waveform else {
                Issue.record("waveform: \(run.outcome.waveform)"); return
            }
            guard case .available = run.outcome.spectrogram else {
                Issue.record("spectrogram: \(run.outcome.spectrogram)"); return
            }
            guard case let .available(levels) = run.outcome.signalLevelMetrics else {
                Issue.record("signal levels: \(run.outcome.signalLevelMetrics)"); return
            }
            guard case let .available(peak) = run.outcome.truePeak else {
                Issue.record("true peak: \(run.outcome.truePeak)"); return
            }
            // And a silent file is measured by them rather than being absent: a real, computed zero is
            // exactly what the two amplitude measurements are supposed to report here.
            #expect(levels.overallPeakSample == 0)
            #expect(peak.overallTruePeak == 0)
        }
    }

    /// **Frames past the last whole hop are discarded, not folded into a final block.** BS.1770-5 forms
    /// blocks from whole 400 ms windows on a 100 ms grid; an incomplete tail is simply never pushed.
    ///
    /// This test exists because a negative control found the gap: every published vector's duration is a
    /// whole number of seconds at 48 kHz, so every one of them lands exactly on a hop boundary and none
    /// of them can see a trailing-block error at all. Including the partial tail left the entire
    /// production suite green.
    ///
    /// The assertion is production-observable and needs no intermediate: a file of *N* whole hops and the
    /// same file with a few extra frames must read **identically**, because those frames form no complete
    /// sub-block. Padding or folding them in changes the last block's energy and moves the reading.
    @Test(
        "frames past the last whole hop change nothing, through the production path",
        arguments: [1, 137, 2_399, 4_799]
    )
    func aPartialTrailingHopIsDiscardedRatherThanFolded(_ extraFrames: Int) async throws {
        // 5 s at 48 kHz is 50 whole hops of 4 800 frames; 4 799 extra frames is one frame short of a
        // fifty-first, which is the worst case for a tail that is nearly complete.
        let wholeHops = 240_000
        try await withTemporaryDirectory { directory in
            func measure(frames: Int, name: String) async throws -> Double {
                let spec = AudioFixtureSpec(
                    name: name, format: .wavFloat,
                    signal: .sine(frequency: 997, amplitude: 0.25),
                    sampleRate: 48_000, channels: 2, frames: AVAudioFrameCount(frames)
                )
                let run = try await LoudnessProductionHarness.run(
                    fileAt: try writeFloatPCMFixture(spec, in: directory)
                )
                return try #require(run.integratedLoudness, "\(name): no measurement")
            }

            let aligned = try await measure(frames: wholeHops, name: "hop-aligned")
            let withTail = try await measure(frames: wholeHops + extraFrames, name: "hop-tail-\(extraFrames)")
            #expect(
                aligned == withTail,
                "\(extraFrames) extra frames moved the reading: aligned \(aligned), with tail \(withTail)"
            )
        }
    }

    // MARK: - The validated number is the one the product ships

    /// **Closing the loop.** Everything above validates a number against a published document; this
    /// asserts that *that* number is the one the JSON carries — unrounded, in LUFS, with the identity
    /// that actually ran.
    ///
    /// Without it, the compliance evidence and the product could drift apart silently: a rounding slipped
    /// into the mapper would leave every vector test green while the exported document no longer carried
    /// the validated value.
    @Test("the value validated against the published target is the value the JSON exports")
    func theValidatedValueIsTheValueExported() async throws {
        let published = try #require(LoudnessTestVector.table1Test1.expectedLUFS)
        let tolerance = try #require(LoudnessTestVector.table1Test1.expectedTolerance)

        try await withTemporaryDirectory { directory in
            let run = try await LoudnessProductionHarness.run(.table1Test1, in: directory)
            let measurement = try #require(run.measurement)
            #expect(abs(measurement.integratedLoudness - published) <= tolerance)

            // The extraction the report surface performs, then the real exporter.
            let exportable = ExportableMeasurements.value(
                of: RootView.loudnessPresentation(for: try #require(LoudnessState(run.loudness)))
            )
            let data = try exportData(report(status: .completed), loudness: exportable)
            let json = try JSONDecoder().decode(JSONValue.self, from: data)
            let exported = try #require(json["measurements"]?["integratedLoudness"])

            #expect(
                exported["value"]?.double == measurement.integratedLoudness,
                "the exported value is not the measured one"
            )
            #expect(exported["method"]?["algorithm"]?.string == "itu_r_bs1770_5_integrated_v1")
            #expect(exported["method"]?["weighting"]?.string == "itu_r_bs1770_5_tables_1_2_48k")
            // Unrounded: the screen's one decimal never reaches the wire.
            let text = try #require(String(data: data, encoding: .utf8))
            #expect(!text.contains("\"value\":-23}"), "the value was rounded on the way out")
        }
    }

    /// The same measurement into the report surface. The presentation **rounds for the eye and changes
    /// nothing else** — the model it was given and the value the export carries are untouched by it.
    @Test("the presentation rounds the validated value for display without altering it")
    func thePresentationRoundsForDisplayOnly() async throws {
        try await withTemporaryDirectory { directory in
            let run = try await LoudnessProductionHarness.run(.table1Test1, in: directory)
            let measurement = try #require(run.measurement)
            let presentation = RootView.loudnessPresentation(for: try #require(LoudnessState(run.loudness)))

            // The presentation carries the measurement itself, not a copy of a rounded number.
            #expect(presentation == .measurement(measurement))

            let row = LoudnessCopy.row(for: measurement)
            #expect(row.value == "-23.0 LUFS", "the validated −22.99… did not read as −23.0")
            #expect(row.accessibilityLabel == "Integrated loudness, -23.0 LUFS")

            // And the model behind it still holds every digit that was validated.
            #expect(measurement.integratedLoudness != -23.0, "the presentation's rounding reached the model")
            #expect(abs(measurement.integratedLoudness - (-23.0)) <= LoudnessTestVector.publishedTolerance)
        }
    }

    // MARK: - Samples beyond full scale

    /// A programme genuinely above full scale is **measured, not limited**, all the way through the
    /// production path — and doubling its amplitude raises the reading by 6.02 dB, the energy ratio,
    /// rather than saturating at some ceiling.
    ///
    /// The two amplitude measurements beside it keep their own semantics: the true peak reports above
    /// unity because that is the fact it exists to reveal, and the clipped-sample count is a **count**
    /// that says nothing about the loudness figure. Nothing derives clipping from loudness.
    @Test("a programme beyond full scale is measured rather than limited, and nothing derives clipping from it")
    func productionDoesNotLimitAProgrammeBeyondFullScale() async throws {
        try await withTemporaryDirectory { directory in
            func measure(amplitude: Float, name: String) async throws -> LoudnessProductionHarness.Run {
                let spec = AudioFixtureSpec(
                    name: name, format: .wavFloat,
                    signal: .sine(frequency: 997, amplitude: amplitude),
                    sampleRate: 48_000, channels: 2, frames: 96_000
                )
                return try await LoudnessProductionHarness.run(
                    fileAt: try writeFloatPCMFixture(spec, in: directory)
                )
            }

            let unity = try await measure(amplitude: 1.0, name: "loudness-unity")
            let beyond = try await measure(amplitude: 2.0, name: "loudness-beyond")

            let atUnity = try #require(unity.integratedLoudness)
            let aboveUnity = try #require(beyond.integratedLoudness)

            // Not clamped: twice the amplitude is four times the energy, which is 6.02 dB.
            #expect(
                abs((aboveUnity - atUnity) - 6.0206) <= 0.01,
                "doubling the amplitude moved the reading by \(aboveUnity - atUnity), not 6.02"
            )
            #expect(aboveUnity > atUnity, "a louder programme read no louder")
            #expect(aboveUnity > 0, "a programme this far above full scale reads positive")

            // The neighbouring measurements keep their own meaning, independently.
            guard case let .available(peak) = beyond.outcome.truePeak else {
                Issue.record("true peak: \(beyond.outcome.truePeak)"); return
            }
            guard case let .available(levels) = beyond.outcome.signalLevelMetrics else {
                Issue.record("signal levels: \(beyond.outcome.signalLevelMetrics)"); return
            }
            #expect(try #require(peak.overallTruePeak) > 1.0, "the true peak was clamped")
            #expect(levels.overallClippedSampleCount > 0, "samples at or beyond full scale were not counted")
            // And the loudness carries no trace of any of that: no flag, no second field, no verdict.
            let measurement = try #require(beyond.measurement)
            #expect(measurement.method.algorithm == .integratedBS1770v1)
            #expect(measurement.integratedLoudness.isFinite)
        }
    }
}
