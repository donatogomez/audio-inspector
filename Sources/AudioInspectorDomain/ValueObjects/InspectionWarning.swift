/// A stable, machine-processable warning code. The `rawValue` is the identity; the message is not.
/// New codes are added as static members (grows additively). Not free-form at call sites.
public struct WarningCode: RawRepresentable, Sendable, Equatable, Hashable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

public extension WarningCode {
    static let metadataSizeUnavailable = WarningCode(rawValue: "metadata_size_unavailable")
    static let metadataModifiedAtUnavailable = WarningCode(rawValue: "metadata_modified_at_unavailable")
    static let propertyUnavailable = WarningCode(rawValue: "property_unavailable")
    static let propertyUnsupported = WarningCode(rawValue: "property_unsupported")
    static let propertyUncertain = WarningCode(rawValue: "property_uncertain")
    static let propertyExtractionFailed = WarningCode(rawValue: "property_extraction_failed")
}

/// The kind of non-`available` situation a warning describes. It intentionally excludes `available`
/// (a warning is never raised for a cleanly available property), so a contradictory warning is
/// unrepresentable.
public enum WarningKind: Sendable, Equatable {
    case unavailable
    case unsupported
    case uncertain
    case failed
}

/// A typed warning about a property or piece of file metadata that was not cleanly available.
public struct InspectionWarning: Sendable, Equatable {
    /// Stable code for automated processing.
    public let code: WarningCode
    /// The property/metadata key this concerns, or `nil` if general.
    public let field: String?
    /// Which non-`available` situation this describes.
    public let kind: WarningKind
    /// Human-facing description (not part of the code's identity).
    public let message: String

    public init(code: WarningCode, field: String?, kind: WarningKind, message: String) {
        self.code = code
        self.field = field
        self.kind = kind
        self.message = message
    }
}
