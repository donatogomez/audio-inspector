import AudioInspectorDomain
import Foundation

/// The export capability: turn a domain `InspectionReport` into `schemaVersion` 1 JSON `Data`.
///
/// It is deliberately narrow (ADR-0009): it takes a pure domain report and returns encoded bytes.
/// It **never** accepts or returns a `URL`, and it **never** writes to disk — choosing a destination
/// and persisting the bytes is a separate delivery concern (group 5). Encoding can fail (e.g. a
/// non-representable numeric value), so the operation is `throws`.
///
/// Lives in the export layer, not the domain: there is no domain use case that exports, so an export
/// protocol in `AudioInspectorDomain` would be a port with no domain consumer (ADR-0009). It depends
/// only on `AudioInspectorDomain`, so it can be extracted into its own target later untouched.
public protocol ReportExporting: Sendable {
    /// Encodes `report` into `schemaVersion` 1 JSON bytes. Throws on an encoding failure.
    func export(_ report: InspectionReport) throws -> Data
}

/// The identity of whatever produced an export — the envelope's `generator` object.
///
/// Injected into the exporter so it is **not** coupled to the real app bundle: tests supply a fixed
/// identity, and the composition root (group 5) supplies the app's real name/version.
public struct ReportGenerator: Sendable, Equatable {
    public let name: String
    public let version: String

    public init(name: String, version: String) {
        self.name = name
        self.version = version
    }
}
