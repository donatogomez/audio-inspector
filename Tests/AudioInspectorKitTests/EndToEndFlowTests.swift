import CryptoKit
import Foundation
import Testing

import AudioInspectorDomain
import AudioInspectorTesting
import FeatureImport
@testable import AudioInspectorApp
@testable import FeatureAnalysis

/// The end-to-end validation of the MVP slice (task 7.1) together with the source-integrity guarantee
/// (task 7.2's first half).
///
/// One run walks the **entire production chain**: a real PCM file on disk → the safe reference →
/// the real AVFoundation reader → the use case → the report held by `ImportFlowModel` → the
/// presentation formatter → the real JSON exporter → a real write to a different file → the bytes
/// read back and decoded with `Codable`.
///
/// The **only** doubles are the two points where a human would act, plus the two envelope inputs that
/// must be deterministic: the source picker, the destination picker, the clock, and the generator
/// identity. `NSOpenPanel` and `NSSavePanel` are never opened; the sandbox powerbox and the visual
/// rendering are out of reach from SwiftPM and are covered by `docs/manual-validation-mvp.md`.
@MainActor
@Suite("End-to-end — inspect a real file and export its report")
struct EndToEndFlowTests {

    /// Descriptive attributes captured straight from the filesystem, to compare before and after.
    /// Access time is deliberately **not** captured: reading a file legitimately updates it.
    private struct SourceAttributes: Equatable {
        let sizeBytes: Int?
        let modifiedAt: Date?
    }

    private func attributes(of url: URL) throws -> SourceAttributes {
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        return SourceAttributes(sizeBytes: values.fileSize, modifiedAt: values.contentModificationDate)
    }

    /// SHA-256 over every byte of the file, using the platform's own crypto — no subprocess, no
    /// external tool. `CryptoKit` is used here in tests only; production never hashes anything.
    private func sha256(of url: URL) throws -> SHA256Digest {
        SHA256.hash(data: try Data(contentsOf: url))
    }

