import Foundation
import Testing

import AudioInspectorAnalysis
import AudioInspectorDomain
import AudioInspectorTesting
import FeatureImport

@testable import AudioInspectorApp

// MARK: - A decoder the test can stop in the middle of

/// A one-shot gate. `wait()` suspends until `open()` is called, and returns immediately afterwards.
///
/// This is the whole synchronisation mechanism these tests use. There is **no sleep, no polling and no
/// `Task.yield()`**: the decoder suspends at a point the test chose, the test acts, and the decoder is
/// released. Nothing here depends on one task winning a race against another.
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

/// Counts what a decode actually handed over, so a test can assert the read stopped rather than infer
/// it from an outcome.
private actor DeliveryLog {
    private(set) var delivered = 0
    func record() { delivered += 1 }
}

/// A decoder that can be suspended at a chosen chunk, and that can fail **after** delivering audio.
///
/// `FakeAudioDecoding` covers the outcomes that need no timing. This covers the two that do: stopping
/// the read at a known point so the test can cancel the surrounding task, and failing partway through so
/// the composition is asked to answer for chunks it already accumulated.
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
        return stream
    }
}

/// The guarantees the shared read must keep, each proved rather than inferred.
///
/// Group 2's suite asserts what the composition *produces*; this one asserts what it must keep true
/// while producing it — that one analysis cannot disturb another, that a producer failure is a
/// different thing from a consumer failure, and that a cancelled read leaks nothing.
@Suite("App — the shared read's isolation guarantees")
struct SharedPCMAnalysisIsolationTests {
    private func reference() -> AudioFileReference {
        AudioFileReference(
            displayName: "fixture",
            fileExtension: "wav",
            sizeBytes: nil,
            modifiedAt: nil,
            source: .userSelectedLocalFile(displayName: "fixture", locationDisclosure: .omitted)
        )
    }

    private func stream(frames: Int, channels: Int = 2) throws -> PCMStreamDescription {
        try #require(PCMStreamDescription(sampleRate: 44_100, channelCount: channels, frameCount: frames))
    }

    private func chunks(frames: Int, channels: Int = 2, per chunkFrames: Int) throws -> [PCMChunk] {
        var built: [PCMChunk] = []
        var start = 0
        while start < frames {
            let count = min(chunkFrames, frames - start)
            let samples = (0 ..< count).map { index in
                Float(0.5 * sin(2 * Double.pi * 997 * Double(start + index) / 44_100))
            }
            built.append(try PCMChunk(startFrame: start, channels: Array(repeating: samples, count: channels)))
            start += count
        }
        return built
    }

    /// True peak's **independent reference**: the accumulator fed the same chunks directly, with no
    /// composition involved. There is no `TruePeakGeneration` to compare against — true peak was never
    /// wired as an operation of its own — so this is what "what it produces on its own" means for it,
    /// and it shares no line of code with the shared pass beyond the accumulator both use.
    private func referenceTruePeak(_ material: [PCMChunk], channelCount: Int = 2) -> TruePeakMeasurement? {
        guard var accumulator = TruePeakAccumulator(channelCount: channelCount) else { return nil }
        for chunk in material { accumulator.accumulate(chunk) }
        return accumulator.finish()
    }

    // MARK: - 3.1 — a consumer's failure is invisible to the others

    /// The spectrogram cannot be built for this stream while the signal level metrics can, so exactly
    /// one consumer leaves the read. The other must not merely survive: it must produce **the same
    /// value, byte for byte**, that it produces when nothing fails.
    @Test("a failed consumer leaves the other's result identical to its undisturbed value")
    func failedConsumerLeavesTheOtherIdentical() async throws {
        let frames = 4_096
        let material = try chunks(frames: frames, per: 512)

        let withFailure = await SharedPCMAnalysisGeneration(
            decoder: FakeAudioDecoding(streaming: try stream(frames: Int.max), chunks: material)
        ).run(for: reference())
        let control = await SharedPCMAnalysisGeneration(
            decoder: FakeAudioDecoding(streaming: try stream(frames: frames), chunks: material)
        ).run(for: reference())

        guard case .failed = withFailure.spectrogram else {
            Issue.record("expected the spectrogram to fail, got \(withFailure.spectrogram)"); return
        }
        // Not "available", not "not nil": the whole outcome, compared to the run where nothing failed.
        #expect(withFailure.signalLevelMetrics == control.signalLevelMetrics)
        // And the same for the consumer added last: a third analysis in the loop is a third analysis
        // that must not notice the first one leaving.
        #expect(withFailure.truePeak == control.truePeak)
    }

