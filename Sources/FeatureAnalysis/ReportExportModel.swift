import AudioInspectorDomain
import Observation

/// The **only** state the presentation owns: the transient status of an export of the report it was
/// given. It deliberately does **not** hold an `InspectionReport?` — the report is provided to the
/// view as non-optional input, and its global lifecycle belongs to a later slice (group 6). The
/// export work itself is an injected `ReportExportAction`; this model just sequences it and maps the
/// outcome to a presentable phase.
@MainActor
@Observable
final class ReportExportModel {
    enum Phase: Equatable, Sendable {
        case idle
        case exporting
        case succeeded
        /// A presentable, non-technical message (never a path or a raw framework error).
        case failed(message: String)
    }

    private(set) var phase: Phase = .idle
    private let action: ReportExportAction

    init(action: @escaping ReportExportAction) {
        self.action = action
    }

    /// Runs one export of `report`, plus whatever signal level metrics are currently available
    /// (`nil` when there is nothing to report). Re-entrancy is prevented: while `exporting`, further
    /// calls are ignored, so the action runs at most once per in-flight operation. Cancellation
    /// returns to `idle`; failures become a presentable message.
    func export(_ report: InspectionReport, signalLevelMetrics: SignalLevelMetrics?) async {
        guard phase != .exporting else { return }
        phase = .exporting
        switch await action(report, signalLevelMetrics) {
        case .succeeded:
            phase = .succeeded
        case .cancelled:
            phase = .idle
        case .encodingFailed:
            phase = .failed(message: "The report could not be encoded.")
        case .writeFailed:
            phase = .failed(message: "The file could not be written.")
        }
    }
}
