import AVFoundation
import Foundation
import Testing

// What the official loudness vectors assert **without any external tool**.
//
// This suite runs everywhere, including CI, and it is the half of the loudness groundwork that survives
// when FFmpeg is absent. It answers two questions:
//
// 1. **Is the generated signal the one the publishers describe?** Levels, durations, frequency, channel
//    count, rate — and that the tone's phase is continuous across a level change rather than restarted.
// 2. **Does each vector actually catch something, and something different from its neighbours?** A
//    battery where five tests fail for one reason is one test wearing five names.
//
// It asserts **nothing** about integrated loudness, because nothing computes it yet. There is no stub,
// no placeholder and no test written against a type that does not exist: the vectors are the target the
// accumulator will be built against, and a target that already agreed with something would be useless.
//
// The agreement with an independent implementation lives in "Analysis — integrated loudness against the
// FFmpeg oracle", which skips without the tool.

@Suite("Test support — official loudness test vectors")
struct LoudnessTestVectorTests {

    /// Levels here span 0 dBFS to −72 dBFS, so comparisons are relative rather than absolute.
    private let levelTolerance = 1e-4

    private func sample(_ vector: LoudnessTestVector, frame: Int) -> Float {
        vector.signal.sample(channel: 0, frame: frame, sampleRate: vector.sampleRate)
    }

    // MARK: - The transcription itself

    @Test("every published vector carries the publishers' own tolerance")
    func publishedToleranceIsTheirs() {
        for vector in LoudnessTestVector.normativeVectors {
            guard case let .measured(_, tolerance) = vector.expectation else {
                Issue.record("\(vector.name) is published, so it must expect a reading")
                continue
            }
            #expect(tolerance == LoudnessTestVector.publishedTolerance, "\(vector.name)")
            #expect(vector.authority.isNormative, "\(vector.name)")
        }
    }

    @Test("Tech 3341's signals are transcribed at the rate they are published at")
    func publishedSignalsAre48k() {
        for vector in LoudnessTestVector.tech3341Table1 + [.calibration] {
            #expect(vector.sampleRate == 48_000, "\(vector.name)")
            #expect(vector.channels == 2, "\(vector.name)")
            #expect(vector.frequency == 1_000, "\(vector.name)")
        }
    }

    /// Tests 1, 2 and §2.9 are the same signal at three levels, so their expectations must sit on a
    /// straight line of slope 1. A transcription slip in any one of them breaks this without needing a
    /// meter to notice.
    @Test("the three steady-level vectors are exactly their own levels apart")
    func steadyLevelsAreCollinear() throws {
        let one = try #require(LoudnessTestVector.table1Test1.expectedLUFS)
        let two = try #require(LoudnessTestVector.table1Test2.expectedLUFS)
        let calibration = try #require(LoudnessTestVector.calibration.expectedLUFS)

        #expect(two - one == -10.0)
        #expect(calibration - one == 5.0)
    }

    /// A stereo 1 kHz sine reads its own peak level in LUFS: the sine's −3.01 dB of RMS against peak
    /// and the +3.01 dB of summing two equal channels cancel, and the −0.691 offset cancels the
    /// K-weighting gain there. So a steady vector's transcribed **level** and its transcribed
    /// **expected reading** are the same number — and a slip in either is caught here, without a meter.
    @Test("a steady stereo 1 kHz vector's expected reading equals the level it is described with")
    func steadyVectorsReadTheirOwnLevel() throws {
        for vector in [LoudnessTestVector.table1Test1, .table1Test2, .calibration] {
            let expected = try #require(vector.expectedLUFS)
            let level = try #require(vector.segments.first?.dBFS)
            #expect(vector.segments.count == 1, "\(vector.name)")
            #expect(expected == level, "\(vector.name)")
        }
    }

    /// The durations Table 1 publishes, transcribed a second time and independently. A level can be
    /// checked against its own reading (above); a duration cannot, because the gating vectors read the
    /// same value under several wrong durations — so the only defence is stating them twice.
    @Test("Table 1's published structure survives transcription")
    func publishedStructureIsIntact() {
        let published: [(vector: LoudnessTestVector, seconds: [Double])] = [
            (.table1Test1, [20]),
            (.table1Test2, [20]),
            (.table1Test3, [10, 60, 10]),
            (.table1Test4, [10, 10, 60, 10, 10]),
            (.table1Test5, [20, 20.1, 20]),
        ]
        for (vector, seconds) in published {
            #expect(vector.segments.map(\.seconds) == seconds, "\(vector.name) durations")
            #expect(vector.totalSeconds == seconds.reduce(0, +), "\(vector.name) total")
        }

        // And the levels, likewise stated a second time.
        #expect(LoudnessTestVector.table1Test3.segments.map(\.dBFS) == [-36, -23, -36])
        #expect(LoudnessTestVector.table1Test4.segments.map(\.dBFS) == [-72, -36, -23, -36, -72])
        #expect(LoudnessTestVector.table1Test5.segments.map(\.dBFS) == [-26, -20, -26])
    }

