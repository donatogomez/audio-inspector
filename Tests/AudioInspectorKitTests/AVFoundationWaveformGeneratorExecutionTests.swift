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

/// Ordered record of events, all appended from the main actor so the order is well defined.
@MainActor
private final class OrderLog {
    private(set) var entries: [String] = []
    func append(_ entry: String) { entries.append(entry) }
}

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

    // MARK: Gate B — the main actor stays responsive

    /// If the read ran on the main actor it would hold it for its whole duration: there is no
    /// suspension point inside the loop, so nothing else could be serviced until it finished.
    ///
    /// Both entries below are appended **on the main actor**, so their order is decided by whether the
    /// main actor was free while the generation was still working — not by any duration. A blocking
    /// adapter produces the opposite order, so the assertion cannot pass for the wrong reason.
    @Test("a long generation leaves the main actor free to do other work")
    func doesNotBlockTheMainActor() async throws {
        try await withTemporaryDirectory { directory in
            let url = try writeLongFixture(in: directory)
            let log = OrderLog()
            let (started, continuation) = AsyncStream<Void>.makeStream()

            let generator = AVFoundationWaveformGenerator(
                chunkFrames: 1_024,
                resolveURL: { _ in
                    continuation.yield()
                    continuation.finish()
                    return url
                }
            )

            let task = Task {
                let envelope = try await generator.makeWaveform(for: reference())
                log.append("generation finished")
                return envelope
            }

            // Suspends the main actor until the adapter's body has begun.
            for await _ in started { break }

            // Reached only while the generation is still in flight — unless it holds the main actor.
            log.append("main actor work")

            let envelope = try #require(await task.value)

            #expect(log.entries == ["main actor work", "generation finished"])
            #expect(envelope.frameCount == Int(Self.longFixtureFrames), "and the result is still complete")
        }
    }

    // MARK: Gate C — cancellation requested while the work is under way

    /// Distinct from the cancellation test in the acceptance matrix, which cancels a task **before it
    /// starts**: there the flag is already set when the first boundary is reached, so it only proves
    /// the adapter refuses to begin. Here the cancellation is requested strictly **after** the body has
    /// begun executing, which is what a user pressing cancel actually does.
    ///
    /// What is observed: the body started, cancellation was requested afterwards from another task, and
    /// the result is `cancelled` rather than an envelope. What is **inferred, not observed**: that at
    /// least one chunk had been read by then. Between the resolver signalling and the first read there
    /// is no suspension point, so the body cannot be parked in between — but the suite cannot see the
    /// chunk counter, and this test does not pretend otherwise.
    @Test("cancelling after the read has begun returns cancelled, not an envelope")
    func cancellationDuringTheReadIsObserved() async throws {
        try await withTemporaryDirectory { directory in
            let url = try writeLongFixture(in: directory)
            let (started, continuation) = AsyncStream<Void>.makeStream()

            let generator = AVFoundationWaveformGenerator(
                chunkFrames: 1, // many boundaries, so a later one is always reachable
                resolveURL: { _ in
                    continuation.yield()
                    continuation.finish()
                    return url
                }
            )

            let task = Task { try await generator.makeWaveform(for: reference()) }

            for await _ in started { break } // the body is now running
            task.cancel() // requested from the main actor, strictly afterwards

            let error = await #expect(throws: WaveformError.self) { try await task.value }
            #expect(error?.code == .cancelled)
            #expect(error?.code != .readFailed, "cancellation must not be reported as a failure of the file")
        }
    }
}
