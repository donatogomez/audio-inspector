import AudioInspectorDomain

/// What producing a waveform actually yielded, once it is over.
///
/// It has no "still working" case on purpose: this is the *result* of a generation, and a result that
/// has not happened yet is not a result. Waiting is a state of the flow, not of the outcome — see
/// `WaveformState`.
public enum WaveformOutcome: Sendable, Equatable {
    /// The file's amplitude envelope. An envelope with no buckets is a complete answer for a file
    /// with no frames, not an absence.
    case available(WaveformEnvelope)
    /// The file offered nothing to build an envelope from. Caused by the file, and not a failure.
    case unavailable
    /// Producing it failed. The message is human and neutral: it names no path and no framework.
    case failed(message: String)
    /// The operation was cancelled — by the user picking something else, never by the file. It says
    /// nothing about the file and must never be shown as a limitation of it.
    case cancelled
}

/// What the surface can say about a waveform right now.
///
/// The extra case over `WaveformOutcome` is `loading`, which exists only between the report arriving
/// and the generation finishing. `cancelled` is deliberately **absent**: a cancelled generation
/// belongs to an operation the user already replaced, so its result is discarded rather than shown.
public enum WaveformState: Sendable, Equatable {
    case loading
    case available(WaveformEnvelope)
    case unavailable
    case failed(message: String)

    /// The state an outcome settles into.
    ///
    /// Returns `nil` for `cancelled`, because there is nothing to show: the operation that produced
    /// it has been superseded, and rendering it as an absence would blame the file for the user's
    /// own action.
    public init?(_ outcome: WaveformOutcome) {
        switch outcome {
        case let .available(envelope): self = .available(envelope)
        case .unavailable: self = .unavailable
        case let .failed(message): self = .failed(message: message)
        case .cancelled: return nil
        }
    }
}

/// A report together with whatever is currently known about its waveform.
///
/// The two are **beside** each other, never nested: the waveform is not part of `InspectionReport`,
/// so the report's meaning, its warnings, its status and the `schemaVersion` 1 export are untouched by
/// anything here (ADR-0009). This type is not `Codable` and is never persisted.
///
/// It knows no `URL`, no AVFoundation type and no filesystem: the location stays in
/// `AudioInspectorApp` (ADR-0010).
public struct InspectionPresentation: Sendable, Equatable {
    /// The inspection's own result, complete on its own. A waveform that is loading, absent or failed
    /// never withholds it.
    public let report: InspectionReport
    public var waveform: WaveformState

    public init(report: InspectionReport, waveform: WaveformState) {
        self.report = report
        self.waveform = waveform
    }
}
