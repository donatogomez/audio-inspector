/// A stable, machine-processable code for a **waveform** failure.
///
/// Its own space, disjoint from `InspectionErrorCode` (a whole-file inspection failure) and from
/// `PropertyFailureCode` (a single property's failure): a waveform that could not be produced says
/// nothing about the file's technical properties, and must never be confused with either. The
/// `rawValue` is the identity; the message is not. Grows additively via static members.
public struct WaveformErrorCode: RawRepresentable, Sendable, Equatable, Hashable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

public extension WaveformErrorCode {
    /// The requested resolution or the described file cannot yield an envelope — for example a
    /// negative frame count, no channels, or a bucket cap below one.
    static let invalidConfiguration = WaveformErrorCode(rawValue: "waveform_invalid_configuration")
    /// A sample was `NaN` or infinite. Not clamped and not skipped: a value that is not a number is
    /// not audio, and treating it as one would fabricate the drawing.
    static let nonFiniteSample = WaveformErrorCode(rawValue: "waveform_non_finite_sample")
    /// Samples were offered for a channel the file does not have.
    static let channelOutOfBounds = WaveformErrorCode(rawValue: "waveform_channel_out_of_bounds")
    /// Samples were offered outside the frame range the envelope was built for.
    static let frameRangeOutOfBounds = WaveformErrorCode(rawValue: "waveform_frame_range_out_of_bounds")
    /// The envelope was finished before every slice of the file had been seen, so some buckets would
    /// describe nothing. Producing them anyway would invent silence the file may not contain.
    static let incompleteCoverage = WaveformErrorCode(rawValue: "waveform_incomplete_coverage")
}

/// A waveform failure: a stable `code` (the identity, for automated processing) plus a descriptive
/// `message` that is **not** part of that identity.
///
/// Only faults this layer can actually produce are named here. Opening and decoding failures belong
/// to the adapter and are added to `WaveformErrorCode` when that adapter exists — never mapped onto
/// one of these. No framework error, no file path and no URL ever reaches this type (ADR-0011).
public struct WaveformError: Error, Sendable, Equatable {
    public let code: WaveformErrorCode
    public let message: String

    public init(code: WaveformErrorCode, message: String) {
        self.code = code
        self.message = message
    }
}
