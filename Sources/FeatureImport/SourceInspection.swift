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
    /// A file was inspected; the report carries the outcome, including a global failure. Both
    /// visualisations travel **beside** it, and whatever became of either never changes the report.
    case inspected(InspectionReport, waveform: WaveformOutcome, spectrogram: SpectrogramOutcome)
    /// The selection could not be turned into an inspectable file at all.
    case preparationFailed
}

/// One thing an inspection has finished, delivered the moment it is known.
///
/// A single channel rather than one handler per result, so adding a third visualisation later cannot
/// mean a third parameter threaded through every call site. Each case updates **only** its own part of
/// the presentation: a waveform that arrives first does not wait for the spectrogram, and neither
/// waits for the other to fail.
public enum InspectionUpdate: Sendable {
    /// The report, the moment it exists — before either visualisation has been produced.
    case report(InspectionReport)
    /// What became of the amplitude envelope.
    case waveform(WaveformOutcome)
    /// What became of the spectral model.
    case spectrogram(SpectrogramOutcome)
}

/// Receives each part of an inspection as it settles, on the main actor.
///
/// It exists so the report is not held hostage by optional extras: reading samples takes longer than
/// reading metadata, and the report is complete without either visualisation. `report` arrives at most
/// once per operation, and each visualisation at most once.
public typealias InspectionUpdateHandler = @MainActor (InspectionUpdate) -> Void

/// The action the import feature receives as an injected dependency from the composition root.
///
/// `@MainActor` (it drives a native panel) and `async` (it awaits the user's choice, the inspection and
/// then the visualisations). It reports each part through the given handler as soon as that part is
/// known, and returns the complete outcome once everything has settled. The Feature never learns how
/// the file is chosen, accessed, or read.
public typealias SourceInspectionAction = @MainActor (InspectionUpdateHandler) async -> SourceInspectionOutcome
