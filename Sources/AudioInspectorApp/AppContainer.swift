import FeatureAnalysis
import SwiftUI

/// The application's composition root.
///
/// This is the only place that wires concrete implementations (media, analysis, export) to the
/// domain ports/features. The root view is still empty: presenting `ReportView` needs a real report,
/// which only arrives once source selection and inspection are wired (group 6). This slice therefore
/// leaves `makeRootView` untouched and only vends the **export action** the presentation will use, so
/// group 6 can hand a report to `ReportView(report:export:)` without any further composition work.
@MainActor
public struct AppContainer {
    /// The exporter identity for this build. Injected here (never read from the bundle in the
    /// exporter) so the export layer stays decoupled from `Bundle`.
    private static let reportGenerator = ReportGenerator(name: "Audio Inspector", version: "0.1.0")

    public init() {}

    /// The app's root view. Still empty — a real report (and thus `ReportView`) arrives with group 6.
    public func makeRootView() -> some View {
        RootView()
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
        return { report in await coordinator.export(report) }
    }
}
