import Foundation
import Testing

import AudioInspectorDomain
@testable import AudioInspectorApp
@testable import FeatureImport

// Group 9's fourth subject: **a drawing never reaches the wire** (task 9.5).
//
// `ExportComparisonIsolationTests` next door already asserts that *a comparison* changes no byte of a
// file's document. This suite asserts the stronger thing this change makes possible and that one
// could not: that **a settled pair of drawings** — the whole feature, on screen, retained, presented —
// changes no byte either.
//
// ## Why it is exported through the coordinator and not the encoder
//
// Because the encoder alone cannot be wrong in the way that matters. `ReportExporting.export` takes a
// report and its measurements, so the interesting failure is not *the encoder invented a key* but
// *something on the path handed the encoder more than it should have*. So the path is the real one:
// the same `JSONReportExporter` the composition root builds, inside the same `ReportExportCoordinator`,
// writing real bytes to a real file, with the two things production injects — the clock and the
// generator identity — injected fixed so that two exports of the same report are comparable at all.
// The only substitution is the destination: an `NSSavePanel` cannot be driven from a test, and a
// temporary directory is what every other export test uses in its place.
//
// The bytes are compared as `Data`. A structural comparison would pass a document that gained a key
// encoded differently, and byte identity is what the task asks for.

@MainActor
@Suite("Export — a pair of drawings on screen changes no byte")
struct PairedVisualsExportIsolationTests {

    // MARK: - The real export path, minus the panel

    /// The exporter the composition root builds, with production's own two injections replaced by
    /// fixed values, run through the production coordinator, writing to `destination`.
    private func exportThroughTheRealPath(
        _ report: InspectionReport, measurements: ReportMeasurements, to destination: URL
    ) async throws -> Data {
        let coordinator = ReportExportCoordinator(
            exporter: JSONReportExporter(generator: fixedGenerator, now: { fixedNow }),
            chooseDestination: { _ in destination }
        )
        let outcome = await coordinator.export(report, measurements: measurements)
        #expect(outcome == .succeeded)
        return try Data(contentsOf: destination)
    }

    private func temporaryDirectory() throws -> URL {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("audio-inspector-group-9-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    // MARK: - Fixtures: a flow driven to a real, settled pair

    private func report(_ name: String, properties: TechnicalProperties = allAvailableProperties()) -> InspectionReport {
        InspectionReport(
            file: AudioFileReference(
                displayName: name, fileExtension: "wav", sizeBytes: 2_048,
                modifiedAt: date("2026-06-12T09:03:00Z"),
                source: .userSelectedLocalFile(displayName: name, locationDisclosure: .omitted)
            ),
            properties: properties, warnings: [], status: .completed
        )
    }

    private func envelope(peak: Float) -> WaveformEnvelope {
        WaveformEnvelope(
            buckets: [WaveformBucket(minimum: -peak, maximum: peak)!],
            frameCount: 2_048, channelCount: 2
        )!
    }

    private func model(rate: Double) -> Spectrogram {
        Spectrogram(
            values: [-30, -40, -50, -60], columnCount: 2, bandCount: 2,
            sampleRate: rate, frameCount: 2_048, channelCount: 2
        )!
    }

    private func analyses(rate: Double, peak: Float) -> InspectionAnalyses {
        InspectionAnalyses(
            waveform: .available(envelope(peak: peak)),
            spectrogram: .available(model(rate: rate)),
            signalLevelMetrics: .unavailable, truePeak: .unavailable,
            loudness: .unavailable, significantBandwidth: .unavailable,
            stream: PCMStreamDescription(sampleRate: rate, channelCount: 2, frameCount: 2_048)!
        )
    }

    /// A flow showing `primary`'s report with its own drawings settled. **No comparison at all** —
    /// not a dismissed one, not a cancelled one: the state the app is in before this feature has
    /// anything to do.
    private func flowShowingOneFile(_ primary: InspectionReport) async -> ImportFlowModel {
        let action = ImportFlowComparisonTests.ControllableAction(delivering: [.report(primary)])
        let flow = ImportFlowModel(action: action.run)
        let running = Task { await flow.selectAndInspect() }
        await action.waitUntilStarted()
        action.finish(.inspected(primary, analyses: analyses(rate: 44_100, peak: 0.5)))
        await running.value
        return flow
    }

    /// The same, plus a second file inspected and a **pair settled** — asserted settled, so what
    /// follows is a statement about a pair rather than about its absence.
    private func flowShowingAPair(_ primary: InspectionReport, against second: InspectionReport) async -> ImportFlowModel {
        let flow = await flowShowingOneFile(primary)
        let compared = ImportFlowComparisonTests.ControllableAction()
        let comparing = Task { await flow.compare(using: compared.run) }
        await compared.waitUntilStarted()
        compared.finish(.inspected(second, analyses: analyses(rate: 96_000, peak: 0.9)))
        await comparing.value

        guard case .ready(_, _, .some) = flow.comparison else {
            Issue.record("the fixture did not settle a pair; every assertion below would be vacuous")
            return flow
        }
        return flow
    }

    /// What the composition root hands the exporter, taken from the flow rather than rebuilt.
    private func whatTheSurfaceWouldExport(_ flow: ImportFlowModel) -> (InspectionReport, ReportMeasurements)? {
        guard case let .report(presentation) = flow.state else { return nil }
        return (presentation.report, presentation.settledMeasurements ?? ReportMeasurements(signalLevelMetrics: nil, truePeak: nil, loudness: nil, programmeBandwidth: nil))
    }

    // MARK: - 9.5 · the byte-identity claim

    /// **The main assertion.** The same file, exported with a settled pair of drawings on screen and
    /// exported with no comparison at all, produces identical bytes — through the real coordinator,
    /// off the real filesystem.
    @Test("a file's JSON is byte-identical with a settled pair on screen and without one")
    func theJSONIsByteIdenticalWithAndWithoutAPair() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let primary = report("a.wav")
        let alone = try #require(whatTheSurfaceWouldExport(await flowShowingOneFile(primary)))
        let paired = try #require(
            whatTheSurfaceWouldExport(await flowShowingAPair(primary, against: report("b.wav")))
        )

        let withoutAPair = try await exportThroughTheRealPath(
            alone.0, measurements: alone.1, to: directory.appendingPathComponent("alone.json")
        )
        let withAPair = try await exportThroughTheRealPath(
            paired.0, measurements: paired.1, to: directory.appendingPathComponent("paired.json")
        )

        #expect(withoutAPair == withAPair)
        #expect(!withoutAPair.isEmpty)
    }

