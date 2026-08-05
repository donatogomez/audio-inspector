/// Builds a `WaveformEnvelope` from samples as they arrive, one run at a time.
///
/// It is the reduction's **rules**, not its loop. Whoever reads the file owns the loop, the buffers
/// and the chunk size; this type only decides what a bucket ends up containing. That split is what
/// lets the honesty rules — no averaging, no normalisation, opposing phase does not cancel — be
/// proved by unit tests over plain numbers, with no file and no framework anywhere near them.
///
/// Samples arrive as any `Collection<Float>`, so a reader can hand over a channel's slice of a buffer
/// without copying it and without this type ever learning what a buffer is.
///
/// A run is offered per channel, with the absolute frame its first sample sits at. Bucket boundaries
/// come from `WaveformBucketMapping`, which is a function of the file alone, so **the same file
/// yields the same envelope whatever chunk sizes the runs are cut into**.
public struct WaveformEnvelopeAccumulator: Sendable {
    private let mapping: WaveformBucketMapping
    private let channelCount: Int
    /// Extremes per bucket. A bucket that has seen no sample keeps its infinities, which is how
    /// `finished()` can tell "silent" from "never covered" — silence is `0`, absence is not finite.
    private var minima: [Float]
    private var maxima: [Float]

    /// Fails when the file cannot be described, or when the resolution is not usable.
    public init?(
        totalFrameCount: Int,
        channelCount: Int,
        maximumBucketCount: Int = WaveformBucketMapping.defaultMaximumBucketCount
    ) {
        guard channelCount >= 1,
              let mapping = WaveformBucketMapping(
                  totalFrameCount: totalFrameCount,
                  maximumBucketCount: maximumBucketCount
              )
        else { return nil }
        self.mapping = mapping
        self.channelCount = channelCount
        minima = [Float](repeating: .infinity, count: mapping.bucketCount)
        maxima = [Float](repeating: -.infinity, count: mapping.bucketCount)
    }

    /// Folds one channel's run of samples into the buckets it spans.
    ///
    /// Values are recorded **as read**: nothing is averaged, nothing is scaled, and a sample beyond
    /// `-1...1` is kept rather than clamped. Non-finite samples are refused instead — a `NaN` is not a
    /// quiet sample, and turning it into one would fabricate the drawing.
    public mutating func accumulate(
        _ samples: some Collection<Float>,
        ofChannel channelIndex: Int,
        startingAtFrame startFrame: Int
    ) throws(WaveformError) {
        guard channelIndex >= 0, channelIndex < channelCount else {
            throw WaveformError(
                code: .channelOutOfBounds,
                message: "Samples were offered for channel \(channelIndex) of a \(channelCount)-channel envelope."
            )
        }
        guard startFrame >= 0, startFrame + samples.count <= mapping.totalFrameCount else {
            throw WaveformError(
                code: .frameRangeOutOfBounds,
                message: "A run of \(samples.count) frames at \(startFrame) does not fit \(mapping.totalFrameCount) frames."
            )
        }

        var frame = startFrame
        for sample in samples {
            guard sample.isFinite else {
                throw WaveformError(
                    code: .nonFiniteSample,
                    message: "Frame \(frame) of channel \(channelIndex) is not a finite value."
                )
            }
            // `bucketIndex` cannot be nil here: the range was checked above.
            if let bucket = mapping.bucketIndex(forFrame: frame) {
                if sample < minima[bucket] { minima[bucket] = sample }
                if sample > maxima[bucket] { maxima[bucket] = sample }
            }
            frame += 1
        }
    }

    /// The finished envelope.
    ///
    /// Throws when a bucket was never covered, rather than filling it with silence the file may not
    /// contain: an envelope that quietly invented a flat stretch would be indistinguishable from a
    /// correct one.
    public func finished() throws(WaveformError) -> WaveformEnvelope {
        var buckets: [WaveformBucket] = []
        buckets.reserveCapacity(minima.count)

        for index in minima.indices {
            guard let bucket = WaveformBucket(minimum: minima[index], maximum: maxima[index]) else {
                throw WaveformError(
                    code: .incompleteCoverage,
                    message: "Bucket \(index) of \(minima.count) received no samples."
                )
            }
            buckets.append(bucket)
        }

        guard let envelope = WaveformEnvelope(
            buckets: buckets,
            frameCount: mapping.totalFrameCount,
            channelCount: channelCount
        ) else {
            throw WaveformError(
                code: .invalidConfiguration,
                message: "\(buckets.count) buckets do not describe \(mapping.totalFrameCount) frames."
            )
        }
        return envelope
    }
}
