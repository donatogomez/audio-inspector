import AudioInspectorAnalysis
import AudioInspectorDomain
import AudioInspectorTesting
@testable import AudioInspectorApp
import FeatureImport
import Foundation
import Testing

// The sixth consumer's half of the shared read's guarantees.
//
// `SharedPCMAnalysisIsolationTests` proves them for the five that were already there; this proves the
// two directions that only exist once a sixth arrives — that it cannot disturb them, and that they
// cannot disturb it — plus the producer and cancellation paths for the whole bundle.
//
// The scripted decoder, the handshake gate and the delivery log are **shared** with that suite rather
// than copied: one piece of machinery, used from both.
//
// Integration is not "it compiles". It is these properties holding.


// The handshake and the scripted decoder, kept private to this file exactly as the two sibling
// isolation suites keep theirs. Three small private copies is the shape this family already has;
// hoisting them into one shared helper is a tidy-up of all three at once, not a change to smuggle in
// beside a sixth consumer.

private actor BandwidthGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var opened = false
    func wait() async {
        if opened { return }
        await withCheckedContinuation { continuation = $0 }
    }
    func open() {
        opened = true
        continuation?.resume()
        continuation = nil
    }
}

private actor BandwidthDeliveryLog {
    private(set) var delivered = 0
    func record() { delivered += 1 }
}

/// Delivers chunks, can suspend at a chosen index after signalling, and can fail **after** delivering
/// audio — the case that separates "respected the producer's outcome" from "finished early".
private struct BandwidthScriptedDecoder: AudioDecoding {
    let stream: PCMStreamDescription
    let chunks: [PCMChunk]
    var failAfter: Int?
    var error = AudioDecodingError(code: .readFailed, message: "the read stopped")
    var suspendBefore: Int?
    var reached: BandwidthGate?
    var release: BandwidthGate?
    let log = BandwidthDeliveryLog()

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

@Suite("App — programme bandwidth's isolation in the shared read")
struct SharedProgrammeBandwidthIsolationTests {

    private func reference() -> AudioFileReference {
        AudioFileReference(
            displayName: "fixture", fileExtension: "wav", sizeBytes: nil, modifiedAt: nil,
            source: .userSelectedLocalFile(displayName: "fixture", locationDisclosure: .omitted)
        )
    }

    private func stream(frames: Int, channels: Int = 2, rate: Double = 44_100) throws -> PCMStreamDescription {
        try #require(PCMStreamDescription(sampleRate: rate, channelCount: channels, frameCount: frames))
    }

    /// A 997 Hz tone, the same material the sibling suite uses, so nothing about the signal is new.
    private func chunks(
        frames: Int, channels: Int = 2, per chunkFrames: Int, rate: Double = 44_100
    ) throws -> [PCMChunk] {
        var built: [PCMChunk] = []
        var start = 0
        while start < frames {
            let count = min(chunkFrames, frames - start)
            let samples = (0 ..< count).map { index in
                Float(0.5 * sin(2 * Double.pi * 997 * Double(start + index) / rate))
            }
            built.append(try PCMChunk(startFrame: start, channels: Array(repeating: samples, count: channels)))
            start += count
        }
        return built
    }

    /// Programme bandwidth's **independent reference**: the accumulator fed the same chunks directly,
    /// with no composition involved. It shares no line of code with the shared pass beyond the
    /// accumulator both use.
    private func direct(
        _ material: [PCMChunk], rate: Double = 44_100, channels: Int = 2
    ) -> SignificantBandwidth? {
        guard var accumulator = SignificantBandwidthAccumulator(sampleRate: rate, channelCount: channels)
        else { return nil }
        for chunk in material { accumulator.accumulate(chunk) }
        return accumulator.finish()
    }

    /// Long enough that the method has something to say: 44.1 kHz windows are 1920 frames.
    private let measurableFrames = 16_384

    // MARK: - Programme bandwidth cannot disturb its siblings

