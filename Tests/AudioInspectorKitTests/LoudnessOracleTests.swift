import AVFoundation
import Foundation
import Testing

@testable import AudioInspectorAnalysis

// The official loudness vectors, measured by an independent implementation.
//
// **What this suite establishes, and what it does not.** Nothing in this product computes loudness yet,
// so nothing here compares production against anything. What it does is qualify the oracle: it shows
// that FFmpeg's `ebur128` reproduces the publishers' own expected readings on the publishers' own
// signals, which is the difference between "a second implementation happened to agree" and "a second
// implementation that passes the acceptance set agrees". Until `LoudnessAccumulator` exists, that is the
// whole value — and it is worth having *before* the accumulator, because a target validated after the
// fact is a target that was fitted.
//
// It also confirms the generated fixtures survive the round trip to a real file, which the pure-signal
// checks in "Test support — official loudness test vectors" cannot.

// MARK: - The oracle's output format, with no tool needed

/// Parsing is pinned here rather than in the gated suite below, because the mistake it guards against —
/// reading the *Loudness range* threshold as the integrated one — is a silent 10 LU error, and a rule
/// that only holds on machines with FFmpeg installed is not a rule.
@Suite("Test support — reading FFmpeg's ebur128 output")
struct LoudnessOracleParsingTests {

    /// A faithful excerpt of FFmpeg 8.1.2's output for Tech 3341 test 3, including the interleaving of
    /// the stdout metadata stream with the stderr summary that a shared pipe produces.
    private let sampleOutput = """
    lavfi.r128.M=-23.021
    lavfi.r128.S=-23.021
    lavfi.r128.I=-23.019
    lavfi.r128.LRA=13.000
    [Parsed_ebur128_0 @ 0x14f00] Summary:

      Integrated loudness:
        I:         -23.0 LUFS
        Threshold: -34.2 LUFS

      Loudness range:
        LRA:        13.0 LU
        Threshold: -44.0 LUFS
        LRA low:   -36.0 LUFS
        LRA high:  -23.0 LUFS

    lavfi.r128.M=-35.993
    lavfi.r128.S=-35.993
    lavfi.r128.I=-23.021
    lavfi.r128.LRA=13.000
    lavfi.r128.LRA.low=-36.000
    lavfi.r128.LRA.high=-23.000
    """

    @Test("the integrated value comes from the metadata stream, at its full precision")
    func integratedComesFromMetadata() throws {
        let reading = try LoudnessOracle.parse(sampleOutput)
        // Three decimals, and the *last* emission — not the summary's rounded −23.0 and not the
        // running value from part-way through the file.
        #expect(reading.integrated == -23.021)
    }

    /// The whole reason this parser is section-aware.
    @Test("the threshold is the integrated block's relative gate, never the loudness range's")
    func thresholdIsNotTheLoudnessRangeOne() throws {
        let reading = try LoudnessOracle.parse(sampleOutput)
        #expect(reading.relativeThreshold == -34.2)
        #expect(reading.relativeThreshold != -44.0, "−44.0 is EBU Tech 3342's −20 LU gate for LRA")
    }

    /// `lavfi.r128.LRA` and `lavfi.r128.LRA.low` share a prefix with nothing that matters, but a
    /// prefix match rather than an exact one would accept them.
    @Test("a key is matched exactly, so neighbouring r128 keys are not mistaken for the integrated one")
    func keysAreMatchedExactly() throws {
        let reading = try LoudnessOracle.parse("""
        lavfi.r128.LRA=13.000
        lavfi.r128.LRA.low=-36.000
        lavfi.r128.I=-23.021
          Integrated loudness:
            Threshold: -34.2 LUFS
        """)
        #expect(reading.integrated == -23.021)
    }

