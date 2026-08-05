import AudioInspectorDomain
import Testing

// The waveform model's invariants, over plain numbers. No file, no framework, no fixture: everything
// the reduction promises is a property of arithmetic, and is proved here rather than inferred from an
// integration test that happens to pass.

@Suite("Domain — waveform bucket")
struct WaveformBucketTests {
    @Test("a bucket accepts ordered finite extremes")
    func acceptsOrderedFiniteExtremes() throws {
        let bucket = try #require(WaveformBucket(minimum: -0.5, maximum: 0.25))
        #expect(bucket.minimum == -0.5)
        #expect(bucket.maximum == 0.25)
    }

    @Test("a bucket accepts a single value as both extremes")
    func acceptsAPoint() throws {
        let bucket = try #require(WaveformBucket(minimum: 0.1, maximum: 0.1))
        #expect(bucket.minimum == bucket.maximum)
    }

    @Test("silence is zero to zero")
    func silenceIsZero() {
        #expect(WaveformBucket.silent.minimum == 0)
        #expect(WaveformBucket.silent.maximum == 0)
    }

    @Test("a bucket rejects extremes in the wrong order")
    func rejectsInvertedExtremes() {
        #expect(WaveformBucket(minimum: 0.5, maximum: -0.5) == nil)
    }

    @Test("values beyond the nominal range are kept, not clamped", arguments: [
        (Float(-1.5), Float(1.5)),
        (Float(-4), Float(-2)),
        (Float(2), Float(9)),
    ])
    func keepsValuesBeyondTheNominalRange(minimum: Float, maximum: Float) throws {
        let bucket = try #require(WaveformBucket(minimum: minimum, maximum: maximum))
        #expect(bucket.minimum == minimum)
        #expect(bucket.maximum == maximum)
    }

    @Test("a bucket rejects values that are not numbers", arguments: [
        (Float.nan, Float(0)),
        (Float(0), Float.nan),
        (Float.nan, Float.nan),
        (Float.signalingNaN, Float(0)),
    ])
    func rejectsNotANumber(minimum: Float, maximum: Float) {
        #expect(WaveformBucket(minimum: minimum, maximum: maximum) == nil)
    }

    @Test("a bucket rejects infinities", arguments: [
        (-Float.infinity, Float(0)),
        (Float(0), Float.infinity),
        (-Float.infinity, Float.infinity),
    ])
    func rejectsInfinities(minimum: Float, maximum: Float) {
        #expect(WaveformBucket(minimum: minimum, maximum: maximum) == nil)
    }

    @Test("buckets compare by value")
    func comparesByValue() throws {
        let one = try #require(WaveformBucket(minimum: -0.2, maximum: 0.3))
        let same = try #require(WaveformBucket(minimum: -0.2, maximum: 0.3))
        let other = try #require(WaveformBucket(minimum: -0.2, maximum: 0.4))
        #expect(one == same)
        #expect(one != other)
    }
}

@Suite("Domain — waveform envelope")
struct WaveformEnvelopeStructureTests {
    private func bucket(_ minimum: Float, _ maximum: Float) throws -> WaveformBucket {
        try #require(WaveformBucket(minimum: minimum, maximum: maximum))
    }

    @Test("an envelope keeps its buckets, frame count and channel count")
    func keepsItsParts() throws {
        let envelope = try #require(
            WaveformEnvelope(buckets: [try bucket(-1, 1), try bucket(0, 0)], frameCount: 8, channelCount: 2)
        )
        #expect(envelope.buckets.count == 2)
        #expect(envelope.frameCount == 8)
        #expect(envelope.channelCount == 2)
    }

    @Test("a file with no frames has an envelope with no buckets")
    func emptyIsValid() throws {
        let envelope = try #require(WaveformEnvelope.empty(channelCount: 2))
        #expect(envelope.buckets.isEmpty)
        #expect(envelope.frameCount == 0)
    }

    @Test("buckets without frames, or frames without buckets, are not representable")
    func emptinessMustAgreeWithTheFrameCount() throws {
        #expect(WaveformEnvelope(buckets: [try bucket(0, 0)], frameCount: 0, channelCount: 1) == nil)
        #expect(WaveformEnvelope(buckets: [], frameCount: 4, channelCount: 1) == nil)
    }

    @Test("an envelope cannot have more buckets than frames")
    func bucketsCannotOutnumberFrames() throws {
        #expect(
            WaveformEnvelope(
                buckets: [try bucket(0, 0), try bucket(0, 0), try bucket(0, 0)],
                frameCount: 2,
                channelCount: 1
            ) == nil
        )
    }

    @Test("an envelope rejects impossible descriptions", arguments: [(-1, 1), (4, 0), (4, -2)])
    func rejectsImpossibleDescriptions(frameCount: Int, channelCount: Int) {
        #expect(WaveformEnvelope(buckets: [], frameCount: frameCount, channelCount: channelCount) == nil)
    }

    @Test("envelopes compare by value")
    func comparesByValue() throws {
        let one = try #require(WaveformEnvelope(buckets: [try bucket(-1, 1)], frameCount: 4, channelCount: 1))
        let same = try #require(WaveformEnvelope(buckets: [try bucket(-1, 1)], frameCount: 4, channelCount: 1))
        let other = try #require(WaveformEnvelope(buckets: [try bucket(-1, 1)], frameCount: 4, channelCount: 2))
        #expect(one == same)
        #expect(one != other)
    }
}

