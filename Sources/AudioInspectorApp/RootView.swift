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
            case let .report(presentation):
                reportSurface(presentation)
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

    /// Translates the flow's waveform state into the report surface's own.
    ///
    /// The two enums are deliberately separate types rather than one shared one: `FeatureImport` and
    /// `FeatureAnalysis` depend on `AudioInspectorDomain` and never on each other, so the module that
    /// obtains an envelope and the module that draws one cannot see each other's vocabulary. Joining
    /// them is the composition root's job, and this is the whole of it.
    ///
    /// It is total by construction — every state the flow can hold has exactly one presentation, and
    /// none is invented — which is why it is a plain function with no default case. `nonisolated`
    /// because it reads nothing and touches nothing: `View` puts it on the main actor by inference,
    /// and there is no reason for a pure mapping between two value types to need one.
    nonisolated static func waveformPresentation(for state: WaveformState) -> WaveformPresentation {
        switch state {
        case .loading: .loading
        case let .available(envelope): .envelope(envelope)
        case .unavailable: .absent
        case let .failed(message): .failed(message: message)
        }
    }

    /// Translates the flow's spectrogram state into the report surface's own, for the reason and in
    /// the shape `waveformPresentation` already establishes: the two feature modules never see each
    /// other's vocabulary, and joining them is the composition root's job.
    ///
    /// Total by construction, with no default case — every state the flow can hold has exactly one
    /// presentation, and none is invented.
    nonisolated static func spectrogramPresentation(for state: SpectrogramState) -> SpectrogramPresentation {
        switch state {
        case .loading: .loading
        case let .available(model): .model(model)
        case .unavailable: .absent
        case let .failed(message): .failed(message: message)
        }
    }

    /// The inspected report plus the way back to picking another file. `ReportView` is used exactly as
    /// group 5 shipped it — the export action is passed straight through, unchanged.
    /// The comparison's own controls, beside the existing way to pick another file.
    ///
    /// **No new navigation.** Comparing is an action on the report already on screen, so it is an
    /// action next to it — not a mode, not a second window, not a separate screen.
    @ViewBuilder
    private var comparisonControls: some View {
        switch flow.comparison {
        case .none:
            Button("Compare with another file…") {
                Task { await flow.selectAndCompare() }
            }
        case .loading:
            // Disabled rather than hidden: a control that vanishes reads as a bug, and the section
            // itself already says in words what is happening.
            Button("Compare with another file…") {}
                .disabled(true)
        case .ready, .failed:
            // A comparison on screen can be replaced by another file, or closed. Closing touches
            // nothing about the report.
            Button("Compare with another file…") {
                Task { await flow.selectAndCompare() }
            }
            Button("Close comparison") { flow.dismissComparison() }
        }
    }

    /// Translates the flow's comparison state into the presentation vocabulary, exactly as the two
    /// visualisations are translated.
    private static func comparisonPresentation(
        for state: ImportFlowModel.ComparisonState
    ) -> ComparisonPresentation {
        switch state {
        case .none: .none
        case .loading: .loading
        case let .ready(comparison): .ready(comparison)
        case let .failed(message): .failed(message: message)
        }
    }

    private func reportSurface(_ presentation: InspectionPresentation) -> some View {
        VStack(spacing: 0) {
            ReportView(
                report: presentation.report,
                waveform: Self.waveformPresentation(for: presentation.waveform),
                spectrogram: Self.spectrogramPresentation(for: presentation.spectrogram),
                comparison: Self.comparisonPresentation(for: flow.comparison),
                export: export
            )
            Divider()
            HStack(spacing: 12) {
                Spacer()
                comparisonControls
                Button("Choose another file…") {
                    Task { await flow.selectAndInspect() }
                }
            }
            .padding(12)
        }
    }
}
