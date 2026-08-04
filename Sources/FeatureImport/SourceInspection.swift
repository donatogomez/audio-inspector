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
    /// A file was inspected; the report carries the outcome, including a global failure.
    case inspected(InspectionReport)
    /// The selection could not be turned into an inspectable file at all.
    case preparationFailed
}

/// The action the import feature receives as an injected dependency from the composition root.
///
/// `@MainActor` (it drives a native panel) and `async` (it awaits the user's choice and the
/// inspection). The Feature calls it and reacts to the returned outcome; it never learns how the file
/// is chosen, accessed, or read.
public typealias SourceInspectionAction = @MainActor () async -> SourceInspectionOutcome
