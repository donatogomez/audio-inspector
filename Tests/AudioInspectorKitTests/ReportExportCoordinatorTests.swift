import Foundation
import Testing

import AudioInspectorDomain
import FeatureAnalysis
@testable import AudioInspectorApp

/// Coordinator tests with the destination selector injected (no real `NSSavePanel`). Writes go to a
/// unique temporary directory and are cleaned up. The written bytes are inspected via `Codable`
/// (`JSONValue`) — never an untyped-object serialization API. `FileManager` is used only in the test
/// harness, never in production code.
@MainActor
@Suite("App — report export coordinator")
struct ReportExportCoordinatorTests {

    /// An exporter that always throws — proves the exporter is (or isn't) reached.
    private struct ThrowingExporter: ReportExporting {
        struct Failure: Error {}
        func export(_: InspectionReport, measurements _: ReportMeasurements) throws -> Data {
            throw Failure()
        }
    }

    /// Signals each encode through an injected `@Sendable` callback, so "invoked exactly once" is
    /// enforced by Swift Testing's `confirmation` — no isolation assumptions, locks, or shared state.
    private struct ConfirmingExporter: ReportExporting {
        let inner: JSONReportExporter
        let onExport: @Sendable () -> Void
        func export(_ report: InspectionReport, measurements: ReportMeasurements) throws -> Data {
            onExport()
            return try inner.export(report, measurements: measurements)
        }
    }

    private func realExporter() -> JSONReportExporter {
        JSONReportExporter(generator: fixedGenerator, now: { fixedNow })
    }

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - Cancellation

    @Test func cancellationDoesNotEncodeOrWrite() async {
        // A throwing exporter would surface `.encodingFailed` if reached; `.cancelled` proves it wasn't.
        let coordinator = ReportExportCoordinator(exporter: ThrowingExporter(), chooseDestination: { _ in nil })
        let outcome = await coordinator.export(report(status: .completed), measurements: ReportMeasurements(signalLevelMetrics: nil, truePeak: nil, loudness: nil, programmeBandwidth: nil))
        #expect(outcome == .cancelled)
    }

    // MARK: - Success

    @Test func successWritesExporterOutputToApprovedURLExactlyOnce() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let destination = dir.appendingPathComponent("out.json")

        let exporter = realExporter()
        let subject = report(status: .completed)
        var capturedName: String?
        var outcome: ExportOutcome?

        // `expectedCount: 1` fails the test if the exporter runs zero times or more than once.
        await confirmation("exporter invoked exactly once", expectedCount: 1) { confirmed in
            let coordinator = ReportExportCoordinator(
                exporter: ConfirmingExporter(inner: exporter, onExport: { confirmed() }),
                chooseDestination: { name in capturedName = name; return destination }
            )
            outcome = await coordinator.export(subject, measurements: ReportMeasurements(signalLevelMetrics: nil, truePeak: nil, loudness: nil, programmeBandwidth: nil))
        }

        #expect(outcome == .succeeded)
        #expect(capturedName == "interview-side-a-inspection.json") // suggested name passed to selector

        // The bytes on disk are exactly the exporter's output (deterministic clock + sorted keys).
        let written = try Data(contentsOf: destination)
        #expect(written == (try exporter.export(subject, measurements: ReportMeasurements(signalLevelMetrics: nil, truePeak: nil, loudness: nil, programmeBandwidth: nil))))

        // And they decode as JSON v1 via Codable.
        let decoded = try JSONDecoder().decode(JSONValue.self, from: written)
        #expect(decoded["schemaVersion"]?.int == 1)
        #expect(decoded["generator"]?["name"]?.string == "Audio Inspector")

        // Only the destination was created — nothing else was touched in the directory.
        let contents = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        #expect(contents == ["out.json"])
    }

    /// Observes the *result* of the replacement: the destination ends up holding exactly the new
    /// bytes. Atomicity itself is not observable from here — it is a property of the production
    /// `Data.write(to:options: [.atomic])` call, not something this test can demonstrate.
    @Test func writeReplacesAnExistingFile() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let destination = dir.appendingPathComponent("out.json")
        try Data("stale".utf8).write(to: destination) // pre-existing file at the destination

        let exporter = realExporter()
        let coordinator = ReportExportCoordinator(exporter: exporter, chooseDestination: { _ in destination })
        let subject = report(status: .completed)

        let outcome = await coordinator.export(subject, measurements: ReportMeasurements(signalLevelMetrics: nil, truePeak: nil, loudness: nil, programmeBandwidth: nil))

        #expect(outcome == .succeeded)
        let written = try Data(contentsOf: destination)
        #expect(written == (try exporter.export(subject, measurements: ReportMeasurements(signalLevelMetrics: nil, truePeak: nil, loudness: nil, programmeBandwidth: nil)))) // fully replaced with the new content
    }

    // MARK: - Failures

    @Test func encodingFailureDoesNotWrite() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let destination = dir.appendingPathComponent("out.json")

        let coordinator = ReportExportCoordinator(exporter: ThrowingExporter(), chooseDestination: { _ in destination })
        let outcome = await coordinator.export(report(status: .completed), measurements: ReportMeasurements(signalLevelMetrics: nil, truePeak: nil, loudness: nil, programmeBandwidth: nil))

        #expect(outcome == .encodingFailed)
        #expect(!FileManager.default.fileExists(atPath: destination.path)) // nothing written
    }

    @Test func writeFailureReturnsWriteFailed() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        // A destination inside a non-existent subdirectory → the atomic write fails.
        let destination = dir.appendingPathComponent("missing-subdir", isDirectory: true).appendingPathComponent("out.json")

        let coordinator = ReportExportCoordinator(exporter: realExporter(), chooseDestination: { _ in destination })
        let outcome = await coordinator.export(report(status: .completed), measurements: ReportMeasurements(signalLevelMetrics: nil, truePeak: nil, loudness: nil, programmeBandwidth: nil))

        #expect(outcome == .writeFailed)
        #expect(!FileManager.default.fileExists(atPath: destination.path))
    }

    // MARK: - Cross-target wiring

    @Test func compositionRootCanBuildTheExportAction() {
        // Demonstrates AudioInspectorApp can construct the FeatureAnalysis-typed action from the
        // coordinator + exporter. Constructed only (no invocation → no panel).
        let action: ReportExportAction = AppContainer().makeReportExportAction()
        _ = action
    }
}
