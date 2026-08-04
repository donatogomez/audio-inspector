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

    /// Why the last drop was refused, if any. **Orthogonal to `state`:** it takes part in no
    /// transition, so a refusal never discards a report already on screen. Any accepted operation —
    /// from the panel or from a drop — clears it, and nothing else does: there is no timer and no
    /// automatic dismissal, so the notice survives exactly until the user's next valid interaction.
    public private(set) var dropRejection: DropRejection?

    private let action: SourceInspectionAction

    public init(action: @escaping SourceInspectionAction) {
        self.action = action
    }

    /// Runs one selection-and-inspection through the panel.
    public func selectAndInspect() async {
        await inspect(using: action)
    }

    /// Runs an inspection of a source the composition root has already accepted. The action is opaque
    /// and already bound to that source, so this model still never learns about panels, `URL`s, the
    /// sandbox or the reader.
    public func inspectDroppedSource(using action: @escaping SourceInspectionAction) async {
        await inspect(using: action)
    }

    /// Records that a drop could not be turned into an inspection. `state` is deliberately untouched.
    public func reject(_ rejection: DropRejection) {
        dropRejection = rejection
    }

    public func clearDropRejection() {
        dropRejection = nil
    }

    /// The single implementation of the flow's transitions, shared by both entry points so they cannot
    /// drift apart. Re-entrancy is prevented: while `working`, further calls are ignored, so at most
    /// one inspection is ever in flight and no stale result can arrive. Cancelling restores the
    /// **previous** state (an earlier report is kept) and shows no error.
    private func inspect(using action: SourceInspectionAction) async {
        guard state != .working else { return }
        dropRejection = nil // an accepted operation supersedes any pending refusal
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