    /// A vector that catches the same thing as another is not a second test.
    @Test("no two vectors claim to discriminate the same property")
    func discriminationIsDistinct() {
        let all = LoudnessTestVector.normativeVectors
            + [.bs1770Anchor, .bs1770AnchorAttenuated]
            + LoudnessTestVector.blockBoundaryVectors
        let sentences = all.map(\.discriminates)
        #expect(Set(sentences).count == sentences.count)
    }

    @Test("BS.1770-5's anchor uses the reference frequency the document names, not the nominal one")
    func anchorUses997Hz() {
        #expect(LoudnessTestVector.bs1770Anchor.frequency == 997)
        #expect(LoudnessTestVector.bs1770Anchor.channels == 1)
        #expect(LoudnessTestVector.bs1770Anchor.segments.first?.dBFS == 0.0)
    }

    // MARK: - Is the generated signal the described one?

    @Test(
        "every vector's segments carry the level and duration they are described with",
        arguments: LoudnessTestVector.allForFixtureChecks
    )
    func segmentsMatchTheirDescription(_ vector: LoudnessTestVector) throws {
        let frames = vector.segmentFrames
        #expect(frames.count == vector.segments.count)

        var start = 0
        for (segment, count) in zip(vector.segments, frames) {
            // The duration survives the seconds → frames conversion exactly.
            #expect(abs(Double(count) / vector.sampleRate - segment.seconds) < 1e-9, "\(vector.name)")

            let window = min(count, Int(vector.sampleRate))
            guard window > 0 else { continue }
            var sumOfSquares = 0.0
            var peak = 0.0
            for offset in 0 ..< window {
                let value = Double(sample(vector, frame: start + offset))
                sumOfSquares += value * value
                peak = max(peak, abs(value))
            }
            let rms = (sumOfSquares / Double(window)).squareRoot()

            if let dBFS = segment.dBFS {
                // A sine's RMS is its amplitude over root two. Every published duration here spans a
                // whole number of cycles, so this holds without an averaging allowance.
                let expected = pow(10.0, dBFS / 20.0) / 2.0.squareRoot()
                #expect(abs(rms - expected) / expected < levelTolerance, "\(vector.name) rms")
                // Nothing is normalised on the way in and nothing overshoots its own level.
                #expect(peak <= Double(segment.amplitude) * (1 + levelTolerance), "\(vector.name) peak")
            } else {
                #expect(rms == 0, "\(vector.name) silence")
                #expect(peak == 0, "\(vector.name) silence")
            }
            start += count
        }
    }

    /// The one property a segmented signal can silently get wrong: restarting the sine at each level
    /// change. That injects a step whose energy is not part of the described signal, and it would move a
    /// loudness reading. Asserted against the definition — absolute phase, stepped amplitude.
    @Test(
        "a level change steps the amplitude without restarting the phase",
        arguments: LoudnessTestVector.allForFixtureChecks
    )
    func phaseIsAbsolute(_ vector: LoudnessTestVector) {
        let frames = vector.segmentFrames
        var start = 0
        for (segment, count) in zip(vector.segments, frames) {
            // Probe the first frame of the segment, one just inside it, and its last frame.
            for frame in [start, start + min(1, count - 1), start + count - 1] where count > 0 {
                let phase = 2.0 * Double.pi * vector.frequency * Double(frame) / vector.sampleRate
                let expected = segment.amplitude * Float(sin(phase))
                #expect(sample(vector, frame: frame) == expected, "\(vector.name) @ \(frame)")
            }
            start += count
        }
        // Past the end there is nothing, rather than a wrapped repeat.
        #expect(sample(vector, frame: vector.totalFrames) == 0, "\(vector.name)")
    }

    @Test("the mono and stereo channel vectors differ by exactly 10·log₁₀2")
    func channelPairDiffersByThreePointZeroOne() throws {
        let pair = LoudnessTestVector.monoAgainstStereo
        let mono = try #require(pair.mono.expectedLUFS)
        let stereo = try #require(pair.stereo.expectedLUFS)

        #expect(pair.mono.channels == 1)
        #expect(pair.stereo.channels == 2)
        #expect(pair.mono.segments.map(\.dBFS) == pair.stereo.segments.map(\.dBFS))
        #expect(abs((stereo - mono) - LoudnessTestVector.stereoOverMonoLU) < 0.01)
    }