    @Test func inspectsAPCMFileExportsItsReportAndLeavesTheSourceUntouched() async throws {
        try await withTemporaryDirectory { directory in
            // 1. A real audio file on disk.
            let source = directory.appendingPathComponent("fixture.wav")
            try writePCMFixture(to: source)

            // 7.2 — the source as it stands before anything touches it.
            let hashBefore = try sha256(of: source)
            let attributesBefore = try attributes(of: source)

            // 2–6. Selection seam → coordinator (mapper + real reader + use case) → flow model.
            let inspection = SourceInspectionCoordinator(chooseSource: { source })
            let flow = ImportFlowModel(action: { onUpdate in await inspection.inspect(onUpdate: onUpdate) })
            await flow.selectAndInspect()

                        guard case let .report(presentation) = flow.state else {
                Issue.record("expected the flow to end in .report, got \(flow.state)"); return
            }
            let report = presentation.report

            // The waveform travelled the same pipeline, beside the report and never inside it: this run
            // uses the production generator, so a real second read of the same file happened inside the
            // one access window.
            guard case let .available(envelope) = presentation.waveform else {
                Issue.record("expected an available waveform, got \(presentation.waveform)"); return
            }
            #expect(envelope.channelCount == 1, "the envelope describes the file the report describes")
            #expect(envelope.frameCount > 0)
            #expect(envelope.buckets.count == min(2_048, envelope.frameCount))
            // It reaches the surface that draws it, as the state that draws it.
            #expect(RootView.waveformPresentation(for: presentation.waveform) == .envelope(envelope))

            // The report describes the selected file, with no location anywhere in it.
            #expect(report.file.displayName == "fixture.wav")
            #expect(report.file.fileExtension == "wav")
            #expect(report.file.sizeBytes == attributesBefore.sizeBytes)
            #expect(report.file.modifiedAt != nil)

            // The PCM facts the reader is validated to produce (spike 0031).
            #expect(report.properties.sampleRate == .available(44_100))
            #expect(report.properties.channelCount == .available(1))
            #expect(report.properties.bitDepth == .available(16))
            #expect(report.properties.codec == .available("lpcm"))
            guard case let .available(seconds) = report.properties.duration else {
                Issue.record("expected an available duration, got \(report.properties.duration)"); return
            }
            #expect(seconds > 0)

            // 7. The report is presentable: the eight rows `ReportView` renders.
            let displays = ReportPropertyFormatter.displays(for: report.properties)
            #expect(displays.count == 8)
            // Every row is well formed: nothing failed to read on a fixture we generated ourselves.
            #expect(displays.allSatisfy { $0.state != .couldNotBeRead })
            // Readable value, with the exact figure preserved beside it.
            #expect(displays.first { $0.name == "Sample rate" }?.value == "44.1 kHz")
            #expect(displays.first { $0.name == "Sample rate" }?.detail == "44,100 Hz")
            // The codec token `lpcm` is now named, with the token preserved as detail.
            #expect(displays.first { $0.name == "Codec" }?.value == "Linear PCM")
            #expect(displays.first { $0.name == "Codec" }?.detail == "lpcm")

            // 8–10. The same report, exported for real to a *different* file.
            let destination = directory.appendingPathComponent("out.json")
            #expect(destination != source)
            var suggestedName: String?
            let exportCoordinator = ReportExportCoordinator(
                exporter: JSONReportExporter(generator: fixedGenerator, now: { fixedNow }),
                chooseDestination: { name in suggestedName = name; return destination }
            )
            let exportModel = ReportExportModel(action: { await exportCoordinator.export($0) })
            await exportModel.export(report)

            #expect(exportModel.phase == .succeeded)
            #expect(suggestedName == "fixture-inspection.json")

            // Exporting neither recalculates nor mutates the report the UI holds, and it leaves
            // whatever became of the waveform beside it untouched.
            #expect(flow.state == .report(presentation))

            // 11. Read the bytes back and decode them with `Codable` only.
            let json = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: destination))

            // 12. The document is coherent with *that* report.
            #expect(json["schemaVersion"]?.int == 1)
            #expect(json["generatedAt"]?.string == "2026-08-03T12:00:00Z")
            #expect(json["generator"]?["name"]?.string == "Audio Inspector")
            #expect(json["generator"]?["version"]?.string == "0.1.0")

            let inspectedFile = try #require(json["inspectedFile"])
            #expect(inspectedFile["name"]?.string == report.file.displayName)
            #expect(inspectedFile["fileExtension"]?.string == "wav")
            #expect(inspectedFile["sizeBytes"]?.int == report.file.sizeBytes)
            #expect(inspectedFile["source"]?["kind"]?.string == "userSelectedLocalFile")
            #expect(inspectedFile["source"]?["locationDisclosure"]?.string == "omitted")