    /// **The positive control, kept permanently.** Byte identity is worth nothing unless the same
    /// path can also report a difference, so a report that genuinely differs is exported through it.
    @Test("the byte comparison through the real path detects a report that really differs")
    func theByteComparisonHasTeeth() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        var altered = allAvailableProperties()
        altered.sampleRate = .available(48_000)

        let original = try await exportThroughTheRealPath(
            report("a.wav"), measurements: ReportMeasurements(signalLevelMetrics: nil, truePeak: nil, loudness: nil, programmeBandwidth: nil),
            to: directory.appendingPathComponent("original.json")
        )
        let different = try await exportThroughTheRealPath(
            report("a.wav", properties: altered), measurements: ReportMeasurements(signalLevelMetrics: nil, truePeak: nil, loudness: nil, programmeBandwidth: nil),
            to: directory.appendingPathComponent("different.json")
        )

        #expect(original != different)
    }

    // MARK: - 9.5 · and nothing of a drawing is in the document

    /// **The envelope is exactly the `schemaVersion` 1 envelope, with a pair on screen.**
    ///
    /// This is the assertion a leak would trip first, and it is the one the negative control is aimed
    /// at: any field carrying anything derived from a visual has to appear at some level of this
    /// document, and the top level is pinned to its seven keys.
    @Test("the document's top level is the seven v1 keys, with a pair on screen")
    func theTopLevelIsUnchanged() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let paired = try #require(
            whatTheSurfaceWouldExport(await flowShowingAPair(report("a.wav"), against: report("b.wav")))
        )
        let data = try await exportThroughTheRealPath(
            paired.0, measurements: paired.1, to: directory.appendingPathComponent("paired.json")
        )
        let value = try JSONDecoder().decode(JSONValue.self, from: data)

        #expect(try #require(value.keys) == [
            "schemaVersion", "generatedAt", "generator",
            "inspectedFile", "technicalProperties", "warnings", "inspectionStatus",
        ])
        #expect(value["schemaVersion"]?.int == 1)
    }

    /// **No key anywhere names a drawing.** Over the tree's keys, never its values: a container or a
    /// codec is a string the user's file chose, and scanning values would report a file legitimately
    /// named `spectrogram.wav`.
    @Test("no key derived from a drawing appears anywhere in the document")
    func noVisualKeyAppears() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let paired = try #require(
            whatTheSurfaceWouldExport(await flowShowingAPair(report("a.wav"), against: report("b.wav")))
        )
        let data = try await exportThroughTheRealPath(
            paired.0, measurements: paired.1, to: directory.appendingPathComponent("paired.json")
        )
        let keys = try allKeys(JSONDecoder().decode(JSONValue.self, from: data))

        for key in [
            "visuals", "visual", "paired", "pairedVisuals", "drawings", "drawing",
            "waveform", "envelope", "buckets", "bucket", "peak", "minimum", "maximum",
            "spectrogram", "spectrum", "columns", "columnCount", "bands", "bandCount",
            "values", "cells", "raster", "image", "pixels", "colourRamp", "colorRamp",
            "stream", "sharedAxis", "nyquist",
        ] {
            #expect(!keys.contains(key), "the document gained a \"\(key)\" key")
        }
    }

    /// **A pair is on screen and the report is not touched by it.** The value handed to the exporter
    /// with a pair settled is the same value it would have been handed without one — the half a
    /// byte comparison of two encodings could not distinguish from an encoder that normalises.
    @Test("the report the surface would export is unchanged by a pair existing")
    func theReportHandedOutIsUnchanged() async throws {
        let primary = report("a.wav")
        let alone = try #require(whatTheSurfaceWouldExport(await flowShowingOneFile(primary)))
        let flow = await flowShowingAPair(primary, against: report("b.wav"))
        let paired = try #require(whatTheSurfaceWouldExport(flow))

        #expect(alone.0 == paired.0)
        #expect(alone.1 == paired.1)
        // And the pair really is there while that holds.
        guard case .ready(_, _, .some) = flow.comparison else {
            Issue.record("expected a settled pair"); return
        }
    }
}
