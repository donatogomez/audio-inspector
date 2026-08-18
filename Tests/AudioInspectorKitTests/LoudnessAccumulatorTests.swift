import Foundation
import Testing

@testable import AudioInspectorAnalysis
import AudioInspectorDomain

// The production accumulator against the targets that were fixed before it existed.
//
// Every expected value here comes from `LoudnessTestVector`, transcribed from EBU Tech 3341 and
// ITU-R BS.1770-5 in an earlier commit and **not touched since**. Nothing in this suite computes what
// the answer ought to be; where a test needs an intermediate, it uses a published relationship rather
// than a second implementation of the standard.

@Suite("Analysis — integrated loudness (48 kHz)")
struct LoudnessAccumulatorTests {

    // MARK: - What the accumulator will and will not accept

    @Test("mono and stereo at 48 kHz are accepted")
    func acceptsSupportedStreams() {
        #expect(LoudnessAccumulator(sampleRate: 48_000, channelCount: 1) != nil)
        #expect(LoudnessAccumulator(sampleRate: 48_000, channelCount: 2) != nil)
    }

    /// BS.1770-5 publishes coefficients for 48 kHz **only**, and asks other rates merely to match that
    /// response without saying how. Deriving them is a later task and a weaker compliance claim, so this
    /// version refuses rather than measuring with the wrong filter.
    @Test(
        "every rate other than 48 kHz is refused rather than measured with the wrong filter",
        arguments: [8_000.0, 44_100.0, 47_999.0, 48_001.0, 88_200.0, 96_000.0, 192_000.0]
    )
    func refusesOtherSampleRates(_ rate: Double) {
        #expect(LoudnessAccumulator(sampleRate: rate, channelCount: 2) == nil)
    }

    /// Beyond stereo the standard weights a channel by its **position**, and a three-channel file could
    /// carry an LFE the standard excludes entirely. The count alone cannot tell, so nothing is measured.
    @Test(
        "channel counts whose weighting cannot be determined are refused",
        arguments: [0, 3, 4, 6, 8]
    )
    func refusesUnknownChannelLayouts(_ channels: Int) {
        #expect(LoudnessAccumulator(sampleRate: 48_000, channelCount: channels) == nil)
    }

    /// The sizes are derived from the published duration and overlap, not written down a second time.
    @Test("the block and hop sizes follow from the published duration and overlap")
    func derivedSizesMatchTheStandard() throws {
        let accumulator = try #require(LoudnessAccumulator(sampleRate: 48_000, channelCount: 2))
        #expect(accumulator.blockFrames == 19_200) // 400 ms
        #expect(accumulator.hopFrames == 4_800) // 100 ms, i.e. 25 % of the block
        #expect(accumulator.subBlocksPerBlock == 4)
        #expect(accumulator.blockFrames == accumulator.subBlocksPerBlock * accumulator.hopFrames)
    }

    @Test("a chunk whose channel count disagrees is ignored rather than folded")
    func ignoresMismatchedChunks() throws {
        var accumulator = try #require(LoudnessAccumulator(sampleRate: 48_000, channelCount: 2))
        let mono = try PCMChunk(startFrame: 0, channels: [[Float](repeating: 0.5, count: 48_000)])
        accumulator.accumulate(mono)
        #expect(accumulator.blockEnergies.isEmpty)
        #expect(accumulator.finish() == nil)
    }

    // MARK: - The official targets

