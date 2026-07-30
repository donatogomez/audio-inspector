/// A stable, machine-processable error code. The `rawValue` is the error's **identity**; the
/// descriptive message that accompanies it (see `InspectionError`) is not. New codes are added as
/// static members (the set grows additively). Not free-form at call sites — use the named members.
public struct InspectionErrorCode: RawRepresentable, Sendable, Equatable, Hashable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

public extension InspectionErrorCode {
    /// Reading a specific property errored.
    static let propertyReadError = InspectionErrorCode(rawValue: "property_read_error")
    /// The file could not be opened for inspection.
    static let fileOpenFailed = InspectionErrorCode(rawValue: "file_open_failed")
    /// The file could be opened but not read.
    static let fileUnreadable = InspectionErrorCode(rawValue: "file_unreadable")
    /// Access to the file was denied (e.g. sandbox).
    static let fileAccessDenied = InspectionErrorCode(rawValue: "file_access_denied")
}

/// A domain error: a stable `code` (the identity, for automated processing) plus a descriptive
/// `message` (human-facing, **not** part of the error's semantic identity).
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
