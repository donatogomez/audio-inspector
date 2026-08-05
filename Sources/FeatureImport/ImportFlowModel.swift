import AudioInspectorDomain
import Observation

/// Owns the import flow's state: pick a file, run the inspection, hold the resulting report, and then
/// hold whatever became of its waveform. The work itself is an injected `SourceInspectionAction`, so
/// this model never learns about panels, `URL`s, the sandbox, or the reader — it only sequences the
/// operation and maps its outcome to a state.
///
/// A **global** inspection failure is not a flow error: it arrives as a report whose status is
/// `.failed` and is presented as a report. `failed` here means only that no inspection could be
/// attempted at all. A waveform that is absent, that failed, or that is still loading is likewise
/// never a flow error — the report stands on its own.
@MainActor
@Observable
public final class ImportFlowModel {
    public enum State: Equatable, Sendable {
        case idle
        case working
        /// A report, plus whatever is known about its waveform at this moment.
        case report(InspectionPresentation)
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

    /// The operation currently in flight, so a newer one can stop it. Only ever cancelled, never
    /// awaited from outside: nothing here waits on a task it is about to replace.
    private var activeTask: Task<Void, Never>?
    /// Identifies the current operation. A result arriving under an older number is stale and is
    /// dropped rather than allowed to overwrite a newer one.
    private var currentOperation = 0

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
    /// drift apart.
    ///
    /// **Re-entrancy follows the accepted specification.** While the *inspection* is running the state
    /// is `.working` and further calls are ignored: a drop in that window "does not start a second
    /// inspection, the running inspection is unaffected, and at most one inspection exists at any
    /// time". That window ends when the report arrives.
    ///
    /// Afterwards the state is `.report`, the inspection is over, and only the waveform is still being
    /// produced. A selection made then is accepted — the user is looking at a finished report and has
    /// asked for another file — so the pending generation is **cancelled** and its result discarded.
    /// Cancelling it is not an error and is never shown as one.
    private func inspect(using action: @escaping SourceInspectionAction) async {
        guard state != .working else { return }

        // Supersede whatever is still in flight — at this point that can only be a waveform.
        activeTask?.cancel()
        currentOperation += 1
        let operation = currentOperation

        dropRejection = nil // an accepted operation supersedes any pending refusal
        let previous = state
        state = .working

        let task = Task { [weak self] in
            let outcome = await action { report in
                // The report is shown the moment it exists, without waiting for the samples.
                guard let self, operation == self.currentOperation else { return }
                self.state = .report(InspectionPresentation(report: report, waveform: .loading))
            }
            guard let self, operation == self.currentOperation else { return } // superseded: drop it
            self.apply(outcome, restoringOnCancellation: previous)
        }
        activeTask = task
        await task.value
    }

    /// Settles the state once an operation has finished. Only ever called for the current operation.
    private func apply(_ outcome: SourceInspectionOutcome, restoringOnCancellation previous: State) {
        switch outcome {
        case let .inspected(report, waveform):
            // A waveform that failed or is absent never withholds or replaces the report.
            //
            // `WaveformState(_:)` is `nil` only for a cancelled generation, which this line cannot
            // normally see: cancelling always bumps the operation number first, so such a result is
            // stale and was already dropped above. The fallback exists so the state stays settled
            // rather than stuck on `loading` if that ever changes, and it is a fallback — not a claim
            // that the file offered nothing.
            let settled = WaveformState(waveform) ?? .unavailable
            state = .report(InspectionPresentation(report: report, waveform: settled))
        case .cancelled:
            state = previous // neutral: back to exactly where the user was
        case .preparationFailed:
            state = .failed(message: "That file could not be opened for inspection.")
        }
    }
}
