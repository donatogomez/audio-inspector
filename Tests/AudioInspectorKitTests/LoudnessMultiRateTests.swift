import Foundation
import Testing

@testable import AudioInspectorAnalysis
import AudioInspectorDomain

// What changes, and what must not, when the same programme arrives at a different sample rate.
//
// **The published vectors are 48 kHz signals.** EBU Tech 3341 says so, and nothing here calls a
// resynthesis at another rate an official vector: those are *derived acceptance cases* — the same
// described signal, generated at another rate, judged against the same published number because the
// signal it describes is the same signal.

@Suite("Analysis — integrated loudness across sample rates")
struct LoudnessMultiRateTests {

    static let rates = [44_100.0, 48_000.0, 88_200.0, 96_000.0, 192_000.0]

    /// **Measured, not assumed.** Our own reading moves at most 0.0066 LU across these five rates; the
    /// bound is set at 0.02 to leave a factor of three, and it sits five times inside the ±0.1 the
    /// publishers allow. For comparison, FFmpeg's reading of the same signals moves 0.03 LU across the
    /// same rates — so this is a tighter claim than the reference implementation makes about itself.
    static let rateInvarianceTolerance = 0.02

    // MARK: - Which weighting ran, on the value itself

    /// Nothing downstream infers the tier from a sample rate: the measurement says which coefficients
    /// produced it, because the accumulator reads that off the filter it actually built.
    @Test("the measurement names the weighting that produced it", arguments: rates)
    func measurementNamesItsWeighting(_ rate: Double) throws {
        let vector = LoudnessAccumulatorHarness.resynthesised(
            LoudnessAccumulatorHarness.tone(dBFS: -20, seconds: 1), at: rate
        )
        let measured = try #require(try LoudnessAccumulatorHarness.measure(vector))

        let expected: LoudnessWeightingIdentifier =
            rate == KWeighting.publishedSampleRate ? .publishedAt48kHz : .derivedFrom48kHz
        #expect(measured.method.weighting == expected, "\(rate)")
        // The algorithm is the same at every rate: only the filter's provenance changes.
        #expect(measured.method.algorithm == .integratedBS1770v1, "\(rate)")
    }

