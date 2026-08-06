/// A stable, machine-processable code for a **PCM decoding** failure.
///
/// Its own space, disjoint from `InspectionErrorCode`, `PropertyFailureCode` and `WaveformErrorCode`.
/// Decoding is now shared by more than one consumer, so a fault here says nothing about any particular
/// visualisation — and collapsing it into one of theirs would tell a caller something untrue about what
/// failed. The `rawValue` is the identity; the message is not. Grows additively via static members.
///
/// **Only faults something already requires are named.** Two are produced by `PCMChunk`, two are
/// required by a contract this layer states — the description a caller must turn into an error, and the
/// cancellation the port promises never to report as an absence — and five arrived with the branches in
/// the native adapter that throw them. Nothing else is declared: there is still no
/// `frameRangeOutOfBounds` and no `incompleteCoverage`, because a code with no producer and no contract
/// behind it is a promise about behaviour nobody has written. A reader that overruns or falls short of
/// the length its file declares is reported as `readFailed`, which is what actually happened.
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

    // MARK: Produced by an adapter that reads a real file
    //
    // Declared here rather than in infrastructure because the code space is the domain's — an adapter
    // maps its platform failures onto these and never invents its own, exactly as the inspection and
    // waveform errors work (ADR-0011). Each arrived with the branch that throws it.

    /// A decode was asked for a chunk size no read can use — zero frames, or fewer.
    static let invalidConfiguration = AudioDecodingErrorCode(rawValue: "decoding_invalid_configuration")
    /// No accessible location was supplied for the file, so nothing could be opened.
    static let fileAccessDenied = AudioDecodingErrorCode(rawValue: "decoding_file_access_denied")
    /// The file could not be opened for reading.
    static let fileOpenFailed = AudioDecodingErrorCode(rawValue: "decoding_file_open_failed")
    /// The file opened, but its decoded form is not a layout chunks can be copied from — for example
    /// interleaved samples, or something other than native float. Distinct from a read failure: nothing
    /// went wrong, the shape is simply not one that can be handed over one channel at a time.
    static let unsupportedProcessingFormat = AudioDecodingErrorCode(rawValue: "decoding_unsupported_processing_format")
    /// The file opened but could not be read through to the end it declared — it failed mid-read,
    /// stopped producing frames early, or produced more than it promised.
    static let readFailed = AudioDecodingErrorCode(rawValue: "decoding_read_failed")
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
