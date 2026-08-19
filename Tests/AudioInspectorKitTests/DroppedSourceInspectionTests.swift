import Foundation
import Testing

import AudioInspectorDomain
import FeatureImport
@testable import AudioInspectorApp

/// Light integration for the drop path: a dropped URL is routed through the real decision, the real
/// coordinator, the real AVFoundation reader and the real use case, over a PCM fixture generated
/// in-test. No panel is opened and no real drag occurs — the URL is injected, which is exactly what the
/// drop handler does after accepting it.
///
/// Export is deliberately not repeated here: `EndToEndFlowTests` already covers it for the shared
/// pipeline, and both entry points converge on that same pipeline.
@MainActor
@Suite("App — dropped source inspection")
struct DroppedSourceInspectionTests {

    @Test func aDroppedFixtureIsInspectedThroughTheRealPipeline() async throws {
        try await withTemporaryDirectory { directory in
            let url = directory.appendingPathComponent("dropped.wav")
            try writePCMFixture(to: url)

            guard case let .accepted(accepted) = DroppedSource.evaluate([url], isInspecting: false) else {
                Issue.record("expected the fixture to be accepted"); return
            }

            // Exactly what `AppContainer.makeDroppedSourceInspectionAction()` builds.
            let coordinator = SourceInspectionCoordinator()
            guard case let .inspected(report, _) = await coordinator.inspect(accepted, onUpdate: { _ in }) else {
                Issue.record("expected an inspected outcome"); return
            }

            // Descriptive metadata comes from the dropped file itself, with no normalisation needed.
            #expect(report.file.displayName == "dropped.wav")
            #expect(report.file.fileExtension == "wav")
            #expect(report.file.sizeBytes != nil)
            #expect(report.properties.sampleRate == .available(44_100))
            #expect(report.properties.channelCount == .available(1))
            #expect(report.properties.codec == .available("lpcm"))
            // The origin stays safe: no path, no URL, no bookmark in the domain reference.
            #expect(report.file.source == .userSelectedLocalFile(displayName: "dropped.wav", locationDisclosure: .omitted))
        }
    }

    @Test func theDroppedSourceFileIsByteIdenticalAfterInspection() async throws {
        try await withTemporaryDirectory { directory in
            let url = directory.appendingPathComponent("untouched.wav")
            try writePCMFixture(to: url)
            let before = try Data(contentsOf: url)

            let coordinator = SourceInspectionCoordinator()
            _ = await coordinator.inspect(url, onUpdate: { _ in })

            #expect(try Data(contentsOf: url) == before) // ADR-0013's read-only promise, drop path
        }
    }

    /// The composition root builds the drop action, and driving the flow model with it lands a report —
    /// the same chain the drop handler runs, without SwiftUI.
    @Test func theCompositionRootDropActionDrivesTheFlowToAReport() async throws {
        try await withTemporaryDirectory { directory in
            let url = directory.appendingPathComponent("wired.wav")
            try writePCMFixture(to: url)

            let makeAction = AppContainer().makeDroppedSourceInspectionAction()
            let model = ImportFlowModel(action: { _ in .cancelled }) // the panel action stays unused
            await model.inspectDroppedSource(using: makeAction(url))

            guard case let .report(presentation) = model.state else {
                Issue.record("expected a report state, got \(model.state)"); return
            }
let report = presentation.report
            #expect(report.file.displayName == "wired.wav")
            #expect(report.properties.sampleRate == .available(44_100))
            #expect(model.dropRejection == nil)
        }
    }

