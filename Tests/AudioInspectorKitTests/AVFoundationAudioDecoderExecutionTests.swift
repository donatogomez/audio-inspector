import AVFoundation
import AudioInspectorDomain
import AudioInspectorMedia
import Foundation
import Testing

// Where the decoder's read actually runs, whether it can be cancelled while it is running, and what
// the callback's shape permits a consumer to do. All three are observed rather than argued.
//
// The observation seam is the adapter's **existing** production seam. `resolveURL` is called from
// inside `decode`, before anything is opened, so a test resolver that signals through an `AsyncStream`
// reports the moment the body begins — with no production change, no lock, no polling and no sleep.
// Nothing here asserts an ordering between the main actor and the decode; that ordering is a race, and
// the waveform suite already recorded what happens to tests that assert one.

/// What a decode handed over, held in a class so the callback captures **one disconnected reference**
/// rather than the enclosing context's variables.
///
/// That distinction is the port's shape, not an implementation detail of this suite. `decode` is
/// `nonisolated`, so a callback formed inside an isolated context and capturing that context's state
/// would be a main-actor-isolated value sent to a nonisolated function — a genuine race, and Swift 6
/// rejects it. Capturing a locally created class keeps the closure in a disconnected region, which is
/// what a real consumer folding chunks will do.
private final class ChunkSink {
    var chunks: [PCMChunk] = []
    var returned = false
    var arrivedAfterReturn = false

    func receive(_ chunk: PCMChunk) {
        if returned { arrivedAfterReturn = true }
        chunks.append(chunk)
    }

    var frameTotal: Int { chunks.reduce(0) { $0 + $1.frameCount } }
}

/// Runs one decode from a **nonisolated** context, which is where the composition root will run it.
///
/// It exists so the tests below can call the decoder from the main actor without forming the callback
/// there: the closure is created here, in a nonisolated function, over a sink the caller owns.
private func decodeCollecting(
    _ decoder: AVFoundationAudioDecoder,
    file: AudioFileReference,
    chunkFrames: Int,
    into sink: ChunkSink
) async throws(AudioDecodingError) -> PCMStreamDescription? {
    try await decoder.decode(file, chunkFrames: chunkFrames) { _, chunk in
        sink.receive(chunk)
        return .continue
    }
}

/// Runs one decode and keeps nothing, for the tests that only care about the outcome.
///
/// Separate from `decodeCollecting` because a sink created on the main actor cannot be handed to a
/// detached `Task` — it would be read there and mutated here. This closure captures nothing at all, so
/// it crosses freely, and the tests below need no accumulator to make their point.
private func decodeDiscarding(
    _ decoder: AVFoundationAudioDecoder,
    file: AudioFileReference,
    chunkFrames: Int
) async throws(AudioDecodingError) -> PCMStreamDescription? {
    try await decoder.decode(file, chunkFrames: chunkFrames) { _, _ in .continue }
}

@MainActor
@Suite("Media — PCM decoding execution")
struct AVFoundationAudioDecoderExecutionTests {
    /// Twenty seconds of audio: long enough that a decode is comfortably still in flight while the main
    /// actor does its work, short enough not to weigh on the suite.
    private static let longFixtureFrames: AVAudioFrameCount = 882_000

    private func reference() -> AudioFileReference {
        AudioFileReference(
            displayName: "fixture", fileExtension: nil, sizeBytes: nil, modifiedAt: nil,
            source: .userSelectedLocalFile(displayName: "fixture", locationDisclosure: .omitted)
        )
    }

    private func writeLongFixture(in directory: URL) throws -> URL {
        try writeAudioFixture(
            AudioFixtureSpec(
                name: "execution", format: .wav, signal: .sine(frequency: 440, amplitude: 0.5),
                channels: 2, frames: Self.longFixtureFrames
            ),
            in: directory
        )
    }

    // MARK: Gate A — which executor runs the loop

    /// `decode` is declared with no isolation annotation, on a type with none, conforming to a protocol
    /// with none, in a package that builds in Swift 6 language mode. Under those rules a nonisolated
    /// `async` function does not inherit the caller's actor.
    ///
    /// This test does not take that on trust: it calls the adapter **from the main actor** and asks the
    /// body itself where it ended up. A decode that inherited the main actor would block the UI for the
    /// length of a file, which is precisely what this shape exists to avoid.
    @Test("the decoder's body does not run on the main actor, even when called from it")
    func bodyLeavesTheMainActor() async throws {
        try await withTemporaryDirectory { directory in
            let url = try writeLongFixture(in: directory)
            let (executor, continuation) = AsyncStream<Bool>.makeStream()

            let decoder = AVFoundationAudioDecoder(resolveURL: { _ in
                continuation.yield(Thread.isMainThread)
                continuation.finish()
                return url
            })

            // The suite is `@MainActor`, so this call originates there. `Thread.isMainThread` is
            // unavailable from an async context and is read inside the synchronous resolver instead —
            // which is exactly where the question is asked.
            let sink = ChunkSink()
            async let stream = decodeCollecting(decoder, file: reference(), chunkFrames: 4_096, into: sink)
            var ranOnMainThread: Bool?
            for await value in executor {
                ranOnMainThread = value
                break
            }
            _ = try await stream

            #expect(ranOnMainThread == false, "the body inherited the main actor instead of leaving it")
        }
    }

