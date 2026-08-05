/// The amplitude extremes observed within one slice of a file, across **all** of its channels.
///
/// It is deliberately *not* an average. Two channels in opposing phase would cancel under a mean and
/// draw a flat line for a file that is not flat, so the minimum and the maximum are taken over every
/// channel's samples. It is a **combined envelope**, never a mono mix or a downmix.
///
/// **Values are kept exactly as they were read.** A sample beyond the nominal `-1...1` scale is not
/// clamped here: the spike measured that native float PCM round-trips such values untouched, and
/// limiting them is a concern of drawing, not of the data. The only range invariant is therefore that
/// both extremes are finite and ordered — a bucket that could not be described honestly is not
/// representable at all.
public struct WaveformBucket: Sendable, Equatable {
    public let minimum: Float
    public let maximum: Float

    /// Fails when either extreme is not finite, or when they are out of order.
    ///
    /// Failable rather than throwing on purpose: a bucket knows nothing about which file, frame or
    /// channel produced it, so it cannot describe *why* the values were wrong. The caller that does
    /// know — `WaveformEnvelopeAccumulator` — turns a `nil` into a `WaveformError` carrying a stable
    /// code. Non-finite values are rejected rather than substituted, because silently turning a `NaN`
    /// into a number would be inventing audio.
    public init?(minimum: Float, maximum: Float) {
        guard minimum.isFinite, maximum.isFinite, minimum <= maximum else { return nil }
        self.minimum = minimum
        self.maximum = maximum
    }

    /// The bucket a run of pure silence produces.
    public static let silent = WaveformBucket(minimum: 0, maximum: 0)!
}

/// A whole file's amplitude envelope: one bucket per slice, in file order.
///
/// The type is intentionally poor. It carries no view width, no normalisation factor, no sample rate,
/// no URL and no chunk size, because none of those describe the audio — and a resolution-independent
/// envelope is what lets a view be resized without decoding the file again.
///
/// It is not `Codable`: the waveform never enters the `schemaVersion` 1 export and is not persisted
/// (ADR-0009). Conforming it would advertise a contract that does not exist.
public struct WaveformEnvelope: Sendable, Equatable {
    /// One bucket per slice of the file, in order. Empty **only** for a file with no frames.
    public let buckets: [WaveformBucket]
    /// Total frames the envelope covers.
    public let frameCount: Int
    /// How many channels were combined into each bucket. Present because "the extremes across all
    /// channels" is not a complete statement without it.
    public let channelCount: Int

    /// Fails when the parts do not describe a possible file.
    ///
    /// The empty case is **valid, not an error**: a file with zero frames has zero buckets. That is a
    /// waveform of nothing, and it is a different thing from *no waveform was produced* — which is an
    /// absence expressed by the port, not by this type — and different again from *generating one
    /// failed*, which is a thrown `WaveformError`. Keeping the three apart is why this model carries
    /// no notion of availability.
    public init?(buckets: [WaveformBucket], frameCount: Int, channelCount: Int) {
        guard frameCount >= 0, channelCount >= 1 else { return nil }
        guard buckets.isEmpty == (frameCount == 0) else { return nil }
        guard buckets.count <= frameCount else { return nil }
        self.buckets = buckets
        self.frameCount = frameCount
        self.channelCount = channelCount
    }

    /// The envelope of a file that has no frames at all.
    public static func empty(channelCount: Int) -> WaveformEnvelope? {
        WaveformEnvelope(buckets: [], frameCount: 0, channelCount: channelCount)
    }
}
