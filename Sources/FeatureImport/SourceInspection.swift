import AudioInspectorDomain

/// The outcome of one "pick a file and inspect it" attempt, expressed **outside Domain** and free of
/// `URL`, AppKit, and filesystem types. The Feature only needs these three cases to drive its state;
/// the panel, the security-scoped access, the metadata read, and the reader all live in
/// `AudioInspectorApp`, which produces one of these values.
///
/// A **global** inspection failure is *not* one of these cases: it arrives as an `InspectionReport`
/// whose `status` is `.failed`, because the domain already models it that way. `preparationFailed`
/// covers only the failures that happen *before* an inspection can be attempted at all.
public enum SourceInspectionOutcome: Sendable, Equatable {
    /// The user dismissed the picker — **not** an error.
    case cancelled
    /// A file was inspected; the report carries the outcome, including a global failure. The waveform
    /// travels **beside** it, and whatever became of it never changes the report.
    case inspected(InspectionReport, waveform: WaveformOutcome)
    /// The selection could not be turned into an inspectable file at all.
    case preparationFailed
}

/// Receives the inspection's report the moment it exists, before the waveform is generated.
///
/// It exists so the report is not held hostage by an optional extra: reading samples takes longer than
/// reading metadata, and the report is complete without it. Called at most once per operation, on the
/// main actor.
public typealias InspectionReportHandler = @MainActor (InspectionReport) -> Void

/// The action the import feature receives as an injected dependency from the composition root.
///
/// `@MainActor` (it drives a native panel) and `async` (it awaits the user's choice, the inspection and
/// then the waveform). It hands the report back through the given handler as soon as the inspection is
/// done, and returns the complete outcome when the waveform has settled too. The Feature never learns
/// how the file is chosen, accessed, or read.
public typealias SourceInspectionAction = @MainActor (InspectionReportHandler) async -> SourceInspectionOutcome
