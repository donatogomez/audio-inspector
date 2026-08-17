import AVFoundation
import Foundation
import Testing

import AudioInspectorAnalysis
import AudioInspectorDomain
import AudioInspectorMedia
import AudioInspectorTesting
import FeatureImport

@testable import AudioInspectorApp

// The waveform as the **fourth consumer** of the shared read.
//
// The legacy `WaveformGenerating` path is deliberately still alive, and that is what makes this suite
// possible: every equivalence assertion below compares the shared envelope against the one the file's
// own read produces, on the same file, through the real AVFoundation adapters. Retiring the old path
// is group 3's job precisely so this comparison exists first.

// MARK: - A decoder the test can stop in the middle of

/// A one-shot gate. `wait()` suspends until `open()` is called, and returns immediately afterwards.
/// The same mechanism the shared-PCM isolation tests already use: no sleep, no polling, no
/// `Task.yield()`.
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

/// A decoder that suspends before delivering its first chunk, so a test can cancel the surrounding
/// task at a point it chose rather than at one it hopes for.
private struct GatedDecoder: AudioDecoding {
    let stream: PCMStreamDescription
    let chunks: [PCMChunk]
    let reached: Gate
    let release: Gate

    func decode(
        _ file: AudioFileReference,
        chunkFrames: Int,
        receive: (PCMStreamDescription, PCMChunk) -> PCMChunkDisposition
    ) async throws(AudioDecodingError) -> PCMStreamDescription? {
        await reached.open()
        await release.wait()
        for chunk in chunks where receive(stream, chunk) == .stop { return stream }
        return stream
    }
}

@Suite("App — the waveform is produced by the shared read")
struct SharedWaveformConsumerTests {
    private func reference(named name: String = "fixture") -> AudioFileReference {
        AudioFileReference(
            displayName: name, fileExtension: "wav", sizeBytes: nil, modifiedAt: nil,
            source: .userSelectedLocalFile(displayName: name, locationDisclosure: .omitted)
        )
    }

    private func stream(frames: Int, channels: Int = 2, sampleRate: Double = 44_100) throws -> PCMStreamDescription {
        try #require(PCMStreamDescription(sampleRate: sampleRate, channelCount: channels, frameCount: frames))
    }

    /// Chunks covering `frames` exactly, each channel a recognisable run.
    private func chunks(
        frames: Int, channels: Int = 2, per chunkFrames: Int = 1_024, amplitude: Float = 0.5
    ) throws -> [PCMChunk] {
        var built: [PCMChunk] = []
        var start = 0
        while start < frames {
            let count = min(chunkFrames, frames - start)
            let samples = (0 ..< count).map { index in
                amplitude * Float(sin(2 * Double.pi * 997 * Double(start + index) / 44_100))
            }
            built.append(try PCMChunk(startFrame: start, channels: Array(repeating: samples, count: channels)))
            start += count
        }
        return built
    }

    /// The envelope the shared read produced, or a recorded failure.
    private func sharedEnvelope(
        decoder: any AudioDecoding, chunkFrames: Int = 4_096, maximumBucketCount: Int? = nil
    ) async throws -> WaveformEnvelope {
        let outcome = await run(decoder: decoder, chunkFrames: chunkFrames, maximumBucketCount: maximumBucketCount)
        guard case let .available(envelope) = outcome.waveform else {
            Issue.record("expected an available shared waveform, got \(outcome.waveform)")
            throw CancellationError()
        }
        return envelope
    }

    private func run(
        decoder: any AudioDecoding, chunkFrames: Int = 4_096, maximumBucketCount: Int? = nil
    ) async -> SharedPCMAnalysisOutcome {
        if let maximumBucketCount {
            return await SharedPCMAnalysisGeneration(
                decoder: decoder, chunkFrames: chunkFrames, maximumBucketCount: maximumBucketCount
            ).run(for: reference())
        }
        return await SharedPCMAnalysisGeneration(decoder: decoder, chunkFrames: chunkFrames).run(for: reference())
    }