    /// EBU Tech 3341 §2.9 and Table 1 tests 1–5, each against its **published** expected reading and its
    /// **published** tolerance.
    @Test(
        "every published expectation is reproduced within the published tolerance",
        arguments: LoudnessTestVector.normativeVectors
    )
    func reproducesPublishedTargets(_ vector: LoudnessTestVector) throws {
        let expected = try #require(vector.expectedLUFS)
        let tolerance = try #require(vector.expectedTolerance)
        let value = try LoudnessAccumulatorHarness.measure(vector)
        let measured = try #require(value)
        #expect(
            abs(measured - expected) <= tolerance,
            "\(vector.name): measured \(measured), expected \(expected) ±\(tolerance)"
        )
    }

    /// BS.1770-5's own anchor. 997 Hz is where the −0.691 offset exactly cancels the K-weighting gain,
    /// so this pins the conversion offset far more sharply than a 1 kHz signal — which sits on a filter
    /// slope, as Tech 3341 §2.9 warns.
    @Test(
        "BS.1770-5's own calibration anchor is reproduced",
        arguments: [LoudnessTestVector.bs1770Anchor, LoudnessTestVector.bs1770AnchorAttenuated]
    )
    func reproducesTheITUAnchor(_ vector: LoudnessTestVector) throws {
        let expected = try #require(vector.expectedLUFS)
        let tolerance = try #require(vector.expectedTolerance)
        let value = try LoudnessAccumulatorHarness.measure(vector)
        let measured = try #require(value)
        #expect(
            abs(measured - expected) <= tolerance,
            "\(vector.name): measured \(measured), expected \(expected)"
        )
    }

    /// The channels are summed, not averaged — BS.1770-5 Table 3's equal weights.
    @Test("stereo reads 10·log₁₀2 above the same tone in mono")
    func stereoIsThreePointZeroOneAboveMono() throws {
        let pair = LoudnessTestVector.monoAgainstStereo
        let monoValue = try LoudnessAccumulatorHarness.measure(pair.mono)
        let stereoValue = try LoudnessAccumulatorHarness.measure(pair.stereo)
        let mono = try #require(monoValue)
        let stereo = try #require(stereoValue)
        #expect(abs((stereo - mono) - LoudnessTestVector.stereoOverMonoLU) <= 0.01)
    }

    // MARK: - The gates

    /// Test 4 is test 3 wrapped in −72 dBFS. Every added block falls below the absolute gate, so it is
    /// removed *before* the relative threshold is derived and the two programmes must produce **the same
    /// number**. Not merely within a tolerance: the surviving block set is identical, so the arithmetic
    /// is too.
    @Test("the absolute gate makes test 4 identical to test 3, not merely close")
    func absoluteGateRemovesTheQuietPassagesEntirely() throws {
        let threeValue = try LoudnessAccumulatorHarness.measure(.table1Test3)
        let fourValue = try LoudnessAccumulatorHarness.measure(.table1Test4)
        let three = try #require(threeValue)
        let four = try #require(fourValue)
        #expect(three == four)
    }

    /// The reading alone does **not** prove the absolute gate ran, and a negative control proved it: with
    /// the gate removed entirely, tests 3 and 4 still produce identical values, because the relative gate
    /// happens to exclude the same blocks by itself. The threshold is where the difference shows — the
    /// −72 dBFS passages drag the intermediate mean down by about a loudness unit before the subtraction,
    /// so with the gate working, test 4 must derive **test 3's** threshold rather than its own.
    @Test("the absolute gate is visible in the threshold, which the reading alone does not prove")
    func absoluteGateIsVisibleInTheDerivedThreshold() throws {
        var three = try #require(LoudnessAccumulator(sampleRate: 48_000, channelCount: 2))
        try LoudnessAccumulatorHarness.feed(.table1Test3, into: &three, chunkFrames: 4_096)
        var four = try #require(LoudnessAccumulator(sampleRate: 48_000, channelCount: 2))
        try LoudnessAccumulatorHarness.feed(.table1Test4, into: &four, chunkFrames: 4_096)

        let threeThreshold = try #require(three.relativeThreshold())
        let fourThreshold = try #require(four.relativeThreshold())
        // Close rather than equal, and the residual is real: test 4's extra transitions produce blocks
        // that *straddle* −72 dBFS and clear the gate, which test 3 has no counterpart for. Measured at
        // 0.032 LU. Without the absolute gate the same comparison is about **1 LU** out, so this bound
        // separates the two cases by a factor of thirty.
        #expect(
            abs(threeThreshold - fourThreshold) <= 0.1,
            "test 3 derived \(threeThreshold), test 4 derived \(fourThreshold)"
        )
        // And test 4 has strictly more blocks, so the agreement is gating rather than the two files
        // being the same programme.
        #expect(four.blockEnergies.count > three.blockEnergies.count)
    }

    /// Where the relative gate excludes nothing, eq. (6) makes the threshold exactly the reading minus
    /// 10 LU. Tests 1 and 5 are both such cases.
    @Test(
        "a programme the relative gate does not touch derives a threshold exactly 10 LU below its reading",
        arguments: [LoudnessTestVector.table1Test1, LoudnessTestVector.table1Test5]
    )
    func thresholdIsTenBelowWhereNothingIsExcluded(_ vector: LoudnessTestVector) throws {
        var accumulator = try #require(LoudnessAccumulator(sampleRate: 48_000, channelCount: 2))
        try LoudnessAccumulatorHarness.feed(vector, into: &accumulator, chunkFrames: 4_096)
        let threshold = try #require(accumulator.relativeThreshold())
        let reading = try #require(accumulator.finish())
        #expect(abs(threshold - (reading - LoudnessAccumulator.relativeGateOffset)) <= 0.05)
    }

    /// The gate is a strict inequality on the block's loudness at −70 LKFS. A stereo 1 kHz tone reads
    /// its own peak level, so a level either side of −70 brackets it.
    @Test("a programme just above the absolute gate measures and one just below does not")
    func absoluteGateBoundary() throws {
        let above = LoudnessAccumulatorHarness.tone(dBFS: -69.5, seconds: 2)
        let below = LoudnessAccumulatorHarness.tone(dBFS: -70.5, seconds: 2)

        let aboveValue = try LoudnessAccumulatorHarness.measure(above)
        let measured = try #require(aboveValue)
        #expect(abs(measured - (-69.5)) <= 0.1)
        let belowValue = try LoudnessAccumulatorHarness.measure(below)
        #expect(belowValue == nil)
    }

    /// A programme entirely below the gate forms blocks and then loses all of them — a different route to
    /// "no value" from having formed none, and the accumulator's own block count is what tells them
    /// apart.
    @Test("blocks below the gate are formed and then excluded, unlike blocks that never existed")
    func gatedAwayIsNotTheSameAsNeverFormed() throws {
        var gatedAway = try #require(LoudnessAccumulator(sampleRate: 48_000, channelCount: 2))
        try LoudnessAccumulatorHarness.feed(
            LoudnessAccumulatorHarness.tone(dBFS: -80, seconds: 2), into: &gatedAway, chunkFrames: 4_096
        )
        #expect(!gatedAway.blockEnergies.isEmpty, "blocks were formed")
        #expect(gatedAway.finish() == nil, "and every one was gated away")

        var tooShort = try #require(LoudnessAccumulator(sampleRate: 48_000, channelCount: 2))
        try LoudnessAccumulatorHarness.feed(
            LoudnessAccumulatorHarness.tone(dBFS: -20, seconds: 0.399), into: &tooShort, chunkFrames: 4_096
        )
        #expect(tooShort.blockEnergies.isEmpty, "no block was ever formed")
        #expect(tooShort.finish() == nil)
    }

    /// Test 5's ungated mean is already the published answer, so it cannot be passed by gating harder;
    /// test 3's is not, so it cannot be passed without gating. Both are checked above against their
    /// published values — this asserts the relative gate actually fired on one and not the other, which
    /// the readings alone do not show.
    @Test("the relative gate excludes test 3's quiet passages and leaves test 5's alone")
    func relativeGateFiresWhereItShould() throws {
        var three = try #require(LoudnessAccumulator(sampleRate: 48_000, channelCount: 2))
        try LoudnessAccumulatorHarness.feed(.table1Test3, into: &three, chunkFrames: 4_096)
        let threeAll = three.blockEnergies.count
        let threeGated = try #require(three.finish())

        var five = try #require(LoudnessAccumulator(sampleRate: 48_000, channelCount: 2))
        try LoudnessAccumulatorHarness.feed(.table1Test5, into: &five, chunkFrames: 4_096)
        let fiveAll = five.blockEnergies.count
        let fiveGated = try #require(five.finish())

        // The ungated mean of the blocks, which is what the reading would be with no relative gate.
        func ungated(_ energies: [Double]) -> Double {
            LoudnessAccumulator.loudness(of: LoudnessAccumulator.mean(of: energies))
        }
        #expect(abs(threeGated - ungated(three.blockEnergies)) > 1.0, "test 3's gate changed the answer")
        #expect(abs(fiveGated - ungated(five.blockEnergies)) <= 0.05, "test 5's gate changed nothing")
        #expect(threeAll > 0 && fiveAll > 0)
    }

    // MARK: - The block boundary and the trailing partial block

    /// Derived from BS.1770-5 eq. (3)'s index set: ⌊(T − 400 ms) / 100 ms⌋ is 0 at exactly 400 ms and
    /// negative below it.
    @Test(
        "the measurement boundary is exactly one block, inclusive",
        arguments: LoudnessTestVector.blockBoundaryVectors
    )
    func blockBoundaryIsInclusiveAt400ms(_ vector: LoudnessTestVector) throws {
        let measured = try LoudnessAccumulatorHarness.measure(vector)
        switch vector.expectation {
        case let .measured(expected, tolerance):
            let present = try #require(measured, "\(vector.name) should measure")
            #expect(abs(present - expected) <= tolerance, "\(vector.name): \(present)")
        case .notComputable:
            #expect(measured == nil, "\(vector.name) should not measure")
        }
    }

    /// An incomplete trailing block is discarded, not zero-padded: the frames past the last whole
    /// sub-block contribute nothing, so a programme with a partial tail reads the same as one truncated
    /// to its last whole hop.
    @Test("frames past the last whole hop are discarded rather than padded")
    func trailingPartialBlockIsDiscarded() throws {
        // 450 ms is four whole 100 ms hops plus 50 ms; 400 ms is the four hops alone.
        let tailValue = try LoudnessAccumulatorHarness.measure(
            LoudnessAccumulatorHarness.tone(dBFS: -20, seconds: 0.450)
        )
        let truncatedValue = try LoudnessAccumulatorHarness.measure(
            LoudnessAccumulatorHarness.tone(dBFS: -20, seconds: 0.400)
        )
        let withTail = try #require(tailValue)
        let truncated = try #require(truncatedValue)
        #expect(withTail == truncated)

        // And a fifth whole hop does add a block, so the discarding is of the partial tail only.
        var five = try #require(LoudnessAccumulator(sampleRate: 48_000, channelCount: 2))
        try LoudnessAccumulatorHarness.feed(
            LoudnessAccumulatorHarness.tone(dBFS: -20, seconds: 0.500), into: &five, chunkFrames: 4_096
        )
        #expect(five.blockEnergies.count == 2)

        var four = try #require(LoudnessAccumulator(sampleRate: 48_000, channelCount: 2))
        try LoudnessAccumulatorHarness.feed(
            LoudnessAccumulatorHarness.tone(dBFS: -20, seconds: 0.450), into: &four, chunkFrames: 4_096
        )
        #expect(four.blockEnergies.count == 1)
    }

    // MARK: - Not computable

    @Test(
        "digital silence yields no value, and never the gate's own level",
        arguments: LoudnessTestVector.silenceVectors
    )
    func silenceIsNotComputable(_ vector: LoudnessTestVector) throws {
        let measured = try LoudnessAccumulatorHarness.measure(vector)
        #expect(measured == nil, "\(vector.name)")
    }

    @Test("a stream with no frames at all yields no value")
    func emptyStreamIsNotComputable() throws {
        let accumulator = try #require(LoudnessAccumulator(sampleRate: 48_000, channelCount: 2))
        #expect(accumulator.finish() == nil)
    }

    // MARK: - Samples beyond full scale

    /// BS.1770-5's loudness path contains no clamp; its only attenuation is a headroom step in the
    /// *true-peak* Annex, which that text itself calls unnecessary in floating point.
    @Test("samples beyond full scale are measured, not limited")
    func aboveFullScaleIsMeasuredNotClamped() throws {
        let unityValue = try LoudnessAccumulatorHarness.measure(
            LoudnessAccumulatorHarness.tone(dBFS: 0, seconds: 2)
        )
        let unity = try #require(unityValue)
        for (amplitude, decibels) in [(1.5, 20 * log10(1.5)), (2.0, 20 * log10(2.0)), (8.0, 20 * log10(8.0))] {
            let loud = LoudnessAccumulatorHarness.tone(dBFS: 20 * log10(amplitude), seconds: 2)
            let loudValue = try LoudnessAccumulatorHarness.measure(loud)
            let measured = try #require(loudValue)
            #expect(measured.isFinite)
            #expect(
                abs((measured - unity) - decibels) <= 0.01,
                "amplitude \(amplitude) read \(measured), unity read \(unity)"
            )
        }
    }

    // MARK: - Chunk independence

    /// **Exact**, not within a tolerance. A loudness figure that moved with the decoder's buffer size
    /// would be a reproducibility defect at any magnitude, and this is the assertion that made
    /// `vDSP_biquadD` unusable here: it differed in the last two or three digits across these sizes.
    @Test(
        "the result is bit-identical at every chunk size",
        arguments: [
            LoudnessAccumulatorHarness.tone(dBFS: -18, seconds: 2),
            LoudnessAccumulatorHarness.segments([(-36.0, 0.5), (-23.0, 3.0), (-36.0, 0.5)]),
            LoudnessAccumulatorHarness.segments([(-72.0, 0.5), (-36.0, 0.5), (-23.0, 3.0), (-72.0, 0.5)]),
            LoudnessAccumulatorHarness.tone(dBFS: nil, seconds: 1),
            LoudnessAccumulatorHarness.tone(dBFS: 20 * log10(1.5), seconds: 1),
        ]
    )
    func resultIsIdenticalAtEveryChunkSize(_ vector: LoudnessTestVector) throws {
        let reference = try LoudnessAccumulatorHarness.measure(vector, chunkFrames: nil)
        for size in [1, 3, 127, 512, 4_096, 65_536] {
            let measured = try LoudnessAccumulatorHarness.measure(vector, chunkFrames: size)
            #expect(measured == reference, "\(vector.name) at \(size): \(measured ?? .nan)")
        }
    }

    /// The published gating vectors are 80 and 100 seconds long, so one frame per chunk would mean nearly
    /// four million chunks. They are covered here at every size the suite can afford; the shapes above
    /// carry the same structure at 1 and 3.
    @Test(
        "the published gating vectors are identical at every practical chunk size",
        arguments: [LoudnessTestVector.table1Test3, LoudnessTestVector.table1Test4]
    )
    func publishedGatingVectorsAreChunkIndependent(_ vector: LoudnessTestVector) throws {
        let reference = try LoudnessAccumulatorHarness.measure(vector, chunkFrames: nil)
        for size in [512, 4_096, 65_536] {
            let measured = try LoudnessAccumulatorHarness.measure(vector, chunkFrames: size)
            #expect(measured == reference, "\(vector.name) at \(size)")
        }
    }

    // MARK: - Per-channel state

    /// The two channels' filters must not share state. Silence in the right channel contributes no
    /// energy, so a stereo pair of (tone, silence) must read exactly what the tone reads in mono — any
    /// bleed between the filters would move it.
    @Test("the channels' filter states are independent")
    func channelStatesDoNotShare() throws {
        let frames = 48_000 * 2
        let tone = LoudnessAccumulatorHarness.tone(dBFS: -20, seconds: 2, channels: 1)
        let plane = tone.signal.samples(channel: 0, from: 0, count: frames, sampleRate: 48_000)

        var mono = try #require(LoudnessAccumulator(sampleRate: 48_000, channelCount: 1))
        try LoudnessAccumulatorHarness.feed(planes: [plane], chunkFrames: 4_096, into: &mono)

        var stereo = try #require(LoudnessAccumulator(sampleRate: 48_000, channelCount: 2))
        try LoudnessAccumulatorHarness.feed(
            planes: [plane, [Float](repeating: 0, count: frames)], chunkFrames: 4_096, into: &stereo
        )

        let monoResult = try #require(mono.finish())
        let stereoResult = try #require(stereo.finish())
        #expect(monoResult == stereoResult)
    }

    /// And the reverse: a tone in the *right* channel alone reads the same as the same tone in the left
    /// alone. If the two shared a filter, the order the channels are folded in would matter.
    @Test("which channel carries the signal does not change the reading")
    func channelOrderDoesNotMatter() throws {
        let frames = 48_000 * 2
        let tone = LoudnessAccumulatorHarness.tone(dBFS: -20, seconds: 2, channels: 1)
        let plane = tone.signal.samples(channel: 0, from: 0, count: frames, sampleRate: 48_000)
        let silence = [Float](repeating: 0, count: frames)

        var left = try #require(LoudnessAccumulator(sampleRate: 48_000, channelCount: 2))
        try LoudnessAccumulatorHarness.feed(planes: [plane, silence], chunkFrames: 4_096, into: &left)

        var right = try #require(LoudnessAccumulator(sampleRate: 48_000, channelCount: 2))
        try LoudnessAccumulatorHarness.feed(planes: [silence, plane], chunkFrames: 4_096, into: &right)

        let leftResult = try #require(left.finish())
        let rightResult = try #require(right.finish())
        #expect(leftResult == rightResult)
    }
}
