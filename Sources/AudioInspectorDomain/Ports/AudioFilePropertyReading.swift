/// Reads basic, metadata-level technical properties of a file — **no DSP**.
///
/// This is a domain **port**: the implementation lives in infrastructure (`AudioInspectorMedia`,
/// later), using AVFoundation/AudioToolbox and mapping platform metadata to the domain's own value
/// types, so those frameworks never leak inward.
///
/// Responsibility is narrow — it only *reads*. Per-property issues are encoded as `Property` cases
/// (`unavailable`/`unsupported`/`uncertain`/`failed`); a **global** failure (the file cannot be
/// opened or read at all) is signalled by a typed `throws(InspectionError)`. Deriving warnings and
/// the global `InspectionStatus`, and assembling the `InspectionReport`, is the future use case's
/// job — not this port's.
public protocol AudioFilePropertyReading: Sendable {
    func readProperties(of file: AudioFileReference) async throws(InspectionError) -> TechnicalProperties
}
