import AudioInspectorDomain
@testable import AudioInspectorApp
import AudioInspectorTesting
import Foundation
import Testing

// The production composition — decode → accumulate → finish — over a scripted decoder. No file, no
// sleep, no polling and no assumption about scheduler order: every outcome is driven by what the fake
// is told to do. Mirrors `SpectrogramGenerationTests` line for line, adapted where the two compositions
// genuinely differ (level metrics need no frame position, and stay in linear amplitude rather than
// dBFS at this layer).

@Suite("App — signal level metrics generation")
struct SignalLevelMetricsGenerationTests {
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
    private func chunks(
        frames: Int, per chunkFrames: Int, channels: Int = 1, amplitude: Float = 0.5
    ) throws -> [PCMChunk] {
        try stride(from: 0, to: frames, by: chunkFrames).map { start in
            let count = min(chunkFrames, frames - start)
            let data = (0 ..< channels).map { _ in
                (0 ..< count).map { offset -> Float in
                    let phase = 2 * Double.pi * 1_000 * Double(start + offset) / 44_100
                    return amplitude * Float(sin(phase))
                }
            }
            return try PCMChunk(startFrame: start, channels: data)
        }
    }

    // MARK: The four outcomes

    @Test("a readable stream becomes signal level metrics")
    func aStreamBecomesSignalLevelMetrics() async throws {
        let description = try stream(frames: 40_960)
        let decoder = FakeAudioDecoding(streaming: description, chunks: try chunks(frames: 40_960, per: 4_096))

        let outcome = await SignalLevelMetricsGeneration(decoder: decoder).run(for: reference())

        guard case let .available(metrics) = outcome else {
            Issue.record("expected signal level metrics, got \(outcome)")
            return
        }
        #expect(metrics.channels.count == 1)
        #expect(metrics.channels[0].sampleCount == 40_960)
        let peak = try #require(metrics.overallPeakSample)
        #expect(abs(peak - 0.5) < 0.01, "the signal's own peak reached the model")
        #expect(metrics.overallClippedSampleCount == 0)
    }

    /// An unusable frame count is the file offering nothing to size an analysis against — an absence,
    /// never a failure.
    @Test("an unusable frame count becomes an absence, not a failure")
    func anUnusableFrameCountIsAnAbsence() async {
        let decoder = FakeAudioDecoding(.absent)
        let outcome = await SignalLevelMetricsGeneration(decoder: decoder).run(for: reference())
        #expect(outcome == .unavailable)
    }

    /// A file with no audio delivers no chunk, so no accumulator is ever built from one. Its metrics are
    /// a complete, empty answer — every channel reports "not computable" — a different thing from an
    /// absence.
    @Test("a file with no audio becomes a complete, empty answer")
    func zeroFramesBecomesAnEmptyAnswer() async throws {
        let description = try stream(frames: 0, channels: 2)
        let decoder = FakeAudioDecoding(streaming: description, chunks: [])

        let outcome = await SignalLevelMetricsGeneration(decoder: decoder).run(for: reference())

        guard case let .available(metrics) = outcome else {
            Issue.record("expected empty metrics, got \(outcome)")
            return
        }
        #expect(metrics.channels.count == 2)
        for channel in metrics.channels {
            #expect(channel.sampleCount == 0)
            #expect(channel.peakSample == nil)
            #expect(channel.rms == nil)
            #expect(channel.dcOffset == nil)
            #expect(channel.clippedSampleCount == 0)
        }
        #expect(metrics.overallPeakSample == nil)
        #expect(metrics.overallRMS == nil)
        #expect(metrics.overallDCOffset == nil)
        #expect(metrics.overallClippedSampleCount == 0)
        #expect(outcome != .unavailable, "a complete empty answer is not an absence")
    }

    @Test("a decoding failure becomes a failure, carrying no framework text")
    func aDecodingFailureBecomesAFailure() async {
        let decoder = FakeAudioDecoding(failingWith: AudioDecodingError(code: .readFailed, message: "short"))
        let outcome = await SignalLevelMetricsGeneration(decoder: decoder).run(for: reference())

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
        let outcome = await SignalLevelMetricsGeneration(decoder: decoder).run(for: reference())

        #expect(outcome == .cancelled)
        #expect(outcome != .unavailable)
    }

    // MARK: The fault the callback cannot throw

    /// **The check this suite exists for.** The port's callback returns a disposition, not a result, so
    /// a fault detected while folding has to be remembered and answered for after `decode` returns —
    /// and `.stop` ends a decode *normally*. Delete that check in `SignalLevelMetricsGeneration` and
    /// this test fails: the generation would return `.available` with metrics folded from only the
    /// chunks read before the mismatch.
    @Test("a chunk that does not match its stream fails the generation instead of being ignored")
    func aMismatchedChunkFailsTheGeneration() async throws {
        let description = try stream(frames: 40_960, channels: 2)
        // The first chunks are well formed; the fourth claims a channel the stream does not have.
        var scripted = try chunks(frames: 12_288, per: 4_096, channels: 2)
        scripted.append(try PCMChunk(startFrame: 12_288, channels: [[Float](repeating: 0.5, count: 4_096)]))
        let decoder = FakeAudioDecoding(streaming: description, chunks: scripted)

        let outcome = await SignalLevelMetricsGeneration(decoder: decoder).run(for: reference())

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

        let outcome = await SignalLevelMetricsGeneration(decoder: decoder).run(for: reference())

        guard case .failed = outcome else {
            Issue.record("a chunk past the declared end was accepted: \(outcome)")
            return
        }
    }