    @Test("the derived identity is the exact string published with derived results")
    func derivedIdentityIsStable() {
        #expect(
            LoudnessWeightingIdentifier.derivedFrom48kHz.rawValue
                == "itu_r_bs1770_5_48k_prototype_rediscretised_v1"
        )
        #expect(LoudnessWeightingIdentifier.derivedFrom48kHz != .publishedAt48kHz)
    }

    // MARK: - The same signal reads the same at every rate

    /// The frequencies where the weighting has slope matter most, so the sweep includes the high-pass
    /// knee, the shelf transition and the plateau — not only the calibration tone.
    @Test(
        "the same tone reads the same loudness at every rate",
        arguments: [40.0, 100.0, 997.0, 1_000.0, 4_000.0, 12_000.0]
    )
    func readingIsInvariantAcrossRates(_ frequency: Double) throws {
        var readings: [(rate: Double, value: Double)] = []
        for rate in Self.rates {
            let vector = LoudnessAccumulatorHarness.resynthesised(
                LoudnessAccumulatorHarness.tone(dBFS: -20, seconds: 3, frequency: frequency), at: rate
            )
            readings.append((rate, try #require(try LoudnessAccumulatorHarness.measureLoudness(vector))))
        }
        let values = readings.map(\.value)
        let spread = (values.max() ?? 0) - (values.min() ?? 0)
        #expect(spread <= Self.rateInvarianceTolerance, "\(frequency) Hz: \(readings)")
    }

    /// A programme, not a tone: three levels so the gating runs, at every rate.
    @Test("a gated programme reads the same at every rate")
    func gatedProgrammeIsInvariantAcrossRates() throws {
        let shape = LoudnessAccumulatorHarness.segments([(-36.0, 0.5), (-23.0, 3.0), (-36.0, 0.5)])
        var values: [Double] = []
        for rate in Self.rates {
            values.append(
                try #require(
                    try LoudnessAccumulatorHarness.measureLoudness(
                        LoudnessAccumulatorHarness.resynthesised(shape, at: rate)
                    )
                )
            )
        }
        let spread = (values.max() ?? 0) - (values.min() ?? 0)
        #expect(spread <= Self.rateInvarianceTolerance, "\(values)")
    }

    // MARK: - The published expectations, at rates the publisher did not synthesise

    /// The steady vectors resynthesised at each rate, judged against the **same published number**. The
    /// signal Tech 3341 describes is a level and a duration; generating it at 96 kHz produces that signal,
    /// so the expected reading is unchanged even though the file is not the publisher's.
    @Test(
        "a published vector resynthesised at another rate still meets its published expectation",
        arguments: [LoudnessTestVector.calibration, LoudnessTestVector.table1Test1]
    )
    func publishedVectorsHoldAtEveryRate(_ vector: LoudnessTestVector) throws {
        let expected = try #require(vector.expectedLUFS)
        let tolerance = try #require(vector.expectedTolerance)
        for rate in Self.rates {
            let measured = try #require(
                try LoudnessAccumulatorHarness.measureLoudness(
                    LoudnessAccumulatorHarness.resynthesised(vector, at: rate)
                )
            )
            #expect(abs(measured - expected) <= tolerance, "\(vector.name) at \(rate): \(measured)")
        }
    }

    /// The gating vectors are 80 and 100 seconds long, so they are spot-checked at the extremes of the
    /// supported range rather than at all five — the gating itself is rate-independent by construction,
    /// and what multi-rate has to prove is the weighting.
    @Test(
        "the relative-gate vector holds at the extremes of the supported range",
        arguments: [44_100.0, 192_000.0]
    )
    func gatingVectorHoldsAtTheExtremes(_ rate: Double) throws {
        let vector = LoudnessTestVector.table1Test3
        let expected = try #require(vector.expectedLUFS)
        let tolerance = try #require(vector.expectedTolerance)
        let measured = try #require(
            try LoudnessAccumulatorHarness.measureLoudness(LoudnessAccumulatorHarness.resynthesised(vector, at: rate))
        )
        #expect(abs(measured - expected) <= tolerance, "at \(rate): \(measured)")
    }

    // MARK: - 192 kHz, treated as its own case

    /// The highest rate is where a bilinear-derived filter has the most to prove: its poles crowd the unit
    /// circle, and the response has the furthest to be carried. True peak had an oracle limitation at this
    /// rate; that limitation belonged to oversampling and is **not** inherited here, which is measured
    /// rather than assumed — the reading is invariant with the rest and the poles stay inside.
    @Test("192 kHz is stable, in-band and in agreement rather than merely accepted")
    func highestRateIsMeasuredRatherThanAssumed() throws {
        let weighting = try #require(KWeighting(sampleRate: 192_000))
        #expect(weighting.stage1.isStable)
        #expect(weighting.stage2.isStable)
        #expect(!weighting.isPublished)

        let anchor = LoudnessAccumulatorHarness.resynthesised(LoudnessTestVector.bs1770Anchor, at: 192_000)
        let measured = try #require(try LoudnessAccumulatorHarness.measureLoudness(anchor))
        let expected = try #require(LoudnessTestVector.bs1770Anchor.expectedLUFS)
        #expect(abs(measured - expected) <= LoudnessTestVector.publishedTolerance, "\(measured)")
    }

    // MARK: - Chunk independence, at every rate

    /// Still **bit-identical**, not within a tolerance. One second rather than four, because a chunk size
    /// of one frame at 192 kHz is already 192 000 chunks and the property does not need a longer file to
    /// be exercised: a second spans seven gating blocks.
    @Test(
        "the result is bit-identical at every chunk size, at every rate",
        arguments: [44_100.0, 48_000.0, 96_000.0, 192_000.0]
    )
    func chunkIndependenceHoldsAtEveryRate(_ rate: Double) throws {
        let shapes = [
            LoudnessAccumulatorHarness.tone(dBFS: -18, seconds: 1),
            LoudnessAccumulatorHarness.tone(dBFS: -20, seconds: 1, frequency: 40),
            LoudnessAccumulatorHarness.tone(dBFS: -20, seconds: 1, frequency: 12_000),
            LoudnessAccumulatorHarness.segments([(-36.0, 0.3), (-23.0, 0.6), (-36.0, 0.3)]),
        ]
        for shape in shapes {
            let vector = LoudnessAccumulatorHarness.resynthesised(shape, at: rate)
            let reference = try LoudnessAccumulatorHarness.measureLoudness(vector, chunkFrames: nil)
            for size in [1, 3, 127, 4_096, 65_536] {
                let measured = try LoudnessAccumulatorHarness.measureLoudness(vector, chunkFrames: size)
                #expect(measured == reference, "\(vector.name) at \(rate), chunk \(size)")
            }
        }
    }
}