            let technical = try #require(json["technicalProperties"])
            #expect(try #require(technical.keys) == [
                "container", "duration", "sampleRate", "channelCount",
                "bitDepth", "codec", "declaredBitrate", "estimatedBitrate",
            ])
            #expect(technical["sampleRate"]?["value"]?.int == 44_100)
            #expect(technical["codec"]?["value"]?.string == "lpcm")

            // Warnings and status come from the report unchanged — the exporter derives nothing.
            let warnings = try #require(json["warnings"]?.array)
            #expect(warnings.count == report.warnings.count)
            #expect(json["inspectionStatus"]?["state"]?.string == wireState(of: report.status))

            // Privacy: no location can appear anywhere, and the ephemeral id never leaks.
            let forbidden: Set<String> = [
                "path", "url", "fileURL", "absolutePath", "bookmark", "securityScopedBookmark",
                "parentDirectory", "directory", "location", "bookmarkData", "id",
            ]
            #expect(allKeys(json).isDisjoint(with: forbidden))
            let text = try #require(String(data: try Data(contentsOf: destination), encoding: .utf8))
            #expect(!text.contains(directory.path))
            #expect(!text.contains(directory.lastPathComponent))
            #expect(!text.contains(report.file.id.uuidString))

            // The directory holds exactly the source and its export — nothing else was written.
            let contents = try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
            #expect(contents == ["fixture.wav", "out.json"])

            // 7.2 — the source is byte-identical after inspecting *and* exporting.
            #expect(try sha256(of: source) == hashBefore)
            #expect(try attributes(of: source) == attributesBefore)
        }
    }

    /// The same walk, for a file whose samples cannot be read.
    ///
    /// The point is not that the waveform is missing — that is scripted — but that **nothing else
    /// moves when it is**: the same pipeline runs end to end, the report is complete, the export
    /// succeeds and the document written to disk is byte-identical to the one the run above produced.
    /// The only substitution beyond the two panels is the waveform port; the property reader, the use
    /// case, the flow model, the exporter and the write are all real.
    @Test func theSamePipelineRunsAndExportsIdenticallyWhenNoWaveformCanBeProduced() async throws {
        try await withTemporaryDirectory { directory in
            let source = directory.appendingPathComponent("fixture.wav")
            try writePCMFixture(to: source)
            let hashBefore = try sha256(of: source)

            @MainActor
            func run(waveform: FakeWaveformGenerating.Outcome) async throws -> (InspectionPresentation, Data) {
                let inspection = SourceInspectionCoordinator(
                    chooseSource: { source },
                    makeWaveformGenerator: { _ in FakeWaveformGenerating(waveform) }
                )
                let flow = ImportFlowModel(action: { onUpdate in await inspection.inspect(onUpdate: onUpdate) })
                await flow.selectAndInspect()

                guard case let .report(presentation) = flow.state else {
                    throw FlowDidNotProduceAReport()
                }
                let destination = directory.appendingPathComponent("out-\(UUID().uuidString).json")
                let exportCoordinator = ReportExportCoordinator(
                    exporter: JSONReportExporter(generator: fixedGenerator, now: { fixedNow }),
                    chooseDestination: { _ in destination }
                )
                let exportModel = ReportExportModel(action: { await exportCoordinator.export($0) })
                await exportModel.export(presentation.report)
                #expect(exportModel.phase == .succeeded)

                return (presentation, try Data(contentsOf: destination))
            }

            let bucket = try #require(WaveformBucket(minimum: -0.5, maximum: 0.5))
            let envelope = try #require(
                WaveformEnvelope(buckets: [bucket], frameCount: 8, channelCount: 1)
            )
            let (withWaveform, documentWithWaveform) = try await run(waveform: .success(envelope))
            let (withoutWaveform, documentWithoutWaveform) = try await run(waveform: .absent)

            // Both walks produced a real, complete report.
            #expect(withWaveform.waveform == .available(envelope))
            #expect(withoutWaveform.waveform == .unavailable)
            #expect(withoutWaveform.report.properties.sampleRate == .available(44_100))
            #expect(withoutWaveform.report.properties.channelCount == .available(1))

            // The report says the same thing either way…
            #expect(withoutWaveform.report.properties == withWaveform.report.properties)
            #expect(withoutWaveform.report.warnings == withWaveform.report.warnings)
            #expect(withoutWaveform.report.status == withWaveform.report.status)

            // …and so does every byte written to disk.
            #expect(documentWithoutWaveform == documentWithWaveform)

            // The surface is told the truth about the absence rather than shown an empty drawing.
            #expect(RootView.waveformPresentation(for: withoutWaveform.waveform) == .absent)

            // And neither walk touched the source.
            #expect(try sha256(of: source) == hashBefore)
        }
    }

    private struct FlowDidNotProduceAReport: Error {}

    /// The wire token for a domain status, so the JSON is compared against the report rather than
    /// against a hard-coded expectation.
    private func wireState(of status: InspectionStatus) -> String {
        switch status {
        case .completed: "completed"
        case .partial: "partial"
        case .failed: "failed"
        }
    }
}
