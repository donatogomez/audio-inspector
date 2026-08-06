import AudioInspectorDomain
import AudioInspectorTesting
import Testing

// The port fake, so Analysis and feature tests can fold real chunks without a real file. What matters
// is that it can script every outcome the port has and cannot quietly merge two of them.

@Suite("Testing support — PCM decoding fake")
struct FakeAudioDecodingTests {
    private func reference() -> AudioFileReference {
        AudioFileReference(
            displayName: "fixture", fileExtension: nil, sizeBytes: nil, modifiedAt: nil,
            source: .userSelectedLocalFile(displayName: "fixture", locationDisclosure: .omitted)
        )
    }

    private func stream(frameCount: Int = 6, channels: Int = 1) throws -> PCMStreamDescription {
        try #require(PCMStreamDescription(sampleRate: 44_100, channelCount: channels, frameCount: frameCount))
    }

    private func chunks(count: Int, framesEach: Int = 2) throws -> [PCMChunk] {
        try (0 ..< count).map { index in
            try PCMChunk(
                startFrame: index * framesEach,
                channels: [(0 ..< framesEach).map { Float(index * framesEach + $0) / 100 }]
            )
        }
    }

    @Test("a scripted stream is handed over chunk by chunk, in order")
    func replaysAStream() async throws {
        let description = try stream()
        let scripted = try chunks(count: 3)
        let fake = FakeAudioDecoding(streaming: description, chunks: scripted)

        var seen: [Int] = []
        let produced = try await fake.decode(reference(), chunkFrames: 2) { chunk in
            seen.append(chunk.startFrame)
            return .continue
        }

        #expect(produced == description)
        #expect(seen == [0, 2, 4])
    }

    /// The callback is synchronous and non-escaping here too, so a test folding chunks needs no actor
    /// and nothing to await — the same shape the real adapter offers.
    @Test("the fake's callback can mutate an ordinary local")
    func aPlainLocalIsEnough() async throws {
        let fake = FakeAudioDecoding(streaming: try stream(), chunks: try chunks(count: 3))

        var frames = 0
        _ = try await fake.decode(reference(), chunkFrames: 2) { chunk in
            frames += chunk.frameCount
            return .continue
        }

        #expect(frames == 6)
    }

    @Test("an absence is not a failure and not an empty stream")
    func scriptsAnAbsence() async throws {
        let fake = FakeAudioDecoding(.absent)

        var called = false
        let produced = try await fake.decode(reference(), chunkFrames: 4_096) { _ in
            called = true
            return .continue
        }

        #expect(produced == nil)
        #expect(called == false, "an absence hands over no chunks")
    }

    @Test("a file with no audio is a description with no chunks, not an absence")
    func scriptsAnEmptyFile() async throws {
        let description = try stream(frameCount: 0)
        let fake = FakeAudioDecoding(streaming: description, chunks: [])

        let produced = try await fake.decode(reference(), chunkFrames: 4_096) { _ in .continue }

        #expect(produced != nil, "zero frames is an answer, not an absence")
        #expect(produced?.frameCount == 0)
    }

    @Test("a failure is thrown, and carries its code")
    func scriptsAFailure() async throws {
        let fake = FakeAudioDecoding(failingWith: AudioDecodingError(code: .readFailed, message: "short"))

        let error = await #expect(throws: AudioDecodingError.self) {
            try await fake.decode(reference(), chunkFrames: 4_096) { _ in .continue }
        }
        #expect(error?.code == .readFailed)
    }

    /// Cancellation is scripted as its own code rather than as an absence — the distinction the port
    /// exists to keep, and one a fake that could not express it would quietly erase.
    @Test("cancellation is scriptable, and arrives as an error rather than as nil")
    func scriptsACancellation() async throws {
        let fake = FakeAudioDecoding(failingWith: AudioDecodingError(code: .cancelled, message: "cancelled"))

        let error = await #expect(throws: AudioDecodingError.self) {
            try await fake.decode(reference(), chunkFrames: 4_096) { _ in .continue }
        }
        #expect(error?.code == .cancelled)
    }

    @Test("a consumer that stops is obeyed, and the stop is recorded")
    func stoppingEarlyIsHonoured() async throws {
        let description = try stream(frameCount: 10, channels: 1)
        let fake = FakeAudioDecoding(streaming: description, chunks: try chunks(count: 5))

        var seen = 0
        let produced = try await fake.decode(reference(), chunkFrames: 2) { _ in
            seen += 1
            return seen == 2 ? .stop : .continue
        }

        #expect(seen == 2, "the fake kept going past the stop")
        #expect(produced == description, "stopping early is not a failure")
        #expect(await fake.spy.lastDeliveredChunkCount == 2)
    }

    @Test("the fake records what it was asked")
    func recordsTheCall() async throws {
        let fake = FakeAudioDecoding(streaming: try stream(), chunks: try chunks(count: 3))
        let file = reference()

        _ = try await fake.decode(file, chunkFrames: 512) { _ in .continue }
        _ = try await fake.decode(file, chunkFrames: 1_024) { _ in .continue }

        #expect(await fake.spy.callCount == 2)
        #expect(await fake.spy.lastChunkFrames == 1_024)
        #expect(await fake.spy.lastFile?.displayName == "fixture")
        #expect(await fake.spy.lastDeliveredChunkCount == 3)
    }
}
