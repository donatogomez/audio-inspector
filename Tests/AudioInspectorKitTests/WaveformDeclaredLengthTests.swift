import AVFoundation
import Foundation
import Testing

import AudioInspectorDomain
import AudioInspectorMedia
import AudioInspectorTesting
import FeatureImport

@testable import AudioInspectorApp

// **The one place the shared read is deliberately not equivalent to the read it replaced.**
//
// This suite is not an equivalence suite and must not be read as one. Everything else about the
// waveform is identical through both paths; what follows is a bounded, intentional exception, and it
// concerns a file whose decoder delivers **more** frames than the file declares.
//
// ## The two policies
//
// - **Legacy `AVFoundationWaveformGenerator`**: its loop consumed
//   `usable = min(valid, frameCount - framesRead)` — anything a decoder handed over beyond the declared
//   length was **silently discarded**, and the reduction succeeded as though the file had read exactly
//   as it declared.
// - **The shared read**: `AVFoundationAudioDecoder` refuses it. A chunk that does not fit the stream it
//   came from ends the read with `readFailed`, and `SharedPCMAnalysisGeneration` faults **every**
//   consumer, because the fault is in the audio they all just received rather than in any one of them.
//
// ## The policy this change adopts
//
// **The declared frame count sizes the reduction and bounds the read. Frames delivered beyond it are a
// fault of the read, reported as one — never trimmed away, and never folded in.** The envelope always
// describes exactly the frames the stream declared: no more, because a surplus ends the read; no fewer,
// because an uncovered bucket is refused rather than invented.
//
// ## Why the divergence cannot be shown by comparing the two paths
//
// **No writable container over-reads.** Measured before this suite was written, across WAV, AIFF, ALAC,
// FLAC, AAC and 32-bit float WAV, reading both bounded by the declared length and unbounded past it:
// every format delivered exactly what it declared, in both directions. So the input that separates the
// two policies cannot be produced natively, and a "legacy versus shared" test for it would be a test of
// a fixture that does not exist. What is pinned below is the **shared** policy, at the one seam where a
// misbehaving decoder is expressible — the port itself.
//
// The legacy clamp is recorded from its source rather than exercised, and `AVFoundationAudioDecoder`
// already documents why that clamp was the wrong shape: with it in place, replacing `frameLength` with
// `frameCapacity` changed nothing any test could see.

@Suite("App — what the waveform does with a file's declared length")
struct WaveformDeclaredLengthTests {
    private func reference() -> AudioFileReference {
        AudioFileReference(
            displayName: "fixture", fileExtension: "wav", sizeBytes: nil, modifiedAt: nil,
            source: .userSelectedLocalFile(displayName: "fixture", locationDisclosure: .omitted)
        )
    }

    private func stream(frames: Int, channels: Int = 2) throws -> PCMStreamDescription {
        try #require(PCMStreamDescription(sampleRate: 44_100, channelCount: channels, frameCount: frames))
    }

    private func run(_ decoder: any AudioDecoding) async -> SharedPCMAnalysisOutcome {
        await SharedPCMAnalysisGeneration(decoder: decoder).run(for: reference())
    }

    // MARK: - The declared length sizes the reduction

    /// The envelope describes the frames the stream declared, and the resolution decides only how many
    /// buckets they are divided into. Nothing about the transport appears in either number.
    @Test("the declared frame count is what the envelope reports having reduced")
    func theDeclaredLengthSizesTheEnvelope() async throws {
        let declared = 20_480
        var chunks: [PCMChunk] = []
        var start = 0
        while start < declared {
            let count = min(4_096, declared - start)
            let samples = [Float](repeating: 0.5, count: count)
            chunks.append(try PCMChunk(startFrame: start, channels: [samples, samples]))
            start += count
        }

        let outcome = await run(FakeAudioDecoding(streaming: try stream(frames: declared), chunks: chunks))
        guard case let .available(envelope) = outcome.waveform else {
            Issue.record("expected an envelope, got \(outcome.waveform)"); return
        }
        #expect(envelope.frameCount == declared)
        #expect(envelope.buckets.count == min(declared, WaveformBucketMapping.defaultMaximumBucketCount))
    }

