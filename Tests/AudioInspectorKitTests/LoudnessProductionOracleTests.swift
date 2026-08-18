import AVFoundation
import Foundation
import Testing

import AudioInspectorDomain
@testable import AudioInspectorApp

// **Production against an independent implementation**, on the same file.
//
// The existing oracle suite measures the vectors with FFmpeg and compares that against the published
// targets — it qualifies the *oracle*. This one measures the same file **both ways** and compares them
// against each other, which is the only comparison that says anything about our implementation.
//
// ## Three magnitudes that must not be confused
//
// - the **published target** — what EBU Tech 3341 and ITU-R BS.1770-5 say a compliant meter reports,
//   with the publishers' own ±0.1;
// - the **oracle** — what FFmpeg 8.1.2 reports, an implementation with no authority over the number;
// - **production** — what this project reports.
//
// Agreement with the oracle is *not* compliance evidence and is never treated as such: the published
// targets are asserted in "Analysis — published loudness targets through the production path", against
// the documents. What the oracle adds is independence — two implementations arriving at the same number
// from the same file rules out a shared misreading of the text in a way one implementation cannot.
//
// The suite is gated on FFmpeg, which is a **dev/test dependency and absent from CI** (ADR-0003). A
// skipped run is not agreement, and the skip message says so.

@Suite(
    "Analysis — production loudness against the FFmpeg oracle (local evidence, not CI coverage)",
    .enabled(
        if: FFmpegTool.isAvailable,
        """
        FFmpeg is not installed on this machine, so production cannot be compared against an \
        independent implementation on the same file. This suite is SKIPPED, and a skipped run is NOT \
        evidence that the two agree. The published targets are asserted without FFmpeg in "Analysis — \
        published loudness targets through the production path", and those still ran.
        """
    )
)
struct LoudnessProductionOracleTests {

    /// **0.01 LU**, stated from measurement at a single rate.
    ///
    /// The worst production-versus-oracle difference observed over every vector below is **0.0071 LU**,
    /// and the differences are same-signed and of similar size, which is the signature of a small
    /// systematic offset rather than of noise. The bound leaves a factor of 1.4 — deliberately tight,
    /// because this comparison is between two implementations of one algorithm on identical samples, and
    /// there is no physical reason for them to drift.
    ///
    /// It is **not** the ±0.1 published tolerance and must not be read as one: that describes what a
    /// compliant meter may differ from a *document* by. Nor is it the 0.03 LU used for rate-invariance,
    /// which is FFmpeg's own drift *across rates* — a magnitude that does not apply to a comparison at
    /// one rate.
    static let oracleAgreement = 0.01

    /// One file, measured twice: once by the production composition, once by FFmpeg.
    private func compare(
        _ vector: LoudnessTestVector, in directory: URL
    ) async throws -> (production: Double, oracle: Double) {
        let run = try await LoudnessProductionHarness.run(vector, in: directory)
        let production = try #require(run.integratedLoudness, "\(vector.name): production produced nothing")
        let oracle = try LoudnessOracle.read(run.url)
        return (production, oracle.integrated)
    }

    // MARK: - The published vectors, measured both ways

