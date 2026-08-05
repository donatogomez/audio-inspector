import AudioInspectorDomain
import Testing

// The reduction's rules, over plain numbers. These are the assertions that keep the drawing honest —
// no averaging, no normalisation, opposing phase does not cancel — and they are unit tests precisely
// so they cannot be weakened later by a fixture that happens to agree.

@Suite("Domain — waveform reduction")
struct WaveformEnvelopeAccumulatorTests {
    /// Feeds whole channels at once, cut into runs of `chunk` frames, exactly as a chunked reader
    /// would. `channels[c][f]` is channel `c`'s sample at frame `f`.
    private func reduce(
        channels: [[Float]],
        maximumBucketCount: Int,
        chunk: Int
    ) throws -> WaveformEnvelope {
        let frameCount = channels.first?.count ?? 0
        var accumulator = try #require(
            WaveformEnvelopeAccumulator(
                totalFrameCount: frameCount,
                channelCount: channels.count,
                maximumBucketCount: maximumBucketCount
            )
        )
        var start = 0
        while start < frameCount {
            let end = min(start + chunk, frameCount)
            for (index, samples) in channels.enumerated() {
                try accumulator.accumulate(samples[start ..< end], ofChannel: index, startingAtFrame: start)
            }
            start = end
        }
        return try accumulator.finished()
    }

    // MARK: Shape

    @Test("a single frame yields a single bucket holding that sample")
    func singleFrame() throws {
        let envelope = try reduce(channels: [[0.4]], maximumBucketCount: 2_048, chunk: 8)
        #expect(envelope.buckets.count == 1)
        #expect(envelope.frameCount == 1)
        #expect(envelope.buckets[0].minimum == 0.4)
        #expect(envelope.buckets[0].maximum == 0.4)
    }

    @Test("fewer frames than buckets gives one bucket per frame, never empty padding")
    func fewerFramesThanBuckets() throws {
        let envelope = try reduce(channels: [[0.1, -0.2, 0.3]], maximumBucketCount: 2_048, chunk: 2)
        #expect(envelope.buckets.count == 3)
        #expect(envelope.buckets.map(\.maximum) == [0.1, -0.2, 0.3])
    }

    @Test("a file with no frames reduces to an envelope with no buckets")
    func noFrames() throws {
        // Built through the production default, so the injectable cap and its default agree.
        let accumulator = try #require(WaveformEnvelopeAccumulator(totalFrameCount: 0, channelCount: 2))
        let envelope = try accumulator.finished()
        #expect(envelope.buckets.isEmpty)
        #expect(envelope.frameCount == 0)
        #expect(envelope.channelCount == 2)
    }

    @Test("an evenly divisible file fills every bucket equally")
    func evenlyDivisible() throws {
        let samples = (0 ..< 100).map { Float($0) / 100 }
        let envelope = try reduce(channels: [samples], maximumBucketCount: 10, chunk: 7)
        #expect(envelope.buckets.count == 10)
        // Bucket b covers frames 10b ..< 10b+10, so its maximum is frame 10b+9.
        for index in 0 ..< 10 {
            #expect(envelope.buckets[index].maximum == Float(index * 10 + 9) / 100)
        }
    }

    @Test("a final partial bucket is included rather than dropped")
    func finalPartialBucketIsIncluded() throws {
        let samples = (0 ..< 101).map { Float($0) / 1_000 }
        let envelope = try reduce(channels: [samples], maximumBucketCount: 10, chunk: 16)
        #expect(envelope.buckets.count == 10)
        #expect(envelope.frameCount == 101)
        // The last frame must be represented, whatever the uneven split does to the boundaries.
        #expect(envelope.buckets[9].maximum == Float(100) / 1_000)
    }

    @Test("a prime frame count is reduced without losing the tail")
    func primeFrameCount() throws {
        let samples = (0 ..< 44_101).map { Float($0 % 7) / 10 }
        let envelope = try reduce(channels: [samples], maximumBucketCount: 2_048, chunk: 1_024)
        #expect(envelope.buckets.count == 2_048)
        #expect(envelope.frameCount == 44_101)
    }

    @Test("the bucket cap is never exceeded", arguments: [1, 2, 31, 2_048])
    func neverExceedsTheCap(maximumBucketCount: Int) throws {
        let samples = (0 ..< 5_000).map { Float($0 % 11) / 20 }
        let envelope = try reduce(channels: [samples], maximumBucketCount: maximumBucketCount, chunk: 97)
        #expect(envelope.buckets.count == maximumBucketCount)
        #expect(envelope.buckets.count <= 2_048)
    }

    // MARK: Content

    @Test("silence reduces to zero, not to an absence")
    func silence() throws {
        let envelope = try reduce(channels: [[Float](repeating: 0, count: 500)], maximumBucketCount: 16, chunk: 64)
        #expect(envelope.buckets.count == 16)
        #expect(envelope.buckets.allSatisfy { $0.minimum == 0 && $0.maximum == 0 })
    }

    @Test("a positive impulse survives in exactly one bucket")
    func positiveImpulse() throws {
        var samples = [Float](repeating: 0, count: 400)
        samples[250] = 0.8
        let envelope = try reduce(channels: [samples], maximumBucketCount: 8, chunk: 33)

        let loud = envelope.buckets.filter { $0.maximum != 0 }
        #expect(loud.count == 1)
        #expect(loud.first?.maximum == 0.8)
        #expect(envelope.buckets[5].maximum == 0.8, "250 * 8 / 400 = 5")
    }

    @Test("a negative impulse survives as a minimum, not as a magnitude")
    func negativeImpulse() throws {
        var samples = [Float](repeating: 0, count: 400)
        samples[250] = -0.8
        let envelope = try reduce(channels: [samples], maximumBucketCount: 8, chunk: 33)

        #expect(envelope.buckets[5].minimum == -0.8)
        #expect(envelope.buckets[5].maximum == 0, "the rest of the bucket is silent")
    }

    @Test("a signal close to full scale keeps its amplitude")
    func nearFullScale() throws {
        let samples = (0 ..< 200).map { $0.isMultiple(of: 2) ? Float(0.99) : Float(-0.99) }
        let envelope = try reduce(channels: [samples], maximumBucketCount: 4, chunk: 16)
        #expect(envelope.buckets.allSatisfy { $0.minimum == -0.99 && $0.maximum == 0.99 })
    }

    @Test("samples beyond the nominal range are preserved, never clamped")
    func beyondTheNominalRangeIsPreserved() throws {
        let samples: [Float] = [-1.5, -1, -0.25, 0, 0.25, 1, 1.5]
        let envelope = try reduce(channels: [samples], maximumBucketCount: 1, chunk: 3)
        #expect(envelope.buckets.count == 1)
        #expect(envelope.buckets[0].minimum == -1.5)
        #expect(envelope.buckets[0].maximum == 1.5)
    }

    @Test("nothing is normalised: two levels of the same signal stay proportional")
    func noNormalisation() throws {
        let quiet = (0 ..< 300).map { Float($0 % 10) / 100 }
        let loud = quiet.map { $0 * 8 }

        let quietEnvelope = try reduce(channels: [quiet], maximumBucketCount: 10, chunk: 32)
        let loudEnvelope = try reduce(channels: [loud], maximumBucketCount: 10, chunk: 32)

        for index in quietEnvelope.buckets.indices {
            #expect(loudEnvelope.buckets[index].maximum == quietEnvelope.buckets[index].maximum * 8)
        }
    }

    // MARK: Channels

    @Test("identical channels give the same envelope as one channel alone")
    func identicalChannels() throws {
        let samples = (0 ..< 300).map { Float($0 % 13) / 20 - 0.3 }
        let mono = try reduce(channels: [samples], maximumBucketCount: 12, chunk: 40)
        let stereo = try reduce(channels: [samples, samples], maximumBucketCount: 12, chunk: 40)

        #expect(mono.buckets == stereo.buckets)
        #expect(stereo.channelCount == 2)
    }

    @Test("channels in opposing polarity do not cancel")
    func oppositePolarityDoesNotCancel() throws {
        let left = (0 ..< 300).map { Float($0 % 10) / 10 }
        let right = left.map { -$0 }

        let envelope = try reduce(channels: [left, right], maximumBucketCount: 10, chunk: 64)

        // An average would flatten this to zero everywhere. The combined envelope must not.
        #expect(envelope.buckets.contains { $0.maximum > 0.5 })
        #expect(envelope.buckets.contains { $0.minimum < -0.5 })
        for bucket in envelope.buckets {
            #expect(bucket.minimum == -bucket.maximum, "the extremes mirror, because the channels do")
        }
    }

    @Test("more than two channels all contribute")
    func manyChannels() throws {
        let frames = 240
        let channels: [[Float]] = (0 ..< 4).map { channel in
            (0 ..< frames).map { _ in Float(channel + 1) / 10 }
        }
        let envelope = try reduce(channels: channels, maximumBucketCount: 6, chunk: 50)

        #expect(envelope.channelCount == 4)
        // The extremes span the quietest and loudest channel, not any single one and not their mean.
        #expect(envelope.buckets.allSatisfy { abs($0.minimum - 0.1) < 1e-6 })
        #expect(envelope.buckets.allSatisfy { abs($0.maximum - 0.4) < 1e-6 })
    }

    // MARK: Chunk independence

    @Test(
        "the same file reduces identically at every chunk size",
        arguments: [1, 2, 3, 7, 31, 64, 127, 1_024, 4_096]
    )
    func chunkSizeDoesNotChangeTheResult(chunk: Int) throws {
        let left = (0 ..< 44_101).map { Float(($0 * 7) % 101) / 100 - 0.5 }
        let right = (0 ..< 44_101).map { Float(($0 * 13) % 97) / 100 - 0.5 }

        let reference = try reduce(channels: [left, right], maximumBucketCount: 2_048, chunk: 44_101)
        let chunked = try reduce(channels: [left, right], maximumBucketCount: 2_048, chunk: chunk)

        #expect(chunked == reference)
    }

    // MARK: Refusals

    @Test("a sample that is not a number is refused, never treated as quiet", arguments: [
        Float.nan, Float.infinity, -Float.infinity, Float.signalingNaN,
    ])
    func refusesNonFiniteSamples(sample: Float) throws {
        var accumulator = try #require(WaveformEnvelopeAccumulator(totalFrameCount: 4, channelCount: 1))
        let error = #expect(throws: WaveformError.self) {
            try accumulator.accumulate([0, sample, 0, 0], ofChannel: 0, startingAtFrame: 0)
        }
        #expect(error?.code == .nonFiniteSample)
    }

    @Test("samples for a channel the file does not have are refused")
    func refusesUnknownChannel() throws {
        var accumulator = try #require(WaveformEnvelopeAccumulator(totalFrameCount: 4, channelCount: 2))
        let error = #expect(throws: WaveformError.self) {
            try accumulator.accumulate([0, 0, 0, 0], ofChannel: 2, startingAtFrame: 0)
        }
        #expect(error?.code == .channelOutOfBounds)
    }

    @Test("samples outside the file's frame range are refused", arguments: [(0, 5), (3, 2), (-1, 1)])
    func refusesFramesOutsideTheFile(startFrame: Int, count: Int) throws {
        var accumulator = try #require(WaveformEnvelopeAccumulator(totalFrameCount: 4, channelCount: 1))
        let error = #expect(throws: WaveformError.self) {
            try accumulator.accumulate([Float](repeating: 0, count: count), ofChannel: 0, startingAtFrame: startFrame)
        }
        #expect(error?.code == .frameRangeOutOfBounds)
    }

    @Test("finishing before the whole file was seen is refused, not filled with invented silence")
    func refusesIncompleteCoverage() throws {
        var accumulator = try #require(
            WaveformEnvelopeAccumulator(totalFrameCount: 100, channelCount: 1, maximumBucketCount: 10)
        )
        try accumulator.accumulate([Float](repeating: 0.5, count: 50), ofChannel: 0, startingAtFrame: 0)

        let error = #expect(throws: WaveformError.self) { try accumulator.finished() }
        #expect(error?.code == .incompleteCoverage)
    }

    @Test("an unusable configuration yields no accumulator at all", arguments: [(-1, 1, 2_048), (10, 0, 2_048), (10, 1, 0)])
    func refusesUnusableConfiguration(totalFrameCount: Int, channelCount: Int, maximumBucketCount: Int) {
        #expect(
            WaveformEnvelopeAccumulator(
                totalFrameCount: totalFrameCount,
                channelCount: channelCount,
                maximumBucketCount: maximumBucketCount
            ) == nil
        )
    }
}
