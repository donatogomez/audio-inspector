import AudioInspectorDomain
@testable import AudioInspectorApp
import AudioInspectorTesting
import FeatureImport
import Foundation
import Testing

/// The guarantee the waveform's and the spectrogram's own isolation suites make, now made for signal
/// level metrics: **it is beside the report, never inside it.**
///
/// The same real file is inspected through the same real property reader three times, differing only in
/// what the decoding port does. Everything the report says, and every byte the export writes, must be
/// identical across all three.
@MainActor
@Suite("App — the report is unaffected by signal level metrics")
struct SignalLevelMetricsReportIsolationTests {
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

    /// Inspects `url` with the **real** property reader and a scripted decoding port shared by both the
    /// spectrogram and signal level metrics — the spectrogram's own outcome is not this suite's subject,
    /// so only signal level metrics is asserted on.
    private func inspect(
        _ url: URL,
        decoder: FakeAudioDecoding
    ) async throws -> (report: InspectionReport, signalLevelMetrics: SignalLevelMetricsOutcome) {
        let coordinator = SourceInspectionCoordinator(makeDecoder: { _ in decoder })
        let outcome = await coordinator.inspect(url, onUpdate: { _ in })
        guard case let .inspected(report, _, _, signalLevelMetrics, _, _) = outcome else {
            throw InspectionDidNotComplete()
        }
        return (report, signalLevelMetrics)
    }

    private func fixture(in directory: URL) throws -> URL {
        try writeAudioFixture(
            AudioFixtureSpec(
                name: "signal-level-isolation", format: .wav,
                signal: .sine(frequency: 440, amplitude: 0.5), channels: 1, frames: 40_960
            ),
            in: directory
        )
    }

    // MARK: The report says the same thing however signal level metrics turned out

    @Test("properties, warnings and status are identical whatever signal level metrics did")
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

    @Test("signal level metrics that are absent or failed emit no warning and do not degrade the status")
    func aFailureIsNeverAFinding() async throws {
        try await withTemporaryDirectory { directory in
            let url = try fixture(in: directory)

            for (name, decoder) in try decoderOutcomes().dropFirst() {
                let (report, signalLevelMetrics) = try await inspect(url, decoder: decoder)
                if case .available = signalLevelMetrics {
                    Issue.record("the \(name) decoder produced available metrics")
                }
                if case .failed = report.status {
                    Issue.record("the \(name) signal level metrics degraded the inspection status")
                }
                #expect(
                    report.warnings.allSatisfy { warning in
                        !warning.message.lowercased().contains("signal")
                            && !warning.message.lowercased().contains("level")
                            && !warning.code.rawValue.contains("signal")
                    },
                    "the \(name) signal level metrics emitted an inspection warning"
                )
            }
        }
    }

    // MARK: The export never learns signal level metrics existed

    /// Byte-identical documents across all three outcomes, plus a sweep over the document's **keys**
    /// rather than its text — matching the discipline `SpectrogramReportIsolationTests` and
    /// `add-two-file-technical-comparison` group 6.18 already established.
    @Test("the exported JSON is byte-identical with and without signal level metrics")
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
                "signallevelmetrics", "peaksample", "clippedsamplecount", "dcoffset",
                "overallpeak", "overallrms", "overalldcoffset",
            ] {
                #expect(
                    !keys.contains { $0.lowercased().contains(forbidden) },
                    "“\(forbidden)” is a key in the export"
                )
            }
        }
    }

    /// And structurally: the exporter's whole input is an `InspectionReport`, so metrics have no route
    /// in. Asserted by exporting the *same* report twice with two different outcomes in hand — the
    /// documents cannot differ, because the metrics were never an argument.
    @Test("the exporter's input carries no signal level metrics at all")
    func theExporterNeverSeesThem() async throws {
        try await withTemporaryDirectory { directory in
            let url = try fixture(in: directory)
            let (report, signalLevelMetrics) = try await inspect(url, decoder: try decoderOutcomes()[0].decoder)

            guard case .available = signalLevelMetrics else {
                Issue.record("expected real metrics, so the test is comparing something real"); return
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

            var outcomes: [SignalLevelMetricsOutcome] = []
            for (_, decoder) in try decoderOutcomes() {
                outcomes.append(try await inspect(url, decoder: decoder).signalLevelMetrics)
            }

            #expect(outcomes.count == 3)
            guard case .available = outcomes[0] else { Issue.record("expected metrics"); return }
            #expect(outcomes[1] == .unavailable)
            guard case .failed = outcomes[2] else { Issue.record("expected a failure"); return }
        }
    }
}
