import Foundation
import Testing

import AudioInspectorAnalysis
import AudioInspectorDomain
import AudioInspectorTesting
import FeatureImport

@testable import AudioInspectorApp

// **What the shared read must keep true now that the waveform is one of its consumers.**
//
// `SharedWaveformConsumerTests` asserts what the waveform *produces*; `SharedWaveformEquivalenceTests`
// asserts that it is the same envelope the file's own read produced. This suite asserts what must stay
// true while producing it: that the waveform's failure is its own, that the read outlives it, that a
// producer's failure is a different thing, and that a cancelled read leaks nothing.
//
// **Every survivor is compared as a whole outcome against an independent reference** — the accumulator
// fed the same chunks directly, sharing no line of the composition. "Not nil" and "is available" are
// deliberately absent: they would pass on a composition that quietly degraded a model.

// MARK: - A decoder the test can script and observe

/// A one-shot gate. No sleep, no polling, no `Task.yield()`.
private actor Gate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var opened = false

    func wait() async {
        if opened { return }
        await withCheckedContinuation { continuation = $0 }
    }

    func open() {
        guard !opened else { return }
        opened = true
        continuation?.resume()
        continuation = nil
    }
}

/// Counts what a decode actually handed over, so "the read continued" is observed at the port rather
/// than inferred from a result that merely looks complete.
private actor DeliveryLog {
    private(set) var delivered = 0
    private(set) var finishedNormally = false
    func record() { delivered += 1 }
    func recordNormalEnd() { finishedNormally = true }
}

private struct ScriptedDecoder: AudioDecoding {
    let stream: PCMStreamDescription
    let chunks: [PCMChunk]
    /// Deliver this many chunks, then throw. `nil` delivers them all and returns normally.
    var failAfter: Int?
    var error = AudioDecodingError(code: .readFailed, message: "the read stopped")
    /// Suspends before delivering the chunk at this index, after signalling `reached`.
    var suspendBefore: Int?
    var reached: Gate?
    var release: Gate?
    let log = DeliveryLog()

    func decode(
        _ file: AudioFileReference,
        chunkFrames: Int,
        receive: (PCMStreamDescription, PCMChunk) -> PCMChunkDisposition
    ) async throws(AudioDecodingError) -> PCMStreamDescription? {
        for (index, chunk) in chunks.enumerated() {
            if let failAfter, index == failAfter { throw error }
            if let suspendBefore, index == suspendBefore {
                await reached?.open()
                await release?.wait()
            }
            await log.record()
            if receive(stream, chunk) == .stop { return stream }
        }
        if failAfter != nil { throw error }
        await log.recordNormalEnd()
        return stream
    }
}

@Suite("App — the waveform's isolation as a shared consumer")
struct SharedWaveformIsolationTests {
    private func reference() -> AudioFileReference {
        AudioFileReference(
            displayName: "fixture", fileExtension: "wav", sizeBytes: nil, modifiedAt: nil,
            source: .userSelectedLocalFile(displayName: "fixture", locationDisclosure: .omitted)
        )
    }

    private func stream(frames: Int, channels: Int = 2) throws -> PCMStreamDescription {
        try #require(PCMStreamDescription(sampleRate: 44_100, channelCount: channels, frameCount: frames))
    }

    private func chunks(
        frames: Int, channels: Int = 2, per chunkFrames: Int = 1_024, sample: (Int) -> Float = {
            Float(0.5 * sin(2 * Double.pi * 997 * Double($0) / 44_100))
        }
    ) throws -> [PCMChunk] {
        var built: [PCMChunk] = []
        var start = 0
        while start < frames {
            let count = min(chunkFrames, frames - start)
            let samples = (0 ..< count).map { sample(start + $0) }
            built.append(try PCMChunk(startFrame: start, channels: Array(repeating: samples, count: channels)))
            start += count
        }
        return built
    }

    // MARK: - Independent references