@Suite("Domain — waveform bucket mapping")
struct WaveformBucketMappingTests {
    @Test("the bucket count is the frame count capped by the maximum")
    func bucketCountIsCapped() throws {
        let long = try #require(WaveformBucketMapping(totalFrameCount: 100_000, maximumBucketCount: 2_048))
        #expect(long.bucketCount == 2_048)

        let short = try #require(WaveformBucketMapping(totalFrameCount: 300, maximumBucketCount: 2_048))
        #expect(short.bucketCount == 300)
    }

    @Test("the production cap is 2048")
    func productionCapIsTwoThousandFortyEight() throws {
        let mapping = try #require(WaveformBucketMapping(totalFrameCount: 1_000_000))
        #expect(WaveformBucketMapping.defaultMaximumBucketCount == 2_048)
        #expect(mapping.bucketCount == 2_048)
    }

    @Test("an unusable description is refused", arguments: [(-1, 2_048), (10, 0), (10, -5)])
    func refusesUnusableDescriptions(totalFrameCount: Int, maximumBucketCount: Int) {
        #expect(WaveformBucketMapping(totalFrameCount: totalFrameCount, maximumBucketCount: maximumBucketCount) == nil)
    }

    @Test("a frame count large enough to overflow the mapping is refused")
    func refusesOverflowingSizes() {
        #expect(WaveformBucketMapping(totalFrameCount: Int.max, maximumBucketCount: 2_048) == nil)
        #expect(WaveformBucketMapping(totalFrameCount: Int.max / 2_048 + 1, maximumBucketCount: 2_048) == nil)
        #expect(WaveformBucketMapping(totalFrameCount: Int.max / 2_048, maximumBucketCount: 2_048) != nil)
    }

    @Test("frames outside the file map to nothing")
    func framesOutsideTheFileMapToNothing() throws {
        let mapping = try #require(WaveformBucketMapping(totalFrameCount: 10, maximumBucketCount: 4))
        #expect(mapping.bucketIndex(forFrame: -1) == nil)
        #expect(mapping.bucketIndex(forFrame: 10) == nil)
        #expect(mapping.bucketIndex(forFrame: 9) != nil)
    }

    /// The property the whole envelope rests on: the map is total and single-valued over the file, so
    /// no frame is lost and none is counted twice — including at sizes that do not divide evenly.
    @Test(
        "every frame lands in exactly one bucket, and every bucket receives at least one frame",
        arguments: [
            (1, 2_048), (2, 2_048), (7, 4), (10, 4), (100, 7), (2_048, 2_048),
            (4_096, 2_048), (44_100, 2_048), (44_101, 2_048), (44_101, 31), (99_991, 2_048),
        ]
    )
    func mappingIsTotalAndCovering(totalFrameCount: Int, maximumBucketCount: Int) throws {
        let mapping = try #require(
            WaveformBucketMapping(totalFrameCount: totalFrameCount, maximumBucketCount: maximumBucketCount)
        )
        #expect(mapping.bucketCount == min(totalFrameCount, maximumBucketCount))

        var perBucket = [Int](repeating: 0, count: mapping.bucketCount)
        for frame in 0 ..< totalFrameCount {
            let index = try #require(mapping.bucketIndex(forFrame: frame))
            #expect(index >= 0 && index < mapping.bucketCount)
            perBucket[index] += 1
        }

        #expect(perBucket.reduce(0, +) == totalFrameCount, "every frame counted exactly once")
        #expect(perBucket.allSatisfy { $0 >= 1 }, "no bucket left empty")
    }

    @Test("the mapping is monotonic, so buckets follow the file's order")
    func mappingIsMonotonic() throws {
        let mapping = try #require(WaveformBucketMapping(totalFrameCount: 44_101, maximumBucketCount: 2_048))
        var previous = 0
        for frame in 0 ..< mapping.totalFrameCount {
            let index = try #require(mapping.bucketIndex(forFrame: frame))
            #expect(index >= previous)
            previous = index
        }
        #expect(previous == mapping.bucketCount - 1, "the last frame lands in the last bucket")
    }
}