    /// **The mirror direction, which now has a real input.** True peak is the one consumer with a
    /// failure a *valid* chunk can trigger: `PCMChunk` refuses `NaN` and infinity but keeps finite
    /// samples of any magnitude, and a 48-tap convolution over enormous ones overflows to a value
    /// `TruePeakMeasurement` refuses. The file is deliberately shorter than one FFT window, so the
    /// spectrogram transforms nothing and cannot overflow with it — leaving exactly one consumer failing.
    @Test("a failed true peak leaves the other two results identical to their undisturbed values")
    func failedTruePeakLeavesTheOthersIdentical() async throws {
        let frames = 512
        let extreme = (0 ..< frames).map { $0.isMultiple(of: 2) ? Float.greatestFiniteMagnitude : -.greatestFiniteMagnitude }
        let overflowing = [try PCMChunk(startFrame: 0, channels: [extreme, extreme])]
        let description = try stream(frames: frames)

        let withFailure = await SharedPCMAnalysisGeneration(
            decoder: FakeAudioDecoding(streaming: description, chunks: overflowing)
        ).run(for: reference())
        // The control is the same audio through the same composition, read by the analyses that do not
        // fail on it — so any difference below is true peak's failure leaking, not the input.
        let separateSpectrogram = await SpectrogramGeneration(
            decoder: FakeAudioDecoding(streaming: description, chunks: overflowing)
        ).run(for: reference())
        let separateLevels = await SignalLevelMetricsGeneration(
            decoder: FakeAudioDecoding(streaming: description, chunks: overflowing)
        ).run(for: reference())

        guard case .failed = withFailure.truePeak else {
            Issue.record("expected true peak to fail, got \(withFailure.truePeak)"); return
        }
        // The spectrogram's whole outcome, compared exactly, exactly as 3.1 compares it.
        #expect(withFailure.spectrogram == separateSpectrogram)

        // **Signal levels cannot be compared with `==` on this input, and the reason is IEEE rather
        // than a difference.** Samples this large square to infinity in `Float`, so its RMS is `inf`
        // and its DC offset is `NaN` — and `NaN != NaN` by definition, which makes the two identical
        // outcomes compare unequal. Every field that *is* comparable is compared instead, against the
        // separate read of the same audio; the incomparable ones are named rather than skipped
        // silently, and both being `NaN` is itself asserted.
        guard case let .available(sharedLevels) = withFailure.signalLevelMetrics,
              case let .available(separate) = separateLevels else {
            Issue.record("true peak's failure took the signal level metrics with it"); return
        }
        #expect(sharedLevels.channels.map(\.sampleCount) == separate.channels.map(\.sampleCount))
        #expect(sharedLevels.channels.map(\.peakSample) == separate.channels.map(\.peakSample))
        #expect(sharedLevels.channels.map(\.clippedSampleCount) == separate.channels.map(\.clippedSampleCount))
        #expect(sharedLevels.overallPeakSample == separate.overallPeakSample)
        #expect(sharedLevels.overallClippedSampleCount == separate.overallClippedSampleCount)
        #expect(sharedLevels.overallDCOffset?.isNaN == separate.overallDCOffset?.isNaN)
        #expect(sharedLevels.overallRMS == separate.overallRMS)
        guard case .available = withFailure.spectrogram else {
            Issue.record("true peak's failure took the spectrogram with it"); return
        }
    }

