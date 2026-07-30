/// Coordinates a single basic (metadata-only, **no DSP**) inspection of an already-selected file.
///
/// It is a thin orchestrator with no state of its own: it asks the injected `AudioFilePropertyReading`
/// port for the technical properties, derives typed warnings from any non-`available` property,
/// computes the global `InspectionStatus`, and assembles the `InspectionReport`. It knows nothing
/// about `URL`s, security-scoped access, AVFoundation, AppKit/SwiftUI, JSON, export, persistence, or
/// DSP — those live in other layers.
///
/// The port's typed `throws(InspectionError)` (a **global** failure — the file could not be opened or
/// read at all) is caught here and turned into a `.failed` report, so callers never have to
/// reconstruct a failed report themselves and never see a thrown error from `execute`.
public struct InspectAudioFileUseCase: Sendable {
    private let reader: any AudioFilePropertyReading

    /// - Parameter reader: the only dependency — the port that reads technical properties.
    public init(reader: any AudioFilePropertyReading) {
        self.reader = reader
    }

    /// Inspects `file` and always returns a report (never throws): a global read failure becomes a
    /// `.failed` status carrying the original `InspectionError`, with an empty (all-`unavailable`)
    /// `TechnicalProperties`.
    public func execute(file: AudioFileReference) async -> InspectionReport {
        do {
            let properties = try await reader.readProperties(of: file)
            let warnings = Self.warnings(for: properties)
            let status: InspectionStatus = warnings.isEmpty ? .completed : .partial(message: Self.partialMessage)
            return InspectionReport(file: file, properties: properties, warnings: warnings, status: status)
        } catch {
            // Typed throw: `error` is an `InspectionError`. The properties are represented explicitly
            // as the default all-`unavailable` set — nothing is fabricated; the reason lives in the
            // failed status. The contract does not require per-property warnings on a global failure.
            return InspectionReport(
                file: file,
                properties: TechnicalProperties(),
                warnings: [],
                status: .failed(error)
            )
        }
    }
}

// MARK: - Warning & status policy (centralized Property → warning translation)

private extension InspectAudioFileUseCase {
    /// Deterministic message for a `partial` status; the per-property detail lives in `warnings`.
    static let partialMessage = "Some properties could not be read cleanly; see warnings for details."

    /// Stable field identifiers used as `InspectionWarning.field`. The raw values are the identity and
    /// must not drift; the declaration order fixes the deterministic warning order.
    enum Field: String {
        case container
        case duration
        case sampleRate
        case channelCount
        case bitDepth
        case codec
        case declaredBitrate
        case estimatedBitrate
    }

    /// One warning per problematic property, in a fixed field order. An all-`available` set yields `[]`.
    /// Each field contributes at most one warning, so there are never duplicates.
    static func warnings(for p: TechnicalProperties) -> [InspectionWarning] {
        [
            warning(for: p.container, field: .container),
            warning(for: p.duration, field: .duration),
            warning(for: p.sampleRate, field: .sampleRate),
            warning(for: p.channelCount, field: .channelCount),
            warning(for: p.bitDepth, field: .bitDepth),
            warning(for: p.codec, field: .codec),
            warning(for: p.declaredBitrate, field: .declaredBitrate),
            warning(for: p.estimatedBitrate, field: .estimatedBitrate),
        ].compactMap { $0 }
    }

    /// The single place that maps a `Property` state to a warning. `available` produces no warning;
    /// every other case maps to its stable `WarningCode`/`WarningKind` and a deterministic message.
    /// Generic over `Value` because only the *case* matters here, never the carried value.
    static func warning<Value>(for property: Property<Value>, field: Field) -> InspectionWarning? {
        let (code, kind): (WarningCode, WarningKind)
        switch property {
        case .available:
            return nil
        case .unavailable:
            (code, kind) = (.propertyUnavailable, .unavailable)
        case .unsupported:
            (code, kind) = (.propertyUnsupported, .unsupported)
        case .uncertain:
            (code, kind) = (.propertyUncertain, .uncertain)
        case .failed:
            (code, kind) = (.propertyExtractionFailed, .failed)
        }
        return InspectionWarning(code: code, field: field.rawValue, kind: kind, message: message(kind, field))
    }

    /// Deterministic, centralized human-facing message per `(kind, field)`.
    static func message(_ kind: WarningKind, _ field: Field) -> String {
        switch kind {
        case .unavailable:
            "Property '\(field.rawValue)' is not available for this file."
        case .unsupported:
            "Property '\(field.rawValue)' is not supported by this file's format."
        case .uncertain:
            "Property '\(field.rawValue)' was read but is not reliable."
        case .failed:
            "Property '\(field.rawValue)' could not be extracted."
        }
    }
}
