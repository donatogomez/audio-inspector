/// A stable, machine-processable code for a **PCM decoding** failure.
///
/// Its own space, disjoint from `InspectionErrorCode`, `PropertyFailureCode` and `WaveformErrorCode`.
/// Decoding is now shared by more than one consumer, so a fault here says nothing about any particular
/// visualisation — and collapsing it into one of theirs would tell a caller something untrue about what
/// failed. The `rawValue` is the identity; the message is not. Grows additively via static members.
///
/// **Only faults this layer can actually produce are named.** There is no `fileOpenFailed` or
/// `readFailed` here: no adapter exists yet to raise them, and a code with no producer is a promise
/// about behaviour nobody has written. They are added with the adapter that can throw them, exactly as
/// the waveform's own codes were.
public struct AudioDecodingErrorCode: RawRepresentable, Sendable, Equatable, Hashable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

public extension AudioDecodingErrorCode {
    /// The described stream cannot exist — a non-positive or non-finite sample rate, no channels, or a
    /// negative frame count.
    static let invalidStreamDescription = AudioDecodingErrorCode(rawValue: "decoding_invalid_stream_description")
    /// A chunk's parts do not describe a possible run of audio: channels of differing lengths, a
    /// negative starting frame, or no channels at all.
    static let invalidChunk = AudioDecodingErrorCode(rawValue: "decoding_invalid_chunk")
    /// A sample was `NaN` or infinite.
    ///
    /// Refused at this boundary rather than clamped or floored later. The spike measured what the
    /// alternative costs: a single `NaN` did not leak a non-finite value into a spectrogram, but
    /// silently collapsed 184 cells to the floor, so a corrupted region would have read as *an absence
    /// of energy* rather than as a fault. A value that is not a number is not audio, and quietly
    /// turning it into silence would fabricate the result.
    static let nonFiniteSample = AudioDecodingErrorCode(rawValue: "decoding_non_finite_sample")
    /// A chunk falls outside the frame range the stream declared.
    static let frameRangeOutOfBounds = AudioDecodingErrorCode(rawValue: "decoding_frame_range_out_of_bounds")
    /// The stream ended before every frame it declared had been delivered.
    static let incompleteCoverage = AudioDecodingErrorCode(rawValue: "decoding_incomplete_coverage")
    /// The operation was cancelled before the whole file had been read.
    ///
    /// **It says nothing about the file.** Cancellation is something the caller did, not a defect or a
    /// failure to read, and must never be shown as one.
    ///
    /// It is deliberately an error rather than a `nil` result, because `nil` from `AudioDecoding` means
    /// the file exposed no usable frame count. A caller who cancels has learnt nothing about their
    /// file, and collapsing the two would tell them they had — the same distinction `WaveformErrorCode`
    /// draws for the same reason.
    static let cancelled = AudioDecodingErrorCode(rawValue: "decoding_cancelled")
}

/// A decoding failure: a stable `code` (the identity, for automated processing) plus a descriptive
/// `message` that is **not** part of that identity.
///
/// No framework error, no file path and no URL ever reaches this type (ADR-0011).
public struct AudioDecodingError: Error, Sendable, Equatable {
    public let code: AudioDecodingErrorCode
    public let message: String

    public init(code: AudioDecodingErrorCode, message: String) {
        self.code = code
        self.message = message
    }
}