    /// True peak leaving must not end the read for the others either — the same property 3.1 proved for
    /// the spectrogram, asserted for the consumer that can now genuinely fail on valid audio.
    @Test("the read continues to the end after true peak fails")
    func theReadContinuesAfterTruePeakFails() async throws {
        let frames = 512
        let perChunk = 64
        var material: [PCMChunk] = []
        var start = 0
        while start < frames {
            let count = min(perChunk, frames - start)
            let extreme = (0 ..< count).map { (start + $0).isMultiple(of: 2) ? Float.greatestFiniteMagnitude : -.greatestFiniteMagnitude }
            material.append(try PCMChunk(startFrame: start, channels: [extreme, extreme]))
            start += count
        }
        let decoder = ScriptedDecoder(stream: try stream(frames: frames), chunks: material)

        let outcome = await SharedPCMAnalysisGeneration(decoder: decoder).run(for: reference())

        guard case .failed = outcome.truePeak else {
            Issue.record("expected true peak to fail, got \(outcome.truePeak)"); return
        }
        #expect(await decoder.log.delivered == material.count)
    }

    /// A consumer leaving must not end the read for the others — the decode has to run to the end.
    @Test("the read continues to the end after a consumer fails")
    func theReadContinuesAfterAConsumerFails() async throws {
        let frames = 4_096
        let material = try chunks(frames: frames, per: 512)
        let decoder = ScriptedDecoder(stream: try stream(frames: Int.max), chunks: material)

        let outcome = await SharedPCMAnalysisGeneration(decoder: decoder).run(for: reference())

        guard case .failed = outcome.spectrogram else {
            Issue.record("expected the spectrogram to fail"); return
        }
        // Every chunk was still offered: the surviving consumer got the whole file.
        #expect(await decoder.log.delivered == material.count)
    }

    /// The mirror direction has no input, and this says so in a way that stops passing if that changes.
    @Test("signal level metrics still have no failure a valid stream can trigger")
    func signalLevelMetricsHaveNoReachableSoloFailure() {
        #expect(PCMStreamDescription(sampleRate: 44_100, channelCount: 0, frameCount: 1_024) == nil)
        #expect(SignalLevelMetricsAccumulator(channelCount: 0) == nil)
        #expect(SignalLevelMetricsAccumulator(channelCount: 1) != nil)
        #expect(SignalLevelMetricsAccumulator(channelCount: 2) != nil)
    }

    // MARK: - 3.2 — a producer failure is a different thing from a consumer failure

    /// **Producer failure, after audio was already accumulated.** The composition holds partial state
    /// for both consumers when the read dies; neither may present it as a finished model.
    @Test("a decoder that fails partway publishes no partial model")
    func producerFailurePartwayPublishesNothingPartial() async throws {
        let frames = 8_192
        let material = try chunks(frames: frames, per: 512)
        let decoder = ScriptedDecoder(stream: try stream(frames: frames), chunks: material, failAfter: 8)

        let outcome = await SharedPCMAnalysisGeneration(decoder: decoder).run(for: reference())

        // Chunks really were accumulated before the failure — otherwise this proves nothing.
        #expect(await decoder.log.delivered == 8)
        guard case let .failed(spectrogramMessage) = outcome.spectrogram else {
            Issue.record("a partial spectrogram escaped: \(outcome.spectrogram)"); return
        }
        guard case let .failed(levelsMessage) = outcome.signalLevelMetrics else {
            Issue.record("partial signal level metrics escaped: \(outcome.signalLevelMetrics)"); return
        }
        guard case let .failed(truePeakMessage) = outcome.truePeak else {
            Issue.record("a partial true peak escaped: \(outcome.truePeak)"); return
        }
        // Each answers for itself. A reader of one never has to consult the others, and there is no
        // shared "the read failed" anywhere for them to consult.
        #expect(spectrogramMessage != levelsMessage)
        #expect(truePeakMessage != spectrogramMessage)
        #expect(truePeakMessage != levelsMessage)
    }

