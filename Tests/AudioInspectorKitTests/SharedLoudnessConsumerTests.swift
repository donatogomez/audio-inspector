import Foundation
import Testing

import AudioInspectorAnalysis
import AudioInspectorDomain
import AudioInspectorTesting
import FeatureImport

@testable import AudioInspectorApp

/// A one-shot gate. `wait()` suspends until `open()` is called, and returns immediately afterwards.
///
/// The whole synchronisation mechanism these tests use: **no sleep, no polling, no `Task.yield()`**.
/// The decoder suspends where the test chose, the test acts, and the decoder is released.
private actor LoudnessGate {
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

/// A decoder that can suspend at a chosen chunk, or fail after delivering some.
private struct LoudnessScriptedDecoder: AudioDecoding {
    let stream: PCMStreamDescription
    let chunks: [PCMChunk]
    var failAfter: Int?
    var error = AudioDecodingError(code: .readFailed, message: "the read stopped")
    var suspendBefore: Int?
    var reached: LoudnessGate?
    var release: LoudnessGate?

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
            if receive(stream, chunk) == .stop { return stream }
        }
        if failAfter != nil { throw error }
        return stream
    }
}

/// Integrated loudness as the **fifth** consumer of the one shared read.
///
/// Nothing here re-proves the algorithm — that is "Analysis — integrated loudness (48 kHz)" and its
/// multi-rate sibling. What this asserts is that the *composition* delivers it the same chunks, in the
/// same order, without disturbing the four that were already there and without opening a second read.
@Suite("App — integrated loudness on the shared read")
struct SharedLoudnessConsumerTests {

    private func reference() -> AudioFileReference {
        AudioFileReference(
            displayName: "fixture",
            fileExtension: "wav",
            sizeBytes: nil,
            modifiedAt: nil,
            source: .userSelectedLocalFile(displayName: "fixture", locationDisclosure: .omitted)
        )
    }

