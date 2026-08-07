import AVFoundation
import AudioInspectorDomain
import AudioInspectorMedia
import Foundation
import Testing

// Where the adapter's synchronous read actually runs, and whether it can be cancelled while it is
// running. Both are observed rather than argued: `makeWaveform` carries no isolation annotation, so
// what it does under Swift 6 is a property of the language mode the package builds in, and the only
// honest way to state it is to watch it happen.
//
// The observation seam is the adapter's **existing** production seam. `resolveURL` is called from
// inside `makeWaveform`, before anything is opened, so a test resolver that signals through an
// `AsyncStream` reports the moment the body begins — with no production change, no lock, no polling
// and no sleep.

@MainActor
@Suite("Media — waveform generation execution")
struct AVFoundationWaveformGeneratorExecutionTests {
    /// Twenty seconds of audio: long enough that a generation is comfortably still in flight while the
    /// main actor does its work, short enough not to weigh on the suite.
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

    /// `makeWaveform` is declared with no isolation annotation, on a type with none, conforming to a
    /// protocol with none, in a package that builds in Swift 6 language mode with no upcoming feature
    /// enabled. Under those rules a nonisolated `async` function does not inherit the caller's actor.
    ///
    /// This test does not take that on trust: it calls the adapter **from the main actor** and asks the
    /// body itself where it ended up.
    @Test("the adapter's body does not run on the main actor, even when called from it")
    func bodyLeavesTheMainActor() async throws {
        try await withTemporaryDirectory { directory in
            let url = try writeLongFixture(in: directory)
            let (executor, continuation) = AsyncStream<Bool>.makeStream()

            let generator = AVFoundationWaveformGenerator(resolveURL: { _ in
                continuation.yield(Thread.isMainThread)
                continuation.finish()
                return url
            })

            // The suite is `@MainActor`, so this call originates there. `Thread.isMainThread` is
            // unavailable from an async context and is read inside the synchronous resolver instead —
            // which is exactly where the question is asked.
            async let envelope = generator.makeWaveform(for: reference())
            var ranOnMainThread: Bool?
            for await value in executor {
                ranOnMainThread = value
                break
            }
            _ = try await envelope

            #expect(ranOnMainThread == false, "the body inherited the main actor instead of leaving it")
        }
    }

    // MARK: Gate B — deliberately absent: main-actor responsiveness has no deterministic observation

    // There was a test here asserting that a long generation leaves the main actor free, by starting
    // the work, waiting for the body to signal that it had begun, appending an entry from the main
    // actor, and requiring that entry to precede the generation's own.
    //
    // **It was a race, and CI won it.** The order it asserted holds only when the main actor is
    // resumed before the generation finishes, which nothing guarantees: on a shared runner the
    // generation completed first and the entries arrived reversed — with the main actor free the whole
    // time. Its own comment claimed the order depended on availability "not on any duration", and that
    // was simply wrong.
    //
    // It is removed rather than repaired. Every repair available would have been dishonest: a longer
    // fixture only widens the race, accepting either order asserts nothing, and observing the loop from
    // outside would mean cutting a seam into production purely to keep a test.
    //
    // **Nothing is lost.** Gate A observes the executor directly — it asks the body, from inside it,
    // whether it is on the main thread — and a body that is not on the main actor cannot block it. The
    // responsiveness this test tried to demonstrate is a consequence of Gate A's result, not an
    // independent property, and Gate A is deterministic. That the envelope is complete for a long file
    // is covered several times over by the acceptance matrix.

    // MARK: Gate C — deliberately absent, for the same reason Gate B was

    // There was a test here asserting that cancelling **after** the body had begun returns `cancelled`
    // rather than an envelope. Its own doc-comment already admitted the weak point: that at least one
    // chunk had been read was *"inferred, not observed"*. The inference was wrong.
    //
    // The signal is emitted from `resolveURL`, which the generator calls **before** it opens the file —
    // before `AVAudioFile(forReading:)`, before the format check and before a single chunk is read. So
    // it means "the body entered `makeWaveform`", never "a chunk has been read". Two orderings are both
    // legal:
    //
    // 1. the body resolves the URL, opens the file and starts reading; the main actor is rescheduled,
    //    cancels, and the next chunk boundary observes it — the test passes; or
    // 2. the body reads the **whole** file — 882 000 frames at one frame per chunk — before the main
    //    actor is rescheduled at all. `makeWaveform` returns an envelope, the later `cancel()` lands on
    //    a finished task and does nothing, and the test fails.
    //
    // Which happens is decided by how quickly the main actor is rescheduled against how long the read
    // takes, and nothing in the test controls either. Measured: it failed roughly one run in six of the
    // full suite on `main`, and repeatedly took CI red.
    //
    // It is removed rather than repaired, exactly as Gate B above was: a longer fixture only widens the
    // window, a threshold is a sleep with better manners, and accepting either outcome asserts nothing.
    //
    // **Nothing is lost.** That the loop consults cancellation at a chunk boundary is proved
    // deterministically by the acceptance suite's own cancellation test — the flag is already set when
    // the first boundary is reached, and there is no separate code path for a first boundary. Removing
    // `Task.checkCancellation()` from the loop makes that test fail, which is what makes it the real
    // guarantee rather than this one.
}