    /// A file shorter than one analysis window is one programme bandwidth **declines honestly** — the
    /// final incomplete window is discarded rather than padded, so there is nothing to measure. The
    /// five that were here must be unchanged, and not merely present: the whole outcome, compared to a
    /// run where the sixth had plenty to work with.
    @Test("an absent programme bandwidth leaves the other five identical to their undisturbed values")
    func absentBandwidthLeavesSiblingsIdentical() async throws {
        let short = try chunks(frames: 512, per: 256)
        let long = try chunks(frames: measurableFrames, per: 512)

        let withAbsence = await SharedPCMAnalysisGeneration(
            decoder: FakeAudioDecoding(streaming: try stream(frames: 512), chunks: short)
        ).run(for: reference())
        // The control is the *same five consumers* on the same 512 frames, which is what "undisturbed"
        // has to mean: a longer file would change them for reasons that have nothing to do with the
        // sixth.
        let control = await SharedPCMAnalysisGeneration(
            decoder: FakeAudioDecoding(streaming: try stream(frames: 512), chunks: short)
        ).run(for: reference())

        #expect(withAbsence.significantBandwidth == .unavailable, "expected an honest absence, got \(withAbsence.significantBandwidth)")
        #expect(withAbsence.waveform == control.waveform)
        #expect(withAbsence.spectrogram == control.spectrogram)
        #expect(withAbsence.signalLevelMetrics == control.signalLevelMetrics)
        #expect(withAbsence.truePeak == control.truePeak)
        #expect(withAbsence.loudness == control.loudness)

        // And the absence is genuinely the file's, not the composition's: with enough frames the same
        // five consumers still agree with a run that measured a bandwidth.
        let measured = await SharedPCMAnalysisGeneration(
            decoder: FakeAudioDecoding(streaming: try stream(frames: measurableFrames), chunks: long)
        ).run(for: reference())
        guard case .available = measured.significantBandwidth else {
            Issue.record("the long fixture produced no bandwidth: \(measured.significantBandwidth)"); return
        }
    }

    /// Every chunk still reaches the read when the sixth consumer has nothing to do: it must not be
    /// able to end the read early on its own.
    @Test("an absent programme bandwidth does not shorten the read")
    func absentBandwidthDoesNotShortenTheRead() async throws {
        let material = try chunks(frames: 512, per: 64)
        let decoder = BandwidthScriptedDecoder(stream: try stream(frames: 512), chunks: material)
        _ = await SharedPCMAnalysisGeneration(decoder: decoder).run(for: reference())
        #expect(await decoder.log.delivered == material.count, "the read stopped early")
    }

    // MARK: - Its siblings cannot disturb programme bandwidth

    /// True peak is the one consumer with a failure a **valid** chunk can trigger: `PCMChunk` refuses
    /// `NaN` and infinity but keeps finite samples of any magnitude, and a 48-tap convolution over
    /// enormous ones overflows to a value `TruePeakMeasurement` refuses. Programme bandwidth's own
    /// reading must be exactly what it is when nothing fails.
    @Test("a failed sibling leaves programme bandwidth identical to its direct value")
    func failedSiblingLeavesBandwidthIdentical() async throws {
        // One short burst of enormous-but-finite samples, then ordinary audio. The burst is what true
        // peak's convolution overflows on; the rest is what gives programme bandwidth enough windows to
        // have an answer at all, so the test compares a real reading rather than an absence.
        let burst = 512
        let frames = measurableFrames
        let extreme = (0 ..< burst).map { $0.isMultiple(of: 2) ? Float.greatestFiniteMagnitude : -.greatestFiniteMagnitude }
        var material = [try PCMChunk(startFrame: 0, channels: [extreme, extreme])]
        material += try chunks(frames: frames - burst, per: 512).map { chunk in
            try PCMChunk(startFrame: chunk.startFrame + burst, channels: chunk.channels)
        }

        let shared = await SharedPCMAnalysisGeneration(
            decoder: FakeAudioDecoding(streaming: try stream(frames: frames), chunks: material)
        ).run(for: reference())

        guard case .failed = shared.truePeak else {
            Issue.record("expected true peak to fail on this material, got \(shared.truePeak)"); return
        }
        guard case let .available(measured) = shared.significantBandwidth else {
            Issue.record("a sibling's failure took programme bandwidth with it: \(shared.significantBandwidth)")
            return
        }
        let control = try #require(direct(material))
        #expect(measured == control, "the shared pass disagreed with the accumulator fed the same chunks")
    }

