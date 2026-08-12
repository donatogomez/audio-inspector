import FeatureAnalysis
import FeatureImport
import SwiftUI

/// The application's composition root.
///
/// This is the only place that wires concrete implementations (media, selection, export) to the
/// domain ports and the feature surfaces. It builds the two injected actions — inspect a
/// user-selected file, and export a report to a chosen destination — and hands them to the root view,
/// so the features never see a panel, a `URL`, the sandbox, or the reader.
@MainActor
public struct AppContainer {
    /// The exporter identity for this build. Injected here (never read from the bundle in the
    /// exporter) so the export layer stays decoupled from `Bundle`.
    private static let reportGenerator = ReportGenerator(name: "Audio Inspector", version: "0.1.0")

    public init() {}

    /// The app's root view, wired to the real selection → inspection → presentation → export flow.
    public func makeRootView() -> some View {
        RootView(
            flow: ImportFlowModel(action: makeSourceInspectionAction()),
            inspectDroppedSource: makeDroppedSourceInspectionAction(),
            export: makeReportExportAction()
        )
    }

    /// Builds the inspection action for a file the user dropped and the root view accepted. The URL is
    /// captured inside the returned closure, so `FeatureImport` receives an opaque
    /// `SourceInspectionAction` and never a location. The same coordinator runs it — only its entry
    /// point differs, which is why no second pipeline exists.
    func makeDroppedSourceInspectionAction() -> @MainActor (URL) -> SourceInspectionAction {
        { url in
            let coordinator = SourceInspectionCoordinator()
            return { onUpdate in await coordinator.inspect(url, onUpdate: onUpdate) }
        }
    }

    /// Builds the injectable inspection action: the native open panel supplies the file, and the
    /// coordinator holds security-scoped access, builds the safe reference, and runs the use case with
    /// the real AVFoundation reader. `FeatureImport` receives this as an opaque
    /// `SourceInspectionAction`; it never learns about the panel, the URL, or the reader.
    func makeSourceInspectionAction() -> SourceInspectionAction {
        let coordinator = SourceInspectionCoordinator(chooseSource: { await SourceSelection.choose() })
        return { onUpdate in await coordinator.inspect(onUpdate: onUpdate) }
    }

    /// Builds the injectable export action from the existing JSON exporter and the `NSSavePanel`
    /// destination selector, wired through the coordinator. `FeatureAnalysis` receives this as an
    /// opaque `ReportExportAction`; it never learns about the panel, the URL, or the exporter.
    func makeReportExportAction() -> ReportExportAction {
        let coordinator = ReportExportCoordinator(
            exporter: JSONReportExporter(generator: Self.reportGenerator),
            chooseDestination: { suggestedName in
                await ReportExportDestination.choose(suggestedName: suggestedName)
            }
        )
        return { report, signalLevelMetrics, truePeak in
            await coordinator.export(
                report, signalLevelMetrics: signalLevelMetrics, truePeak: truePeak
            )
        }
    }
}