    // MARK: - The intentional exception: a surplus is a fault, not something to trim

    /// **A run delivered beyond the declared length ends the read, and says so.**
    ///
    /// This is where the shared path and the path it replaced disagree: the legacy loop would have
    /// trimmed the surplus and returned an envelope, and this refuses. Stricter on purpose — a file that
    /// reads differently from how it declares itself is a fact about the file, and the reduction is not
    /// the place to paper over it.
    ///
    /// The fault reaches **every** consumer rather than the waveform alone, because the audio itself is
    /// what does not match: none of them can proceed past it honestly.
    @Test("a chunk reaching past the declared length ends the read for everyone")
    func aSurplusEndsTheRead() async throws {
        let declared = 8_192
        let oversized = [Float](repeating: 0.5, count: declared + 1)
        let outcome = await run(
            FakeAudioDecoding(
                streaming: try stream(frames: declared),
                chunks: [try PCMChunk(startFrame: 0, channels: [oversized, oversized])]
            )
        )

        guard case let .failed(waveformMessage) = outcome.waveform else {
            Issue.record("a surplus was absorbed instead of refused: \(outcome.waveform)"); return
        }
        #expect(waveformMessage.contains("does not match"), "the failure did not name the mismatch")
        guard case .failed = outcome.spectrogram, case .failed = outcome.signalLevelMetrics,
              case .failed = outcome.truePeak
        else {
            Issue.record("the mismatch reached only some consumers"); return
        }
    }

    /// The boundary itself: a run ending **exactly** at the declared length is not a surplus, and must
    /// reduce normally. Without this the test above would pass on an off-by-one that refused every file.
    @Test("a run ending exactly at the declared length is accepted")
    func theBoundaryItselfIsFine() async throws {
        let declared = 8_192
        let exact = [Float](repeating: 0.5, count: declared)
        let outcome = await run(
            FakeAudioDecoding(
                streaming: try stream(frames: declared),
                chunks: [try PCMChunk(startFrame: 0, channels: [exact, exact])]
            )
        )
        guard case let .available(envelope) = outcome.waveform else {
            Issue.record("a file that read exactly as declared was refused: \(outcome.waveform)"); return
        }
        #expect(envelope.frameCount == declared)
    }

    // MARK: - The other direction, for contrast

    /// **A shortfall is the waveform's own failure, not everyone's**, and it is not padded with silence.
    /// Stated here beside the surplus so the asymmetry is deliberate and visible: a surplus means the
    /// audio disagrees with the file and stops the read; a shortfall means only that the reduction never
    /// covered what it was asked to cover, which is a fact about the waveform alone.
    @Test("a shortfall fails the waveform alone and invents nothing")
    func aShortfallIsTheWaveformsOwn() async throws {
        let declared = 16_384
        let covered = 8_192
        var chunks: [PCMChunk] = []
        var start = 0
        while start < covered {
            let count = min(4_096, covered - start)
            let samples = [Float](repeating: 0.5, count: count)
            chunks.append(try PCMChunk(startFrame: start, channels: [samples, samples]))
            start += count
        }

        let outcome = await run(FakeAudioDecoding(streaming: try stream(frames: declared), chunks: chunks))

        guard case let .failed(message) = outcome.waveform else {
            Issue.record("an uncovered file produced an envelope: \(outcome.waveform)"); return
        }
        #expect(message.contains("waveform"), "the failure did not name the waveform")
        guard case .available = outcome.spectrogram, case .available = outcome.signalLevelMetrics,
              case .available = outcome.truePeak
        else {
            Issue.record("the waveform's shortfall reached the other analyses"); return
        }
    }
}
