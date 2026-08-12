import Accelerate

import AudioInspectorDomain

/// Folds decoded PCM into `SignalLevelMetrics`: one running peak, sum, sum-of-squares and clipped count
/// per channel, updated one chunk at a time.
///
/// ## Why this lives in `AudioInspectorAnalysis`, not `AudioInspectorDomain`
///
/// The model (`SignalLevelMetrics`) is a plain, framework-free value type and could live in the domain
/// on its own. Its *accumulation*, measured rather than assumed, cannot: a hand-written scalar Swift
/// loop over a real ten-minute stereo file (26 460 000 frames per channel) cost **9.15 s in an
/// unoptimised build** for the combined peak/sum/sum-of-squares/clip pass — decode alone, over the same
/// file, cost 0.035 s, so the accumulation was the overwhelming majority of the cost, not the reading.
/// `SIMD8<Float>`, the technique `PCMChunk.isProvablyAllFinite` already uses to stay in the domain
/// without Accelerate, brought that to 6.6 s — better, but still nowhere near "clearly insignificant
/// next to decode." **vDSP for the three reductions that have a direct primitive
/// (`vDSP_maxmgv`/`vDSP_sve`/`vDSP_svesq`), combined with `SIMD8<Int32>` only for the clip count vDSP
/// has no direct primitive for, measured at 0.69 s in the same unoptimised build** — the number that
/// actually satisfies "insignificant next to the rest of an inspection," and it is the one implemented
/// here. Every one of those numbers came from a disposable, deleted measurement harness, not from
/// assumption, per this project's own precedent for exactly this question (`SpectrogramAccumulator`,
/// `PCMChunk.isProvablyAllFinite`).
///
/// ## Accumulates in `Double`, stores in `Float` — **and widens before reducing, not after**
///
/// Measured to cost nothing extra: the combined pass above was **0.071 s in Release accumulating in
/// Double versus 0.077 s accumulating in Float** — memory bandwidth and per-sample overhead dominate,
/// not the width of the floating-point type. `Double`'s roughly 15–17 significant decimal digits give a
/// comfortable margin over the worst case this accumulator ever sees (order 10⁸ additions for the
/// longest realistic file), where `Float`'s roughly 7 digits would let a long, quiet file's DC offset
/// accumulate visible rounding error one sample at a time. The running totals are `Double`; only the
/// final per-channel and overall values, in `finish()`, are narrowed to the `Float` the domain type
/// already uses for every other amplitude.
///
/// **Where the widening happens is not a detail, and getting it wrong produced a real defect.** The
/// first implementation ran `vDSP_sve`/`vDSP_svesq` over the `Float` samples and widened each chunk's
/// *result*, which meant every partial sum was formed in `Float32`. `PCMChunk` refuses `NaN` and
/// infinity at the boundary but deliberately keeps finite samples of **any** magnitude, and a partial
/// sum of those overflows long before the answer would: measured, the sum of squares went non-finite
/// from about `1e18` and the plain sum from about `1e37`, with alternating signs turning `+inf + -inf`
/// into a `NaN`. It was also **chunk-dependent** — the same file measured at one frame per chunk stayed
/// finite where the same file at 4 096 did not — which contradicted this type's own independence
/// guarantee.
///
/// The mathematics never justified any of that. Both results are bounded by the largest magnitude the
/// input contains: `|mean| ≤ max|x|` and `RMS = sqrt(mean(x²)) ≤ max|x|`, so **a finite `Float` input
/// always has a finite `Float` answer**. The overflow was purely intermediate, and the fix is to widen
/// each chunk to `Double` *before* reducing it. In `Double` the intermediates cannot overflow either:
/// the largest `Float` squared is ~1.16e77, and even 2⁵³ of them sum to ~1e93 against `Double`'s own
/// ~1.8e308 ceiling.
///
/// ## One pass, `O(channelCount)` memory
///
/// `accumulate(_:)` is the only place any chunk is read, and it updates five running totals per channel
/// — nothing here retains a sample past the call that offered it, so memory does not grow with the
/// file's duration.
///
/// ## Not `Sendable`, deliberately
///
/// It owns mutable per-channel accumulation state with no synchronization. Exactly like
/// `SpectrogramAccumulator`, it is created and consumed inside one `nonisolated async` operation, never
/// stored on a `Sendable` type, never cached, never shared.
public struct SignalLevelMetricsAccumulator {
    /// Full scale on the domain's own normalized linear amplitude. A sample counts as clipped when its
    /// absolute value is at or beyond this. Named and versioned per ADR-0006's own pattern for any
    /// constant tied to the analysis engine version — changing it is changing the engine version, not a
    /// runtime setting, so it is **never user-configurable**: a threshold a user could adjust would make
    /// the same file produce different results across runs, which this project's reproducibility
    /// principle (`docs/project-principles.md` #7) rules out directly.
    public static let clippingThreshold: Float = 1.0

