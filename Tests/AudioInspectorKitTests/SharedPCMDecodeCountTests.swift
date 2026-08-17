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
/// an analysis a read of its own.
///
/// **The number is now one.** The waveform was the last analysis holding a private read; ADR-0021 moved
/// it onto the shared pass, and this suite is where that claim stops being prose. The counters below
/// **Counting alone cannot catch every way a second read could come back**, and that is not a
/// suspicion — it was measured. Reintroducing the legacy waveform read into the coordinator leaves the
/// counters below completely happy, because a directly constructed adapter passes through no injected
/// seam. The source-level assertion at the bottom of this suite is what actually failed in that
/// control, and it is why both live here: the counters pin *how many* reads go through the seam, and the
/// source check pins that there is no other way to open one.
@MainActor
@Suite("App — how many times an inspection reads the samples")
struct SharedPCMDecodeCountTests {
    /// Counts what the real pipeline actually opened. Confined to one test's own call.
    private final class Counts: @unchecked Sendable {
        var decodersMade = 0
        var decodeCalls = 0
        /// Every sample read a whole inspection performs. There is only one way to open one now — the
        /// decoding port — which is why this is simply the decode count.
        var sampleReads: Int { decodeCalls }
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


    /// The real coordinator, with a decoder that counts. **No waveform generator is supplied**, because
    /// production no longer has a seam to supply one to — which is itself the property under test.
    private func coordinator(for counts: Counts) -> SourceInspectionCoordinator {
        SourceInspectionCoordinator(
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

    /// **One sample read for a whole inspection**, with a real file and the real adapters: a single
    /// pass feeding the waveform, the spectrogram, the signal level metrics *and* the true peak. Not
    /// two, not three, and not the four the pre-sharing design would have needed.
    @Test("a whole inspection reads the samples exactly once, with all four analyses produced")
    func aWholeInspectionReadsTheSamplesOnce() async throws {
        try await withTemporaryDirectory { directory in
            let url = try fixture(in: directory)
            let counts = Counts()

            let outcome = await coordinator(for: counts).inspect(url) { _ in }

            #expect(counts.decodersMade == 1, "an analysis was given a decoder of its own")
            #expect(counts.decodeCalls == 1, "the shared read happened more than once")
            #expect(counts.sampleReads == 1, "an inspection read the file's samples \(counts.sampleReads) times")

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

    /// The report is emitted before any sample is read, which is the reason the shared read is allowed
    /// to take as long as it takes. **The order of the four analyses is unchanged by the cutover**: the
    /// waveform is still announced first of them, it simply settles when the one read finishes rather
    /// than when a read of its own did.
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

    /// **The door counting cannot close.** A coordinator could construct a reader itself rather than
    /// take one through a seam, and no spy would see it — measured, not suspected: reintroducing the
    /// legacy read left every counter above completely happy. So the source is asserted too.
    ///
    /// The scope is **every** production target, not just the composition root. `AVFoundationWaveformGenerator`
    /// survives as an independent oracle for the equivalence suites, and this is what keeps that
    /// decision honest: it may be referenced by tests and by nothing else. The moment a production file
    /// names it, the oracle has stopped being test-only and a second read is one call away.
    ///
    /// Comment lines are skipped deliberately — the records that explain where a default came from, or
    /// why the port was retired, must stay readable.
    @Test("no production target reaches for a waveform-reading port")
    func noProductionTargetNamesTheLegacySeam() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let files = FileManager.default
            .enumerator(at: root.appendingPathComponent("Sources"), includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" } ?? []
        #expect(files.count > 20, "no sources were scanned, so this test proved nothing")

        // The oracle's own declaration, and the fake that conforms to the same port, are where these
        // names legitimately live.
        let declarations: Set<String> = ["AVFoundationWaveformGenerator.swift", "WaveformGenerating.swift"]

        var offenders: [String] = []
        for file in files where !declarations.contains(file.lastPathComponent) {
            let source = try String(contentsOf: file, encoding: .utf8)
            for line in source.split(separator: "\n").map(String.init) {
                let code = line.trimmingCharacters(in: .whitespaces)
                guard !code.hasPrefix("//"), !code.hasPrefix("///") else { continue }
                if code.contains("WaveformGenerating") || code.contains("AVFoundationWaveformGenerator") {
                    offenders.append("\(file.lastPathComponent): \(code)")
                }
            }
        }
        #expect(offenders.isEmpty, "a production file reaches for a waveform read: \(offenders)")
    }
}
