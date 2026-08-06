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
            let outcome = await action { update in
                guard let self, operation == self.currentOperation else { return } // superseded: drop it
                self.apply(update)
            }
            guard let self, operation == self.currentOperation else { return } // superseded: drop it
            self.apply(outcome, restoringOnCancellation: previous)
        }
        activeTask = task
        await task.value
    }

    /// Applies one part of an inspection as it settles. Only ever called for the current operation —
    /// a result belonging to a superseded one is dropped before it reaches here, which is what keeps a
    /// slow generation from overwriting the file the user is now looking at.
    ///
    /// Each case touches **only** its own part: whichever visualisation finishes first is shown first,
    /// and neither waits for nor depends on the other.
    private func apply(_ update: InspectionUpdate) {
        switch update {
        case let .report(report):
            // The report is shown the moment it exists, without waiting for any samples.
            state = .report(InspectionPresentation(report: report, waveform: .loading, spectrogram: .loading))
        case let .waveform(outcome):
            guard case var .report(presentation) = state else { return }
            // `nil` means cancelled, which cannot normally arrive here: cancelling bumps the operation
            // number first, so such a result is stale and was already dropped. Leaving the state
            // untouched keeps a cancelled generation from being shown as a limitation of the file.
            guard let settled = WaveformState(outcome) else { return }
            presentation.waveform = settled
            state = .report(presentation)
        case let .spectrogram(outcome):
            guard case var .report(presentation) = state else { return }
            guard let settled = SpectrogramState(outcome) else { return }
            presentation.spectrogram = settled
            state = .report(presentation)
        }
    }

    /// Settles the state once an operation has finished. Only ever called for the current operation.
    private func apply(_ outcome: SourceInspectionOutcome, restoringOnCancellation previous: State) {
        switch outcome {
        case let .inspected(report, waveform, spectrogram):
            // Neither visualisation withholds or replaces the report, whatever became of it.
            //
            // The progressive handler has normally settled both already; this is the backstop for a
            // caller that reported nothing, so the state cannot stay stuck on `loading`. `?? .unavailable`
            // applies only to a cancelled outcome that was not dropped as stale — a fallback, not a
            // claim that the file offered nothing.
            let presentation = InspectionPresentation(
                report: report,
                waveform: WaveformState(waveform) ?? .unavailable,
                spectrogram: SpectrogramState(spectrogram) ?? .unavailable
            )
            // A settled visualisation already shown must not be walked back to a fallback.
            if case let .report(current) = state, current.report == report {
                state = .report(InspectionPresentation(
                    report: report,
                    waveform: current.waveform == .loading ? presentation.waveform : current.waveform,
                    spectrogram: current.spectrogram == .loading ? presentation.spectrogram : current.spectrogram
                ))
            } else {
                state = .report(presentation)
            }
        case .cancelled:
            state = previous // neutral: back to exactly where the user was
        case .preparationFailed:
            state = .failed(message: "That file could not be opened for inspection.")
        }
    }
}