    /// The two failures are **distinguishable by their effect**, which is the point of separating them:
    /// a consumer failure leaves the other analysis available, a producer failure does not.
    @Test("a consumer failure and a producer failure are distinguishable")
    func consumerAndProducerFailuresAreDistinguishable() async throws {
        let frames = 4_096
        let material = try chunks(frames: frames, per: 512)

        let consumerFailure = await SharedPCMAnalysisGeneration(
            decoder: FakeAudioDecoding(streaming: try stream(frames: Int.max), chunks: material)
        ).run(for: reference())
        let producerFailure = await SharedPCMAnalysisGeneration(
            decoder: ScriptedDecoder(stream: try stream(frames: frames), chunks: material, failAfter: 2)
        ).run(for: reference())

        // Both fail the spectrogram...
        guard case .failed = consumerFailure.spectrogram, case .failed = producerFailure.spectrogram else {
            Issue.record("expected both scenarios to fail the spectrogram"); return
        }
        // ...and only one of them takes the other analysis down with it.
        guard case .available = consumerFailure.signalLevelMetrics,
              case .available = consumerFailure.truePeak else {
            Issue.record("a consumer failure ended another analysis"); return
        }
        guard case .failed = producerFailure.signalLevelMetrics,
              case .failed = producerFailure.truePeak else {
            Issue.record("a producer failure left an analysis available"); return
        }
    }

    // MARK: - 3.3 — cancellation, with a handshake rather than a hope

    /// Cancels the inspection while the decoder is **suspended inside the read**, at a point the test
    /// chose. Deterministic: the decoder signals it has arrived, waits, and only continues once the test
    /// releases it — after cancelling.
    @Test("cancelling mid-read cancels every analysis and leaks no partial model")
    func cancellingMidReadCancelsEverything() async throws {
        let frames = 8_192
        let material = try chunks(frames: frames, per: 512)
        let reached = Gate()
        let release = Gate()
        let decoder = ScriptedDecoder(
            stream: try stream(frames: frames), chunks: material,
            suspendBefore: 4, reached: reached, release: release
        )

        let task = Task { await SharedPCMAnalysisGeneration(decoder: decoder).run(for: reference()) }

        // The decoder is now inside the read, four chunks in, and going nowhere until released.
        await reached.wait()
        task.cancel()
        await release.open()
        let outcome = await task.value

        #expect(outcome.spectrogram == .cancelled)
        #expect(outcome.signalLevelMetrics == .cancelled)
        #expect(outcome.truePeak == .cancelled)
        // It stopped at the boundary it noticed, rather than reading the rest of the file.
        #expect(await decoder.log.delivered < material.count)
    }

    /// Cancellation observed **before any audio is accumulated**: the decoder suspends before its first
    /// chunk, the test cancels, and the composition must refuse the chunk it is then offered.
    @Test("cancelling before the first chunk yields cancellation, never an empty model")
    func cancellingBeforeTheFirstChunk() async throws {
        let frames = 8_192
        let material = try chunks(frames: frames, per: 512)
        let reached = Gate()
        let release = Gate()
        let decoder = ScriptedDecoder(
            stream: try stream(frames: frames), chunks: material,
            suspendBefore: 0, reached: reached, release: release
        )

        let task = Task { await SharedPCMAnalysisGeneration(decoder: decoder).run(for: reference()) }
        await reached.wait()
        task.cancel()
        await release.open()
        let outcome = await task.value

        // An empty model would be the dangerous answer here: it is a *complete* answer for a file with
        // no audio, and this file has plenty.
        #expect(outcome.spectrogram == .cancelled)
        #expect(outcome.signalLevelMetrics == .cancelled)
        #expect(outcome.truePeak == .cancelled)
        #expect(await decoder.log.delivered == 1)
    }

    // MARK: - 3.4 — the four ways a read can produce nothing, kept apart

    /// **A — a stream, but no chunks.** Inherited behaviour, not invented here: each analysis reports the
    /// empty model it has always reported for this input, which is what the separate reads did.
    @Test("a stream that hands over no chunks yields each analysis's own empty answer")
    func streamWithNoChunks() async throws {
        let description = try stream(frames: 8_192)
        let shared = await SharedPCMAnalysisGeneration(
            decoder: FakeAudioDecoding(streaming: description, chunks: [])
        ).run(for: reference())
        let separateSpectrogram = await SpectrogramGeneration(
            decoder: FakeAudioDecoding(streaming: description, chunks: [])
        ).run(for: reference())
        let separateLevels = await SignalLevelMetricsGeneration(
            decoder: FakeAudioDecoding(streaming: description, chunks: [])
        ).run(for: reference())

        #expect(shared.spectrogram == separateSpectrogram)
        #expect(shared.signalLevelMetrics == separateLevels)
        // No chunks means nothing was measured: every channel reports `nil` rather than a measured
        // zero, which is a complete answer for a file with no audio and not an absence.
        #expect(shared.truePeak == .available(try #require(referenceTruePeak([]))))
    }