    @Test("output with no metadata is a parse failure, distinct from the tool failing")
    func missingMetadataIsItsOwnFailure() {
        #expect(throws: LoudnessOracle.ParseFailure.self) {
            _ = try LoudnessOracle.parse("  Integrated loudness:\n    Threshold: -34.2 LUFS")
        }
    }

    /// The summary is logged at INFO level, so `-loglevel error` discards it and leaves the metadata
    /// behind. That produces exactly this failure, and the message says so.
    @Test("output with metadata but no summary is a different parse failure")
    func missingSummaryIsItsOwnFailure() {
        #expect(throws: LoudnessOracle.ParseFailure.self) {
            _ = try LoudnessOracle.parse("lavfi.r128.I=-23.021")
        }
    }

    @Test("the invocation is a separated argument vector and asks for both channels of information")
    func invocationIsExplicit() {
        let arguments = LoudnessOracle.arguments(for: URL(fileURLWithPath: "/tmp/a b.wav"))
        #expect(arguments.contains("/tmp/a b.wav"), "the path is one argument, never a shell string")
        #expect(arguments.contains { $0.contains("ebur128=metadata=1") })
        #expect(!arguments.contains { $0.contains("loglevel") }, "the summary is INFO-level")
    }
}

// MARK: - The measurement itself

@Suite(
    "Analysis — official loudness vectors against the FFmpeg oracle (local evidence, not CI coverage)",
    .enabled(
        if: FFmpegTool.isAvailable,
        """
        FFmpeg is not installed on this machine, so the official loudness vectors cannot be measured \
        against an independent implementation. This suite is SKIPPED, and a skipped run is NOT evidence \
        that the vectors are reproducible or that the oracle is qualified. The transcription and \
        discrimination checks in "Test support — official loudness test vectors" are unaffected and \
        still ran.
        """
    )
)
struct LoudnessOracleTests {

    /// Writes a vector, checks the file is what it claims, and measures it.
    private func measure(_ vector: LoudnessTestVector, in directory: URL) throws -> LoudnessOracle.Reading {
        let url = try writeFloatPCMFixture(vector.fixtureSpec, in: directory)

        let metadata = try readBackMetadata(of: url)
        #expect(metadata.sampleRate == vector.sampleRate, "\(vector.name) rate")
        #expect(metadata.channels == vector.channels, "\(vector.name) channels")
        #expect(metadata.frames == AVAudioFramePosition(vector.totalFrames), "\(vector.name) frames")

        return try LoudnessOracle.read(url)
    }

    // MARK: The published vectors

