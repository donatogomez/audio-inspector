import AudioInspectorDomain
@testable import AudioInspectorApp
import AudioInspectorTesting
import Foundation
import Testing

// The production composition — decode → accumulate → finish — over a scripted decoder. No file, no
// sleep, no polling and no assumption about scheduler order: every outcome is driven by what the fake
// is told to do.

@Suite("App — spectrogram generation")
struct SpectrogramGenerationTests {
    private func reference() -> AudioFileReference {
        AudioFileReference(
            displayName: "fixture", fileExtension: nil, sizeBytes: nil, modifiedAt: nil,
            source: .userSelectedLocalFile(displayName: "fixture", locationDisclosure: .omitted)
        )
    }

    private func stream(frames: Int, channels: Int = 1) throws -> PCMStreamDescription {
        try #require(PCMStreamDescription(sampleRate: 44_100, channelCount: channels, frameCount: frames))
    }

    /// A tone, chunked exactly as a decoder would deliver it.
    private func chunks(frames: Int, per chunkFrames: Int, channels: Int = 1) throws -> [PCMChunk] {
        try stride(from: 0, to: frames, by: chunkFrames).map { start in
            let count = min(chunkFrames, frames - start)
            let data = (0 ..< channels).map { _ in
                (0 ..< count).map { offset -> Float in
                    let phase = 2 * Double.pi * 1_000 * Double(start + offset) / 44_100
                    return 0.5 * Float(sin(phase))
                }
            }
            return try PCMChunk(startFrame: start, channels: data)
        }
    }

    // MARK: The five outcomes

    @Test("a readable stream becomes a spectrogram")
    func aStreamBecomesASpectrogram() async throws {
        let description = try stream(frames: 40_960)
        let decoder = FakeAudioDecoding(streaming: description, chunks: try chunks(frames: 40_960, per: 4_096))

        let outcome = await SpectrogramGeneration(decoder: decoder).run(for: reference())

        guard case let .available(model) = outcome else {
            Issue.record("expected a spectrogram, got \(outcome)")
            return
        }
        #expect(model.frameCount == 40_960)
        #expect(model.columnCount > 0)
        #expect(model.sampleRate == 44_100)
        #expect(model.values.contains { $0 > -20 }, "the signal reached the model")
    }

    /// An unusable frame count is the file offering nothing to size an analysis against — an absence,
    /// never a failure.
    @Test("an unusable frame count becomes an absence, not a failure")
    func anUnusableFrameCountIsAnAbsence() async {
        let decoder = FakeAudioDecoding(.absent)
        let outcome = await SpectrogramGeneration(decoder: decoder).run(for: reference())
        #expect(outcome == .unavailable)
    }

    /// A file with no audio delivers no chunk, so no accumulator is ever built from one. Its model is
    /// an empty one — a complete answer, and a different thing from an absence.
    @Test("a file with no audio becomes a valid empty model")
    func zeroFramesBecomesAnEmptyModel() async throws {
        let description = try stream(frames: 0, channels: 2)
        let decoder = FakeAudioDecoding(streaming: description, chunks: [])

        let outcome = await SpectrogramGeneration(decoder: decoder).run(for: reference())

        guard case let .available(model) = outcome else {
            Issue.record("expected an empty model, got \(outcome)")
            return
        }
        #expect(model.columnCount == 0)
        #expect(model.frameCount == 0)
        #expect(model.channelCount == 2)
        #expect(outcome != .unavailable, "an empty model is not an absence")
    }

    @Test("a decoding failure becomes a failure, carrying no framework text")
    func aDecodingFailureBecomesAFailure() async {
        let decoder = FakeAudioDecoding(failingWith: AudioDecodingError(code: .readFailed, message: "short"))
        let outcome = await SpectrogramGeneration(decoder: decoder).run(for: reference())

        guard case let .failed(message) = outcome else {
            Issue.record("expected a failure, got \(outcome)")
            return
        }
        #expect(!message.contains("readFailed"))
        #expect(!message.contains("decoding_"))
        #expect(!message.isEmpty)
    }