    // MARK: Gate B — cancellation requested while the read is under way

    /// Distinct from the acceptance suite's cancellation test, which cancels a task **before it starts**:
    /// there the flag is already set when the first boundary is reached, so it only proves the adapter
    /// refuses to begin. Here cancellation is requested strictly **after** the body has begun executing,
    /// which is what a user pressing cancel actually does.
    ///
    /// No sleep, no polling and no timing assumption: the resolver signals through an `AsyncStream`, and
    /// the cancellation is requested only once that signal has been received.
    @Test("cancelling after the read has begun returns cancelled, not a description")
    func cancellationDuringTheReadIsObserved() async throws {
        try await withTemporaryDirectory { directory in
            let url = try writeLongFixture(in: directory)
            let (started, continuation) = AsyncStream<Void>.makeStream()

            let decoder = AVFoundationAudioDecoder(resolveURL: { _ in
                continuation.yield()
                continuation.finish()
                return url
            })
            let file = reference()

            // Chunk size 1: many boundaries, so a later one is always reachable.
            let task = Task { try await decodeDiscarding(decoder, file: file, chunkFrames: 1) }

            for await _ in started { break } // the body is now running
            task.cancel() // requested from the main actor, strictly afterwards

            let error = await #expect(throws: AudioDecodingError.self) { try await task.value }
            #expect(error?.code == .cancelled)
            #expect(error?.code != .readFailed, "cancellation must not be reported as a failure of the file")
        }
    }

    /// Cancelling one decode must not disturb another. ADR-0016 decision 15 makes this a property of the
    /// seam rather than a nicety: the waveform and the spectrogram read the same file as independent
    /// operations, and cancelling one visualisation may not cancel the other.
    @Test("cancelling one decode leaves another running to completion")
    func operationsAreIndependent() async throws {
        try await withTemporaryDirectory { directory in
            let url = try writeLongFixture(in: directory)
            let (started, continuation) = AsyncStream<Void>.makeStream()

            let signalling = AVFoundationAudioDecoder(resolveURL: { _ in
                continuation.yield()
                continuation.finish()
                return url
            })
            let quiet = AVFoundationAudioDecoder(resolveURL: { _ in url })
            let file = reference()

            let cancelled = Task { try await decodeDiscarding(signalling, file: file, chunkFrames: 1) }
            let survivor = Task { try await decodeDiscarding(quiet, file: file, chunkFrames: 65_536) }

            for await _ in started { break }
            cancelled.cancel()

            let error = await #expect(throws: AudioDecodingError.self) { try await cancelled.value }
            #expect(error?.code == .cancelled)

            // A returned description is itself the proof that the survivor read the file in full: the
            // adapter throws `readFailed` rather than returning short, so there is no state to inspect
            // here and no accumulator to smuggle across the task boundary.
            let description = try #require(await survivor.value)
            #expect(description.frameCount == Int(Self.longFixtureFrames), "the other decode was cut short")
        }
    }

    // MARK: Gate C — what the callback's shape permits

    /// The reason the callback is synchronous, non-escaping and **not** `@Sendable`, stated as code
    /// rather than as a comment. `ChunkSink` is a non-`Sendable` class mutated directly from inside the
    /// callback: no actor, no lock, nothing to await.
    ///
    /// That this test **compiles** is half the assertion. Marking `receive` `@Sendable` would reject the
    /// capture outright — which is why the port does not, and why a consumer can fold chunks into
    /// ordinary local state.
    @Test("a non-Sendable local accumulator can be mutated from inside the callback")
    func aPlainLocalAccumulatorIsEnough() async throws {
        try await withTemporaryDirectory { directory in
            let url = try writeAudioFixture(
                AudioFixtureSpec(
                    name: "accumulate", format: .wav, signal: .sine(frequency: 440, amplitude: 0.5),
                    channels: 2, frames: 10_000
                ),
                in: directory
            )

            let sink = ChunkSink()
            let decoder = AVFoundationAudioDecoder(resolveURL: { _ in url })
            let description = try #require(
                await decodeCollecting(decoder, file: reference(), chunkFrames: 1_024, into: sink)
            )

            #expect(sink.frameTotal == description.frameCount)
            #expect(sink.chunks.count == 10, "10 000 frames at 1 024 per chunk")
        }
    }

    /// The callback does not outlive the call. Every invocation happens strictly before `decode`
    /// returns, so a consumer never has to wonder whether more chunks may still arrive — and the
    /// security-scoped window the caller opened is still open for all of them.
    @Test("every chunk arrives before the call returns")
    func theCallbackNeverOutlivesTheCall() async throws {
        try await withTemporaryDirectory { directory in
            let url = try writeAudioFixture(
                AudioFixtureSpec(
                    name: "lifetime", format: .wav, signal: .silence, channels: 1, frames: 8_000
                ),
                in: directory
            )

            let sink = ChunkSink()
            let decoder = AVFoundationAudioDecoder(resolveURL: { _ in url })
            _ = try await decodeCollecting(decoder, file: reference(), chunkFrames: 1_000, into: sink)
            sink.returned = true

            #expect(sink.chunks.count == 8)
            #expect(sink.arrivedAfterReturn == false, "a chunk arrived after decode had returned")
        }
    }
}