    /// **B — a valid stream of zero frames.** A file with no audio: a complete answer, not an absence.
    @Test("a stream of zero frames yields a complete empty answer, not a failure")
    func zeroFrameStream() async throws {
        let description = try stream(frames: 0)
        let shared = await SharedPCMAnalysisGeneration(
            decoder: FakeAudioDecoding(streaming: description, chunks: [])
        ).run(for: reference())
        let separateSpectrogram = await SpectrogramGeneration(
            decoder: FakeAudioDecoding(streaming: description, chunks: [])
        ).run(for: reference())
        let separateLevels = await SignalLevelMetricsGeneration(
            decoder: FakeAudioDecoding(streaming: description, chunks: [])
        ).run(for: reference())

        #expect(shared.spectrogram == separateSpectrogram)
        #expect(shared.signalLevelMetrics == separateLevels)
        #expect(shared.truePeak == .available(try #require(referenceTruePeak([]))))
        guard case .available = shared.spectrogram, case .available = shared.signalLevelMetrics,
              case let .available(measurement) = shared.truePeak else {
            Issue.record("a file with no audio was reported as something other than available"); return
        }
        // Not a measured zero — the absence of a maximum, which is what an unmeasured channel has.
        #expect(measurement.channels.allSatisfy { $0.truePeak == nil && $0.sampleCount == 0 })
        #expect(measurement.overallTruePeak == nil)
    }

    /// **C — no usable frame count.** An absence caused by the file, and it is *not* a failure.
    @Test("no usable frame count is an absence, distinct from a failure")
    func absentIsNotFailure() async throws {
        let shared = await SharedPCMAnalysisGeneration(decoder: FakeAudioDecoding(.absent)).run(for: reference())
        #expect(shared.spectrogram == .unavailable)
        #expect(shared.signalLevelMetrics == .unavailable)
        #expect(shared.truePeak == .unavailable)
    }

    /// **D — a real decoder failure.** Distinct from all three above.
    @Test("the four ways a read produces nothing stay distinguishable from one another")
    func theFourEmptyOutcomesAreDistinct() async throws {
        let noChunks = await SharedPCMAnalysisGeneration(
            decoder: FakeAudioDecoding(streaming: try stream(frames: 8_192), chunks: [])
        ).run(for: reference())
        let zeroFrames = await SharedPCMAnalysisGeneration(
            decoder: FakeAudioDecoding(streaming: try stream(frames: 0), chunks: [])
        ).run(for: reference())
        let absent = await SharedPCMAnalysisGeneration(decoder: FakeAudioDecoding(.absent)).run(for: reference())
        let failed = await SharedPCMAnalysisGeneration(
            decoder: FakeAudioDecoding(failingWith: AudioDecodingError(code: .readFailed, message: "boom"))
        ).run(for: reference())

        // Absence and failure are never the same answer, and neither is ever an empty model.
        #expect(absent.signalLevelMetrics == .unavailable)
        #expect(absent.signalLevelMetrics != failed.signalLevelMetrics)
        #expect(noChunks.signalLevelMetrics != absent.signalLevelMetrics)
        #expect(zeroFrames.signalLevelMetrics != absent.signalLevelMetrics)
        #expect(zeroFrames.signalLevelMetrics != failed.signalLevelMetrics)
        // The two "empty model" cases agree with each other, because both describe a read that produced
        // no audio — the difference between them is the file, not the answer.
        #expect(noChunks.signalLevelMetrics == zeroFrames.signalLevelMetrics)
    }

    // MARK: - 3.5 — chunk-size independence, compared against the same chunking