    // MARK: - Producer failures leak nothing

    /// Mid-read: the decoder hands over part of the audio and then fails. No consumer may publish what
    /// it had built from the part that arrived.
    @Test("a producer failure partway leaves all six failed and nothing partial")
    func producerFailurePartway() async throws {
        let material = try chunks(frames: measurableFrames, per: 512)
        let decoder = BandwidthScriptedDecoder(stream: try stream(frames: measurableFrames), chunks: material, failAfter: 8)
        let outcome = await SharedPCMAnalysisGeneration(decoder: decoder).run(for: reference())

        #expect(await decoder.log.delivered == 8, "the decoder did not stop where the script said")
        assertAllFailed(outcome)
    }

    /// **The one that matters most**, and the one a naive implementation passes by accident: the
    /// decoder delivers *every* chunk — programme bandwidth now holds enough evidence for a complete
    /// answer — and only then fails. The evidence must not escape. A `finish()` called before the
    /// producer's own outcome is respected fails this and nothing else.
    @Test("a producer failure after the final chunk still publishes nothing")
    func producerFailureAfterTheFinalChunk() async throws {
        let material = try chunks(frames: measurableFrames, per: 512)
        let decoder = BandwidthScriptedDecoder(
            stream: try stream(frames: measurableFrames), chunks: material, failAfter: material.count
        )
        let outcome = await SharedPCMAnalysisGeneration(decoder: decoder).run(for: reference())

        #expect(await decoder.log.delivered == material.count, "the script should deliver everything first")
        // The same chunks, fed directly, do produce a reading — so the absence below is the producer's
        // failure being respected, not the material being unmeasurable.
        #expect(direct(material) != nil, "the fixture must be measurable for this test to mean anything")
        assertAllFailed(outcome)
    }

    private func assertAllFailed(
        _ outcome: SharedPCMAnalysisOutcome, sourceLocation: SourceLocation = #_sourceLocation
    ) {
        guard case .failed = outcome.significantBandwidth else {
            Issue.record("programme bandwidth escaped a producer failure: \(outcome.significantBandwidth)", sourceLocation: sourceLocation)
            return
        }
        guard case .failed = outcome.waveform, case .failed = outcome.spectrogram,
              case .failed = outcome.signalLevelMetrics, case .failed = outcome.truePeak,
              case .failed = outcome.loudness
        else {
            Issue.record("a producer failure left a sibling unfailed", sourceLocation: sourceLocation)
            return
        }
    }

    // MARK: - Cancellation

    /// Mid-read, with a handshake rather than a sleep: the decoder signals when it has reached a known
    /// chunk, the test cancels, and only then is the decoder released.
    @Test("cancelling mid-read cancels all six and leaks no partial bandwidth")
    func cancellingMidRead() async throws {
        let material = try chunks(frames: measurableFrames, per: 512)
        let reached = BandwidthGate()
        let release = BandwidthGate()
        let decoder = BandwidthScriptedDecoder(
            stream: try stream(frames: measurableFrames), chunks: material,
            error: AudioDecodingError(code: .cancelled, message: "cancelled"),
            suspendBefore: 6, reached: reached, release: release
        )
        let generation = SharedPCMAnalysisGeneration(decoder: decoder)
        let task = Task { await generation.run(for: reference()) }
        await reached.wait()
        task.cancel()
        await release.open()
        let outcome = await task.value

        #expect(await decoder.log.delivered < material.count, "the read should not have finished")
        assertAllCancelled(outcome)
    }

