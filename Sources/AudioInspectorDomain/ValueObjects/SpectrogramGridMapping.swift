/// Which column each transform frame belongs to, and which band each frequency bin belongs to.
///
/// The whole arithmetic of the spectrogram's resolution, isolated from any transform: it needs no
/// samples, no file and no framework, so the properties that matter can be proved exhaustively by unit
/// tests. It is the sibling of `WaveformBucketMapping`, and follows the same rule for the same reason.
///
/// Both mappings are `index * outputCount / inputCount` in integer arithmetic. That makes them a
/// **function of the file alone**, which is what lets a result be independent of the chunk size a
/// reader happens to use: boundaries cannot move when the reading does. It also means every frame and
/// every bin lands in exactly one place, none is lost and none is counted twice — total by
/// construction rather than by an accumulator keeping count.
public struct SpectrogramGridMapping: Sendable, Equatable {
    /// The production caps. Caps, not promised resolutions: neither is exported, persisted or shown, so
    /// both can change without breaking anything. Declared once so no call site repeats the literal.
    public static let defaultMaximumColumnCount = 1_024
    public static let defaultMaximumBandCount = 512

    /// How many transform frames the file yields. **Zero is valid** — a file with no audio, or one
    /// shorter than a single window, produces no frames and therefore no columns.
    public let stftFrameCount: Int
    /// How many frequency bins each transform frame carries.
    public let binCount: Int
    public let columnCount: Int
    public let bandCount: Int

    /// Fails on a description no analysis can have, and on sizes large enough for a mapping to overflow.
    ///
    /// The overflow guards are exact rather than assumed: `index * outputCount` must stay representable,
    /// so neither input may exceed `Int.max / outputCount`. At the production caps those bounds are
    /// astronomically beyond any real file, but the check costs nothing and turns a silent wraparound
    /// into a refusal.
    public init?(
        stftFrameCount: Int,
        binCount: Int,
        maximumColumnCount: Int = SpectrogramGridMapping.defaultMaximumColumnCount,
        maximumBandCount: Int = SpectrogramGridMapping.defaultMaximumBandCount
    ) {
        guard stftFrameCount >= 0, binCount >= 0 else { return nil }
        guard maximumColumnCount >= 1, maximumBandCount >= 1 else { return nil }
        guard stftFrameCount <= Int.max / maximumColumnCount else { return nil }
        guard binCount <= Int.max / maximumBandCount else { return nil }

        self.stftFrameCount = stftFrameCount
        self.binCount = binCount
        // Fewer inputs than the cap means one output each, so no column and no band is ever empty —
        // and no column is invented for a file that produced no frames.
        columnCount = min(stftFrameCount, maximumColumnCount)
        bandCount = min(binCount, maximumBandCount)
    }

    /// The column `frameIndex` belongs to, or `nil` when it lies outside the analysis.
    public func columnIndex(forFrame frameIndex: Int) -> Int? {
        guard frameIndex >= 0, frameIndex < stftFrameCount, columnCount > 0 else { return nil }
        return frameIndex * columnCount / stftFrameCount
    }

    /// The band `binIndex` belongs to, or `nil` when it lies outside the spectrum.
    public func bandIndex(forBin binIndex: Int) -> Int? {
        guard binIndex >= 0, binIndex < binCount, bandCount > 0 else { return nil }
        return binIndex * bandCount / binCount
    }
}