    private let channelCount: Int
    private var peak: [Double]
    private var sum: [Double]
    private var sumOfSquares: [Double]
    private var clippedCount: [Int]
    private var sampleCount: [Int]

    /// The chunk widened to `Double`, grown to the largest chunk seen and then reused — so the widening
    /// costs no allocation per chunk and memory stays a function of the caller's buffer size, never of
    /// the file's duration. The same technique `TruePeakAccumulator` already uses for its own scratch.
    private var widened: [Double] = []

    /// Fails only on a channel count no stream can have.
    public init?(channelCount: Int) {
        guard channelCount >= 1 else { return nil }
        self.channelCount = channelCount
        peak = [Double](repeating: 0, count: channelCount)
        sum = [Double](repeating: 0, count: channelCount)
        sumOfSquares = [Double](repeating: 0, count: channelCount)
        clippedCount = [Int](repeating: 0, count: channelCount)
        sampleCount = [Int](repeating: 0, count: channelCount)
    }

    /// Folds one chunk's samples into the running per-channel totals.
    ///
    /// Mathematically independent of feed order and of chunk size, exactly like
    /// `WaveformEnvelopeAccumulator`'s own fold: every running total here is a commutative, associative
    /// reduction (max, sum, sum-of-squares, count), so it does not matter which channel arrives first,
    /// how many chunks the file was split into, or how many frames each one carried. A chunk whose
    /// channel count disagrees with this accumulator's is ignored, mirroring
    /// `SpectrogramAccumulator.accumulate(_:)`'s own guard.
    ///
    /// **Peak, the clip count and the sample count are bit-exact regardless of chunking.** `rms` and
    /// `dcOffset` are independent **only up to floating-point rounding**, and this is stated rather than
    /// glossed over: `vDSP_sve`/`vDSP_svesq` compute each chunk's own partial sum in `Float32` before it
    /// is widened to this accumulator's `Double` running total, and *how* a chunk's elements pair up
    /// during that reduction is vDSP's own implementation detail — different chunk boundaries hand vDSP
    /// different groupings, which round differently in the last bit or two of each partial sum. Measured
    /// at up to ~10⁻⁵ absolute on values of order 10⁻¹, across chunk sizes from 1 to 65 536 frames — see
    /// `SignalLevelMetricsAccumulatorTests.chunkSizeIndependence`.
    public mutating func accumulate(_ chunk: PCMChunk) {
        guard chunk.channelCount == channelCount else { return }
        for channel in 0 ..< channelCount {
            accumulate(chunk.channels[channel], intoChannel: channel)
        }
    }

    private mutating func accumulate(_ samples: [Float], intoChannel channel: Int) {
        guard !samples.isEmpty else { return }
        let count = vDSP_Length(samples.count)

        // The maximum is taken in `Float`: a maximum of magnitudes cannot overflow, since its result is
        // one of the inputs. The two *sums* are the ones that can, so they are formed in `Double`.
        var maxMagnitude: Float = 0
        vDSP_maxmgv(samples, 1, &maxMagnitude, count)
        peak[channel] = max(peak[channel], Double(maxMagnitude))

        if widened.count < samples.count { widened = [Double](repeating: 0, count: samples.count) }
        widened.withUnsafeMutableBufferPointer { destination in
            guard let target = destination.baseAddress else { return }
            vDSP_vspdp(samples, 1, target, 1, count)

            var sampleSum = 0.0
            vDSP_sveD(target, 1, &sampleSum, count)
            sum[channel] += sampleSum

            var sampleSumOfSquares = 0.0
            vDSP_svesqD(target, 1, &sampleSumOfSquares, count)
            sumOfSquares[channel] += sampleSumOfSquares
        }

        clippedCount[channel] += Self.clippedCount(in: samples)
        sampleCount[channel] += samples.count
    }