    @Test("the sample-rate sweep covers every rate the product supports, and only 48 kHz is published")
    func rateSweepIsHonestAboutItsAuthority() {
        let rates = LoudnessTestVector.sampleRateVectors.map(\.sampleRate)
        #expect(rates == [44_100, 48_000, 88_200, 96_000, 192_000])
        // Tech 3341 publishes its signals synthesised at 48 kHz, so every row here — including the
        // 48 kHz one, whose duration is ours — is a target rather than a published result.
        #expect(LoudnessTestVector.sampleRateVectors.allSatisfy { !$0.authority.isNormative })
    }

    // MARK: - The simplified reduction, calibrated before it is used

    /// The reduction collapses a segment to its level, which is only meaningful because a stereo 1 kHz
    /// sine measures its own peak level in LUFS. Checked against the published expectations first, so
    /// the discrimination arguments below rest on something rather than on an assertion.
    @Test("the simplified reduction reproduces the published value for a steady tone")
    func reductionIsCalibrated() throws {
        for vector in [LoudnessTestVector.table1Test1, .table1Test2, .calibration] {
            let expected = try #require(vector.expectedLUFS)
            #expect(abs(LoudnessSegmentReduction.ungated(vector.segments) - expected) < 1e-9, "\(vector.name)")
        }
    }

    // MARK: - What each gating vector actually catches

    /// Test 3 is the only published vector an ungated implementation fails outright.
    @Test("test 3 rejects an implementation with no relative gate")
    func testThreeCatchesTheMissingRelativeGate() throws {
        let vector = LoudnessTestVector.table1Test3
        let expected = try #require(vector.expectedLUFS)
        let ungated = LoudnessSegmentReduction.ungated(vector.segments)

        #expect(abs(ungated - expected) > 1.0)
        #expect(abs(LoudnessSegmentReduction.fullyGated(vector.segments) - expected) < 1e-9)
    }

    /// Test 4's integrated value equals test 3's, so `I` alone hardly separates them. What separates
    /// them is the threshold: the absolute gate removes the −72 dB passages *before* the relative
    /// threshold is derived, which makes test 4's absolutely-gated level identical to test 3's.
    @Test("test 4 catches a missing absolute gate through the threshold, not through the reading")
    func testFourCatchesTheMissingAbsoluteGate() throws {
        let three = LoudnessTestVector.table1Test3.segments
        let four = LoudnessTestVector.table1Test4.segments

        // With the absolute gate, test 4 *is* test 3.
        #expect(
            abs(
                LoudnessSegmentReduction.absoluteGated(four)
                    - LoudnessSegmentReduction.absoluteGated(three)
            ) < 1e-9
        )

        // Without it, the −72 dB passages drag the derived threshold down by about a loudness unit.
        let correct = LoudnessSegmentReduction.relativeThreshold(four, applyingAbsoluteGate: true)
        let broken = LoudnessSegmentReduction.relativeThreshold(four, applyingAbsoluteGate: false)
        #expect(correct - broken > 0.5)

