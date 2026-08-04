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
    @State private var isDropTargeted = false
    private let inspectDroppedSource: @MainActor (URL) -> SourceInspectionAction
    private let export: ReportExportAction

    init(
        flow: ImportFlowModel,
        inspectDroppedSource: @escaping @MainActor (URL) -> SourceInspectionAction,
        export: @escaping ReportExportAction
    ) {
        _flow = State(initialValue: flow)
        self.inspectDroppedSource = inspectDroppedSource
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
        // The whole window is the drop target, in every state — dropping onto a report replaces it.
        .dropDestination(for: URL.self) { (items: [URL], _: CGPoint) -> Bool in
            handleDrop(items)
        } isTargeted: { (targeted: Bool) -> Void in
            isDropTargeted = targeted
        }
        .overlay {
            DropFeedbackOverlay(isTargeted: isDropTargeted, rejection: flow.dropRejection)
        }
    }

    /// The synchronous half of the drop. Decides in `AudioInspectorApp` — where `URL` belongs — and
    /// hands the feature an opaque action already bound to the accepted file. Returns whether the drop
    /// was taken for processing.
    private func handleDrop(_ items: [URL]) -> Bool {
        switch DroppedSource.evaluate(items, isInspecting: flow.state == .working) {
        case let .accepted(url):
            let action = inspectDroppedSource(url)
            // The handler must return synchronously; the inspection is async. A plain MainActor task
            // is enough — the observation confirmed the granted access survives this hop, so nothing
            // is acquired here and no bookmark exists (ADR-0014).
            Task { @MainActor in await flow.inspectDroppedSource(using: action) }
            return true
        case let .rejected(rejection):
            flow.reject(rejection) // leaves `state` untouched, so any report on screen survives
            return false
        }
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
            }
            .padding(12)
        }
    }
}
