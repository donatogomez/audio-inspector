/// The domain result of inspecting one file.
///
/// It groups **only** inspection-domain data: the file reference, the technical properties, the
/// warnings, and the global status. It deliberately does **not** carry the JSON export envelope
/// (`schemaVersion`, `generatedAt`, `generator`), a JSON DTO, `JSONEncoder`, a `URL`, or any
/// AVFoundation/SwiftUI/AppKit type — those belong to the export/UI layers (ADR-0009).
public struct InspectionReport: Sendable, Equatable {
    public let file: AudioFileReference
    public let properties: TechnicalProperties
    public let warnings: [InspectionWarning]
    public let status: InspectionStatus

    public init(
        file: AudioFileReference,
        properties: TechnicalProperties,
        warnings: [InspectionWarning],
        status: InspectionStatus
    ) {
        self.file = file
        self.properties = properties
        self.warnings = warnings
        self.status = status
    }
}
