/// Which bucket each frame of a file belongs to.
///
/// The whole arithmetic of the envelope's resolution, isolated from any reading: it needs no file, no
/// samples and no framework, so the properties that matter can be proved exhaustively by unit tests.
///
/// Frames are mapped by `frameIndex * bucketCount / totalFrameCount` in integer arithmetic. That is a
/// **function of the file alone**, which is what makes an envelope independent of the chunk size a
/// reader happens to use: bucket boundaries cannot move when the reading does. It also means every
/// frame lands in exactly one bucket, none is lost and none is counted twice — the map is total over
/// `0 ..< totalFrameCount` by construction, rather than by an accumulator keeping count.
public struct WaveformBucketMapping: Sendable, Equatable {
    /// The production cap. A cap, not a promised resolution: it is never exported, persisted or shown,
    /// so it can change without breaking anything. Declared once so no call site repeats the literal.
    public static let defaultMaximumBucketCount = 2_048

    public let totalFrameCount: Int
    public let bucketCount: Int

    /// Fails on a description no file can have, and on sizes large enough for the mapping to overflow.
    ///
    /// The overflow guard is exact rather than assumed: `frameIndex * bucketCount` must stay
    /// representable, so `totalFrameCount` may not exceed `Int.max / maximumBucketCount`. At the
    /// production cap that bound is over four quadrillion frames — centuries of audio — but the check
    /// costs nothing and turns a silent wraparound into a refusal.
    public init?(totalFrameCount: Int, maximumBucketCount: Int = WaveformBucketMapping.defaultMaximumBucketCount) {
        guard totalFrameCount >= 0, maximumBucketCount >= 1 else { return nil }
        guard totalFrameCount <= Int.max / maximumBucketCount else { return nil }
        self.totalFrameCount = totalFrameCount
        // A file shorter than the cap gets one bucket per frame, so no bucket is ever empty.
        bucketCount = min(totalFrameCount, maximumBucketCount)
    }

    /// The bucket `frameIndex` belongs to, or `nil` when it lies outside the file.
    public func bucketIndex(forFrame frameIndex: Int) -> Int? {
        guard frameIndex >= 0, frameIndex < totalFrameCount else { return nil }
        return frameIndex * bucketCount / totalFrameCount
    }
}
