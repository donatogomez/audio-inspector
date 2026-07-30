/// A stable, machine-processable code for a **global inspection failure** (the whole file could not
/// be inspected). Distinct from `PropertyFailureCode` (a single property's failure). The `rawValue`
/// is the identity; the accompanying message is not. Grows additively via static members. Not
/// free-form at call sites — use the named members.
public struct InspectionErrorCode: RawRepresentable, Sendable, Equatable, Hashable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

public extension InspectionErrorCode {
    /// The file could not be opened for inspection.
    static let fileOpenFailed = InspectionErrorCode(rawValue: "file_open_failed")
    /// The file could be opened but not read.
    static let fileUnreadable = InspectionErrorCode(rawValue: "file_unreadable")
    /// Access to the file was denied (e.g. sandbox).
    static let fileAccessDenied = InspectionErrorCode(rawValue: "file_access_denied")
}

/// A **global** inspection error — the whole file could not be inspected (used by the reading port's
/// typed throw and by `InspectionStatus.failed`). It is **not** used for a single property's failure
/// (that is `PropertyFailure`). A stable `code` (identity, for automated processing) plus a
/// descriptive `message` (human-facing, **not** part of the error's semantic identity).
///
/// Conforms to the standard-library `Error` protocol so it can be used with typed throws
/// (`throws(InspectionError)`); this keeps the domain free of any framework dependency.
public struct InspectionError: Error, Sendable, Equatable {
    public let code: InspectionErrorCode
    public let message: String

    public init(code: InspectionErrorCode, message: String) {
        self.code = code
        self.message = message
    }
}
