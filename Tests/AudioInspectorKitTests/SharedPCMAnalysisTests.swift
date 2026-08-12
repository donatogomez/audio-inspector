import Foundation
import Testing

import AudioInspectorAnalysis
import AudioInspectorDomain
import AudioInspectorTesting
import FeatureImport

@testable import AudioInspectorApp

/// What the shared read must guarantee, asserted as **properties** rather than as an arrangement.
///
/// The tests these replace scripted two decoders by call order and asserted that each analysis got its
/// own instance. That was an assertion about the mechanism, and ADR-0020 replaced the mechanism while
/// keeping the guarantee: one analysis may not fail, cancel or delay another. Everything here checks
/// the guarantee.
@Suite("App — one PCM read, several analyses")
struct SharedPCMAnalysisTests {
    private func reference() -> AudioFileReference {
        AudioFileReference(
            displayName: "fixture",
            fileExtension: "wav",
            sizeBytes: nil,
            modifiedAt: nil,
            source: .userSelectedLocalFile(displayName: "fixture", locationDisclosure: .omitted)
        )
    }

    private func stream(frames: Int, channels: Int = 2, sampleRate: Double = 44_100) throws -> PCMStreamDescription {
        try #require(PCMStreamDescription(sampleRate: sampleRate, channelCount: channels, frameCount: frames))
    }