    /// The finished metrics, or `nil` when they could not be described honestly.
    ///
    /// Optional for the reason `SpectrogramAccumulator.finish()` and `TruePeakAccumulator.finish()`
    /// already are, and this type was the odd one out: the domain model refuses states it cannot
    /// describe, and a producer that cannot satisfy it must say so rather than hand back something
    /// contradictory. With the widening fixed above, every guard the model applies is met by
    /// construction — `|mean| ≤ max|x|` and `RMS ≤ max|x|`, both finite for finite input — so this is a
    /// **backstop**, not a path the arithmetic can reach. Whoever holds the context turns the `nil` into
    /// a failed outcome; nothing invents a number to avoid it.
    public func finish() -> SignalLevelMetrics? {
        var channels: [SignalLevelMetrics.Channel] = []
        channels.reserveCapacity(channelCount)
        for channel in 0 ..< channelCount {
            let n = sampleCount[channel]
            let made: SignalLevelMetrics.Channel?
            if n > 0 {
                let mean = sum[channel] / Double(n)
                let meanSquare = sumOfSquares[channel] / Double(n)
                made = SignalLevelMetrics.Channel(
                    sampleCount: n,
                    peakSample: Float(peak[channel]),
                    rms: Float(meanSquare.squareRoot()),
                    dcOffset: Float(mean),
                    clippedSampleCount: clippedCount[channel]
                )
            } else {
                made = SignalLevelMetrics.Channel(
                    sampleCount: 0, peakSample: nil, rms: nil, dcOffset: nil,
                    clippedSampleCount: clippedCount[channel]
                )
            }
            guard let made else { return nil }
            channels.append(made)
        }

        let totalSamples = sampleCount.reduce(0, +)
        let overallPeak = totalSamples > 0 ? Float(peak.max() ?? 0) : nil
        let overallDCOffset = totalSamples > 0 ? Float(sum.reduce(0, +) / Double(totalSamples)) : nil
        let overallRMS = totalSamples > 0
            ? Float((sumOfSquares.reduce(0, +) / Double(totalSamples)).squareRoot())
            : nil

        return SignalLevelMetrics(
            channels: channels,
            overallPeakSample: overallPeak,
            overallRMS: overallRMS,
            overallDCOffset: overallDCOffset,
            overallClippedSampleCount: clippedCount.reduce(0, +)
        )
    }
}

// MARK: - The clip count, in SIMD8 — the one operation vDSP has no direct primitive for

private extension SignalLevelMetricsAccumulator {
    /// Counts samples at or beyond `clippingThreshold` in absolute value.
    ///
    /// The same technique `PCMChunk.isProvablyAllFinite` already uses to vectorise a per-sample scan
    /// without Accelerate: eight lanes at a time via `SIMD8<Float>`, with a scalar tail for whatever does
    /// not divide evenly by eight. Unlike the finiteness screen, this is exact rather than one-sided —
    /// every clipped sample is counted, not merely suspected.
    static func clippedCount(in samples: [Float]) -> Int {
        samples.withUnsafeBytes { raw in
            let count = samples.count
            let threshold = SIMD8<Float>(repeating: clippingThreshold)
            let negatedThreshold = SIMD8<Float>(repeating: -clippingThreshold)
            var lanes = SIMD8<Int32>(repeating: 0)
            var offset = 0
            while offset + 8 <= count {
                let lane = raw.loadUnaligned(fromByteOffset: offset * 4, as: SIMD8<Float>.self)
                let clipped = (lane .>= threshold) .| (lane .<= negatedThreshold)
                lanes.replace(with: lanes &+ SIMD8<Int32>(repeating: 1), where: clipped)
                offset += 8
            }
            var total = (0 ..< 8).reduce(0) { $0 + Int(lanes[$1]) }
            while offset < count {
                if abs(raw.loadUnaligned(fromByteOffset: offset * 4, as: Float.self)) >= clippingThreshold {
                    total += 1
                }
                offset += 1
            }
            return total
        }
    }
}