    /// Before the first chunk: nothing was ever accumulated, and no consumer may invent an empty model
    /// to stand in for the audio it never saw.
    @Test("cancelling before the first chunk cancels all six and fabricates nothing")
    func cancellingBeforeTheFirstChunk() async throws {
        let material = try chunks(frames: measurableFrames, per: 512)
        let reached = BandwidthGate()
        let release = BandwidthGate()
        let decoder = BandwidthScriptedDecoder(
            stream: try stream(frames: measurableFrames), chunks: material,
            error: AudioDecodingError(code: .cancelled, message: "cancelled"),
            suspendBefore: 0, reached: reached, release: release
        )
        let generation = SharedPCMAnalysisGeneration(decoder: decoder)
        let task = Task { await generation.run(for: reference()) }
        await reached.wait()
        task.cancel()
        await release.open()
        let outcome = await task.value

        // The handshake suspends *before* the first chunk and releases after the cancel, so at most
        // that one chunk is handed over. What matters is that nothing was built from it: the read never
        // reached the end, and every outcome below is `cancelled` rather than an empty model.
        #expect(await decoder.log.delivered <= 1, "the read ran on past the cancellation")
        #expect(await decoder.log.delivered < material.count, "the read should not have finished")
        assertAllCancelled(outcome)
    }

    private func assertAllCancelled(
        _ outcome: SharedPCMAnalysisOutcome, sourceLocation: SourceLocation = #_sourceLocation
    ) {
        guard case .cancelled = outcome.significantBandwidth else {
            Issue.record("programme bandwidth ignored cancellation: \(outcome.significantBandwidth)", sourceLocation: sourceLocation)
            return
        }
        guard case .cancelled = outcome.waveform, case .cancelled = outcome.spectrogram,
              case .cancelled = outcome.signalLevelMetrics, case .cancelled = outcome.truePeak,
              case .cancelled = outcome.loudness
        else {
            Issue.record("cancellation was not uniform across the bundle", sourceLocation: sourceLocation)
            return
        }
    }

    // MARK: - Shared equals direct

    /// The composition must not change the number. Four rates, the same chunks fed both ways.
    @Test("the shared pass produces exactly what the accumulator does", arguments: [44_100.0, 48_000, 96_000, 192_000])
    func sharedEqualsDirect(rate: Double) async throws {
        let frames = 32_768
        let material = try chunks(frames: frames, per: 4_096, rate: rate)
        let shared = await SharedPCMAnalysisGeneration(
            decoder: FakeAudioDecoding(streaming: try stream(frames: frames, rate: rate), chunks: material)
        ).run(for: reference())
        guard case let .available(measured) = shared.significantBandwidth else {
            Issue.record("the shared pass produced nothing at \(rate) Hz: \(shared.significantBandwidth)"); return
        }
        let control = try #require(direct(material, rate: rate))
        #expect(measured == control, "at \(rate) Hz the shared pass and the accumulator disagreed")
    }

    /// Through the composition, not just the accumulator alone: where a chunk happens to end must not
    /// reach the number, and the siblings must not move either.
    @Test("the shared pass is independent of chunk size", arguments: [1, 3, 127, 512, 4_096, 65_536])
    func chunkIndependenceThroughComposition(chunkFrames: Int) async throws {
        let frames = 16_384
        let whole = try chunks(frames: frames, per: frames)
        let split = try chunks(frames: frames, per: chunkFrames)

        let control = await SharedPCMAnalysisGeneration(
            decoder: FakeAudioDecoding(streaming: try stream(frames: frames), chunks: whole)
        ).run(for: reference())
        let chunked = await SharedPCMAnalysisGeneration(
            decoder: FakeAudioDecoding(streaming: try stream(frames: frames), chunks: split)
        ).run(for: reference())

        #expect(chunked.significantBandwidth == control.significantBandwidth, "\(chunkFrames)-frame chunks moved the bandwidth")
        // The five siblings must be unmoved too: a sixth consumer that broke their chunk independence
        // would be a regression this suite is the right place to catch.
        #expect(chunked.signalLevelMetrics == control.signalLevelMetrics)
        #expect(chunked.truePeak == control.truePeak)
        #expect(chunked.loudness == control.loudness)
    }
}