    /// A run of audio with a recognisable level, so a result computed over it can be compared exactly.
    private func chunks(frames: Int, channels: Int = 2, per chunkFrames: Int = 1_024) throws -> [PCMChunk] {
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

    // MARK: - One read

    @Test("the analyses are produced from a single decode")
    func oneDecodeForEveryAnalysis() async throws {
        let frames = 8_192
        let decoder = FakeAudioDecoding(
            streaming: try stream(frames: frames), chunks: try chunks(frames: frames)
        )
        _ = await SharedPCMAnalysisGeneration(decoder: decoder).run(for: reference())

        // The observable behaviour of the port, not a private name: the file's samples were read once.
        #expect(await decoder.spy.callCount == 1)
    }

    /// **The architectural gate, and the whole reason true peak waited for this change.** Its own group
    /// 5 measured a fourth read at 0.47–0.53 s for a compressed file and refused it. Three consumers,
    /// one call: adding a third analysis must add no read at all, and this counts at the port rather
    /// than trusting the composition's shape.
    @Test("three analyses still cost exactly one decode")
    func threeConsumersStillCostOneDecode() async throws {
        let frames = 8_192
        let decoder = FakeAudioDecoding(
            streaming: try stream(frames: frames), chunks: try chunks(frames: frames)
        )
        let outcome = await SharedPCMAnalysisGeneration(decoder: decoder).run(for: reference())

        #expect(await decoder.spy.callCount == 1)
        // All three really were produced from that one call — otherwise the count is trivially met.
        guard case .available = outcome.spectrogram,
              case .available = outcome.signalLevelMetrics,
              case .available = outcome.truePeak else {
            Issue.record("a consumer produced nothing from the shared read"); return
        }
    }

    @Test("each analysis reports its own outcome, and neither is derived from the other")
    func eachAnalysisReportsItsOwn() async throws {
        let frames = 8_192
        let decoder = FakeAudioDecoding(
            streaming: try stream(frames: frames), chunks: try chunks(frames: frames)
        )
        let outcome = await SharedPCMAnalysisGeneration(decoder: decoder).run(for: reference())

        guard case let .available(spectrogram) = outcome.spectrogram else {
            Issue.record("expected an available spectrogram, got \(outcome.spectrogram)"); return
        }
        guard case let .available(levels) = outcome.signalLevelMetrics else {
            Issue.record("expected available signal level metrics, got \(outcome.signalLevelMetrics)"); return
        }
        guard case let .available(truePeak) = outcome.truePeak else {
            Issue.record("expected an available true peak, got \(outcome.truePeak)"); return
        }
        #expect(spectrogram.channelCount == 2)
        #expect(levels.channels.count == 2)
        #expect(levels.overallPeakSample != nil)
        #expect(truePeak.channels.count == 2)
        // The methodology travels with the value, and it is the accumulator's own — nothing in the
        // composition chose, passed or repeated it (ADR-0006, ADR-0019).
        #expect(truePeak.method.oversamplingFactor == 8)
        #expect(truePeak.method.filter == .polyphaseFIRv1)
        // The relationship the reconstruction guarantees, observed through the shared read.
        #expect(try #require(truePeak.overallTruePeak) >= (try #require(levels.overallPeakSample)))
    }

    // MARK: - Equivalence: the transport changed, the analysis did not

    /// The shared read must produce **exactly** what each analysis produced when it read the file
    /// alone. Value for value, with no tolerance: sharing changes how samples arrive, not what is
    /// computed from them.
    @Test("the shared read produces exactly what each analysis produced on its own")
    func equivalenceWithSeparateReads() async throws {
        let frames = 20_480
        let description = try stream(frames: frames)
        let material = try chunks(frames: frames)

        let separateSpectrogram = await SpectrogramGeneration(
            decoder: FakeAudioDecoding(streaming: description, chunks: material)
        ).run(for: reference())
        let separateLevels = await SignalLevelMetricsGeneration(
            decoder: FakeAudioDecoding(streaming: description, chunks: material)
        ).run(for: reference())

        let shared = await SharedPCMAnalysisGeneration(
            decoder: FakeAudioDecoding(streaming: description, chunks: material)
        ).run(for: reference())

        var referenceAccumulator = try #require(TruePeakAccumulator(channelCount: 2))
        for chunk in material { referenceAccumulator.accumulate(chunk) }
        let finished = referenceAccumulator.finish()
        let separateTruePeak = try #require(finished)

        #expect(shared.spectrogram == separateSpectrogram)
        #expect(shared.signalLevelMetrics == separateLevels)
        // True peak has no `Generation` of its own to compare against — it was never wired as a separate
        // operation — so its reference is the accumulator fed the same chunks directly. Bit-exact, which
        // is its own guarantee and not merely this suite's preference.
        #expect(shared.truePeak == .available(separateTruePeak))
    }

    // MARK: - Isolation

    /// **Case C — the producer fails: every consumer ends, each on its own terms.**
    @Test("a decoder failure ends every analysis, each reporting its own outcome")
    func producerFailureEndsEveryone() async throws {
        let outcome = await SharedPCMAnalysisGeneration(
            decoder: FakeAudioDecoding(failingWith: AudioDecodingError(code: .readFailed, message: "boom"))
        ).run(for: reference())

        guard case let .failed(spectrogramMessage) = outcome.spectrogram else {
            Issue.record("expected the spectrogram to fail"); return
        }
        guard case let .failed(levelsMessage) = outcome.signalLevelMetrics else {
            Issue.record("expected the signal level metrics to fail"); return
        }
        // Each keeps the wording it had when it read the file alone — a reader of one result never has
        // to consult the other to learn what happened.
        #expect(spectrogramMessage.contains("spectrogram"))
        #expect(levelsMessage.contains("signal level metrics"))
        #expect(spectrogramMessage != levelsMessage)
    }

    @Test("a file with no audio yields each analysis's own complete empty answer")
    func emptyFileIsACompleteAnswer() async throws {
        let outcome = await SharedPCMAnalysisGeneration(
            decoder: FakeAudioDecoding(streaming: try stream(frames: 0), chunks: [])
        ).run(for: reference())

        guard case let .available(spectrogram) = outcome.spectrogram else {
            Issue.record("expected an available empty spectrogram, got \(outcome.spectrogram)"); return
        }
        guard case let .available(levels) = outcome.signalLevelMetrics else {
            Issue.record("expected available empty metrics, got \(outcome.signalLevelMetrics)"); return
        }
        #expect(spectrogram.columnCount == 0)
        #expect(levels.channels.allSatisfy { $0.sampleCount == 0 })
        #expect(levels.overallPeakSample == nil)
    }

    @Test("audio that does not match the stream faults every analysis, since none can proceed past it")
    func mismatchedAudioFaultsEveryone() async throws {
        let mismatched = try PCMChunk(startFrame: 0, channels: [[0.1, 0.2, 0.3]])
        let outcome = await SharedPCMAnalysisGeneration(
            decoder: FakeAudioDecoding(streaming: try stream(frames: 4_096), chunks: [mismatched])
        ).run(for: reference())

        guard case let .failed(spectrogramMessage) = outcome.spectrogram else {
            Issue.record("expected the spectrogram to fail"); return
        }
        guard case let .failed(levelsMessage) = outcome.signalLevelMetrics else {
            Issue.record("expected the signal level metrics to fail"); return
        }
        // The fault is in the audio they all just received, not in either of them — so both name it.
        #expect(spectrogramMessage.contains("does not match"))
        #expect(levelsMessage.contains("does not match"))
    }

    // MARK: - Cancellation

    @Test("a cancelled read cancels every analysis and leaks no partial model")
    func cancellationCancelsEveryone() async throws {
        let outcome = await SharedPCMAnalysisGeneration(
            decoder: FakeAudioDecoding(failingWith: AudioDecodingError(code: .cancelled, message: "cancelled"))
        ).run(for: reference())
        #expect(outcome.spectrogram == .cancelled)
        #expect(outcome.signalLevelMetrics == .cancelled)
    }

    // **A deterministic in-callback cancellation test is group 3's job, not this one's.**
    //
    // The obvious version — start a `Task`, cancel it, await the value — is a race: if the task runs to
    // completion before `cancel()` lands, both analyses succeed and the assertion fails for reasons that
    // have nothing to do with the code under test. One such non-deterministic test was written here and
    // removed rather than left to fail occasionally.
    //
    // What is covered deterministically today: the decoder reporting cancellation (above), which is the
    // path a cancelled inspection actually takes. Proving the callback's own `Task.isCancelled` check
    // needs a decoder that hands over a chunk only after the surrounding task has certainly been
    // cancelled — a handshake, not a hope — and that belongs with the rest of group 3's cancellation
    // proofs.
}
