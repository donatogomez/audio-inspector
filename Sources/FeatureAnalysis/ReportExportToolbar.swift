import AudioInspectorDomain
import SwiftUI

/// **The export action, attached to the window rather than to one surface.**
///
/// The export used to live inside `ReportView`, which was correct while `ReportView` *was* the report:
/// one page, always on screen whenever there was something to export. The workspace redesign made that
/// false a section at a time, and R7 made it visible — with every section carrying its own content,
/// `ReportView` renders only while a comparison is on screen, so a reader inspecting a single file had
/// no way to export it at all.
///
/// The fix is not to give a section the export back. It is to attach it where the thing being exported
/// actually lives: **a window has one report, and that report can be exported from wherever the reader
/// happens to be standing.** So this is a modifier the composition root applies once, to the surface
/// that exists exactly when a report does.
///
/// ## What it does not move
///
/// `ReportExportModel` still owns the transient phase and still sequences one injected
/// `ReportExportAction`; `ExportableMeasurements` still turns four presentation states into the four
/// optionals the domain's `ReportMeasurements` carries. **The payload is untouched** — same rule, same
/// values, same `schemaVersion` 1. Only the placement of the control changed, which is the whole point:
/// R0 extracted that rule out of the view precisely so the view could be taken apart without the export
/// following it.
public struct ReportExportToolbar: ViewModifier {
    private let report: InspectionReport
    private let signalLevelMetrics: SignalLevelMetricsPresentation
    private let truePeak: TruePeakPresentation
    private let loudness: LoudnessPresentation
    private let programmeBandwidth: SignificantBandwidthPresentation
    @State private var model: ReportExportModel

    public init(
        report: InspectionReport,
        signalLevelMetrics: SignalLevelMetricsPresentation,
        truePeak: TruePeakPresentation,
        loudness: LoudnessPresentation,
        programmeBandwidth: SignificantBandwidthPresentation,
        export: @escaping ReportExportAction
    ) {
        self.report = report
        self.signalLevelMetrics = signalLevelMetrics
        self.truePeak = truePeak
        self.loudness = loudness
        self.programmeBandwidth = programmeBandwidth
        _model = State(initialValue: ReportExportModel(action: export))
    }

    public func body(content: Content) -> some View {
        content.toolbar {
            ToolbarItem(placement: .primaryAction) { action }
        }
    }

    /// The transient phase sits beside the action rather than occupying a permanent row of any section —
    /// the arrangement the report page already used, kept exactly as it was.
    private var action: some View {
        HStack(spacing: 8) {
            switch model.phase {
            case .idle:
                EmptyView()
            case .exporting:
                Text("Exporting…").font(.callout).foregroundStyle(.secondary)
            case .succeeded:
                Text("Exported").font(.callout).foregroundStyle(.secondary)
            case let .failed(message):
                Text(message).font(.callout).foregroundStyle(.red)
            }

            Button("Export JSON…") {
                Task {
                    await model.export(
                        report,
                        measurements: ExportableMeasurements.measurements(
                            signalLevelMetrics: signalLevelMetrics,
                            truePeak: truePeak,
                            loudness: loudness,
                            programmeBandwidth: programmeBandwidth
                        )
                    )
                }
            }
            .disabled(model.phase == .exporting)
        }
    }
}

public extension View {
    /// Attaches the report's export action to the window, for as long as this surface is on screen.
    ///
    /// **Applied once, to the surface that exists exactly when a report does** — never per section, so
    /// the control neither multiplies with the sections nor disappears with any of them.
    func reportExportToolbar(
        report: InspectionReport,
        signalLevelMetrics: SignalLevelMetricsPresentation,
        truePeak: TruePeakPresentation,
        loudness: LoudnessPresentation,
        programmeBandwidth: SignificantBandwidthPresentation,
        export: @escaping ReportExportAction
    ) -> some View {
        modifier(ReportExportToolbar(
            report: report,
            signalLevelMetrics: signalLevelMetrics,
            truePeak: truePeak,
            loudness: loudness,
            programmeBandwidth: programmeBandwidth,
            export: export
        ))
    }
}