    /// Tech 3341 §2.9 and Table 1 tests 1–5. Each assertion carries **all three** numbers, so a failure
    /// says immediately whether production drifted, the oracle changed, or both moved away from the
    /// document together.
    @Test(
        "production and the oracle agree on every published vector, and both meet the published target",
        arguments: LoudnessTestVector.normativeVectors
    )
    func productionAgreesWithTheOracleOnPublishedVectors(_ vector: LoudnessTestVector) async throws {
        let published = try #require(vector.expectedLUFS)
        let publishedTolerance = try #require(vector.expectedTolerance)

        try await withTemporaryDirectory { directory in
            let (production, oracle) = try await compare(vector, in: directory)
            #expect(
                abs(production - oracle) <= Self.oracleAgreement,
                "\(vector.name): production \(production), oracle \(oracle), published \(published)"
            )
            // Both against the document, separately — so agreement between two wrong implementations
            // could never be recorded here as success.
            #expect(abs(production - published) <= publishedTolerance, "\(vector.name): production \(production)")
            #expect(abs(oracle - published) <= publishedTolerance, "\(vector.name): oracle \(oracle)")
        }
    }

    /// BS.1770-5's own anchor at 997 Hz, where the conversion offset is pinned most sharply.
    @Test(
        "production and the oracle agree on BS.1770-5's anchor",
        arguments: [LoudnessTestVector.bs1770Anchor, LoudnessTestVector.bs1770AnchorAttenuated]
    )
    func productionAgreesWithTheOracleOnTheAnchor(_ vector: LoudnessTestVector) async throws {
        let published = try #require(vector.expectedLUFS)
        try await withTemporaryDirectory { directory in
            let (production, oracle) = try await compare(vector, in: directory)
            #expect(
                abs(production - oracle) <= Self.oracleAgreement,
                "\(vector.name): production \(production), oracle \(oracle), published \(published)"
            )
        }
    }

    // MARK: - A programme rather than a tone

    /// **Every published vector is a steady sine**, which is the one shape a meter is least likely to get
    /// wrong. A programme with a moving level exercises the block set, both gates and the energy mean
    /// together, and it has no published expectation — so the oracle is the only reference available and
    /// this is exactly what an independent implementation is *for*.
    @Test("production and the oracle agree on a programme whose level moves")
    func productionAgreesWithTheOracleOnAComplexProgramme() async throws {
        try await withTemporaryDirectory { directory in
            let programme = AudioFixtureSpec(
                name: "programme-varying-level",
                format: .wavFloat,
                signal: .segmentedSine(frequency: 997, segments: [
                    AudioFixtureSegment(amplitude: 0.0708, frames: 240_000), //  −23 dBFS, 5 s
                    AudioFixtureSegment(amplitude: 0.0089, frames: 144_000), //  −41 dBFS, 3 s
                    AudioFixtureSegment(amplitude: 0.3548, frames: 384_000), //   −9 dBFS, 8 s
                    AudioFixtureSegment(amplitude: 0.0003, frames: 240_000), //  −70 dBFS, 5 s
                    AudioFixtureSegment(amplitude: 0.1259, frames: 336_000), //  −18 dBFS, 7 s
                ]),
                sampleRate: 48_000,
                channels: 2,
                frames: 1_344_000
            )
            let url = try writeFloatPCMFixture(programme, in: directory)
            let run = try await LoudnessProductionHarness.run(fileAt: url)
            let production = try #require(run.integratedLoudness)
            let oracle = try LoudnessOracle.read(url).integrated

            #expect(
                abs(production - oracle) <= Self.oracleAgreement,
                "production \(production), oracle \(oracle)"
            )
            // The programme really does exercise gating: a −70 dBFS passage sits below the absolute
            // gate, so a meter that included it would read lower than both of these.
            #expect(production > -20, "the quiet passages were not gated out")
        }
    }

    // MARK: - Per container

    /// Task 6.6's own words: real files of **each container**, cross-checked against the oracle.
    ///
    /// The same described signal in every container the fixture writer can produce, measured by both
    /// implementations on the identical file. This is where a decode difference would appear — our
    /// decoder is AVFoundation's and FFmpeg's is its own, so for a lossy container the two are not even
    /// decoding the same samples.
    @Test(
        "production and the oracle agree on every container, on the same file",
        arguments: AudioFixtureFormat.allCases
    )
    func productionAgreesWithTheOraclePerContainer(_ format: AudioFixtureFormat) async throws {
        try await withTemporaryDirectory { directory in
            let spec = AudioFixtureSpec(
                name: "oracle-container-\(format)",
                format: format,
                signal: .sine(frequency: 997, amplitude: Float(pow(10.0, -23.0 / 20.0))),
                sampleRate: 48_000,
                channels: 2,
                frames: 960_000
            )
            let url = try writeAudioFixture(spec, in: directory)
            let production = try #require(
                try await LoudnessProductionHarness.run(fileAt: url).integratedLoudness,
                "\(format): production produced nothing"
            )
            let oracle = try LoudnessOracle.read(url).integrated
            #expect(
                abs(production - oracle) <= Self.oracleAgreement,
                "\(format): production \(production), oracle \(oracle)"
            )
        }
    }

    // MARK: - Per rate

    /// **Away from 48 kHz, agreement with the oracle is the wrong thing to assert**, and measuring it
    /// showed why rather than merely suggesting it.
    ///
    /// BS.1770-5 publishes coefficients for 48 kHz alone and asks every other rate only to *match that
    /// frequency response*, without publishing a prototype, a per-rate table or a method. So at any other
    /// rate two implementations are running **two different derivations**, and a disagreement between
    /// them is not evidence that either is wrong. Measured on Table 1 test 1, whose published reading is
    /// −23.0:
    ///
    /// | rate | production | oracle | production − oracle |
    /// | --- | --- | --- | --- |
    /// | 44 100 | −22.994376 | −23.000 | +0.0056 |
    /// | 48 000 | −22.993298 | −23.000 | +0.0067 |
    /// | 88 200 | −22.989190 | −23.010 | +0.0208 |
    /// | 96 000 | −22.988921 | −23.020 | +0.0311 |
    /// | 192 000 | −22.987827 | −23.030 | +0.0422 |
    ///
    /// **The movement is the oracle's.** Its reading drifts monotonically away from the published −23.0
    /// as the rate rises, ending 0.030 LU below it — exactly the drift the spike recorded in §B5.
    /// Production's own spread over the same five files is **0.0065 LU**, and it stays within 0.0122 of
    /// the published value everywhere.
    ///
    /// So this test asserts the two things that are actually meaningful — production meets the *document*
    /// at every rate, and production is the more rate-stable of the two — and keeps only a deliberately
    /// loose sanity bound on the disagreement itself, whose job is to catch a gross divergence rather
    /// than to certify agreement nobody can claim.
    @Test("away from the published rate, production tracks the document better than the oracle does")
    func perRateDisagreementWithTheOracleIsTheOraclesOwnDrift() async throws {
        let published = try #require(LoudnessTestVector.table1Test1.expectedLUFS)
        let publishedTolerance = try #require(LoudnessTestVector.table1Test1.expectedTolerance)

        try await withTemporaryDirectory { directory in
            var production: [Double] = []
            var oracle: [Double] = []
            for rate in LoudnessProductionRateMatrixTests.rates {
                let run = try await LoudnessProductionHarness.run(.table1Test1, at: rate, in: directory)
                let measured = try #require(run.integratedLoudness)
                production.append(measured)
                oracle.append(try LoudnessOracle.read(run.url).integrated)

                // Production against the **document**, at every rate. This is the claim that matters,
                // and it is made against the publisher rather than against a tool.
                #expect(
                    abs(measured - published) <= publishedTolerance,
                    "\(Int(rate)) Hz: production \(measured), published \(published)"
                )
                // A loose sanity bound on the disagreement: twice the oracle's own recorded drift. It
                // exists to catch a gross divergence, and is explicitly not a claim of agreement.
                #expect(
                    abs(measured - oracle[oracle.count - 1]) <= 0.06,
                    "\(Int(rate)) Hz: production \(measured), oracle \(oracle[oracle.count - 1])"
                )
            }

            // **The substantive finding**: of the two implementations, ours is the one that holds still.
            let productionHighest = try #require(production.max())
            let productionLowest = try #require(production.min())
            let oracleHighest = try #require(oracle.max())
            let oracleLowest = try #require(oracle.min())
            let productionSpread = productionHighest - productionLowest
            let oracleSpread = oracleHighest - oracleLowest
            #expect(
                productionSpread < oracleSpread,
                "production drifted \(productionSpread) across rates, the oracle \(oracleSpread)"
            )
            #expect(productionSpread <= 0.03, "production drift \(productionSpread)")
        }
    }

    // MARK: - Where the two deliberately disagree

    /// **The one place agreement is the wrong goal.** For a signal the standard leaves undefined, FFmpeg
    /// displays −70.000 — its floor, a display convention — and this project reports an absence. The
    /// difference is intended (ADR-0022 §6), and this test exists so it can never be "fixed" by copying
    /// the floor.
    @Test(
        "for an undefined signal the oracle shows its floor and production shows an absence",
        arguments: LoudnessTestVector.silenceVectors
    )
    func productionReportsAnAbsenceWhereTheOracleShowsItsFloor(_ vector: LoudnessTestVector) async throws {
        guard case let .notComputable(floor) = vector.expectation else {
            Issue.record("\(vector.name) must expect no value"); return
        }
        try await withTemporaryDirectory { directory in
            let run = try await LoudnessProductionHarness.run(vector, in: directory)
            #expect(run.loudness == .unavailable, "\(vector.name): production gave \(run.loudness)")
            #expect(run.measurement == nil)
            #expect(try LoudnessOracle.read(run.url).integrated == floor, "the oracle's floor moved")
        }
    }
}