    /// The assertion that keeps both entry points on one pipeline: the same file inspected through the
    /// panel's coordinator and through the drop's produces the same report.
    ///
    /// Everything but `AudioFileReference.id` is compared — that identifier is a fresh `UUID` per
    /// reference, so it plays the same role the exporter's `generatedAt` plays in the JSON: unique per
    /// run by design. The export itself is not repeated here; `EndToEndFlowTests` already covers it,
    /// and the exporter is a pure function of the report, so identical reports export identically.
    @Test func thePanelAndTheDropProduceTheSameReportForTheSameFile() async throws {
        try await withTemporaryDirectory { directory in
            let url = directory.appendingPathComponent("same.wav")
            try writePCMFixture(to: url)

            let viaPanel = SourceInspectionCoordinator(chooseSource: { url })
            let viaDrop = SourceInspectionCoordinator()

            guard case let .inspected(panelReport, _) = await viaPanel.inspect(onUpdate: { _ in }),
                  case let .inspected(dropReport, _) = await viaDrop.inspect(url, onUpdate: { _ in })
            else {
                Issue.record("both entry points must produce a report"); return
            }

            #expect(panelReport.file.displayName == dropReport.file.displayName)
            #expect(panelReport.file.fileExtension == dropReport.file.fileExtension)
            #expect(panelReport.file.sizeBytes == dropReport.file.sizeBytes)
            #expect(panelReport.file.modifiedAt == dropReport.file.modifiedAt)
            #expect(panelReport.file.source == dropReport.file.source)
            #expect(panelReport.properties == dropReport.properties)
            #expect(panelReport.warnings == dropReport.warnings)
            #expect(panelReport.status == dropReport.status)
        }
    }

    /// The contractual half of the same criterion: the canonical spec says both mechanisms produce the
    /// same **exported JSON** apart from the envelope fields the exporter generates per export. With the
    /// clock and the generator identity fixed, those envelope fields are pinned too, so the whole
    /// decoded tree must match — no field is excluded and nothing is normalised away.
    ///
    /// Comparison is structural, through the existing `Codable`-only `JSONValue` tree: no `Any`, no
    /// `[String: Any]`, no `JSONSerialization`, no textual substitution.
    ///
    /// This also proves the report's ephemeral `id` is not exported: the two references carry different
    /// `UUID`s by construction, so identical JSON is only possible if that value never reaches the wire.
    /// It is not a second copy of the group-7 end-to-end test — it asserts only panel/drop equivalence.
    @Test func thePanelAndTheDropExportTheSameJSONForTheSameFile() async throws {
        try await withTemporaryDirectory { directory in
            let url = directory.appendingPathComponent("same.wav")
            try writePCMFixture(to: url)

            let viaPanel = SourceInspectionCoordinator(chooseSource: { url })
            let viaDrop = SourceInspectionCoordinator()

            guard case let .inspected(panelReport, _) = await viaPanel.inspect(onUpdate: { _ in }),
                  case let .inspected(dropReport, _) = await viaDrop.inspect(url, onUpdate: { _ in })
            else {
                Issue.record("both entry points must produce a report"); return
            }

            // Distinct in memory — so an identical export can only mean the id is never serialised.
            #expect(panelReport.file.id != dropReport.file.id)

            let panelJSON = try exportValue(panelReport, now: fixedNow, generator: fixedGenerator)
            let dropJSON = try exportValue(dropReport, now: fixedNow, generator: fixedGenerator)

            // The entire tree, envelope included, compared as one value.
            #expect(panelJSON == dropJSON)

            // Spelled out so a regression names the section that drifted rather than the whole document.
            #expect(panelJSON["inspectedFile"] == dropJSON["inspectedFile"])
            #expect(panelJSON["technicalProperties"] == dropJSON["technicalProperties"])
            #expect(panelJSON["warnings"] == dropJSON["warnings"])
            #expect(panelJSON["inspectionStatus"] == dropJSON["inspectionStatus"])
            #expect(panelJSON["schemaVersion"] == dropJSON["schemaVersion"])
            #expect(panelJSON["generator"] == dropJSON["generator"])
            #expect(panelJSON["generatedAt"] == dropJSON["generatedAt"])

            // All nine technical properties are present and none is entry-point dependent.
            let properties = try #require(panelJSON["technicalProperties"]?.keys)
            #expect(properties == [
                "container", "duration", "sampleRate", "channelCount",
                "bitDepth", "codec", "declaredBitrate", "estimatedBitrate", "averageFileBitrate",
            ])

            // The safe origin travels identically, and no location key appears by either route.
            #expect(!allKeys(dropJSON).contains("path"))
            #expect(!allKeys(dropJSON).contains("url"))
        }
    }

    /// A non-file URL cannot even be prepared, and that stays a preparation failure rather than a
    /// fabricated report — the guard lives in the shared body, so both entry points get it.
    @Test func aNonFileURLReachingTheCoordinatorIsAPreparationFailure() async throws {
        let remote = try #require(URL(string: "https://example.com/song.wav"))
        let coordinator = SourceInspectionCoordinator()

        #expect(await coordinator.inspect(remote, onUpdate: { _ in }) == .preparationFailed)
    }
}