    /// A description the port considers valid but that a chunk cannot be accumulated against is not a
    /// silently-ignored success — it drives the same fault branch as the two tests above.
    @Test("a chunk whose shape the accumulator refuses fails rather than yielding an empty answer")
    func anImpossibleShapeFails() async throws {
        let description = try stream(frames: 40_960, channels: 1)
        let decoder = FakeAudioDecoding(
            streaming: description,
            chunks: [try PCMChunk(startFrame: 0, channels: [[], []])]
        )

        let outcome = await SignalLevelMetricsGeneration(decoder: decoder).run(for: reference())
        guard case .failed = outcome else {
            Issue.record("a chunk with the wrong channel count was accepted: \(outcome)")
            return
        }
    }

    // MARK: Cancellation and partial models

    /// Cancelled before the first chunk is folded: the flag is already set when the callback first
    /// runs, so no timing is assumed. No metrics are produced at all.
    @Test("cancelling before the work starts yields cancellation and no metrics")
    func cancellationBeforeStarting() async throws {
        let description = try stream(frames: 40_960)
        let decoder = FakeAudioDecoding(streaming: description, chunks: try chunks(frames: 40_960, per: 512))
        let file = reference()

        let task = Task { await SignalLevelMetricsGeneration(decoder: decoder).run(for: file) }
        task.cancel()

        let outcome = await task.value
        #expect(outcome == .cancelled)
    }

    /// Cancelled while chunks are arriving. The signal is explicit — the decoder is scripted to deliver
    /// many chunks and the task is cancelled before it is awaited — so this observes the callback's own
    /// cancellation check rather than a race.
    @Test("cancelling while chunks arrive never yields partial metrics")
    func cancellationDuringAccumulationYieldsNoMetrics() async throws {
        let description = try stream(frames: 204_800)
        let decoder = FakeAudioDecoding(streaming: description, chunks: try chunks(frames: 204_800, per: 512))
        let file = reference()

        let task = Task { await SignalLevelMetricsGeneration(decoder: decoder).run(for: file) }
        task.cancel()

        let outcome = await task.value
        #expect(outcome == .cancelled, "partial metrics were presented as a result")
        if case .available = outcome { Issue.record("partial metrics escaped") }
    }

    // MARK: Determinism and linearity

    @Test("the same chunks produce the same metrics")
    func generationIsDeterministic() async throws {
        let description = try stream(frames: 40_960, channels: 2)
        let scripted = try chunks(frames: 40_960, per: 4_096, channels: 2)

        let once = await SignalLevelMetricsGeneration(
            decoder: FakeAudioDecoding(streaming: description, chunks: scripted)
        ).run(for: reference())
        let twice = await SignalLevelMetricsGeneration(
            decoder: FakeAudioDecoding(streaming: description, chunks: scripted)
        ).run(for: reference())

        #expect(once == twice)
    }

    /// The operation folds and nothing more: it introduces no scaling and no unit conversion of its
    /// own. Peak stays in the domain's linear amplitude, exactly proportional to what was fed in — a
    /// stricter check than the spectrogram's own "20 dB per decade" test, since a linear scale has no
    /// rounding to allow for.
    @Test("the operation adds no scaling of its own")
    func theOperationTransformsNothingExtra() async throws {
        let description = try stream(frames: 40_960)

        func peak(amplitude: Float) async throws -> Float {
            let scripted = try chunks(frames: 40_960, per: 4_096, amplitude: amplitude)
            let outcome = await SignalLevelMetricsGeneration(
                decoder: FakeAudioDecoding(streaming: description, chunks: scripted)
            ).run(for: reference())
            guard case let .available(metrics) = outcome, let peak = metrics.overallPeakSample else {
                throw AudioDecodingError(code: .readFailed, message: "no metrics")
            }
            return peak
        }

        let loud = try await peak(amplitude: 0.5)
        let quiet = try await peak(amplitude: 0.25)

        #expect(abs(loud - 2 * quiet) < 0.0001, "the operation scaled the signal on its own")
    }

    /// Chunk size is the decoder's business, not the model's: the same audio delivered differently must
    /// fold into the same metrics.
    @Test("the metrics do not depend on how the decoder chunked the file", arguments: [512, 4_096, 65_536])
    func chunkSizeDoesNotChangeTheResult(chunkFrames: Int) async throws {
        let description = try stream(frames: 44_101)
        let reference = try chunks(frames: 44_101, per: 200_000)
        let chunked = try chunks(frames: 44_101, per: chunkFrames)

        let whole = await SignalLevelMetricsGeneration(
            decoder: FakeAudioDecoding(streaming: description, chunks: reference)
        ).run(for: self.reference())
        let split = await SignalLevelMetricsGeneration(
            decoder: FakeAudioDecoding(streaming: description, chunks: chunked)
        ).run(for: self.reference())

        guard case let .available(wholeMetrics) = whole, case let .available(splitMetrics) = split else {
            Issue.record("expected metrics from both runs")
            return
        }
        // Peak, clip count and sample count are bit-exact regardless of chunking (documented on
        // `SignalLevelMetricsAccumulator.accumulate(_:)`); RMS and DC offset are independent only up to
        // floating-point rounding, so this checks the bit-exact fields rather than full equality.
        #expect(wholeMetrics.overallPeakSample == splitMetrics.overallPeakSample, "chunk size \(chunkFrames) changed the peak")
        #expect(
            wholeMetrics.overallClippedSampleCount == splitMetrics.overallClippedSampleCount,
            "chunk size \(chunkFrames) changed the clip count"
        )
        #expect(
            wholeMetrics.channels[0].sampleCount == splitMetrics.channels[0].sampleCount,
            "chunk size \(chunkFrames) changed the sample count"
        )
    }
}
