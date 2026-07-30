/// A stable, machine-processable code for a **single property's** extraction failure. Distinct from
/// `InspectionErrorCode` (which is for global inspection failures): a property failure is never a
/// "file could not be opened", and a global failure is never a "property read error". The `rawValue`
/// is the identity; the accompanying message is not. Grows additively via static members.
public struct PropertyFailureCode: RawRepresentable, Sendable, Equatable, Hashable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

public extension PropertyFailureCode {
    /// Reading this specific property errored.
    static let propertyReadError = PropertyFailureCode(rawValue: "property_read_error")
}

/// A per-property extraction failure carried by `Property.failed`.
///
/// This is deliberately **not** the same type as `InspectionError` (the global inspection error) and
/// is **not** a Swift `Error` — it is a value describing why one property could not be read, not a
/// thrown error. It carries a stable `code` (identity, for automated processing) and a descriptive
/// `message` (not part of the identity).
public struct PropertyFailure: Sendable, Equatable {
    public let code: PropertyFailureCode
    public let message: String

    public init(code: PropertyFailureCode, message: String) {
        self.code = code
        self.message = message
    }
}