    /// Cancellation from the decoder is the user replacing the operation. It says nothing about the
    /// file and must never arrive as an absence or as a fault of it.
    @Test("a cancelled decode becomes cancellation, never an absence or a failure")
    func aCancelledDecodeBecomesCancellation() async {
        let decoder = FakeAudioDecoding(failingWith: AudioDecodingError(code: .cancelled, message: "cancelled"))
        let outcome = await SpectrogramGeneration(decoder: decoder).run(for: reference())

        #expect(outcome == .cancelled)
        #expect(outcome != .unavailable)
    }

    // MARK: The fault the callback cannot throw

    /// **The check this suite exists for.** The port's callback returns a disposition, not a result, so
    /// a fault detected while folding has to be remembered and answered for after `decode` returns —
    /// and `.stop` ends a decode *normally*. Delete that check in `SpectrogramGeneration` and this test
    /// fails: the generation would return `.available` with a model of the one chunk it managed to read
    /// before the mismatch.
    @Test("a chunk that does not match its stream fails the generation instead of being ignored")
    func aMismatchedChunkFailsTheGeneration() async throws {
        let description = try stream(frames: 40_960, channels: 2)
        // The first chunks are well formed; the fourth claims a channel the stream does not have.
        var scripted = try chunks(frames: 12_288, per: 4_096, channels: 2)
        scripted.append(try PCMChunk(startFrame: 12_288, channels: [[Float](repeating: 0.5, count: 4_096)]))
        let decoder = FakeAudioDecoding(streaming: description, chunks: scripted)

        let outcome = await SpectrogramGeneration(decoder: decoder).run(for: reference())

        guard case .failed = outcome else {
            Issue.record("a mismatched chunk was folded in or ignored: \(outcome)")
            return
        }
    }

    /// The same rule for a chunk that runs past the end of the stream it claims to come from.
    @Test("a chunk beyond the declared stream fails the generation")
    func aChunkBeyondTheStreamFails() async throws {
        let description = try stream(frames: 8_192)
        var scripted = try chunks(frames: 8_192, per: 4_096)
        scripted.append(try PCMChunk(startFrame: 8_192, channels: [[Float](repeating: 0.5, count: 4_096)]))
        let decoder = FakeAudioDecoding(streaming: description, chunks: scripted)

        let outcome = await SpectrogramGeneration(decoder: decoder).run(for: reference())

        guard case .failed = outcome else {
            Issue.record("a chunk past the declared end was accepted: \(outcome)")
            return
        }
    }

    /// A stream that no analysis can be sized against is a fault, not an empty model.
    @Test("a stream no analysis can be built for fails rather than yielding an empty model")
    func anImpossibleStreamFails() async throws {
        // A description the port considers valid but whose channel count the accumulator refuses is not
        // constructible — so this drives the same branch through a chunk that cannot be accumulated.
        let description = try stream(frames: 40_960, channels: 1)
        let decoder = FakeAudioDecoding(
            streaming: description,
            chunks: [try PCMChunk(startFrame: 0, channels: [[], []])]
        )

        let outcome = await SpectrogramGeneration(decoder: decoder).run(for: reference())
        guard case .failed = outcome else {
            Issue.record("a chunk with the wrong channel count was accepted: \(outcome)")
            return
        }
    }

    // MARK: Cancellation and partial models

    /// Cancelled before the first chunk is folded: the flag is already set when the callback first
    /// runs, so no timing is assumed. No model is produced at all.
    @Test("cancelling before the work starts yields cancellation and no model")
    func cancellationBeforeStarting() async throws {
        let description = try stream(frames: 40_960)
        let decoder = FakeAudioDecoding(streaming: description, chunks: try chunks(frames: 40_960, per: 512))
        let file = reference()

        let task = Task { await SpectrogramGeneration(decoder: decoder).run(for: file) }
        task.cancel()

        let outcome = await task.value
        #expect(outcome == .cancelled)
    }

