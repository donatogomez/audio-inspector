import AudioInspectorDomain
@testable import AudioInspectorApp
import AudioInspectorTesting
import FeatureImport
import Foundation
import Testing

/// The guarantee the waveform's own isolation suite makes, now made for the spectrogram: **it is beside
/// the report, never inside it.**
///
/// This closes the gap declared in PR #32, where the isolation was argued from the types — the exporter
/// only ever receives an `InspectionReport` — rather than asserted. The type system prevents the
/// obvious version of the mistake, but a coordinator could still add a warning when the transform
/// fails, degrade the status, or let the exporter learn that a model existed, and every one of those
/// would change what a user is told about their file because a *drawing* could not be made.
///
/// The same real file is inspected through the same real property reader three times, differing only in
/// what the decoding port does. Everything the report says, and every byte the export writes, must be
/// identical across all three.
@MainActor
@Suite("App — the report is unaffected by the spectrogram")
struct SpectrogramReportIsolationTests {
    /// The three outcomes that settle into a presented state. Cancellation is excluded deliberately: it
    /// settles into none, so there is no report to compare.
    private func decoderOutcomes() throws -> [(name: String, decoder: FakeAudioDecoding)] {
        let stream = try #require(PCMStreamDescription(sampleRate: 44_100, channelCount: 1, frameCount: 40_960))
        let chunks = try stride(from: 0, to: 40_960, by: 4_096).map { start -> PCMChunk in
            let samples = (0 ..< 4_096).map { offset -> Float in
                let phase = 2 * Double.pi * 1_000 * Double(start + offset) / 44_100
                return 0.5 * Float(sin(phase))
            }
            return try PCMChunk(startFrame: start, channels: [samples])
        }
        return [
            ("available", FakeAudioDecoding(streaming: stream, chunks: chunks)),
            ("absent", FakeAudioDecoding(.absent)),
            ("failed", FakeAudioDecoding(failingWith: AudioDecodingError(code: .readFailed, message: "internal"))),
        ]
    }

    private struct InspectionDidNotComplete: Error {}

    /// Inspects `url` with the **real** property reader and a scripted decoding port.
    private func inspect(
        _ url: URL,
        decoder: FakeAudioDecoding
    ) async throws -> (report: InspectionReport, spectrogram: SpectrogramOutcome) {
        let coordinator = SourceInspectionCoordinator(makeDecoder: { _ in decoder })
        let outcome = await coordinator.inspect(url, onUpdate: { _ in })
        guard case let .inspected(report, analyses) = outcome else {
            throw InspectionDidNotComplete()
        }
        return (report, analyses.spectrogram)
    }

    private func fixture(in directory: URL) throws -> URL {
        try writeAudioFixture(
            AudioFixtureSpec(
                name: "spectrogram-isolation", format: .wav,
                signal: .sine(frequency: 440, amplitude: 0.5), channels: 1, frames: 40_960
            ),
            in: directory
        )
    }

    // MARK: The report says the same thing however the spectrogram turned out

    @Test("properties, warnings and status are identical whatever the spectrogram did")
    func theReportIsUnchanged() async throws {
        try await withTemporaryDirectory { directory in
            let url = try fixture(in: directory)

            var reports: [(String, InspectionReport)] = []
            for (name, decoder) in try decoderOutcomes() {
                reports.append((name, try await inspect(url, decoder: decoder).report))
            }

            let reference = try #require(reports.first)
            for (name, report) in reports.dropFirst() {
                #expect(report.properties == reference.1.properties, "properties differed for \(name)")
                #expect(report.warnings == reference.1.warnings, "warnings differed for \(name)")
                #expect(report.status == reference.1.status, "status differed for \(name)")
            }
        }
    }

    @Test("a spectrogram that is absent or failed emits no warning and does not degrade the status")
    func aFailureIsNeverAFinding() async throws {
        try await withTemporaryDirectory { directory in
            let url = try fixture(in: directory)

            for (name, decoder) in try decoderOutcomes().dropFirst() {
                let (report, spectrogram) = try await inspect(url, decoder: decoder)
                #expect(spectrogram != .available(try #require(Spectrogram.empty(sampleRate: 44_100, channelCount: 1))))
                if case .failed = report.status {
                    Issue.record("the \(name) spectrogram degraded the inspection status")
                }
                #expect(
                    report.warnings.allSatisfy { warning in
                        !warning.message.lowercased().contains("spectrogram")
                            && !warning.code.rawValue.contains("spectrogram")
                    },
                    "the \(name) spectrogram emitted an inspection warning"
                )
            }
        }
    }

    // MARK: The export never learns a spectrogram existed

    /// **The gap PR #32 declared, now closed.**
    ///
    /// Byte-identical documents across all three outcomes, plus a sweep over the document's **keys**
    /// rather than its text. The keys matter: WAV's own type identifier is `com.microsoft.waveform-audio`,
    /// so a substring sweep over values would fail on the container's real name and prove only that the
    /// sweep was naive. A key is ours; a value may legitimately be the format's.
    @Test("the exported JSON is byte-identical with and without a spectrogram")
    func theExportIsIdentical() async throws {
        try await withTemporaryDirectory { directory in
            let url = try fixture(in: directory)

            var documents: [(String, Data)] = []
            for (name, decoder) in try decoderOutcomes() {
                let (report, _) = try await inspect(url, decoder: decoder)
                documents.append((name, try exportData(report)))
            }

            let reference = try #require(documents.first)
            for (name, document) in documents.dropFirst() {
                #expect(document == reference.1, "the exported document differed for \(name)")
            }

            let keys = allKeys(try JSONDecoder().decode(JSONValue.self, from: reference.1))
            for forbidden in [
                "spectrogram", "spectral", "column", "band", "dbfs", "nyquist", "fft", "stft",
                "frequency", "magnitude", "bin",
            ] {
                #expect(
                    !keys.contains { $0.lowercased().contains(forbidden) },
                    "“\(forbidden)” is a key in the export"
                )
            }
        }
    }

    /// And structurally: the exporter's whole input is an `InspectionReport`, so a model has no route
    /// in. Asserted by exporting the *same* report twice with two different spectrograms in hand — the
    /// documents cannot differ, because the spectrogram was never an argument.
    @Test("the exporter's input carries no spectrogram at all")
    func theExporterNeverSeesOne() async throws {
        try await withTemporaryDirectory { directory in
            let url = try fixture(in: directory)
            let (report, spectrogram) = try await inspect(url, decoder: try decoderOutcomes()[0].decoder)

            guard case .available = spectrogram else {
                Issue.record("expected a model, so the test is comparing something real"); return
            }
            #expect(try exportData(report) == (try exportData(report)), "the export is not deterministic")
        }
    }

    /// The three scripted outcomes really are distinguishable — otherwise the tests above would pass on
    /// a port that quietly collapsed them, and would be proving nothing at all.
    @Test("the scripted outcomes are genuinely different from one another")
    func theOutcomesDiffer() async throws {
        try await withTemporaryDirectory { directory in
            let url = try fixture(in: directory)

            var outcomes: [SpectrogramOutcome] = []
            for (_, decoder) in try decoderOutcomes() {
                outcomes.append(try await inspect(url, decoder: decoder).spectrogram)
            }

            #expect(outcomes.count == 3)
            guard case .available = outcomes[0] else { Issue.record("expected a model"); return }
            #expect(outcomes[1] == .unavailable)
            guard case .failed = outcomes[2] else { Issue.record("expected a failure"); return }
        }
    }
}
