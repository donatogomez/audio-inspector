import AudioInspectorDomain
import Observation

/// Owns the import flow's state: pick a file, run the inspection, hold the resulting report. The work
/// itself is an injected `SourceInspectionAction`, so this model never learns about panels, `URL`s,
/// the sandbox, or the reader — it only sequences the operation and maps its outcome to a state.
///
/// A **global** inspection failure is not a flow error: it arrives as a report whose status is
/// `.failed` and is presented as a report. `failed` here means only that no inspection could be
/// attempted at all.
@MainActor
@Observable
public final class ImportFlowModel {
    public enum State: Equatable, Sendable {
        case idle
        case working
        case report(InspectionReport)
        /// A presentable, non-technical message (never a path or a raw framework error).
        case failed(message: String)
    }

    public private(set) var state: State = .idle
    private let action: SourceInspectionAction

    public init(action: @escaping SourceInspectionAction) {
        self.action = action
    }

    /// Runs one selection-and-inspection. Re-entrancy is prevented: while `working`, further calls are
    /// ignored, so at most one inspection is ever in flight and no stale result can arrive. Cancelling
    /// restores the **previous** state (an earlier report is kept) and shows no error.
    public func selectAndInspect() async {
        guard state != .working else { return }
        let previous = state
        state = .working
        switch await action() {
        case let .inspected(report):
            state = .report(report)
        case .cancelled:
            state = previous // neutral: back to exactly where the user was
        case .preparationFailed:
            state = .failed(message: "That file could not be opened for inspection.")
        }
    }
}
