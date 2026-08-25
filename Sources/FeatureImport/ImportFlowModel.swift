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

    /// What is known about a comparison against a **second** file right now.
    ///
    /// **Beside `state`, never inside it.** The primary inspection is what `state` means, and a
    /// comparison is a second thing the user asked for on top of it — folding it into
    /// `InspectionPresentation` would make the second file part of the first file's presentation, which
    /// it is not.
    ///
    /// It wraps the outcome and nothing more. **The field-by-field semantics live only in
    /// `FileComparison`**: there is no parallel notion of difference here, no flag, no list of
    /// differing fields, no count and no presentation type standing in for one.
    ///
    /// A second file whose inspection **failed globally** is not a failure of the comparison. Its report
    /// exists with a `.failed` status and all-unavailable properties, so a comparison is built as
    /// normal and every field reports that nothing was compared. `failed` here means only what it means
    /// for `state`: no inspection of that file could be attempted at all.
    public enum ComparisonState: Equatable, Sendable {
        /// No comparison has been asked for.
        case none
        /// A second file is being chosen or inspected.
        case loading
        /// The comparison of the report on screen against the second file's report, and — once both
        /// files have settled their measurements — the comparison of those too.
        ///
        /// **The second is optional and the first is not**, which is the whole shape of this state. A
        /// technical comparison is complete the moment the second report exists and must not wait for a
        /// PCM read; a measurement comparison cannot exist until *both* sides have finished measuring.
        /// One case with an optional rather than two states, because they are one answer about one pair
        /// of files: two states could drift apart, and a stale guard would have to protect both.
        case ready(FileComparison, MeasurementComparison?)
        /// The second file could not be opened for inspection at all.
        case failed(message: String)
    }

    public private(set) var state: State = .idle

    /// The comparison, if one has been asked for. **Never written by the primary inspection's own
    /// updates**, and it never writes `state` in return.
    public private(set) var comparison: ComparisonState = .none

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

    /// The comparison's own in-flight task and its own operation number, **disjoint from the primary
    /// inspection's**.
    ///
    /// This separation is the whole of group 4. Until now one counter meant one inspection at a time and
    /// every new selection superseded the last; a comparison needs a second inspection that does **not**
    /// supersede the first. Two counters, two tasks, and neither path touches the other's: starting,
    /// finishing, cancelling or replacing a comparison cannot invalidate an update belonging to the
    /// primary inspection, and a late waveform or spectrogram still lands.
    private var comparisonTask: Task<Void, Never>?
    private var currentComparisonOperation = 0

    /// The compared file's settled measurements, retained so the measurement comparison can be rebuilt
    /// if the **primary** file finishes measuring afterwards — which it can, because the compare action
    /// is offered the moment a report is on screen and the two files then read concurrently.
    ///
    /// It belongs to whichever comparison operation is current: cleared when one starts, when one is
    /// dismissed, and when a new primary inspection ends the comparison. Nothing reads it without also
    /// reading `comparison`, so a bundle can never be paired with another operation's technical
    /// comparison.
    private var comparedMeasurements: ReportMeasurements?

    /// The compared file's settled pictures, retained for exactly as long as, and by exactly the same
    /// events as, `comparedMeasurements` above.
    ///
    /// **The read that produced them already happened.** Its envelope and its spectral model were
    /// computed by the same single shared pass that produced the measurements beside them, and until now
    /// they were dropped one line later because `ReportMeasurements` has no field either could occupy.
    /// Keeping them costs no read, no decode and no transform (ADR-0025 §1, §11).
    ///
    /// **Nothing in production reads it yet.** Pairing it with the primary file's own pictures,
    /// publishing that pair, and proving it can never mix two operations are group 3's; this group only
    /// stops the loss. The getter is internal rather than private for one reason — a value nothing reads
    /// cannot be observed indirectly, and retention that is not observed is retention that is asserted.
    /// The setter stays private: nothing outside this model decides what is retained.
    private(set) var comparedVisuals: FileVisuals?

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

    /// Compares the report on screen against a second file, chosen through the **same** path a first
    /// file is — the *Compare with another file…* action.
    ///
    /// Only meaningful with a report on screen, so it does nothing otherwise: there is nothing to
    /// compare against while the flow is idle, working, or showing a failure.
    public func selectAndCompare() async {
        await compare(using: action)
    }

    /// Compares against a second file the composition root has already accepted. The action is opaque
    /// and already bound to that source, exactly as `inspectDroppedSource(using:)` is.
    ///
    /// **Nothing here touches the primary inspection.** It reads the report on screen once, at the
    /// start, and writes only `comparison` from then on. The primary operation's number is not bumped
    /// and its task is not cancelled, so a waveform or spectrogram still being produced for the first
    /// file arrives and lands as it would have.
    ///
    /// **The comparison is built the moment the second report exists**, before either of that file's
    /// visualisations. Those are produced — the pipeline is the same one a first file runs, unchanged —
    /// and this ignores them: they cannot change a technical comparison, and waiting for them would
    /// hold back a result that is already complete.
    public func compare(using action: @escaping SourceInspectionAction) async {
        guard case let .report(presentation) = state else { return }
        let primary = presentation.report

        // Supersede only a previous *comparison*. The primary inspection is untouched.
        comparisonTask?.cancel()
        currentComparisonOperation += 1
        let operation = currentComparisonOperation

        let previous = comparison
        let previousMeasurements = comparedMeasurements
        let previousVisuals = comparedVisuals
        comparedMeasurements = nil
        comparedVisuals = nil
        comparison = .loading

        let task = Task { [weak self] in
            let outcome = await action { update in
                guard let self, operation == self.currentComparisonOperation else { return } // superseded
                // **Only the report takes part, and that has not changed.** The technical comparison is
                // complete the moment it exists and is published immediately; the measurement comparison
                // is deliberately *not* assembled from these progressive updates, because it must be
                // atomic — see `settle`.
                guard case let .report(report) = update else { return }
                self.comparison = .ready(FileComparison(first: primary, second: report), nil)
            }
            guard let self, operation == self.currentComparisonOperation else { return } // superseded
            self.settle(
                outcome, against: primary,
                restoringOnCancellation: previous,
                andMeasurements: previousMeasurements, andVisuals: previousVisuals
            )
        }
        comparisonTask = task
        await task.value
    }

    /// Dismisses the comparison. The report on screen is untouched, and nothing about it is walked back.
    public func dismissComparison() {
        comparisonTask?.cancel()
        currentComparisonOperation += 1 // so a result already in flight cannot land afterwards
        comparedMeasurements = nil
        comparedVisuals = nil
        comparison = .none
    }

    /// Settles a comparison once its operation has finished. Only ever called for the current one.
    private func settle(
        _ outcome: SourceInspectionOutcome,
        against primary: InspectionReport,
        restoringOnCancellation previous: ComparisonState,
        andMeasurements previousMeasurements: ReportMeasurements?,
        andVisuals previousVisuals: FileVisuals?
    ) {
        switch outcome {
        case let .inspected(report, analyses):
            // The technical half is normally already set from the update; this is the backstop for a
            // caller that reported nothing, so a comparison cannot stay stuck on `loading`.
            //
            // **The measurements are taken here and nowhere else.** They are assembled from the settled
            // outcome rather than from the progressive updates, so the four are published together or
            // not at all: a comparison holding this file's loudness beside another file's true peak is
            // not a thing this flow can produce.
            //
            // **The visualisations are taken here too, and from the same bundle.** They stopped being
            // discarded when a container that can hold them arrived: `FileVisuals` carries what became
            // of each drawing together with the stream description that read produced, so an artefact
            // can never be paired with another read's axis. Cancellation is not a settled answer, so a
            // cancelled inspection leaves this `nil` rather than an absence — the file is not blamed for
            // an operation the user replaced.
            comparedMeasurements = analyses.settledMeasurements
            comparedVisuals = analyses.settledVisuals
            comparison = .ready(FileComparison(first: primary, second: report), nil)
            publishMeasurementComparisonIfBothSettled()
        case .cancelled:
            // Neutral: dismissing the picker is not a statement about either file. The comparison that
            // was on screen returns **with** the bundle it was built from, so a later settling of the
            // primary file refreshes that one rather than a superseded file's.
            comparison = previous
            comparedMeasurements = previousMeasurements
            comparedVisuals = previousVisuals
        case .preparationFailed:
            comparison = .failed(message: "That file could not be opened for comparison.")
        }
    }

    /// Publishes the measurement comparison **only when both files have finished measuring**.
    ///
    /// Called from two places, and it has to be: the compared file can settle first, and so can the
    /// primary one. Whichever finishes last is the one that publishes, and until then the technical
    /// comparison stands alone rather than being held back for it.
    ///
    /// **A primary file still measuring is not a primary file with no measurements.** Publishing then
    /// would report its loudness as missing when it is a second away — a statement about this run
    /// dressed up as a fact about the file — which is why `settledMeasurements` returns `nil` for
    /// *unfinished* and this waits for it.
    private func publishMeasurementComparisonIfBothSettled() {
        guard case let .ready(technical, _) = comparison,
              let second = comparedMeasurements,
              case let .report(presentation) = state,
              let first = presentation.settledMeasurements
        else { return }
        comparison = .ready(technical, MeasurementComparison(first: first, second: second))
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

        // **A new primary inspection ends any comparison**, and this direction of the relationship is
        // the only one that exists. A comparison is *against the report on screen*; once that report is
        // being replaced, what the comparison describes is no longer there, and keeping it would leave a
        // result on screen whose left-hand side the user can no longer see.
        comparisonTask?.cancel()
        currentComparisonOperation += 1
        comparedMeasurements = nil
        comparedVisuals = nil
        comparison = .none

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
        case let .signalLevelMetrics(outcome):
            guard case var .report(presentation) = state else { return }
            guard let settled = SignalLevelMetricsState(outcome) else { return }
            presentation.signalLevelMetrics = settled
            state = .report(presentation)
            publishMeasurementComparisonIfBothSettled()
        case let .truePeak(outcome):
            guard case var .report(presentation) = state else { return }
            guard let settled = TruePeakState(outcome) else { return }
            presentation.truePeak = settled
            state = .report(presentation)
            publishMeasurementComparisonIfBothSettled()
        case let .significantBandwidth(outcome):
            guard case var .report(presentation) = state else { return }
            guard let settled = SignificantBandwidthState(outcome) else { return }
            presentation.significantBandwidth = settled
            state = .report(presentation)
            publishMeasurementComparisonIfBothSettled()
        case let .loudness(outcome):
            guard case var .report(presentation) = state else { return }
            guard let settled = LoudnessState(outcome) else { return }
            presentation.loudness = settled
            state = .report(presentation)
            publishMeasurementComparisonIfBothSettled()
        }
    }

    /// Settles the state once an operation has finished. Only ever called for the current operation.
    private func apply(_ outcome: SourceInspectionOutcome, restoringOnCancellation previous: State) {
        switch outcome {
        case let .inspected(report, analyses):
            // None of the three withholds or replaces the report, whatever became of it.
            //
            // The progressive handler has normally settled all three already; this is the backstop for a
            // caller that reported nothing, so the state cannot stay stuck on `loading`. `?? .unavailable`
            // applies only to a cancelled outcome that was not dropped as stale — a fallback, not a
            // claim that the file offered nothing.
            let presentation = InspectionPresentation(
                report: report,
                waveform: WaveformState(analyses.waveform) ?? .unavailable,
                spectrogram: SpectrogramState(analyses.spectrogram) ?? .unavailable,
                signalLevelMetrics: SignalLevelMetricsState(analyses.signalLevelMetrics) ?? .unavailable,
                truePeak: TruePeakState(analyses.truePeak) ?? .unavailable,
                loudness: LoudnessState(analyses.loudness) ?? .unavailable,
                significantBandwidth: SignificantBandwidthState(analyses.significantBandwidth) ?? .unavailable
            )
            // A settled visualisation already shown must not be walked back to a fallback.
            if case let .report(current) = state, current.report == report {
                state = .report(InspectionPresentation(
                    report: report,
                    waveform: current.waveform == .loading ? presentation.waveform : current.waveform,
                    spectrogram: current.spectrogram == .loading ? presentation.spectrogram : current.spectrogram,
                    signalLevelMetrics: current.signalLevelMetrics == .loading
                        ? presentation.signalLevelMetrics : current.signalLevelMetrics,
                    truePeak: current.truePeak == .loading ? presentation.truePeak : current.truePeak,
                    loudness: current.loudness == .loading ? presentation.loudness : current.loudness,
                    significantBandwidth: current.significantBandwidth == .loading
                        ? presentation.significantBandwidth : current.significantBandwidth
                ))
            } else {
                state = .report(presentation)
            }
            // The backstop fills whatever was still `loading`, so this is the last moment the primary
            // file can become settled — and therefore the last chance to publish the pair.
            publishMeasurementComparisonIfBothSettled()
        case .cancelled:
            state = previous // neutral: back to exactly where the user was
        case .preparationFailed:
            state = .failed(message: "That file could not be opened for inspection.")
        }
    }
}