    /// Cancelled while chunks are arriving. The signal is explicit — the decoder is scripted to deliver
    /// many chunks and the task is cancelled before it is awaited — so this observes the callback's own
    /// cancellation check rather than a race.
    @Test("cancelling while chunks arrive never yields a partial model")
    func cancellationDuringAccumulationYieldsNoModel() async throws {
        let description = try stream(frames: 204_800)
        let decoder = FakeAudioDecoding(streaming: description, chunks: try chunks(frames: 204_800, per: 512))
        let file = reference()

        let task = Task { await SpectrogramGeneration(decoder: decoder).run(for: file) }
        task.cancel()

        let outcome = await task.value
        #expect(outcome == .cancelled, "a partial model was presented as a result")
        if case .available = outcome { Issue.record("a partial model escaped") }
    }

    // MARK: Determinism

    @Test("the same chunks produce the same spectrogram")
    func generationIsDeterministic() async throws {
        let description = try stream(frames: 40_960, channels: 2)
        let scripted = try chunks(frames: 40_960, per: 4_096, channels: 2)

        let once = await SpectrogramGeneration(decoder: FakeAudioDecoding(streaming: description, chunks: scripted))
            .run(for: reference())
        let twice = await SpectrogramGeneration(decoder: FakeAudioDecoding(streaming: description, chunks: scripted))
            .run(for: reference())

        #expect(once == twice)
    }

    /// The operation folds and nothing more: it introduces no normalisation, no scaling and no second
    /// transform of its own. Two levels of the same signal stay exactly as far apart as they were.
    @Test("the operation adds no normalisation of its own")
    func theOperationTransformsNothingExtra() async throws {
        let description = try stream(frames: 40_960)

        func model(amplitude: Float) async throws -> Spectrogram {
            let scripted = try stride(from: 0, to: 40_960, by: 4_096).map { start -> PCMChunk in
                let samples = (0 ..< 4_096).map { offset -> Float in
                    let phase = 2 * Double.pi * 1_000 * Double(start + offset) / 44_100
                    return amplitude * Float(sin(phase))
                }
                return try PCMChunk(startFrame: start, channels: [samples])
            }
            let outcome = await SpectrogramGeneration(
                decoder: FakeAudioDecoding(streaming: description, chunks: scripted)
            ).run(for: reference())
            guard case let .available(model) = outcome else {
                throw AudioDecodingError(code: .readFailed, message: "no model")
            }
            return model
        }

        let loud = try await model(amplitude: 0.5)
        let quiet = try await model(amplitude: 0.05)
        let loudPeak = loud.values.max() ?? 0
        let quietPeak = quiet.values.max() ?? 0

        #expect(abs((loudPeak - quietPeak) - 20) < 0.1, "the levels moved by \(loudPeak - quietPeak) dB")
    }

    /// Chunk size is the decoder's business, not the model's: the same audio delivered differently must
    /// fold into the same spectrogram.
    @Test("the model does not depend on how the decoder chunked the file", arguments: [512, 4_096, 65_536])
    func chunkSizeDoesNotChangeTheResult(chunkFrames: Int) async throws {
        let description = try stream(frames: 44_101)
        let reference = try chunks(frames: 44_101, per: 200_000)
        let chunked = try chunks(frames: 44_101, per: chunkFrames)

        let whole = await SpectrogramGeneration(decoder: FakeAudioDecoding(streaming: description, chunks: reference))
            .run(for: self.reference())
        let split = await SpectrogramGeneration(decoder: FakeAudioDecoding(streaming: description, chunks: chunked))
            .run(for: self.reference())

        #expect(whole == split, "chunk size \(chunkFrames) changed the model")
    }
}