    /// For each chunk size, the shared read is compared against **separate reads fed the identical chunk
    /// sequence**. That isolates the question this task asks — does sharing change the result — from the
    /// unrelated one of whether chunking itself changes it, which each accumulator answers for itself.
    @Test(
        "the shared read matches separate reads exactly, at every chunk size",
        arguments: [1, 3, 127, 512, 1_024, 2_048, 4_096, 8_192, 65_536]
    )
    func sharedMatchesSeparateAtEveryChunkSize(_ chunkFrames: Int) async throws {
        let frames = 8_192
        let description = try stream(frames: frames)
        let material = try chunks(frames: frames, per: chunkFrames)

        let separateSpectrogram = await SpectrogramGeneration(
            decoder: FakeAudioDecoding(streaming: description, chunks: material)
        ).run(for: reference())
        let separateLevels = await SignalLevelMetricsGeneration(
            decoder: FakeAudioDecoding(streaming: description, chunks: material)
        ).run(for: reference())
        let shared = await SharedPCMAnalysisGeneration(
            decoder: FakeAudioDecoding(streaming: description, chunks: material)
        ).run(for: reference())

        // Full equality, no tolerance: both sides saw the same chunks, so sharing must change nothing.
        #expect(shared.spectrogram == separateSpectrogram, "spectrogram differed at chunk \(chunkFrames)")
        #expect(shared.signalLevelMetrics == separateLevels, "signal levels differed at chunk \(chunkFrames)")
        // **True peak, bit for bit.** This is the comparison `add-shared-pcm-read` recorded as owed and
        // could not make: its own guarantee is bit-exact chunk independence, stronger than anything the
        // other two promise, and sharing a read must not weaken it by a single ULP.
        #expect(
            shared.truePeak == .available(try #require(referenceTruePeak(material))),
            "true peak differed at chunk \(chunkFrames)"
        )
    }

    /// The whole file in one chunk, which is the boundary case the sizes above approach.
    @Test("the shared read matches separate reads when the file arrives in one chunk")
    func sharedMatchesSeparateInASingleChunk() async throws {
        let frames = 8_192
        let description = try stream(frames: frames)
        let material = try chunks(frames: frames, per: frames)
        #expect(material.count == 1)

        let separateSpectrogram = await SpectrogramGeneration(
            decoder: FakeAudioDecoding(streaming: description, chunks: material)
        ).run(for: reference())
        let separateLevels = await SignalLevelMetricsGeneration(
            decoder: FakeAudioDecoding(streaming: description, chunks: material)
        ).run(for: reference())
        let shared = await SharedPCMAnalysisGeneration(
            decoder: FakeAudioDecoding(streaming: description, chunks: material)
        ).run(for: reference())

        #expect(shared.spectrogram == separateSpectrogram)
        #expect(shared.signalLevelMetrics == separateLevels)
        #expect(shared.truePeak == .available(try #require(referenceTruePeak(material))))
    }

    /// The measurement is not merely equal to the reference — it is the **same at every chunk size**,
    /// which is the property that would break first if a consumer were fed a chunk the others were not.
    @Test("true peak is one value however the file was cut")
    func truePeakIsIdenticalAcrossEveryChunkSize() async throws {
        let frames = 8_192
        let description = try stream(frames: frames)
        var produced: [TruePeakMeasurement] = []

        for chunkFrames in [1, 3, 127, 512, 1_024, 2_048, 4_096, 8_192, 65_536] {
            let shared = await SharedPCMAnalysisGeneration(
                decoder: FakeAudioDecoding(streaming: description, chunks: try chunks(frames: frames, per: chunkFrames))
            ).run(for: reference())
            guard case let .available(measurement) = shared.truePeak else {
                Issue.record("true peak was not available at chunk \(chunkFrames)"); return
            }
            produced.append(measurement)
        }

        let first = try #require(produced.first)
        #expect(produced.allSatisfy { $0 == first }, "the shared read made true peak depend on the chunking")
        // A real value, so the equality above is not the trivial agreement of nine absences.
        #expect(try #require(first.overallTruePeak) > 0)
    }
}
