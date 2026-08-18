import AudioInspectorDomain

/// The outcome of an export attempt, expressed **outside Domain** and free of Foundation/AppKit
/// error types. The Feature only needs to distinguish these four cases to drive its transient UI
/// state; it never sees a `URL`, an `NSError`, or a raw filesystem message. The concrete work
/// (encoding, destination selection, writing) lives in `AudioInspectorApp`, which produces one of
/// these values.
public enum ExportOutcome: Sendable, Equatable {
    /// The report was encoded and written to the user-chosen destination.
    case succeeded
    /// The user dismissed the destination picker — **not** an error.
    case cancelled
    /// The report could not be encoded to JSON.
    case encodingFailed
    /// A destination was chosen but the bytes could not be written.
    case writeFailed
}

/// The export action the Feature receives as an injected dependency from the composition root.
///
/// It is `@MainActor` (it drives a native picker) and `async` (it awaits the user's destination
/// choice and the write). The Feature calls it with the already-available report and whatever
/// measurements are currently shown (each `nil` when there is nothing to report — the Feature collapses
/// loading/absent/failed itself before calling), and reacts to the returned `ExportOutcome`. It knows
/// nothing about how the destination is chosen, written, or how a measurement becomes wire bytes.
///
/// **The third measurement arrived, and the note on `ReportExporting` stands.** Three positional
/// optionals is past the shape's comfortable width, and a container is the answer — but introducing one
/// touches every call site of the export chain, and doing it while wiring a new measurement would hide
/// one change inside another. It is **recorded debt**, on the same reasoning `SourceInspectionOutcome`
/// applied to its fifth payload, and it belongs to whoever adds the fourth.
public typealias ReportExportAction = @MainActor (
    InspectionReport, SignalLevelMetrics?, TruePeakMeasurement?, LoudnessMeasurement?
) async -> ExportOutcome
