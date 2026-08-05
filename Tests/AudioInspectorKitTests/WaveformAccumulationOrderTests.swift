import AudioInspectorDomain
import Testing

// The accumulator promises that the envelope does not depend on the order runs arrive in. That
// promise is what lets a reader feed it whatever way the API it reads from happens to deliver
// channels, so it is pinned here rather than left as a property that merely happens to hold today.
//
// The signal is deliberately asymmetric: each channel peaks in a different place, one channel carries
// a lone sample beyond the nominal range, and the frame count is prime so no chunk size divides it
// evenly. Any order sensitivity shows up as a different envelope rather than as a coincidence.

@Suite("Domain — waveform accumulation order")
struct WaveformAccumulationOrderTests {
    private let frameCount = 1_009 // prime
    private let channelCount = 3
    private let maximumBucketCount = 16
    private let chunk = 97

    private func sample(channel: Int, frame: Int) -> Float {
        switch channel {
        case 0: Float((frame * 7) % 199) / 100 - 1
        case 1: Float((frame * 13) % 97) / 50 - 1
        default: frame == 613 ? 2.5 : Float((frame * 3) % 41) / 80
        }
    }

    private var planes: [[Float]] {
        (0 ..< channelCount).map { channel in
            (0 ..< frameCount).map { sample(channel: channel, frame: $0) }
        }
    }

    private func makeAccumulator() throws -> WaveformEnvelopeAccumulator {
        try #require(
            WaveformEnvelopeAccumulator(
                totalFrameCount: frameCount,
                channelCount: channelCount,
                maximumBucketCount: maximumBucketCount
            )
        )
    }

    private var chunkStarts: [Int] {
        var starts: [Int] = []
        var start = 0
        while start < frameCount {
            starts.append(start)
            start += chunk
        }
        return starts
    }

    // MARK: The six orders

    /// 1. One whole channel at a time, channels ascending. Also the reference every other order is
    /// compared against.
    private func wholeChannelsAscending() throws -> WaveformEnvelope {
        var accumulator = try makeAccumulator()
        for channel in 0 ..< channelCount {
            try accumulator.accumulate(planes[channel], ofChannel: channel, startingAtFrame: 0)
        }
        return try accumulator.finished()
    }

    /// 2. One whole channel at a time, channels descending.
    private func wholeChannelsDescending() throws -> WaveformEnvelope {
        var accumulator = try makeAccumulator()
        for channel in (0 ..< channelCount).reversed() {
            try accumulator.accumulate(planes[channel], ofChannel: channel, startingAtFrame: 0)
        }
        return try accumulator.finished()
    }

    /// 3. Chunk by chunk, front to back, channels in order inside each chunk — what a chunked reader
    /// of a planar buffer actually does.
    private func chunksAscending() throws -> WaveformEnvelope {
        var accumulator = try makeAccumulator()
        for start in chunkStarts {
            let end = min(start + chunk, frameCount)
            for channel in 0 ..< channelCount {
                try accumulator.accumulate(planes[channel][start ..< end], ofChannel: channel, startingAtFrame: start)
            }
        }
        return try accumulator.finished()
    }

    /// 4. The same chunks, delivered back to front.
    private func chunksDescending() throws -> WaveformEnvelope {
        var accumulator = try makeAccumulator()
        for start in chunkStarts.reversed() {
            let end = min(start + chunk, frameCount)
            for channel in 0 ..< channelCount {
                try accumulator.accumulate(planes[channel][start ..< end], ofChannel: channel, startingAtFrame: start)
            }
        }
        return try accumulator.finished()
    }

    /// 5. One frame at a time — the finest granularity the API allows.
    private func frameByFrame() throws -> WaveformEnvelope {
        var accumulator = try makeAccumulator()
        for frame in 0 ..< frameCount {
            for channel in 0 ..< channelCount {
                try accumulator.accumulate(
                    planes[channel][frame ..< frame + 1],
                    ofChannel: channel,
                    startingAtFrame: frame
                )
            }
        }
        return try accumulator.finished()
    }

    /// 6. Chunks back to front, channels rotated inside each one, and runs of differing length.
    /// Legal, pathological, and exactly the sort of thing a future reader might do by accident.
    private func mixedOrder() throws -> WaveformEnvelope {
        var accumulator = try makeAccumulator()
        let rotations = [[1, 2, 0], [2, 0, 1], [0, 1, 2]]
        for (index, start) in chunkStarts.reversed().enumerated() {
            let end = min(start + chunk, frameCount)
            let middle = start + (end - start) / 2
            for channel in rotations[index % rotations.count] {
                // Split each chunk in two, so run lengths differ from every other order as well.
                try accumulator.accumulate(planes[channel][start ..< middle], ofChannel: channel, startingAtFrame: start)
                try accumulator.accumulate(planes[channel][middle ..< end], ofChannel: channel, startingAtFrame: middle)
            }
        }
        return try accumulator.finished()
    }

    // MARK: The guarantee

    @Test("every feeding order produces exactly the same envelope")
    func everyOrderAgrees() throws {
        let reference = try wholeChannelsAscending()

        let orders: [(String, WaveformEnvelope)] = [
            ("whole channels descending", try wholeChannelsDescending()),
            ("chunks ascending", try chunksAscending()),
            ("chunks descending", try chunksDescending()),
            ("frame by frame", try frameByFrame()),
            ("mixed channel and chunk order", try mixedOrder()),
        ]

        for (name, envelope) in orders {
            #expect(envelope == reference, "\(name) disagreed with whole channels ascending")
        }
    }

    @Test("the reference envelope is not trivially uniform, so agreement means something")
    func theSignalWouldExposeOrderSensitivity() throws {
        let envelope = try wholeChannelsAscending()

        #expect(envelope.buckets.count == maximumBucketCount)
        #expect(envelope.frameCount == frameCount)
        #expect(envelope.channelCount == channelCount)

        // Buckets differ from one another: a uniform envelope would agree under any order for the
        // wrong reason.
        #expect(Set(envelope.buckets.map(\.maximum)).count > 1)
        #expect(Set(envelope.buckets.map(\.minimum)).count > 1)

        // The lone out-of-range sample survives, in exactly one bucket, unclamped.
        let outOfRange = envelope.buckets.filter { $0.maximum > 1 }
        #expect(outOfRange.count == 1)
        #expect(outOfRange.first?.maximum == 2.5)
    }
}