        // And the reading alone would not have told us, which is why the oracle's threshold is read.
        let expected = try #require(LoudnessTestVector.table1Test4.expectedLUFS)
        #expect(abs(LoudnessSegmentReduction.fullyGated(four, applyingAbsoluteGate: false) - expected) < 1e-9)
    }

    /// Test 5's ungated mean is already the published answer, so it cannot be passed by gating harder —
    /// it is the vector that fails when the relative offset is too small.
    @Test("test 5 rejects an over-aggressive relative gate and cannot be passed by gating")
    func testFiveCatchesOverGating() throws {
        let vector = LoudnessTestVector.table1Test5
        let expected = try #require(vector.expectedLUFS)

        #expect(abs(LoudnessSegmentReduction.ungated(vector.segments) - expected) < 0.01)
        #expect(abs(LoudnessSegmentReduction.fullyGated(vector.segments) - expected) < 0.01)
        #expect(abs(LoudnessSegmentReduction.fullyGated(vector.segments, offset: 2.0) - expected) > 1.0)
    }

    /// Neither vector pins the relative offset on its own: test 3 fails when it is too large, test 5
    /// when it is too small. Together they bracket it, and the published −10 LU sits inside.
    @Test("tests 3 and 5 together bracket the relative gate's offset around the published 10 LU")
    func theGatingPairBracketsTheOffset() throws {
        let three = LoudnessTestVector.table1Test3
        let five = LoudnessTestVector.table1Test5
        let expectedThree = try #require(three.expectedLUFS)
        let expectedFive = try #require(five.expectedLUFS)

        func passes(_ vector: LoudnessTestVector, _ expected: Double, offset: Double) -> Bool {
            abs(LoudnessSegmentReduction.fullyGated(vector.segments, offset: offset) - expected)
                <= LoudnessTestVector.publishedTolerance
        }

        let accepted = stride(from: 0.5, through: 20.0, by: 0.5).filter {
            passes(three, expectedThree, offset: $0) && passes(five, expectedFive, offset: $0)
        }
        let lower = try #require(accepted.min())
        let upper = try #require(accepted.max())

        // The published offset is inside, and the bracket is genuinely bounded on both sides — which
        // is the whole claim: one vector alone would leave one side open.
        #expect(lower <= 10.0 && upper >= 10.0)
        #expect(lower > 0.5, "test 5 must close the bracket from below")
        #expect(upper < 20.0, "test 3 must close the bracket from above")

        // Each side is closed by a different vector, not by both.
        #expect(!passes(five, expectedFive, offset: 2.0))
        #expect(passes(three, expectedThree, offset: 2.0))
        #expect(!passes(three, expectedThree, offset: 15.0))
        #expect(passes(five, expectedFive, offset: 15.0))
    }

    // MARK: - The undefined cases, as semantics rather than as numbers

    /// The rule this product exists to keep: an absence is an absence. A vector that expects no value
    /// records the oracle's floor so a test can recognise it, and must never expose it as a reading.
    @Test("no vector that expects nothing carries a reading", arguments: LoudnessTestVector.notComputableVectors)
    func undefinedVectorsExposeNoReading(_ vector: LoudnessTestVector) {
        #expect(vector.expectedLUFS == nil, "\(vector.name)")
        guard case let .notComputable(floor) = vector.expectation else {
            Issue.record("\(vector.name) must expect no value")
            return
        }
        #expect(floor == -70.0, "the oracle's floor is recorded, not adopted")
    }

    /// Silence and a too-short programme reach the same outcome by different routes, and the boundary
    /// between "measured" and "not" is one frame wide.
    @Test("the block boundary is inclusive at 400 ms and empty one frame below it")
    func blockBoundaryIsExact() throws {
        let vectors = LoudnessTestVector.blockBoundaryVectors
        #expect(vectors.map(\.totalFrames) == [19_152, 19_200, 19_248])

        #expect(vectors[0].expectedLUFS == nil)
        let atBoundary = try #require(vectors[1].expectedLUFS)
        let justPast = try #require(vectors[2].expectedLUFS)
        #expect(atBoundary == -20.0)
        #expect(justPast == -20.0)

        // 400 ms at 48 kHz is a whole number of frames, so the edge is a frame count and not a rounding.
        #expect(Double(vectors[1].totalFrames) / 48_000 == 0.4)
    }

    @Test("the silent vectors are long enough to form blocks, so their absence is gating and not length")
    func silenceIsNotMerelyShort() {
        for vector in LoudnessTestVector.silenceVectors {
            #expect(vector.totalSeconds >= 1.0, "\(vector.name)")
            #expect(vector.segments.allSatisfy { $0.dBFS == nil }, "\(vector.name)")
        }
    }

    // MARK: - The writer round-trip

    /// One vector goes through the real file path, to show the generator and the writer agree. The rest
    /// are checked as signals: the writer is already covered by "Test support — audio fixtures", and
    /// writing 300 seconds of audio to prove it twice would buy nothing.
    @Test("a vector written as float PCM reads back as the signal it specifies")
    func vectorRoundTripsThroughAFile() async throws {
        let vector = LoudnessTestVector.calibration
        try await withTemporaryDirectory { directory in
            let url = try writeFloatPCMFixture(vector.fixtureSpec, in: directory)

            let metadata = try readBackMetadata(of: url)
            #expect(metadata.sampleRate == vector.sampleRate)
            #expect(metadata.channels == vector.channels)
            #expect(metadata.frames == AVAudioFramePosition(vector.totalFrames))

            let samples = try readBackSamples(of: url, channel: 0, limit: 4_800)
            #expect(samples.count == 4_800)
            for (frame, value) in samples.enumerated() {
                #expect(value == sample(vector, frame: frame))
            }
        }
    }
}

// MARK: - Collections used by the parameterised tests

extension LoudnessTestVector {
    /// Every vector whose generated signal is worth checking against its description.
    static let allForFixtureChecks: [LoudnessTestVector] =
        normativeVectors
            + [bs1770Anchor, bs1770AnchorAttenuated, monoAgainstStereo.mono]
            + blockBoundaryVectors
            + silenceVectors
            + sampleRateVectors

    /// The vectors for which the standard defines no value.
    static let notComputableVectors: [LoudnessTestVector] =
        blockBoundaryVectors.filter { $0.expectedLUFS == nil } + silenceVectors

    /// The reading a vector expects, or `nil` where the standard defines none.
    var expectedLUFS: Double? {
        if case let .measured(lufs, _) = expectation { return lufs }
        return nil
    }

    var expectedTolerance: Double? {
        if case let .measured(_, tolerance) = expectation { return tolerance }
        return nil
    }
}