    /// Tech 3341 §2.9 and Table 1 tests 1–5, each against **its own published expected reading and its
    /// own published tolerance**. Nothing here is fitted: both numbers come from the document.
    @Test(
        "the oracle reproduces every published expected reading within the published tolerance",
        arguments: LoudnessTestVector.normativeVectors
    )
    func oracleReproducesPublishedReadings(_ vector: LoudnessTestVector) async throws {
        let expected = try #require(vector.expectedLUFS)
        let tolerance = try #require(vector.expectedTolerance)

        try await withTemporaryDirectory { directory in
            let reading = try measure(vector, in: directory)
            #expect(
                abs(reading.integrated - expected) <= tolerance,
                "\(vector.name): read \(reading.integrated), expected \(expected) ±\(tolerance)"
            )
        }
    }

    /// BS.1770-5 states its own anchor, and it is the sharpest one available: 997 Hz is exactly where
    /// the −0.691 offset cancels the K-weighting gain, so this pins the offset in a way a 1 kHz signal —
    /// sitting on a filter slope, as Tech 3341 §2.9 warns — cannot.
    @Test(
        "the oracle reproduces BS.1770-5's own calibration anchor",
        arguments: [LoudnessTestVector.bs1770Anchor, LoudnessTestVector.bs1770AnchorAttenuated]
    )
    func oracleReproducesTheITUAnchor(_ vector: LoudnessTestVector) async throws {
        let expected = try #require(vector.expectedLUFS)
        let tolerance = try #require(vector.expectedTolerance)

        try await withTemporaryDirectory { directory in
            let reading = try measure(vector, in: directory)
            #expect(
                abs(reading.integrated - expected) <= tolerance,
                "\(vector.name): read \(reading.integrated), expected \(expected)"
            )
        }
    }

    // MARK: What the gating vectors show through the threshold

    /// Test 4 is test 3 wrapped in −72 dBFS. Their integrated readings match, so `I` alone barely
    /// separates them — but the absolute gate removes those passages *before* the relative threshold is
    /// derived, so the two files must derive the **same** threshold. Without the absolute gate test 4's
    /// would sit about a loudness unit lower.
    @Test("the absolute gate is visible in the threshold tests 3 and 4 share")
    func absoluteGateIsVisibleInTheThreshold() async throws {
        try await withTemporaryDirectory { directory in
            let three = try measure(LoudnessTestVector.table1Test3, in: directory)
            let four = try measure(LoudnessTestVector.table1Test4, in: directory)

            #expect(
                abs(three.relativeThreshold - four.relativeThreshold) <= 0.1,
                "thresholds: test 3 \(three.relativeThreshold), test 4 \(four.relativeThreshold)"
            )
            // And it is not the trivial case of both being the plain reading minus ten: the −36 dB
            // passages pull the absolutely-gated level below the final one.
            #expect(three.relativeThreshold < -33.5)
        }
    }

    /// Where the relative gate excludes nothing, BS.1770-5 eq. (6) makes the threshold exactly the
    /// reading minus 10 LU. Tests 1 and 5 are both such cases, for different reasons.
    @Test(
        "an ungating vector's threshold is its reading minus exactly the 10 LU offset",
        arguments: [LoudnessTestVector.table1Test1, LoudnessTestVector.table1Test5]
    )
    func thresholdIsTheReadingMinusTenWhereNothingIsExcluded(_ vector: LoudnessTestVector) async throws {
        let expected = try #require(vector.expectedLUFS)
        try await withTemporaryDirectory { directory in
            let reading = try measure(vector, in: directory)
            #expect(
                abs(reading.relativeThreshold - (expected - 10.0)) <= 0.1,
                "\(vector.name): threshold \(reading.relativeThreshold)"
            )
        }
    }

    // MARK: The block boundary

    /// 400 ms measures and 399 ms does not, and the edge is one frame wide. Derived from BS.1770-5
    /// eq. (3) rather than published, and labelled as such in the vector.
    @Test(
        "the measurement boundary sits exactly at one gating block",
        arguments: LoudnessTestVector.blockBoundaryVectors
    )
    func blockBoundaryBehavesAsTheIndexSetPredicts(_ vector: LoudnessTestVector) async throws {
        try await withTemporaryDirectory { directory in
            let reading = try measure(vector, in: directory)
            switch vector.expectation {
            case let .measured(expected, tolerance):
                #expect(abs(reading.integrated - expected) <= tolerance, "\(vector.name)")
            case let .notComputable(floor):
                #expect(reading.integrated == floor, "\(vector.name)")
            }
        }
    }

    // MARK: Silence

    /// The floor is observed and **named as the oracle's**. A meter shows something for a signal the
    /// standard leaves undefined; that something is not a measurement, and this suite refuses to record
    /// it as one — the vector carries no reading, and the assertion below is on the vector as much as
    /// on the tool.
    @Test(
        "digital silence shows the oracle's floor, which the catalogue records as an absence",
        arguments: LoudnessTestVector.silenceVectors
    )
    func silenceShowsAFloorAndNotAReading(_ vector: LoudnessTestVector) async throws {
        guard case let .notComputable(floor) = vector.expectation else {
            Issue.record("\(vector.name) must expect no value")
            return
        }
        #expect(vector.expectedLUFS == nil, "the floor must never become the vector's reading")

        try await withTemporaryDirectory { directory in
            let reading = try measure(vector, in: directory)
            #expect(reading.integrated == floor, "\(vector.name): read \(reading.integrated)")
        }
    }

    // MARK: The sample-rate sweep

    /// The acceptance target for the per-rate derivation ADR-0022 §3 commits to. It shows the target is
    /// reachable — a rate-adapting implementation exists — and **not** that ours will match it, because
    /// ours does not exist.
    @Test("the same signal reads the same at every supported rate")
    func readingIsRateInvariant() async throws {
        var readings: [(rate: Double, value: Double)] = []
        for vector in LoudnessTestVector.sampleRateVectors {
            let expected = try #require(vector.expectedLUFS)
            let tolerance = try #require(vector.expectedTolerance)
            let value = try await withTemporaryDirectory { directory in
                let reading = try measure(vector, in: directory)
                #expect(
                    abs(reading.integrated - expected) <= tolerance,
                    "\(vector.name): read \(reading.integrated)"
                )
                return reading.integrated
            }
            readings.append((vector.sampleRate, value))
        }

        let values = readings.map(\.value)
        let spread = (values.max() ?? 0) - (values.min() ?? 0)
        #expect(spread <= 0.1, "spread across rates: \(readings)")
    }

    // MARK: Channel summation

    /// The channels are summed, not averaged. 10·log₁₀2 = 3.0103 dB is what BS.1770-5 Table 3's equal
    /// weights predict, and it is the one measurement that separates the two.
    @Test("stereo reads exactly 10·log₁₀2 above the same tone in mono")
    func stereoIsThreePointZeroOneAboveMono() async throws {
        let pair = LoudnessTestVector.monoAgainstStereo
        try await withTemporaryDirectory { directory in
            let mono = try measure(pair.mono, in: directory)
            let stereo = try measure(pair.stereo, in: directory)
            let difference = stereo.integrated - mono.integrated
            #expect(
                abs(difference - LoudnessTestVector.stereoOverMonoLU) <= 0.05,
                "difference \(difference), expected \(LoudnessTestVector.stereoOverMonoLU)"
            )
        }
    }

    // MARK: The production accumulator against the same files

    /// Three-way: the published target, the oracle, and what `LoudnessAccumulator` makes of the very
    /// same file the oracle was handed.
    ///
    /// The accumulator is judged against the **published** value at the **published** tolerance — that
    /// comparison is the contract and it lives in "Analysis — integrated loudness (48 kHz)", which needs
    /// no tool. What this adds is agreement with a second implementation, which is a different claim and
    /// a weaker one: two implementations can share a misreading of the same document.
    ///
    /// The bound used here is the published ±0.1 rather than something tighter. A tighter one would be
    /// fitted to today's measurement, and ADR-0022 leaves the oracle tolerance open until there is a
    /// reason to close it.
    @Test(
        "the accumulator agrees with the oracle on every published vector",
        arguments: LoudnessTestVector.normativeVectors
            + [LoudnessTestVector.bs1770Anchor, LoudnessTestVector.bs1770AnchorAttenuated]
    )
    func accumulatorAgreesWithTheOracle(_ vector: LoudnessTestVector) async throws {
        let published = try #require(vector.expectedLUFS)
        let produced = try LoudnessAccumulatorHarness.measure(vector)
        let accumulator = try #require(produced, "\(vector.name) should measure")

        try await withTemporaryDirectory { directory in
            let reading = try measure(vector, in: directory)
            #expect(
                abs(accumulator - reading.integrated) <= LoudnessTestVector.publishedTolerance,
                """
                \(vector.name): accumulator \(accumulator), oracle \(reading.integrated), \
                published \(published)
                """
            )
        }
    }

    // MARK: Provenance

    @Test("the FFmpeg build used is recorded with the evidence")
    func recordsTheBuild() throws {
        let version = try FFmpegTool.versionLine()
        #expect(version.contains("ffmpeg version"))
    }
}
