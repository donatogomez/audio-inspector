/// What a decoded stream turned out to be: enough to size an analysis against, and nothing more.
///
/// Deliberately poor. It carries no `URL`, no container, no codec, no UTI, no interleaving and no view
/// size, because none of those describe the audio a consumer is about to fold. Anything a caller wants
/// to *say* about the file already lives in `TechnicalProperties`; this type exists so a reduction can
/// be sized correctly, and it is not a second, competing description of the file.
public struct PCMStreamDescription: Sendable, Equatable {
    /// Frames per second. Finite and positive.
    public let sampleRate: Double
    /// How many channels the stream carries. At least one.
    public let channelCount: Int
    /// Total frames the stream contains. **Zero is valid**: a file with a readable header and no audio
    /// is a complete, honest answer, and a different thing from a file whose length could not be
    /// established — which `AudioDecoding` reports as `nil` rather than as a description.
    public let frameCount: Int

    /// Fails on a description no stream can have.
    ///
    /// Failable rather than throwing: this type knows nothing about which file produced it, so it
    /// cannot describe *why* the numbers were wrong. The caller that does know turns a `nil` into an
    /// `AudioDecodingError` carrying `invalidStreamDescription` — the same split `WaveformBucket` and
    /// `WaveformEnvelopeAccumulator` already use.
    public init?(sampleRate: Double, channelCount: Int, frameCount: Int) {
        guard sampleRate.isFinite, sampleRate > 0 else { return nil }
        guard channelCount >= 1 else { return nil }
        guard frameCount >= 0 else { return nil }
        self.sampleRate = sampleRate
        self.channelCount = channelCount
        self.frameCount = frameCount
    }

    /// The highest frequency the stream can represent. The whole of it is meaningful: a file that
    /// declares a high sample rate and carries nothing in its upper range is showing something, and
    /// no consumer of this type should assume the top is uninteresting.
    public var nyquist: Double { sampleRate / 2 }
}