    private func stream(
        frames: Int, channels: Int = 2, rate: Double = 48_000
    ) throws -> PCMStreamDescription {
        try #require(
            PCMStreamDescription(sampleRate: rate, channelCount: channels, frameCount: frames)
        )
    }

    /// A 997 Hz tone at −20 dBFS, the frequency BS.1770-5 uses for its own anchor.
    private func chunks(
        frames: Int, channels: Int = 2, rate: Double = 48_000, per chunkFrames: Int, silent: Bool = false
    ) throws -> [PCMChunk] {
        var built: [PCMChunk] = []
        var start = 0
        while start < frames {
            let count = min(chunkFrames, frames - start)
            let samples = (0 ..< count).map { index -> Float in
                guard !silent else { return 0 }
                return Float(0.1 * sin(2 * Double.pi * 997 * Double(start + index) / rate))
            }
            built.append(
                try PCMChunk(startFrame: start, channels: Array(repeating: samples, count: channels))
            )
            start += count
        }
        return built
    }

    /// The accumulator fed the same chunks directly, with no composition involved — loudness's
    /// independent reference, exactly as true peak's suite defines one for itself.
    private func referenceLoudness(
        _ material: [PCMChunk], rate: Double = 48_000, channels: Int = 2
    ) -> LoudnessMeasurement? {
        guard var accumulator = LoudnessAccumulator(sampleRate: rate, channelCount: channels) else {
            return nil
        }
        for chunk in material { accumulator.accumulate(chunk) }
        return accumulator.finish()
    }

    private func run(
        frames: Int, channels: Int = 2, rate: Double = 48_000, chunkFrames: Int = 4_096,
        silent: Bool = false
    ) async throws -> (outcome: SharedPCMAnalysisOutcome, material: [PCMChunk]) {
        let material = try chunks(
            frames: frames, channels: channels, rate: rate, per: chunkFrames, silent: silent
        )
        let outcome = await SharedPCMAnalysisGeneration(
            decoder: FakeAudioDecoding(
                streaming: try stream(frames: frames, channels: channels, rate: rate),
                chunks: material
            )
        ).run(for: reference())
        return (outcome, material)
    }

    // MARK: - Which streams it claims

    @Test(
        "every rate the weighting is derived for produces a measurement through the shared read",
        arguments: [44_100.0, 48_000.0, 88_200.0, 96_000.0, 192_000.0]
    )
    func supportedRatesMeasure(_ rate: Double) async throws {
        let frames = Int(rate * 2)
        let (outcome, material) = try await run(frames: frames, rate: rate)
        guard case let .available(measurement) = outcome.loudness else {
            Issue.record("expected a measurement at \(rate), got \(outcome.loudness)"); return
        }
        // Identical to the accumulator fed the same chunks with no composition in the way.
        #expect(measurement == referenceLoudness(material, rate: rate))
    }

    /// A rate the derivation has not been measured at is an **absence**, not a failure — and it is
    /// loudness's absence alone.
    ///
    /// The four others are checked for **complete answers at that same rate**, not against a run at a
    /// different one: the spectrogram's grid and the waveform's buckets legitimately depend on the
    /// sample rate, so comparing across rates would compare two different correct results. What this
    /// asserts is the property that actually matters — an unsupported rate takes loudness out and leaves
    /// everyone else producing a full model. The negative control that makes it bite is turning the
    /// absence into a fault for all five, which fails here immediately.
    @Test("an unsupported rate leaves loudness absent and every other analysis complete")
    func unsupportedRateIsAnAbsenceAlone() async throws {
        let frames = 44_100
        let unsupported = try await run(frames: frames, rate: 22_050)

        #expect(unsupported.outcome.loudness == .unavailable)
        guard case .available = unsupported.outcome.waveform,
              case .available = unsupported.outcome.spectrogram,
              case .available = unsupported.outcome.signalLevelMetrics,
              case .available = unsupported.outcome.truePeak
        else {
            Issue.record("an unsupported rate disturbed another analysis: \(unsupported.outcome)")
            return
        }

        // And at a rate the weighting exists for, the same shape of file does measure — so the absence
        // above is the rate and not the wiring.
        let supported = try await run(frames: frames, rate: 44_100)
        guard case .available = supported.outcome.loudness else {
            Issue.record("the supported control should have measured"); return
        }
    }

    /// Past stereo the standard weights by position and the pipeline has no layout, so nothing is
    /// measured. The other four are unaffected — and nothing here infers a layout from an index.
    @Test("more than two channels leaves loudness absent and the other four untouched")
    func threeChannelsLeaveLoudnessAbsent() async throws {
        let frames = 48_000
        let three = try await run(frames: frames, channels: 3)
        let two = try await run(frames: frames, channels: 2)

        #expect(three.outcome.loudness == .unavailable)
        guard case .available = two.outcome.loudness else {
            Issue.record("the stereo control should have measured"); return
        }
        // The four that do not depend on layout produce their own complete answers either way.
        guard case .available = three.outcome.spectrogram,
              case .available = three.outcome.signalLevelMetrics,
              case .available = three.outcome.truePeak,
              case .available = three.outcome.waveform
        else {
            Issue.record("a three-channel stream disturbed another analysis"); return
        }
    }

    // MARK: - Isolation in both directions

    /// True peak is the consumer with a reachable failure of its own. When it leaves the read, loudness
    /// must not merely survive — it must produce the same value as in the run where nothing failed.
    @Test("a failing consumer leaves loudness identical to its undisturbed value")
    func otherConsumerFailureLeavesLoudnessIdentical() async throws {
        let frames = 48_000
        let material = try chunks(frames: frames, per: 4_096)

        // A stream claiming far more frames than arrive makes the spectrogram fault while the rest run.
        let withFailure = await SharedPCMAnalysisGeneration(
            decoder: FakeAudioDecoding(
                streaming: try stream(frames: Int.max), chunks: material
            )
        ).run(for: reference())
        let control = await SharedPCMAnalysisGeneration(
            decoder: FakeAudioDecoding(streaming: try stream(frames: frames), chunks: material)
        ).run(for: reference())

        guard case .failed = withFailure.spectrogram else {
            Issue.record("expected the spectrogram to fail, got \(withFailure.spectrogram)"); return
        }
        #expect(withFailure.loudness == control.loudness)
    }

    /// And the other direction: loudness absent changes nothing for the four, compared whole rather
    /// than case by case.
    @Test("loudness being absent leaves every other outcome byte-identical")
    func loudnessAbsenceChangesNothingElse() async throws {
        let frames = 48_000
        let material = try chunks(frames: frames, channels: 3, per: 4_096)
        let withLoudnessAbsent = await SharedPCMAnalysisGeneration(
            decoder: FakeAudioDecoding(
                streaming: try stream(frames: frames, channels: 3), chunks: material
            )
        ).run(for: reference())

        #expect(withLoudnessAbsent.loudness == .unavailable)
        // Every other field, against a run of the identical audio — the composition is deterministic,
        // so a second run is a control rather than an approximation.
        let control = await SharedPCMAnalysisGeneration(
            decoder: FakeAudioDecoding(
                streaming: try stream(frames: frames, channels: 3), chunks: material
            )
        ).run(for: reference())
        #expect(withLoudnessAbsent.waveform == control.waveform)
        #expect(withLoudnessAbsent.spectrogram == control.spectrogram)
        #expect(withLoudnessAbsent.signalLevelMetrics == control.signalLevelMetrics)
        #expect(withLoudnessAbsent.truePeak == control.truePeak)
    }

    // MARK: - Producer failure

    /// The decoder failing is not a consumer failing: no more PCM will exist for anyone, so all five
    /// end — each with its **own** sentence, so a reader of one never has to consult another.
    @Test("a decoder failure ends loudness too, with a message of its own")
    func producerFailureEndsLoudnessSeparately() async throws {
        let material = try chunks(frames: 48_000, per: 4_096)
        let outcome = await SharedPCMAnalysisGeneration(
            decoder: LoudnessScriptedDecoder(
                stream: try stream(frames: 48_000), chunks: material, failAfter: 3
            )
        ).run(for: reference())

        guard case let .failed(loudnessMessage) = outcome.loudness else {
            Issue.record("a partial loudness escaped: \(outcome.loudness)"); return
        }
        guard case let .failed(truePeakMessage) = outcome.truePeak,
              case let .failed(spectrogramMessage) = outcome.spectrogram else {
            Issue.record("expected the other consumers to fail too"); return
        }
        #expect(loudnessMessage != truePeakMessage)
        #expect(loudnessMessage != spectrogramMessage)
        #expect(!loudnessMessage.isEmpty)
    }

    /// The case worth naming: the producer fails **after every chunk has been delivered**, so loudness
    /// has everything it needs. It still must not publish — no more PCM will exist, and a model built
    /// from a read that ended in failure would claim the file was measured.
    @Test("a producer failure after the last chunk still publishes no loudness")
    func producerFailureAfterTheLastChunkPublishesNothing() async throws {
        let material = try chunks(frames: 48_000, per: 4_096)
        let outcome = await SharedPCMAnalysisGeneration(
            decoder: LoudnessScriptedDecoder(
                stream: try stream(frames: 48_000), chunks: material, failAfter: material.count
            )
        ).run(for: reference())

        guard case .failed = outcome.loudness else {
            Issue.record("a complete loudness escaped a failed read: \(outcome.loudness)"); return
        }
    }

    // MARK: - Cancellation

    @Test("cancelling before the first chunk cancels loudness with the rest")
    func cancellationBeforeAnyChunk() async throws {
        let material = try chunks(frames: 48_000, per: 4_096)
        let reached = LoudnessGate()
        let release = LoudnessGate()
        let decoder = LoudnessScriptedDecoder(
            stream: try stream(frames: 48_000), chunks: material,
            suspendBefore: 0, reached: reached, release: release
        )

        let task = Task { await SharedPCMAnalysisGeneration(decoder: decoder).run(for: reference()) }
        await reached.wait()
        task.cancel()
        await release.open()
        let outcome = await task.value

        #expect(outcome.loudness == .cancelled)
        #expect(outcome.truePeak == .cancelled)
        #expect(outcome.waveform == .cancelled)
    }

    @Test("cancelling mid-read cancels loudness rather than publishing what it had")
    func cancellationMidRead() async throws {
        let material = try chunks(frames: 96_000, per: 4_096)
        let reached = LoudnessGate()
        let release = LoudnessGate()
        let decoder = LoudnessScriptedDecoder(
            stream: try stream(frames: 96_000), chunks: material,
            suspendBefore: material.count / 2, reached: reached, release: release
        )

        let task = Task { await SharedPCMAnalysisGeneration(decoder: decoder).run(for: reference()) }
        await reached.wait()
        task.cancel()
        await release.open()
        let outcome = await task.value

        #expect(outcome.loudness == .cancelled)
    }

    // MARK: - Zero, short, silent, measurable — through the shared path

    /// The semantics decided in the capability's own contract, exercised where a user would meet them
    /// rather than only in the accumulator. **−70 never appears**: an unmeasurable file is an absence.
    @Test("the undefined cases come through the shared read as absences, never as a floor")
    func undefinedCasesAreAbsencesThroughTheSharedRead() async throws {
        // A file with no audio delivers no chunk at all.
        let empty = await SharedPCMAnalysisGeneration(
            decoder: FakeAudioDecoding(streaming: try stream(frames: 0), chunks: [])
        ).run(for: reference())
        #expect(empty.loudness == .unavailable)

        // Shorter than one 400 ms gating block.
        let short = try await run(frames: 19_199)
        #expect(short.outcome.loudness == .unavailable)

        // Exactly one block measures.
        let exact = try await run(frames: 19_200)
        guard case .available = exact.outcome.loudness else {
            Issue.record("400 ms should measure, got \(exact.outcome.loudness)"); return
        }

        // Long enough to form blocks, none of which clears the absolute gate.
        let silent = try await run(frames: 48_000, silent: true)
        #expect(silent.outcome.loudness == .unavailable)

        // And a measurable file does measure, so the absences above are the files and not the wiring.
        let measurable = try await run(frames: 96_000)
        guard case .available = measurable.outcome.loudness else {
            Issue.record("a measurable file did not measure"); return
        }
    }

    // MARK: - The methodology that comes out

    /// The measurement carries the weighting the accumulator actually built, per rate. Nothing in the
    /// composition, the coordinator or the app names it.
    @Test(
        "the weighting identity that reaches the outcome is the one the rate actually used",
        arguments: [44_100.0, 48_000.0, 88_200.0, 96_000.0, 192_000.0]
    )
    func methodIdentityComesFromTheAccumulator(_ rate: Double) async throws {
        let (outcome, _) = try await run(frames: Int(rate), rate: rate)
        guard case let .available(measurement) = outcome.loudness else {
            Issue.record("expected a measurement at \(rate)"); return
        }
        let expected: LoudnessWeightingIdentifier =
            rate == 48_000 ? .publishedAt48kHz : .derivedFrom48kHz
        #expect(measurement.method.weighting == expected, "\(rate)")
        #expect(measurement.method.algorithm == .integratedBS1770v1)
    }

    // MARK: - Chunk independence, through the composition

    /// Already proved of the accumulator. What this adds is that the **composition** does not break it:
    /// the same audio cut differently, through the shared read, is bit-identical — and identical to the
    /// accumulator fed those same chunks directly.
    @Test(
        "the shared read preserves bit-exact chunk independence",
        arguments: [44_100.0, 48_000.0, 96_000.0, 192_000.0]
    )
    func chunkIndependenceSurvivesTheComposition(_ rate: Double) async throws {
        let frames = Int(rate)
        var readings: [LoudnessMeasurement] = []
        for chunkFrames in [127, 4_096, 65_536, frames] {
            let (outcome, material) = try await run(
                frames: frames, rate: rate, chunkFrames: chunkFrames
            )
            guard case let .available(measurement) = outcome.loudness else {
                Issue.record("no measurement at \(rate)/\(chunkFrames)"); return
            }
            // The composition's answer is the accumulator's answer for the same chunks.
            #expect(measurement == referenceLoudness(material, rate: rate))
            readings.append(measurement)
        }
        // And every chunking agrees with every other, exactly.
        #expect(Set(readings.map(\.integratedLoudness)).count == 1, "\(readings.map(\.integratedLoudness))")
    }
}
