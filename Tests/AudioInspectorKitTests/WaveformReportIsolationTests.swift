import Foundation
import Testing

import AudioInspectorDomain
@testable import AudioInspectorApp
import AudioInspectorTesting
import FeatureImport

/// The guarantee that this whole capability was designed around: **the waveform is beside the report,
/// never inside it.**
///
/// It is asserted here rather than left to the type system because the type system only prevents the
/// obvious version of the mistake. `InspectionReport` cannot hold an envelope, but a coordinator could
/// still add a warning when the samples fail, or degrade the status, or let the exporter learn that a
/// waveform existed — and every one of those would change what a user is told about their file
/// because a *drawing* could not be made.
///
/// The same real file is inspected through the same real property reader three times, differing only
/// in what the waveform port does. Everything the report says, and every byte the export writes, must
/// be identical across all three.
@MainActor
@Suite("App — the report is unaffected by the waveform")
struct WaveformReportIsolationTests {

    /// The three outcomes the port can produce, scripted. Cancellation is excluded deliberately: it
    /// never settles into a presented state, so there is no report to compare.
    private func outcomes(envelope: WaveformEnvelope) -> [(name: String, outcome: FakeWaveformGenerating.Outcome)] {
        [
            ("available", .success(envelope)),
            ("absent", .absent),
            ("failed", .failure(WaveformError(code: .readFailed, message: "internal"))),
        ]
    }

    private func envelope() throws -> WaveformEnvelope {
        let buckets = (0 ..< 16).map { index in
            WaveformBucket(minimum: Float(index) / -32, maximum: Float(index) / 32)!
        }
        return try #require(WaveformEnvelope(buckets: buckets, frameCount: 4_410, channelCount: 2))
    }

    /// Inspects `url` with the **real** property reader and a scripted waveform port.
    private func inspect(
        _ url: URL,
        waveform: FakeWaveformGenerating.Outcome
    ) async throws -> (report: InspectionReport, waveform: WaveformOutcome) {
        let coordinator = SourceInspectionCoordinator(
            makeWaveformGenerator: { _ in FakeWaveformGenerating(waveform) }
        )
        let outcome = await coordinator.inspect(url, onUpdate: { _ in })
        guard case let .inspected(report, waveform, _, _, _) = outcome else {
            throw InspectionDidNotComplete()
        }
        return (report, waveform)
    }

    private struct InspectionDidNotComplete: Error {}

    // MARK: - The report says the same thing however the waveform turned out

    @Test("properties, warnings and status are identical whatever the waveform did")
    func theReportIsIdenticalAcrossEveryWaveformOutcome() async throws {
        try await withTemporaryDirectory { directory in
            let url = try writeAudioFixture(
                AudioFixtureSpec(
                    name: "isolation", format: .wav, signal: .sine(frequency: 440, amplitude: 0.5),
                    channels: 2, frames: 4_410
                ),
                in: directory
            )
            let envelope = try envelope()

            var reports: [(String, InspectionReport)] = []
            for (name, outcome) in outcomes(envelope: envelope) {
                reports.append((name, try await inspect(url, waveform: outcome).report))
            }

            let reference = try #require(reports.first)
            for (name, report) in reports.dropFirst() {
                // Compared field by field rather than with `==`: the report carries an ephemeral id
                // that is new for every inspection by design, and it is not part of what is presented.
                #expect(report.properties == reference.1.properties, "properties changed for \(name)")
                #expect(report.warnings == reference.1.warnings, "warnings changed for \(name)")
                #expect(report.status == reference.1.status, "status changed for \(name)")
                #expect(report.file.displayName == reference.1.file.displayName)
                #expect(report.file.fileExtension == reference.1.file.fileExtension)
                #expect(report.file.sizeBytes == reference.1.file.sizeBytes)
            }
        }
    }

    /// The specific regressions the design forbids by name: a waveform that did not happen must not
    /// become a warning about the file, and must not pull the status down.
    @Test("a waveform that is absent or failed emits no warning and does not degrade the status")
    func aMissingWaveformIsNeverAWarningOrAStatusChange() async throws {
        try await withTemporaryDirectory { directory in
            let url = try writeAudioFixture(
                AudioFixtureSpec(
                    name: "no-warning", format: .wav, signal: .sine(frequency: 440, amplitude: 0.5),
                    channels: 2, frames: 4_410
                ),
                in: directory
            )

            for (name, outcome) in outcomes(envelope: try envelope()) {
                let (report, _) = try await inspect(url, waveform: outcome)

                let mentionsTheDrawing = report.warnings.contains { warning in
                    let text = "\(warning.code) \(warning.field ?? "") \(warning.message)".lowercased()
                    return text.contains("waveform") || text.contains("envelope") || text.contains("sample")
                }
                #expect(!mentionsTheDrawing, "a warning about the waveform appeared for \(name)")

                if case .failed = report.status {
                    Issue.record("the waveform outcome \(name) degraded the inspection status")
                }
            }
        }
    }

    // MARK: - The export cannot tell

    /// Byte-for-byte, with the clock and the generator identity fixed. Anything the waveform added to
    /// the document — a key, a null, a count — would show up as a difference here.
    @Test("the exported JSON is byte-identical with and without a waveform")
    func theExportedDocumentIsIdenticalWithAndWithoutAWaveform() async throws {
        try await withTemporaryDirectory { directory in
            let url = try writeAudioFixture(
                AudioFixtureSpec(
                    name: "export-isolation", format: .wav, signal: .sine(frequency: 440, amplitude: 0.5),
                    channels: 2, frames: 4_410
                ),
                in: directory
            )
            let envelope = try envelope()

            var documents: [(String, Data)] = []
            for (name, outcome) in outcomes(envelope: envelope) {
                let (report, _) = try await inspect(url, waveform: outcome)
                documents.append((name, try exportData(report)))
            }

            let reference = try #require(documents.first)
            for (name, document) in documents.dropFirst() {
                #expect(document == reference.1, "the exported document differed for \(name)")
            }

            // And no key in it belongs to the waveform, whatever the outcome was.
            //
            // Asserted over the document's **keys** rather than its text on purpose: WAV's own type
            // identifier is `com.microsoft.waveform-audio`, so a substring sweep would fail on the
            // container's real name and prove only that the sweep was naive. A key is ours; a value
            // may legitimately be the format's.
            let keys = allKeys(try JSONDecoder().decode(JSONValue.self, from: reference.1))
            for forbidden in ["waveform", "envelope", "buckets", "amplitude", "peak", "samples"] {
                #expect(!keys.contains { $0.lowercased().contains(forbidden) }, "“\(forbidden)” is a key in the export")
            }
        }
    }

    /// The three outcomes really are distinguishable — otherwise the tests above would pass on a port
    /// that quietly collapsed them, and would be proving nothing at all.
    @Test("the scripted outcomes are genuinely different from one another")
    func theOutcomesUnderTestAreDistinct() async throws {
        try await withTemporaryDirectory { directory in
            let url = try writeAudioFixture(
                AudioFixtureSpec(name: "distinct", format: .wav, signal: .silence, frames: 4_410),
                in: directory
            )
            let envelope = try envelope()

            let available = try await inspect(url, waveform: .success(envelope)).waveform
            let absent = try await inspect(url, waveform: .absent).waveform
            let failed = try await inspect(url, waveform: .failure(WaveformError(code: .readFailed, message: "x"))).waveform

            #expect(available == .available(envelope))
            #expect(absent == .unavailable)
            guard case .failed = failed else {
                Issue.record("expected a failed waveform, got \(failed)"); return
            }
            #expect(available != absent)
        }
    }
}
