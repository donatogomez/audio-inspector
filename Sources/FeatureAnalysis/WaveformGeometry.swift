import AudioInspectorDomain
import CoreGraphics

/// Where each bucket lands inside the area available to draw it.
///
/// It is deliberately outside the view: a `Canvas` renderer cannot be asserted, and every property
/// worth guaranteeing here — that zero sits on the centre line, that `-1` and `+1` are symmetric about
/// it, that a value beyond the nominal range is limited **when drawn and only then**, that the buckets
/// tile the width without a gap — is arithmetic that needs no rendering at all.
///
/// It maps buckets onto whatever width it is given and never the other way round. The envelope is
/// resolution-independent by construction, so a resize re-runs this and nothing else: the file is not
/// read again and the model is not touched.
struct WaveformGeometry: Equatable {
    /// The scale the drawing covers. The domain keeps samples exactly as they were read, including
    /// values beyond this range; limiting them is a property of the picture, which has edges, and not
    /// of the data, which does not. Nothing here writes back.
    static let drawnRange: ClosedRange<Float> = -1 ... 1

    /// The least a bucket may occupy vertically. Without it a bucket of very small but non-zero
    /// amplitude would round away to nothing and read as silence — a worse misstatement than a hairline.
    static let minimumBarHeight: CGFloat = 1

    let size: CGSize
    let bucketCount: Int

    /// Fails on an area nothing can be drawn in, and on an envelope with no buckets.
    ///
    /// All three are ordinary situations rather than errors: a `Canvas` is laid out at zero size before
    /// it settles, and a file with no frames legitimately has no buckets. The caller draws the centre
    /// line and stops.
    init?(size: CGSize, bucketCount: Int) {
        guard size.width > 0, size.height >= Self.minimumBarHeight, bucketCount > 0 else { return nil }
        self.size = size
        self.bucketCount = bucketCount
    }

    /// Amplitude zero. Every bar is measured from here, so silence is a line and not an offset.
    var centreY: CGFloat { size.height / 2 }

    /// The vertical position of an amplitude, with `+1` at the top edge and `-1` at the bottom.
    ///
    /// The clamp is the only place the nominal range is imposed, and it applies to the coordinate it
    /// returns — never to the bucket it came from.
    func y(forAmplitude amplitude: Float) -> CGFloat {
        let drawn = min(max(amplitude, Self.drawnRange.lowerBound), Self.drawnRange.upperBound)
        return centreY - CGFloat(drawn) * centreY
    }

    /// The horizontal band belonging to a bucket, or `nil` outside the envelope.
    ///
    /// Both edges are computed from the index rather than accumulated from a step, so rounding cannot
    /// drift across 2048 buckets and one bucket's trailing edge is exactly the next one's leading edge:
    /// the bands tile the width with no gap and no overlap, at any width.
    func horizontalBand(forBucket index: Int) -> (minX: CGFloat, maxX: CGFloat)? {
        guard index >= 0, index < bucketCount else { return nil }
        return (
            minX: size.width * CGFloat(index) / CGFloat(bucketCount),
            maxX: size.width * CGFloat(index + 1) / CGFloat(bucketCount)
        )
    }

    /// The rectangle drawn for one bucket: its band horizontally, its two extremes vertically.
    func bar(forBucket index: Int, of bucket: WaveformBucket) -> CGRect? {
        guard let band = horizontalBand(forBucket: index) else { return nil }
        let top = y(forAmplitude: bucket.maximum) // the maximum is the higher point, so the smaller y
        let bottom = y(forAmplitude: bucket.minimum)
        return CGRect(
            x: band.minX,
            y: raised(top: top, bottom: bottom),
            width: band.maxX - band.minX,
            height: max(bottom - top, Self.minimumBarHeight)
        )
    }

    /// One rectangle per bucket, in file order. Linear in the number of buckets, allocated once, and
    /// drawn as a single path by the caller — never as a view per bucket.
    func bars(for buckets: [WaveformBucket]) -> [CGRect] {
        buckets.enumerated().compactMap { index, bucket in bar(forBucket: index, of: bucket) }
    }

    /// Keeps a bar that had to be widened to the minimum height centred on where it actually was, and
    /// inside the drawing area — a bucket sitting at either extreme would otherwise be pushed half a
    /// point past the edge.
    private func raised(top: CGFloat, bottom: CGFloat) -> CGFloat {
        guard bottom - top < Self.minimumBarHeight else { return top }
        let centre = (top + bottom) / 2 - Self.minimumBarHeight / 2
        return min(max(centre, 0), size.height - Self.minimumBarHeight)
    }
}