    /// The largest absolute difference between two envelopes, bucket by bucket. `nil` when they do not
    /// even describe the same reduction, which is a different failure from a numeric one.
    private func worstDifference(_ a: WaveformEnvelope, _ b: WaveformEnvelope) -> Float? {
        guard a.buckets.count == b.buckets.count, a.frameCount == b.frameCount,
              a.channelCount == b.channelCount
        else { return nil }
        var worst: Float = 0
        for (left, right) in zip(a.buckets, b.buckets) {
            worst = max(worst, abs(left.minimum - right.minimum))
            worst = max(worst, abs(left.maximum - right.maximum))
        }
        return worst
    }

    // MARK: - Equivalence against the file's own read

    /// **The oracle is the legacy path, on the same file, through the real adapters.**
    ///
    /// Lossless containers are asserted **exactly**: sharing changes how samples arrive, not what is
    /// computed from them, and a decoder that returns the same bytes for a different read granularity
    /// leaves nothing for a tolerance to absorb.
    @Test(
        "the shared envelope is exactly the one the file's own read produces",
        arguments: [
            (AudioFixtureFormat.wav, 1 as AVAudioChannelCount, AudioFixtureSignal.sine(frequency: 440, amplitude: 0.5)),
            (.wav, 2, .sine(frequency: 440, amplitude: 0.5)),
            (.flac, 2, .sine(frequency: 440, amplitude: 0.5)),
            (.wav, 2, .silence),
            (.flac, 2, .oppositePolarity(frequency: 440, amplitude: 0.5)),
            (.wav, 2, .impulse(amplitude: 0.9, frameIndex: 1_000)),
        ]
    )
    func losslessEquivalence(
        format: AudioFixtureFormat, channels: AVAudioChannelCount, signal: AudioFixtureSignal
    ) async throws {
        try await withTemporaryDirectory { directory in
            let url = try writeAudioFixture(
                AudioFixtureSpec(
                    name: "equivalence", format: format, signal: signal, channels: channels, frames: 44_100
                ),
                in: directory
            )
            let file = reference()

            let legacy = try #require(
                try await AVFoundationWaveformGenerator(resolveURL: { _ in url }).makeWaveform(for: file)
            )
            let shared = try await sharedEnvelope(decoder: AVFoundationAudioDecoder(resolveURL: { _ in url }))

            #expect(shared == legacy, "the shared envelope differs from the file's own read")
        }
    }

    /// A very short file — fewer frames than the bucket cap, so every bucket holds a single frame and
    /// the mapping's `min(totalFrameCount, maximumBucketCount)` branch is the one under test.
    @Test("a file shorter than the bucket cap reduces identically through both paths")
    func shortFileEquivalence() async throws {
        try await withTemporaryDirectory { directory in
            let url = try writeAudioFixture(
                AudioFixtureSpec(
                    name: "short", format: .wav, signal: .sine(frequency: 440, amplitude: 0.5), frames: 512
                ),
                in: directory
            )
            let legacy = try #require(
                try await AVFoundationWaveformGenerator(resolveURL: { _ in url }).makeWaveform(for: reference())
            )
            let shared = try await sharedEnvelope(decoder: AVFoundationAudioDecoder(resolveURL: { _ in url }))

            #expect(shared.buckets.count == 512)
            #expect(shared == legacy)
        }
    }

    /// **Amplitude beyond full scale, which no writable container round-trips.**
    ///
    /// A 16-bit WAV clamps it and FLAC is integer too, so the oracle here is the reduction itself: the
    /// same accumulator, fed the same chunks directly. That is not a weaker check — it is the exact
    /// rule the shared pass must not alter, and `PCMChunk` deliberately keeps such samples.
    @Test("a sample beyond full scale survives the shared pass unclamped")
    func beyondFullScaleIsPreserved() async throws {
        let frames = 8_192
        let material = try chunks(frames: frames, amplitude: 2.5)
        let shared = try await sharedEnvelope(
            decoder: FakeAudioDecoding(streaming: try stream(frames: frames), chunks: material)
        )

        var oracle = try #require(WaveformEnvelopeAccumulator(totalFrameCount: frames, channelCount: 2))
        for chunk in material {
            for channel in 0 ..< chunk.channelCount {
                try oracle.accumulate(chunk.channels[channel], ofChannel: channel, startingAtFrame: chunk.startFrame)
            }
        }
        #expect(shared == (try oracle.finished()))
        #expect(shared.buckets.contains { $0.maximum > 1 }, "a sample beyond full scale was clamped")
    }

    // MARK: - AAC: exact too, and the record of a hypothesis that fell

    /// **A lossy container reduces identically through both paths, and the tolerance this test was
    /// designed around turned out not to be needed.**
    ///
    /// The pre-implementation probe reported AAC differing in 1 778 of 2 048 buckets by about one ULP,
    /// and the design and ADR-0021 were written expecting a tolerance here. Measured again through the
    /// production composition — the same file, the same decoder, the same accumulator, the same bucket
    /// count, and at the probe's own ten-minute length — the worst bucket error is **exactly zero**, for
    /// a pure sine and for a per-channel signal the encoder cannot fold together. The probe's finding
    /// does not reproduce and is recorded as an artefact of that throwaway harness rather than defended.
    ///
    /// So AAC is asserted **exactly**, like the lossless containers. The worst error is still computed
    /// and printed: if a platform update ever does make the two read paths disagree, this reports the
    /// magnitude instead of merely failing.
    @Test(
        "the shared envelope is exactly the file's own read for a lossy container too",
        arguments: [441_000, 2_646_000]
    )
    func lossyEquivalenceIsExactToo(frameCount: Int) async throws {
        try await withTemporaryDirectory { directory in
            let url = try writeAudioFixture(
                AudioFixtureSpec(
                    name: "lossy-\(frameCount)", format: .aac,
                    signal: .perChannelSine(frequencies: [440, 997], amplitude: 0.5),
                    frames: AVAudioFrameCount(frameCount)
                ),
                in: directory
            )
            let legacy = try #require(
                try await AVFoundationWaveformGenerator(resolveURL: { _ in url }).makeWaveform(for: reference())
            )
            let shared = try await sharedEnvelope(decoder: AVFoundationAudioDecoder(resolveURL: { _ in url }))

            let worst = try #require(
                worstDifference(shared, legacy),
                "the two envelopes do not describe the same reduction"
            )
            print("AAC \(frameCount) frames — worst bucket error: \(worst)")
            #expect(worst == 0, "AAC no longer reduces identically through both paths: worst error \(worst)")
            #expect(shared == legacy)
        }
    }

    // MARK: - Chunk independence

    /// The reduction's own order-independence guarantee, observed through the shared read at the chunk
    /// sizes a caller might actually pass — including one frame at a time and the whole file at once.
    @Test(
        "the shared envelope is identical whatever the chunk size",
        arguments: [1, 3, 127, 512, 2_048, 4_096, 8_192, 65_536, 200_000]
    )
    func chunkSizeIndependence(chunkFrames: Int) async throws {
        try await withTemporaryDirectory { directory in
            let url = try writeAudioFixture(
                AudioFixtureSpec(
                    name: "chunking", format: .wav, signal: .sine(frequency: 440, amplitude: 0.5),
                    frames: framesWithShortFinalChunkAtAnyChunkSize
                ),
                in: directory
            )
            let legacy = try #require(
                try await AVFoundationWaveformGenerator(resolveURL: { _ in url }).makeWaveform(for: reference())
            )
            let shared = try await sharedEnvelope(
                decoder: AVFoundationAudioDecoder(resolveURL: { _ in url }), chunkFrames: chunkFrames
            )
            #expect(shared == legacy, "chunk size \(chunkFrames) changed the envelope")
        }
    }

    // MARK: - `startFrame` is the position, not a coincidence

    /// The accumulator places every sample by the absolute frame it is told. Feeding the chunks **out
    /// of file order** must therefore change nothing — which is only true if the position comes from
    /// `chunk.startFrame` rather than from the order of arrival.
    @Test("the envelope comes from each chunk's own startFrame, not from the order they arrive in")
    func positionComesFromTheChunk() async throws {
        let frames = 8_192
        let material = try chunks(frames: frames, per: 512)
        let forwards = try await sharedEnvelope(
            decoder: FakeAudioDecoding(streaming: try stream(frames: frames), chunks: material)
        )
        let backwards = try await sharedEnvelope(
            decoder: FakeAudioDecoding(streaming: try stream(frames: frames), chunks: material.reversed())
        )
        #expect(forwards == backwards, "the envelope depended on the order the chunks arrived in")
    }

    // MARK: - Absence, emptiness and failure stay three different things

    /// A file with no audio: no chunk is delivered, and the answer is a **complete** envelope with no
    /// buckets — exactly what the legacy generator returns for `frameCount == 0`.
    @Test("a file with no audio yields an empty envelope, not an absence")
    func noAudioIsACompleteAnswer() async throws {
        let outcome = await run(decoder: FakeAudioDecoding(streaming: try stream(frames: 0), chunks: []))
        guard case let .available(envelope) = outcome.waveform else {
            Issue.record("expected an available empty envelope, got \(outcome.waveform)"); return
        }
        #expect(envelope.buckets.isEmpty)
        #expect(envelope.frameCount == 0)
    }

    /// A file whose length could not be established is an **absence** for every consumer, and the
    /// waveform's own port says the same thing by returning `nil`.
    @Test("a file with no usable frame count is absent for the waveform too")
    func noUsableLengthIsAnAbsence() async throws {
        let outcome = await run(decoder: FakeAudioDecoding(.absent))
        #expect(outcome.waveform == .unavailable)
        #expect(outcome.spectrogram == .unavailable)
    }

    /// **The absence the shared pass could most easily have turned into a failure.** A stream this
    /// resolution cannot be mapped to buckets is a file that offered nothing to size an envelope
    /// against — the legacy port returns `nil` for it — so it must stay `unavailable`, and it must not
    /// disturb the three consumers that can still be built.
    @Test("a resolution the stream cannot be mapped to is an absence, and only the waveform's")
    func unmappableResolutionIsAnAbsenceAlone() async throws {
        let frames = 8_192
        let material = try chunks(frames: frames)
        let outcome = await run(
            decoder: FakeAudioDecoding(streaming: try stream(frames: frames), chunks: material),
            maximumBucketCount: .max
        )
        #expect(outcome.waveform == .unavailable, "an absence was reported as a failure")

        let control = await run(decoder: FakeAudioDecoding(streaming: try stream(frames: frames), chunks: material))
        #expect(outcome.spectrogram == control.spectrogram)
        #expect(outcome.signalLevelMetrics == control.signalLevelMetrics)
        #expect(outcome.truePeak == control.truePeak)
    }

    // MARK: - Isolation

    /// **The waveform failing alone, on the one input that reaches it.**
    ///
    /// A read that ends before covering the stream leaves buckets uncovered, and the accumulator refuses
    /// to invent a flat stretch the file may not contain. The other three do not require coverage, so
    /// they settle exactly as they would have — asserted against the accumulators fed the same chunks
    /// directly, which is a stronger control than another run of the same composition.
    @Test("the waveform failing leaves every other analysis exactly as it would have been")
    func waveformFailureIsItsOwn() async throws {
        let declared = 16_384
        let material = try chunks(frames: 8_192) // covers half the stream
        let outcome = await run(
            decoder: FakeAudioDecoding(streaming: try stream(frames: declared), chunks: material)
        )

        guard case let .failed(message) = outcome.waveform else {
            Issue.record("expected the waveform to fail on incomplete coverage, got \(outcome.waveform)"); return
        }
        #expect(message.contains("waveform"), "the waveform's failure did not name the waveform")

        var spectrogram = try #require(
            SpectrogramAccumulator(sampleRate: 44_100, channelCount: 2, frameCount: declared)
        )
        var levels = try #require(SignalLevelMetricsAccumulator(channelCount: 2))
        var truePeak = try #require(TruePeakAccumulator(channelCount: 2))
        for chunk in material {
            spectrogram.accumulate(chunk)
            levels.accumulate(chunk)
            truePeak.accumulate(chunk)
        }
        let finishedTruePeak = truePeak.finish()
        #expect(outcome.spectrogram == .available(try #require(spectrogram.finish())))
        #expect(outcome.signalLevelMetrics == .available(try #require(levels.finish())))
        #expect(outcome.truePeak == .available(try #require(finishedTruePeak)))
    }

    /// The read is not ended by the waveform leaving it: every chunk the decoder had is still handed
    /// over, which is what keeps the other three complete.
    @Test("a waveform that has left the read does not shorten it for the others")
    func aFaultedWaveformDoesNotEndTheRead() async throws {
        let frames = 8_192
        let decoder = FakeAudioDecoding(
            streaming: try stream(frames: 16_384), chunks: try chunks(frames: frames, per: 1_024)
        )
        _ = await run(decoder: decoder)
        #expect(await decoder.spy.lastDeliveredChunkCount == 8, "the read stopped early")
    }

    // MARK: - Cancellation

    /// A cancelled read cancels **every** consumer, the waveform included, and publishes no partial
    /// envelope.
    @Test("a decoder reporting cancellation cancels the waveform too")
    func decoderCancellationCancelsTheWaveform() async throws {
        let outcome = await run(
            decoder: FakeAudioDecoding(failingWith: AudioDecodingError(code: .cancelled, message: "cancelled"))
        )
        #expect(outcome.waveform == .cancelled)
        #expect(outcome.spectrogram == .cancelled)
        #expect(outcome.signalLevelMetrics == .cancelled)
        #expect(outcome.truePeak == .cancelled)
    }

    /// **Cancellation observed inside the callback, deterministically.** The decoder suspends at a point
    /// this test chose, the task is cancelled there, and only then is the read released — a handshake,
    /// not a hope. No sleep, no polling, no `Task.yield()`.
    @Test("a task cancelled mid-read cancels the waveform and leaks no partial envelope")
    func cancellationMidReadCancelsTheWaveform() async throws {
        let frames = 8_192
        let reached = Gate()
        let release = Gate()
        let decoder = GatedDecoder(
            stream: try stream(frames: frames), chunks: try chunks(frames: frames, per: 1_024),
            reached: reached, release: release
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
    }

    // MARK: - The producer failing

    /// A decoder failure ends every consumer, each reporting **its own** outcome — the waveform's is
    /// the sentence `SourceInspectionCoordinator` already produces for a failed generation.
    @Test("a decoder failure ends the waveform with its own message")
    func producerFailureGivesTheWaveformItsOwnMessage() async throws {
        let outcome = await run(
            decoder: FakeAudioDecoding(failingWith: AudioDecodingError(code: .readFailed, message: "boom"))
        )
        guard case let .failed(message) = outcome.waveform else {
            Issue.record("expected the waveform to fail, got \(outcome.waveform)"); return
        }
        #expect(message == "The waveform for this file could not be produced.")
        guard case let .failed(spectrogramMessage) = outcome.spectrogram else {
            Issue.record("expected the spectrogram to fail"); return
        }
        #expect(message != spectrogramMessage, "two analyses reported the same failure")
    }
}
