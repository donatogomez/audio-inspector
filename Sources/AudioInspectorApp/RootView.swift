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
    /// **Where the reader is, owned here and nowhere else** (ADR-0026 §4). It is a plain value in the
    /// composition root's own state: no feature module, no domain type and nothing persisted names it,
    /// and no operation produces it.
    @State private var navigation = WorkspaceNavigation()
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
        // **The only thing that moves the reader, and the only place it is watched.** It sits on the
        // whole window rather than inside the report branch, so it survives every state the flow passes
        // through; a second call site elsewhere would be a second way to navigate, and
        // `WorkspaceOwnershipTests` refuses one. `PrimaryInspection` is a two-field projection so this
        // compares a `UUID`, not two whole inspections — and `observe` answers the same whether it is
        // called once per change or on every render.
        .onChange(of: PrimaryInspection(flow.state)) { _, primary in
            navigation.observe(primary)
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

    /// Translates the flow's signal level metrics state into the report surface's own, for the reason
    /// and in the shape `waveformPresentation`/`spectrogramPresentation` already establish.
    ///
    /// Total by construction, with no default case — every state the flow can hold has exactly one
    /// presentation, and none is invented.
    nonisolated static func signalLevelMetricsPresentation(
        for state: SignalLevelMetricsState
    ) -> SignalLevelMetricsPresentation {
        switch state {
        case .loading: .loading
        case let .available(metrics): .metrics(metrics)
        case .unavailable: .absent
        case let .failed(message): .failed(message: message)
        }
    }

    /// Translates the flow's true peak state into the report surface's own, in the shape the three
    /// analyses before it already established.
    ///
    /// Total by construction, with no default case — every state the flow can hold has exactly one
    /// presentation, and none is invented.
    nonisolated static func truePeakPresentation(for state: TruePeakState) -> TruePeakPresentation {
        switch state {
        case .loading: .loading
        case let .available(measurement): .measurement(measurement)
        case .unavailable: .absent
        case let .failed(message): .failed(message: message)
        }
    }

    /// Translates the flow's integrated loudness state into the report surface's own, in the shape the
    /// four analyses before it already established.
    ///
    /// Total by construction, with no default case — every state the flow can hold has exactly one
    /// presentation, and none is invented. `unavailable` becomes `absent` exactly as its siblings' does,
    /// and the several causes behind it stay where they are known: this mapping adds no reason the flow
    /// did not carry.
    nonisolated static func loudnessPresentation(for state: LoudnessState) -> LoudnessPresentation {
        switch state {
        case .loading: .loading
        case let .available(measurement): .measurement(measurement)
        case .unavailable: .absent
        case let .failed(message): .failed(message: message)
        }
    }

    /// Translates the flow's programme bandwidth state into the report surface's own, in the shape the
    /// five analyses before it already established.
    ///
    /// Total by construction, with no default case — every state the flow can hold has exactly one
    /// presentation, and none is invented. A `default` here would be the same silent omission the
    /// container refactor removed from `InspectionAnalyses`: it would quietly render a state nobody had
    /// thought about as "still loading". `unavailable` becomes `absent` exactly as its siblings' does,
    /// and the several causes behind it stay where they are known.
    nonisolated static func programmeBandwidthPresentation(
        for state: SignificantBandwidthState
    ) -> SignificantBandwidthPresentation {
        switch state {
        case .loading: .loading
        case let .available(measurement): .measurement(measurement)
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
            Button(WorkspaceCopy.startComparison) {
                Task { await flow.selectAndCompare() }
            }
        case .loading:
            // Disabled rather than hidden: a control that vanishes reads as a bug, and the section
            // itself already says in words what is happening.
            Button(WorkspaceCopy.startComparison) {}
                .disabled(true)
        case .ready, .failed:
            // A comparison on screen can be replaced by another file, or closed. Closing touches
            // nothing about the report.
            Button(WorkspaceCopy.startComparison) {
                Task { await flow.selectAndCompare() }
            }
            Button(WorkspaceCopy.closeComparison) { flow.dismissComparison() }
        }
    }

    /// Translates the flow's comparison state into the presentation vocabulary, exactly as the two
    /// visualisations are translated.
    nonisolated static func comparisonPresentation(
        for state: ImportFlowModel.ComparisonState
    ) -> ComparisonPresentation {
        switch state {
        case .none: .none
        case .loading: .loading
        // Both halves travel together, exactly as the flow publishes them: the technical comparison the
        // moment the second report exists, and the measurements once **both** files have settled theirs.
        // The surface renders whichever it has.
        // The paired drawings travel in the same value and are translated by `reportVisuals(for:in:)`,
        // which reads **this same state** in the same call — so the pictures on screen and the facts
        // beside them can never come from two different reads of the flow.
        case let .ready(technical, measurements, _): .ready(technical, measurements: measurements)
        case let .failed(message): .failed(message: message)
        }
    }


    // MARK: - Which drawings the report presents

    /// The first file's own drawings, or two files' on shared axes — decided **once**, for both.
    ///
    /// **Total, with no default.** A new comparison state has to be answered here rather than falling
    /// through to a single drawing, which is the failure a `default` would hide: a pair quietly
    /// disappearing because someone added a case elsewhere.
    ///
    /// A pair that has not settled is not a pair. `.ready` carries `nil` until **both** files have
    /// settled both drawings and both reads have reported their descriptions, so *not yet*, cancelled,
    /// dismissed, superseded and *the second file failed to open* all arrive here as the same answer —
    /// the first file's own drawings, exactly as they are presented without this capability.
    nonisolated static func reportVisuals(
        for presentation: InspectionPresentation, in comparison: ImportFlowModel.ComparisonState
    ) -> ReportVisuals {
        let single = ReportVisuals.single(
            waveform: waveformPresentation(for: presentation.waveform),
            spectrogram: spectrogramPresentation(for: presentation.spectrogram)
        )
        switch comparison {
        case .none, .loading, .failed: return single
        case .ready(_, _, .none): return single
        case let .ready(_, _, .some(paired)): return .paired(pairedVisualsPresentation(for: paired))
        }
    }

    /// The flow's settled pair as the surface's own vocabulary.
    ///
    /// **The geometry is not recomputed here.** Both axes are built by the types that own those rules,
    /// from the two `PCMStreamDescription`s the pair already carries — the same descriptions the reads
    /// reported. No duration, no Nyquist, no amplitude range and no energy range is derived in this
    /// file, and none is taken from either report's declared properties.
    nonisolated static func pairedVisualsPresentation(for paired: PairedVisuals) -> PairedVisualsPresentation {
        PairedVisualsPresentation(
            waveform: PairedWaveformPresentation(
                axis: PairedWaveformAxis(first: paired.first.stream, second: paired.second.stream),
                first: pairedWaveformLane(for: paired.first.waveform),
                second: pairedWaveformLane(for: paired.second.waveform)
            ),
            spectrogram: PairedSpectrogramPresentation(
                axes: PairedSpectrogramAxes(first: paired.first.stream, second: paired.second.stream),
                first: pairedSpectrogramLane(for: paired.first.spectrogram),
                second: pairedSpectrogramLane(for: paired.second.spectrogram)
            )
        )
    }

    /// Total, and the three settled answers stay three: an absence is not a failure, and neither is an
    /// empty drawing.
    nonisolated static func pairedWaveformLane(for settled: SettledWaveform) -> PairedWaveformLane {
        switch settled {
        case let .available(envelope): .envelope(envelope)
        case .unavailable: .absent
        case let .failed(message): .failed(message: message)
        }
    }

    /// The same, for the spectral model. A model with **no columns** arrives as a model, not as an
    /// absence — the distinction `SpectrogramCopyTests` exists to protect survives this layer too.
    nonisolated static func pairedSpectrogramLane(for settled: SettledSpectrogram) -> PairedSpectrogramLane {
        switch settled {
        case let .available(model): .model(model)
        case .unavailable: .absent
        case let .failed(message): .failed(message: message)
        }
    }

    /// **The five sections, and the one the reader is in.**
    ///
    /// A segmented control rather than a sidebar: a sidebar navigates a collection and this window has
    /// one file (ADR-0026 §12). It is the native answer for a single-subject window, and it is the whole
    /// of R1's visible change.
    ///
    /// The five are read from `WorkspaceSection.allCases`, so nothing here can offer four of them — an
    /// absent waveform or a failed spectral model narrows this list by no expression. Their words come
    /// from `WorkspaceCopy`, never from an icon: every section is reachable by reading it, and a
    /// segmented control announces its own selection and takes the keyboard by the native path.
    ///
    /// **Narrow windows are R9's**, and this is what R1 owes them: a control that compresses its labels
    /// keeps all five sections and renames none, so a narrower window changes the layout and never the
    /// section a reader is in.
    private var sectionNavigation: some View {
        Picker(
            WorkspaceCopy.sectionNavigation,
            // The reader is the only thing that selects a section directly, so the binding writes
            // through `select(_:)` rather than to the property.
            selection: Binding(get: { navigation.section }, set: { navigation.select($0) })
        ) {
            ForEach(WorkspaceSection.allCases, id: \.self) { section in
                Text(WorkspaceCopy.label(for: section)).tag(section)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .accessibilityLabel(WorkspaceCopy.sectionNavigation)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func reportSurface(_ presentation: InspectionPresentation) -> some View {
        VStack(spacing: 0) {
            sectionNavigation
            Divider()
            // **One read of the comparison, two answers derived from it.** Reading `flow.comparison`
            // twice in one body could, in principle, straddle a change; binding it once cannot.
            let comparison = flow.comparison
            ReportView(
                report: presentation.report,
                visuals: Self.reportVisuals(for: presentation, in: comparison),
                signalLevelMetrics: Self.signalLevelMetricsPresentation(for: presentation.signalLevelMetrics),
                truePeak: Self.truePeakPresentation(for: presentation.truePeak),
                loudness: Self.loudnessPresentation(for: presentation.loudness),
                programmeBandwidth: Self.programmeBandwidthPresentation(for: presentation.significantBandwidth),
                comparison: Self.comparisonPresentation(for: comparison),
                export: export
            )
            Divider()
            HStack(spacing: 12) {
                Spacer()
                comparisonControls
                Button(WorkspaceCopy.chooseAnotherFile) {
                    Task { await flow.selectAndInspect() }
                }
            }
            .padding(12)
        }
    }
}
