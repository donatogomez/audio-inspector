import AVFoundation
import Foundation
import Testing

import AudioInspectorDomain
import AudioInspectorMedia
import FeatureImport

@testable import AudioInspectorApp

/// **How many times a whole inspection reads the file's samples**, counted at the ports rather than
/// inferred from the composition's shape.
///
/// This is the gate `add-true-peak-measurement`'s group 5 stopped at: it measured a fourth read of a
/// compressed file at 0.47–0.53 s in Release and refused to spend it, which is what made the shared read
/// (ADR-0020) a prerequisite for true peak rather than a nice-to-have. The number below is therefore not
/// a performance detail — it is the architectural claim, and a test that fails the moment someone gives
/// an analysis a decoder of its own.
@MainActor
@Suite("App — how many times an inspection reads the samples")
struct SharedPCMDecodeCountTests {
    /// Counts what the real pipeline actually opened. Confined to one test's own call.
    private final class Counts: @unchecked Sendable {
        var decodersMade = 0
        var decodeCalls = 0
        var waveformReads = 0
        /// Every sample read a whole inspection performs: the shared one and the waveform's own.
        var sampleReads: Int { decodeCalls + waveformReads }
    }

    /// Delegates to the real decoder and counts the call. It changes nothing about the read.
    private struct CountingDecoder: AudioDecoding {
        let wrapped: any AudioDecoding
        let counts: Counts

        func decode(
            _ file: AudioFileReference,
            chunkFrames: Int,
            receive: (PCMStreamDescription, PCMChunk) -> PCMChunkDisposition
        ) async throws(AudioDecodingError) -> PCMStreamDescription? {
            counts.decodeCalls += 1
            return try await wrapped.decode(file, chunkFrames: chunkFrames, receive: receive)
        }
    }

    private struct CountingWaveformGenerator: WaveformGenerating {
        let wrapped: any WaveformGenerating
        let counts: Counts

        func makeWaveform(for file: AudioFileReference) async throws(WaveformError) -> WaveformEnvelope? {
            counts.waveformReads += 1
            return try await wrapped.makeWaveform(for: file)
        }
    }

    private func coordinator(for counts: Counts) -> SourceInspectionCoordinator {
        SourceInspectionCoordinator(
            makeWaveformGenerator: { url in
                CountingWaveformGenerator(
                    wrapped: AVFoundationWaveformGenerator(resolveURL: { _ in url }), counts: counts
                )
            },
            makeDecoder: { url in
                counts.decodersMade += 1
                return CountingDecoder(
                    wrapped: AVFoundationAudioDecoder(resolveURL: { _ in url }), counts: counts
                )
            }
        )
    }

    private func fixture(in directory: URL) throws -> URL {
        try writeAudioFixture(
            AudioFixtureSpec(
                name: "decode-count", format: .wav, signal: .sine(frequency: 440, amplitude: 0.5),
                channels: 2, frames: 8_192
            ),
            in: directory
        )
    }

    /// **Two sample reads for a whole inspection**, with a real file and the real adapters: the
    /// waveform's own, and the one that feeds the spectrogram, the signal level metrics *and* the true
    /// peak. Not three, and not the four the pre-sharing design would have needed.
    @Test("a whole inspection reads the samples exactly twice, with true peak included")
    func aWholeInspectionReadsTheSamplesTwice() async throws {
        try await withTemporaryDirectory { directory in
            let url = try fixture(in: directory)
            let counts = Counts()

            let outcome = await coordinator(for: counts).inspect(url) { _ in }

            #expect(counts.decodersMade == 1, "an analysis was given a decoder of its own")
            #expect(counts.decodeCalls == 1, "the shared read happened more than once")
            #expect(counts.waveformReads == 1)
            #expect(counts.sampleReads == 2, "an inspection read the file's samples \(counts.sampleReads) times")

            // The count only means something if all four analyses really were produced from those reads.
            guard case let .inspected(_, waveform, spectrogram, levels, truePeak) = outcome else {
                Issue.record("expected an inspected outcome, got \(outcome)"); return
            }
            guard case .available = waveform, case .available = spectrogram,
                  case .available = levels, case .available = truePeak else {
                Issue.record("an analysis produced nothing: \(waveform) \(spectrogram) \(levels) \(truePeak)")
                return
            }
        }
    }

    /// True peak's arrival must not have moved the report, which is emitted before any sample is read
    /// and is the reason the shared read is allowed to take as long as it takes.
    @Test("the report is still delivered before either read produces anything")
    func theReportStillComesFirst() async throws {
        try await withTemporaryDirectory { directory in
            let url = try fixture(in: directory)
            let counts = Counts()
            let order = OrderLog()

            _ = await coordinator(for: counts).inspect(url) { update in
                switch update {
                case .report: order.record("report")
                case .waveform: order.record("waveform")
                case .spectrogram: order.record("spectrogram")
                case .signalLevelMetrics: order.record("signalLevelMetrics")
                case .truePeak: order.record("truePeak")
                }
            }

            #expect(order.entries.first == "report", "the report no longer arrives first: \(order.entries)")
            #expect(order.entries == ["report", "waveform", "spectrogram", "signalLevelMetrics", "truePeak"])
        }
    }
}

/// Records the order updates arrived in, on the main actor where the handler runs.
@MainActor
private final class OrderLog {
    private(set) var entries: [String] = []
    func record(_ name: String) { entries.append(name) }
}
