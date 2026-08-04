import Foundation
import Testing

import AudioInspectorDomain
import FeatureAnalysis
@testable import AudioInspectorApp

/// Coordinator tests with the destination selector injected (no real `NSSavePanel`). Writes go to a
/// unique temporary directory and are cleaned up. The written bytes are inspected via `Codable`
/// (`JSONValue`) — never `JSONSerialization`. `FileManager` is used only in the test harness.
@MainActor
@Suite("App — report export coordinator")
struct ReportExportCoordinatorTests {

    /// An exporter that always throws — proves the exporter is (or isn't) reached.
    private struct ThrowingExporter: ReportExporting {
        struct Failure: Error {}
        func export(_: InspectionReport) throws -> Data { throw Failure() }
    }

    /// Counts encode invocations. `@MainActor` (hence `Sendable`); the coordinator calls `export`
    /// synchronously on the main actor, so `assumeIsolated` is valid here.
    @MainActor private final class ExportCounter { var count = 0 }
    private struct CountingExporter: ReportExporting {
        let inner: JSONReportExporter
        let counter: ExportCounter
        func export(_ report: InspectionReport) throws -> Data {
            MainActor.assumeIsolated { counter.count += 1 }
            return try inner.export(report)
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
        let outcome = await coordinator.export(report(status: .completed))
        #expect(outcome == .cancelled)
    }

    // MARK: - Success

    @Test func successWritesExporterOutputToApprovedURLExactlyOnce() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let destination = dir.appendingPathComponent("out.json")

        let exporter = realExporter()
        let counter = ExportCounter()
        var capturedName: String?
        let coordinator = ReportExportCoordinator(
            exporter: CountingExporter(inner: exporter, counter: counter),
            chooseDestination: { name in capturedName = name; return destination }
        )
        let subject = report(status: .completed)

        let outcome = await coordinator.export(subject)

        #expect(outcome == .succeeded)
        #expect(counter.count == 1) // exporter invoked exactly once
        #expect(capturedName == "interview-side-a-inspection.json") // suggested name passed to selector

        // The bytes on disk are exactly the exporter's output (deterministic clock + sorted keys).
        let written = try Data(contentsOf: destination)
        #expect(written == (try exporter.export(subject)))

        // And they decode as JSON v1 via Codable.
        let decoded = try JSONDecoder().decode(JSONValue.self, from: written)
        #expect(decoded["schemaVersion"]?.int == 1)
        #expect(decoded["generator"]?["name"]?.string == "Audio Inspector")

        // Only the destination was created — nothing else was touched in the directory.
        let contents = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        #expect(contents == ["out.json"])
    }

    @Test func writeReplacesAnExistingFileAtomically() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let destination = dir.appendingPathComponent("out.json")
        try Data("stale".utf8).write(to: destination) // pre-existing file at the destination

        let exporter = realExporter()
        let coordinator = ReportExportCoordinator(exporter: exporter, chooseDestination: { _ in destination })
        let subject = report(status: .completed)

        let outcome = await coordinator.export(subject)

        #expect(outcome == .succeeded)
        let written = try Data(contentsOf: destination)
        #expect(written == (try exporter.export(subject))) // fully replaced with the new content
    }

    // MARK: - Failures

    @Test func encodingFailureDoesNotWrite() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let destination = dir.appendingPathComponent("out.json")

        let coordinator = ReportExportCoordinator(exporter: ThrowingExporter(), chooseDestination: { _ in destination })
        let outcome = await coordinator.export(report(status: .completed))

        #expect(outcome == .encodingFailed)
        #expect(!FileManager.default.fileExists(atPath: destination.path)) // nothing written
    }

    @Test func writeFailureReturnsWriteFailed() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        // A destination inside a non-existent subdirectory → the atomic write fails.
        let destination = dir.appendingPathComponent("missing-subdir", isDirectory: true).appendingPathComponent("out.json")

        let coordinator = ReportExportCoordinator(exporter: realExporter(), chooseDestination: { _ in destination })
        let outcome = await coordinator.export(report(status: .completed))

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
