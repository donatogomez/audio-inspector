import AudioInspectorDomain
import FeatureAnalysis
import FeatureImport
import SwiftUI

/// The root of the app: a plain composition of the two feature surfaces, switched by the import
/// flow's state. No navigation stack is introduced — while there is no report the import surface is
/// shown, and once one exists the report surface replaces it, plus an action to pick another file.
///
/// The composition root builds the two injected actions (inspection and export); this view only wires
/// them to the features and knows nothing about panels, `URL`s, or the sandbox.
public struct RootView: View {
    @State private var flow: ImportFlowModel
    private let export: ReportExportAction

    init(flow: ImportFlowModel, export: @escaping ReportExportAction) {
        _flow = State(initialValue: flow)
        self.export = export
    }

    public var body: some View {
        Group {
            switch flow.state {
            case .idle, .working, .failed:
                ImportFlowView(model: flow)
            case let .report(report):
                reportSurface(report)
            }
        }
        .frame(minWidth: 720, minHeight: 480)
    }

    /// The inspected report plus the way back to picking another file. `ReportView` is used exactly as
    /// group 5 shipped it — the export action is passed straight through, unchanged.
    private func reportSurface(_ report: InspectionReport) -> some View {
        VStack(spacing: 0) {
            ReportView(report: report, export: export)
            Divider()
            HStack {
                Spacer()
                Button("Choose another file…") {
                    Task { await flow.selectAndInspect() }
                }
                .disabled(flow.state == .working)
            }
            .padding(12)
        }
    }
}
