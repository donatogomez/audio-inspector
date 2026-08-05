import Foundation
import Testing

import AudioInspectorDomain
import FeatureImport
@testable import AudioInspectorApp

/// Composition-level tests: the app can build the real selection → inspection → presentation flow,
/// and the flow model driven by the **real** coordinator produces a report. The native panel is never
/// opened — the coordinator's source seam supplies a known URL.
@MainActor
@Suite("App — source selection wiring")
struct SourceSelectionWiringTests {

    @Test func compositionRootBuildsTheInspectionAction() {
        // Constructed only — never invoked, so no panel is presented.
        let action: SourceInspectionAction = AppContainer().makeSourceInspectionAction()
        _ = action
    }

    @Test func compositionRootBuildsTheRootViewWithBothActions() {
        // Exercises the real wiring: an import flow model plus the group-5 export action.
        _ = AppContainer().makeRootView()
    }

    /// Light integration: the flow model, the real `SourceInspectionCoordinator`, the real reader and
    /// the real use case, over a file on disk. The file is deliberately not audio, so the reader fails
    /// the whole file — which must still surface as a **report** with a `failed` status (never as a
    /// flow error), proving the real chain is connected end to end.
    @Test func realCoordinatorDrivesTheFlowToAReport() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = directory.appendingPathComponent("not-audio.wav")
        try Data("definitely not audio".utf8).write(to: url)

        let coordinator = SourceInspectionCoordinator(chooseSource: { url })
        let model = ImportFlowModel(action: { onReport in await coordinator.inspect(onReport: onReport) })

        await model.selectAndInspect()

        guard case let .report(presentation) = model.state else {
            Issue.record("expected a report state, got \(model.state)"); return
        }
let report = presentation.report
        // Descriptive metadata came from the real file through the mapper.
        #expect(report.file.displayName == "not-audio.wav")
        #expect(report.file.fileExtension == "wav")
        #expect(report.file.sizeBytes != nil)
        // The reader could not open it → a global failure, expressed inside the report.
        guard case .failed = report.status else {
            Issue.record("expected a failed status, got \(report.status)"); return
        }
        #expect(report.properties == TechnicalProperties())

        // The source file is untouched by the inspection.
        #expect(try Data(contentsOf: url) == Data("definitely not audio".utf8))
    }
}
