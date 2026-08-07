import AVFoundation
import AudioInspectorDomain
import AudioInspectorMedia
import Foundation
import Testing

// Where the decoder's read actually runs, that two decodes cannot reach each other, and what the
// callback's shape permits a consumer to do. All three are observed rather than argued.
//
// The observation seam is the adapter's **existing** production seam: `resolveURL` is called from
// inside `decode`, so a test resolver reports the moment the body begins — with no production change,
// no lock, no polling and no sleep.
//
// **Nothing here asserts an ordering between the main actor and the decode.** That was the rule this
// file already stated, and a cancellation test broke it anyway by inferring "a chunk has been read"
// from a signal emitted before the file was even opened. See Gate B below for what that cost and why
// it is gone rather than repaired.

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

    // MARK: Gate B — deliberately absent: "cancel after the read began" has no deterministic observation

    // There was a test here asserting that cancelling **after** the body had begun returns `.cancelled`
    // rather than a description. It started the decode, waited for the body to signal that it had
    // begun, cancelled, and required `.cancelled`.
    //
    // **Its "no timing assumption" claim was false, and CI proved it.** The signal is emitted from
    // `resolveURL`, which the adapter calls *before* it opens the file — before `AVAudioFile(forReading:)`,
    // before the format check, and before a single chunk is read. So the signal means only "the body
    // entered `decode`", never "at least one chunk has been read". Two orderings are both legal:
    //
    // 1. the body resolves the URL, opens the file and starts reading; the main actor is rescheduled,
    //    cancels, and the next chunk boundary observes it — the test passes; or
    // 2. the body resolves the URL and reads the **whole** file — 882 000 frames at one frame per
    //    chunk — before the main actor is rescheduled at all. `decode` returns a description, the
    //    later `cancel()` lands on a finished task and does nothing, and the test fails.
    //
    // Which one happens is decided by how quickly the main actor is rescheduled against how long the
    // decode takes, and nothing in the test controls either. Run alone the decode takes ~0.5 s and the
    // main actor wakes in microseconds, so it always passed locally; under the full suite on a shared
    // runner it lost, on `main` as well as on this branch, and took the CI red with it.
    //
    // It is removed rather than repaired, exactly as the waveform suite's Gate B was and for the same
    // reason: every repair available is dishonest. A longer fixture only widens the window, a threshold
    // is a sleep with better manners, and accepting either outcome asserts nothing.
    //
    // **Nothing is lost.** That the loop consults cancellation at a chunk boundary is proved
    // deterministically by `cancellationBeforeStarting` in the acceptance suite: the flag is already
    // set when the first boundary is reached, so the branch under test is the same
    // `Task.checkCancellation()` every later boundary runs — there is no separate code path for a
    // first boundary. That a *composition* stops folding when cancelled is proved over the port fake,
    // where delivery is scripted rather than raced.

    /// Two decodes of the same file are independent operations: neither shares a decoder, a file
    /// handle or any state with the other, so one failing cannot disturb the other's result.
    ///
    /// **Failure is used as the disturbance rather than cancellation**, and that is the point. A
    /// cancelled operation is only observably cancelled if the cancellation arrives before it finishes,
    /// which nothing here can guarantee. A failing one fails because of its own configuration — no URL
    /// to resolve — and is therefore deterministic. What this asserts is the same property ADR-0016
    /// decision 15 requires: the operations do not reach each other.
    @Test("one decode failing leaves another running to completion")
    func operationsAreIndependent() async throws {
        try await withTemporaryDirectory { directory in
            let url = try writeLongFixture(in: directory)

            // No resolver, so this one fails at its first step, every time.
            let failing = AVFoundationAudioDecoder()
            let survivor = AVFoundationAudioDecoder(resolveURL: { _ in url })
            let file = reference()

            let failed = Task { try await decodeDiscarding(failing, file: file, chunkFrames: 4_096) }
            let succeeded = Task { try await decodeDiscarding(survivor, file: file, chunkFrames: 65_536) }

            let error = await #expect(throws: AudioDecodingError.self) { try await failed.value }
            #expect(error?.code == .fileAccessDenied)

            // A returned description is itself the proof that the survivor read the file in full: the
            // adapter throws `readFailed` rather than returning short, so there is no state to inspect
            // here and nothing to smuggle across the task boundary.
            let description = try #require(await succeeded.value)
            #expect(description.frameCount == Int(Self.longFixtureFrames), "the other decode was cut short")
        }
    }

    /// And the same in the other direction, so the result does not depend on which operation is which.
    @Test("the survivor is unaffected whichever operation fails first")
    func independenceIsSymmetric() async throws {
        try await withTemporaryDirectory { directory in
            let url = try writeLongFixture(in: directory)
            let survivor = AVFoundationAudioDecoder(resolveURL: { _ in url })
            let file = reference()

            // Started first, and still finishes: a failure alongside it changes nothing.
            let succeeded = Task { try await decodeDiscarding(survivor, file: file, chunkFrames: 65_536) }
            let failed = Task {
                try await decodeDiscarding(AVFoundationAudioDecoder(), file: file, chunkFrames: 4_096)
            }

            let description = try #require(await succeeded.value)
            let error = await #expect(throws: AudioDecodingError.self) { try await failed.value }

            #expect(description.frameCount == Int(Self.longFixtureFrames))
            #expect(error?.code == .fileAccessDenied)
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