    /// Each analysis's own result for the same chunks and the same stream, produced with no part of the
    /// composition involved. This is what "the outcome it would have had" means, and comparing against
    /// it is stronger than comparing two runs of the same composition.
    private func referenceOutcomes(
        _ material: [PCMChunk], stream description: PCMStreamDescription
    ) throws -> (spectrogram: SpectrogramOutcome, levels: SignalLevelMetricsOutcome, truePeak: TruePeakOutcome) {
        var spectrogram = try #require(
            SpectrogramAccumulator(
                sampleRate: description.sampleRate, channelCount: description.channelCount,
                frameCount: description.frameCount
            )
        )
        var levels = try #require(SignalLevelMetricsAccumulator(channelCount: description.channelCount))
        var truePeak = try #require(TruePeakAccumulator(channelCount: description.channelCount))
        for chunk in material {
            spectrogram.accumulate(chunk)
            levels.accumulate(chunk)
            truePeak.accumulate(chunk)
        }
        let finishedTruePeak = truePeak.finish()
        return (
            .available(try #require(spectrogram.finish())),
            .available(try #require(levels.finish())),
            .available(try #require(finishedTruePeak))
        )
    }

    /// The waveform's own reference, the same way.
    private func referenceEnvelope(
        _ material: [PCMChunk], stream description: PCMStreamDescription
    ) throws -> WaveformEnvelope {
        var accumulator = try #require(
            WaveformEnvelopeAccumulator(
                totalFrameCount: description.frameCount, channelCount: description.channelCount
            )
        )
        for chunk in material {
            for channel in 0 ..< chunk.channelCount {
                try chunk.channels[channel].withUnsafeBufferPointer { buffer throws(WaveformError) in
                    try accumulator.accumulate(buffer, ofChannel: channel, startingAtFrame: chunk.startFrame)
                }
            }
        }
        return try accumulator.finished()
    }

    // MARK: - 5.1 — the waveform failing is the waveform's own failure

    /// **The one reachable waveform-only failure**: a read that ends before covering the stream leaves
    /// buckets nothing reached, and the reduction refuses to invent them.
    ///
    /// There is deliberately **no "control run without the failure" over the same input**, because none
    /// exists: this input always fails the waveform. The control is each survivor's own accumulator fed
    /// the identical chunks against the identical stream — which is a stronger reference than a second
    /// run of the same composition, since it shares none of its code.
    @Test("a waveform failure leaves all three survivors byte-for-byte as they would have been")
    func waveformFailureLeavesTheSurvivorsIdentical() async throws {
        let declared = 16_384
        let material = try chunks(frames: 8_192)
        let description = try stream(frames: declared)
        let expected = try referenceOutcomes(material, stream: description)

        let outcome = await SharedPCMAnalysisGeneration(
            decoder: ScriptedDecoder(stream: description, chunks: material)
        ).run(for: reference())

        guard case let .failed(message) = outcome.waveform else {
            Issue.record("expected the waveform to fail, got \(outcome.waveform)"); return
        }
        #expect(message.contains("waveform"), "the failure did not name the waveform")

        #expect(outcome.spectrogram == expected.spectrogram)
        #expect(outcome.signalLevelMetrics == expected.levels)
        #expect(outcome.truePeak == expected.truePeak)
    }

    /// **The read outlives the consumer, observed at the port.** Every chunk is handed over and the
    /// decode returns normally — not inferred from a result that happens to look complete.
    @Test("the read reaches the end of the stream even though the waveform will fail")
    func theReadFinishesDespiteTheWaveform() async throws {
        let material = try chunks(frames: 8_192)
        let decoder = ScriptedDecoder(stream: try stream(frames: 16_384), chunks: material)

        let outcome = await SharedPCMAnalysisGeneration(decoder: decoder).run(for: reference())

        guard case .failed = outcome.waveform else {
            Issue.record("expected the waveform to fail"); return
        }
        #expect(await decoder.log.delivered == material.count, "the read stopped early")
        #expect(await decoder.log.finishedNormally, "the decode did not reach the end of the stream")
    }

    // MARK: - 5.2 — another consumer failing leaves the waveform alone

    /// True peak is the one sibling with a failure a valid chunk can reach: its 48-tap reconstruction
    /// overflows on finite-but-enormous samples of alternating sign. The waveform reduces the same audio
    /// without difficulty — a minimum and a maximum cannot overflow — so this is a real, reachable test
    /// of the other direction rather than a symmetric assumption.
    @Test("true peak failing leaves the waveform's envelope exactly as it would have been")
    func aFailingSiblingLeavesTheWaveformAlone() async throws {
        let frames = 512
        let material = try chunks(frames: frames, per: frames) { index in
            index.isMultiple(of: 2) ? .greatestFiniteMagnitude : -.greatestFiniteMagnitude
        }
        let description = try stream(frames: frames)
        let expected = try referenceEnvelope(material, stream: description)

        let outcome = await SharedPCMAnalysisGeneration(
            decoder: ScriptedDecoder(stream: description, chunks: material)
        ).run(for: reference())

        guard case .failed = outcome.truePeak else {
            Issue.record("expected true peak to fail on this input, got \(outcome.truePeak)"); return
        }
        guard case let .available(envelope) = outcome.waveform else {
            Issue.record("a sibling's failure reached the waveform: \(outcome.waveform)"); return
        }
        #expect(envelope == expected, "the waveform's envelope changed when true peak failed")
        #expect(envelope.buckets.contains { $0.maximum == .greatestFiniteMagnitude })
    }

    // MARK: - 5.3 — a producer failure is a different thing

    /// Chunks are delivered first, so there **is** a partial envelope to leak, and then the decoder
    /// fails. All four end, each with its own sentence, and nothing partial is published.
    @Test("a decoder that fails partway ends all four, each on its own terms, publishing nothing partial")
    func producerFailureEndsEveryone() async throws {
        let material = try chunks(frames: 8_192)
        let decoder = ScriptedDecoder(
            stream: try stream(frames: 8_192), chunks: material, failAfter: 4
        )

        let outcome = await SharedPCMAnalysisGeneration(decoder: decoder).run(for: reference())

        #expect(await decoder.log.delivered == 4, "the failure did not come partway through")
        #expect(await decoder.log.finishedNormally == false)

        guard case let .failed(waveformMessage) = outcome.waveform,
              case let .failed(spectrogramMessage) = outcome.spectrogram,
              case let .failed(levelsMessage) = outcome.signalLevelMetrics,
              case let .failed(truePeakMessage) = outcome.truePeak
        else {
            Issue.record("a producer failure did not end every analysis: \(outcome)"); return
        }
        // Each keeps the wording it had when it read the file alone.
        #expect(waveformMessage.contains("waveform"))
        #expect(spectrogramMessage.contains("spectrogram"))
        #expect(levelsMessage.contains("signal level metrics"))
        #expect(truePeakMessage.contains("true peak"))
        #expect(Set([waveformMessage, spectrogramMessage, levelsMessage, truePeakMessage]).count == 4)
    }

    /// **The case where a partial model would actually be publishable**, and therefore the one worth
    /// guarding: the decoder hands over **every** chunk and only then fails. The waveform's coverage is
    /// complete at that moment, so `finished()` would succeed — a composition that reached for it would
    /// hand back a perfectly plausible envelope produced by a read that failed.
    ///
    /// It must not. A read that ended in failure produces no model, however finished the accumulation
    /// happens to look.
    @Test("a producer failing after the last chunk still publishes no envelope")
    func producerFailureAfterFullCoveragePublishesNothing() async throws {
        let material = try chunks(frames: 8_192)
        let decoder = ScriptedDecoder(
            stream: try stream(frames: 8_192), chunks: material, failAfter: material.count
        )

        let outcome = await SharedPCMAnalysisGeneration(decoder: decoder).run(for: reference())

        // Every chunk really was accumulated, so a complete envelope was there to be published.
        #expect(await decoder.log.delivered == material.count)
        #expect(await decoder.log.finishedNormally == false)
        guard case .failed = outcome.waveform else {
            Issue.record("a failed read published an envelope: \(outcome.waveform)"); return
        }
        guard case .failed = outcome.spectrogram, case .failed = outcome.signalLevelMetrics,
              case .failed = outcome.truePeak
        else {
            Issue.record("a producer failure did not end every analysis"); return
        }
    }

    // MARK: - 5.4 — cancellation

    /// Cancellation forced **deterministically**: the decoder suspends at a chunk this test chose, the
    /// task is cancelled there, and only then is the read released. A handshake, not a hope.
    @Test("cancelling mid-read cancels all four and lets no partial envelope escape")
    func cancellingMidReadCancelsEveryone() async throws {
        let material = try chunks(frames: 8_192)
        let reached = Gate()
        let release = Gate()
        let decoder = ScriptedDecoder(
            stream: try stream(frames: 8_192), chunks: material,
            suspendBefore: 4, reached: reached, release: release
        )

        let running = Task { await SharedPCMAnalysisGeneration(decoder: decoder).run(for: reference()) }
        await reached.wait()
        running.cancel()
        await release.open()
        let outcome = await running.value

        #expect(outcome.waveform == .cancelled, "a cancelled read published a waveform")
        #expect(outcome.spectrogram == .cancelled)
        #expect(outcome.signalLevelMetrics == .cancelled)
        #expect(outcome.truePeak == .cancelled)
        #expect(await decoder.log.finishedNormally == false, "a cancelled read reached the end anyway")
        #expect(await decoder.log.delivered < material.count, "every chunk was delivered despite cancellation")
    }

    /// Cancelled before a single chunk exists: still cancellation, never an empty envelope. An empty
    /// envelope is what a file with no frames produces, and a cancelled read must not be mistaken for
    /// one.
    @Test("cancelling before the first chunk yields cancellation, never an empty envelope")
    func cancellingBeforeTheFirstChunk() async throws {
        let material = try chunks(frames: 8_192)
        let reached = Gate()
        let release = Gate()
        let decoder = ScriptedDecoder(
            stream: try stream(frames: 8_192), chunks: material,
            suspendBefore: 0, reached: reached, release: release
        )

        let running = Task { await SharedPCMAnalysisGeneration(decoder: decoder).run(for: reference()) }
        await reached.wait()
        running.cancel()
        await release.open()
        let outcome = await running.value

        #expect(outcome.waveform == .cancelled)
        #expect(await decoder.log.delivered == 1, "the cancellation was not observed on the first chunk")
        if case .available = outcome.waveform {
            Issue.record("a cancelled read published an envelope")
        }
    }

    // MARK: - Absence is not failure, and the four empty answers stay apart

    /// The four ways a read can produce nothing, for the waveform specifically. Collapsing any pair
    /// would tell a user something untrue about their file, and each is asserted against the others
    /// rather than only against itself.
    @Test("the four ways the waveform produces nothing stay distinguishable")
    func theFourEmptyAnswersStayApart() async throws {
        let material = try chunks(frames: 8_192)
        let description = try stream(frames: 8_192)

        // 1. A stream of zero frames: a complete answer with no buckets.
        let zeroFrames = await SharedPCMAnalysisGeneration(
            decoder: ScriptedDecoder(stream: try stream(frames: 0), chunks: [])
        ).run(for: reference())

        // 2. No usable frame count at all: an absence caused by the file.
        let noLength = await SharedPCMAnalysisGeneration(decoder: FakeAudioDecoding(.absent)).run(for: reference())

        // 3. A resolution the stream cannot be mapped to: also an absence, and the waveform's alone.
        let unmappable = await SharedPCMAnalysisGeneration(
            decoder: ScriptedDecoder(stream: description, chunks: material), maximumBucketCount: .max
        ).run(for: reference())

        // 4. The producer failing: a failure, with a message.
        let failed = await SharedPCMAnalysisGeneration(
            decoder: ScriptedDecoder(stream: description, chunks: material, failAfter: 0)
        ).run(for: reference())

        guard case let .available(empty) = zeroFrames.waveform else {
            Issue.record("zero frames did not produce a complete empty answer: \(zeroFrames.waveform)"); return
        }
        #expect(empty.buckets.isEmpty)
        #expect(noLength.waveform == .unavailable)
        #expect(unmappable.waveform == .unavailable)
        guard case .failed = failed.waveform else {
            Issue.record("a producer failure was not a failure: \(failed.waveform)"); return
        }

        // And no two of them are the same answer.
        #expect(zeroFrames.waveform != noLength.waveform, "an empty answer collapsed into an absence")
        #expect(noLength.waveform != failed.waveform, "an absence collapsed into a failure")
        #expect(unmappable.waveform != failed.waveform, "an absence collapsed into a failure")
    }

    /// **Absence leaves the siblings alone too**, which failure and absence must both do — otherwise
    /// only one of the two paths would have been checked.
    @Test("a waveform that is absent leaves all three survivors as they would have been")
    func absenceLeavesTheSurvivorsIdentical() async throws {
        let material = try chunks(frames: 8_192)
        let description = try stream(frames: 8_192)
        let expected = try referenceOutcomes(material, stream: description)

        let outcome = await SharedPCMAnalysisGeneration(
            decoder: ScriptedDecoder(stream: description, chunks: material), maximumBucketCount: .max
        ).run(for: reference())

        #expect(outcome.waveform == .unavailable)
        #expect(outcome.spectrogram == expected.spectrogram)
        #expect(outcome.signalLevelMetrics == expected.levels)
        #expect(outcome.truePeak == expected.truePeak)
    }

    // MARK: - What could not be observed, and why

    /// **"The waveform stops receiving chunks once it has failed" is not observable, and this records
    /// why rather than pretending otherwise.**
    ///
    /// The composition does skip a faulted waveform — `accumulate(_:)` checks the fault before folding —
    /// but there is no input that reaches that branch. Of the three errors
    /// `WaveformEnvelopeAccumulator.accumulate` can throw, every one is already impossible by the time a
    /// chunk arrives:
    ///
    /// - `channelOutOfBounds` — the accumulator is built with the stream's channel count and the
    ///   composition refuses a chunk whose channel count differs;
    /// - `frameRangeOutOfBounds` — it is built with the stream's frame count and the composition refuses
    ///   a chunk that does not fit that stream;
    /// - `nonFiniteSample` — `PCMChunk` refuses non-finite samples at construction.
    ///
    /// So the waveform's only reachable failure arrives at `finished()`, **after** the last chunk, and
    /// there is nothing left to stop receiving. The assertions below are the alarm: if any of these
    /// three guards weakens, the branch becomes reachable and this test starts failing, at which point
    /// the property becomes observable and should be tested for real.
    ///
    /// This is a *mechanism is sound* statement, not a *both directions were observed* one, and the
    /// difference is deliberate.
    @Test("the waveform has no failure a valid chunk can trigger, so it never stops mid-read")
    func theWaveformHasNoReachableAccumulationFailure() throws {
        // A stream always has at least one channel, so the accumulator always builds for a real stream.
        #expect(PCMStreamDescription(sampleRate: 44_100, channelCount: 0, frameCount: 1_024) == nil)
        #expect(WaveformEnvelopeAccumulator(totalFrameCount: 1_024, channelCount: 0) == nil)
        #expect(WaveformEnvelopeAccumulator(totalFrameCount: 1_024, channelCount: 1) != nil)

        // A chunk carrying a non-finite sample cannot exist.
        #expect(throws: AudioDecodingError.self) {
            _ = try PCMChunk(startFrame: 0, channels: [[0.5, .nan]])
        }

        // And a chunk that does not fit its stream is refused before any consumer sees it.
        let description = try #require(PCMStreamDescription(sampleRate: 44_100, channelCount: 1, frameCount: 1_000))
        #expect(!(try PCMChunk(startFrame: 999, channels: [[0.1, 0.2]]).fits(description)))
        #expect(try PCMChunk(startFrame: 998, channels: [[0.1, 0.2]]).fits(description))
    }
}
