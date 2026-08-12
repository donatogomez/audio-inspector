import Accelerate

import AudioInspectorDomain

/// Folds decoded PCM into a `TruePeakMeasurement`: the maximum of the waveform the samples represent,
/// including what it does **between** them, one running maximum per channel.
///
/// ## The constants are measured, and they are not settings
///
/// 8× oversampling, 48 taps per phase, Kaiser β 6.0, cutoff at exactly the original Nyquist, each phase
/// normalised to unit sum, and the signal zero-extended past its first and last sample. Every one of
/// them comes from `docs/spikes/2026-08-11-true-peak-methodology-validation.md`, and together they *are*
/// `TruePeakFilterIdentifier.polyphaseFIRv1` — changing any one produces a different measurement and
/// requires a new identity, not a new configuration option. Nothing here is public and nothing is
/// reachable from a feature or the app: a threshold a user could retune would make the same file
/// produce different results across runs, which this project's reproducibility principle rules out
/// (ADR-0006's own pattern for engine-versioned constants).
///
/// ## Why the numbers are what they are, in one line each
///
/// - **8×, not ADR-0006's 4× floor.** The grid a factor `L` evaluates on can miss a crest by up to
///   `1 − cos(π·f/(L·sr))`; measured over 64 signal phases, that worst case is **−0.169 dB at 4×** and
///   **−0.042 dB at 8×**. R128 limits are quoted to 0.1 dB, so 4× can flip the judgement a reader makes.
/// - **48 taps per phase.** The shortest design measured flat within ±0.1 dB up to 0.93·Nyquist, and
///   16–20 kHz — where this product looks for a lossy cutoff — is 0.73–0.91·Nyquist at 44.1 kHz. 32
///   taps reaches only 0.89·N.
/// - **Kaiser β 6.0.** Image leakage was ≤ +0.02 dB for every β measured, so the stopband never became
///   the binding constraint and the flattest passband won.
/// - **Cutoff exactly 1.0.** Not a tuning knob: it is what makes phase 0 the identity, and therefore
///   what makes `truePeak >= samplePeak` structural (see `PolyphaseInterpolationFilter`). Measured
///   negative control: at cutoff 0.90 the invariant breaks by −0.16.
///
/// ## `Float`, deliberately, where `SignalLevelMetricsAccumulator` uses `Double`
///
/// That type accumulates a running **sum** over ~10⁸ samples, where `Float`'s ~7 significant digits
/// erode one addition at a time. A maximum accumulates nothing: each output point is computed once and
/// compared, so there is no error to grow. Measured across 21 fixtures, `Float` and `Double`
/// convolutions differ by at most **1.9 × 10⁻⁷** linear (2 × 10⁻⁶ dB) at identical cost.
///
/// ## One pass, memory bounded by the chunk and never by the file
///
/// Nothing retains audio past the call that offered it except the `tapsPerPhase - 1` samples an FIR
/// genuinely needs to span a chunk boundary. Peak memory is
/// `O(channelCount × (tapsPerPhase + chunkFrames))`, and the `chunkFrames` term is the caller's own
/// buffer size, not a function of duration.
///
/// ## Not `Sendable`, deliberately
///
/// It owns mutable per-channel state with no synchronisation. Exactly like `SpectrogramAccumulator` and
/// `SignalLevelMetricsAccumulator`, it is created and consumed inside one `nonisolated async`
/// operation, never stored on a `Sendable` type, never cached, never shared.
public struct TruePeakAccumulator {
    /// Points per input sample the reconstruction is evaluated at.
    static let oversamplingFactor = 8
    /// Taps each phase reads. Even, so the support around the interpolated point stays symmetric.
    static let tapsPerPhase = 48
    /// Total coefficients: `tapsPerPhase × oversamplingFactor`.
    static let coefficientCount = tapsPerPhase * oversamplingFactor
    /// Kaiser window β.
    static let kaiserBeta = 6.0
    /// Sinc cutoff as a fraction of the **input** Nyquist. `1.0` is the whole original band, and it is
    /// what keeps phase 0 an exact identity.
    static let cutoff = 1.0

    /// Samples that must cross a chunk boundary for an FIR of this length: the 23 of left context a
    /// position needs, plus the 24 of lookahead that stop the last positions of a chunk from being
    /// emitted until the next one arrives. Exactly `tapsPerPhase - 1`, which is the information an FIR
    /// of length `tapsPerPhase` cannot do without — fewer would make the result depend on the chunking.
    static let carriedSamples = tapsPerPhase - 1
    /// How many samples before a position its window reaches — `tapsPerPhase / 2 - 1`. Also the depth of
    /// the zero-extension the file starts with.
    static let leftContext = tapsPerPhase / 2 - 1
    /// How many samples after a position its window reaches — `tapsPerPhase / 2`. Also the depth of the
    /// zero-extension `finish()` runs the tail through.
    static let lookahead = tapsPerPhase / 2

    private let filter: PolyphaseInterpolationFilter
    private let channelCount: Int

    // MARK: Mutable state, all confined to one operation

    /// The window not yet consumed, per channel, in **extended** coordinates: it begins as
    /// `leftContext` zeros, which is the zero-extension before the file's first frame.
    private var pending: [[Float]]
    /// Frames folded in so far, per channel.
    private var sampleCount: [Int]
    /// The running maximum of `|y|`, per channel, in linear amplitude.
    private var peak: [Float]

    /// Scratch for one phase's convolution output, grown to the largest chunk seen and then reused, so
    /// no allocation happens per chunk or per phase.
    private var convolved: [Float] = []
    /// The samples one call convolves over: the carried tail followed by the incoming chunk. Reused for
    /// the same reason.
    private var window: [Float] = []

    /// Fails only on a channel count no stream can have.
    public init?(channelCount: Int) {
        guard channelCount >= 1 else { return nil }
        self.channelCount = channelCount
        filter = PolyphaseInterpolationFilter(
            factor: Self.oversamplingFactor,
            tapsPerPhase: Self.tapsPerPhase,
            beta: Self.kaiserBeta,
            cutoff: Self.cutoff
        )
        pending = Array(repeating: [Float](repeating: 0, count: Self.leftContext), count: channelCount)
        sampleCount = [Int](repeating: 0, count: channelCount)
        peak = [Float](repeating: 0, count: channelCount)
    }

    /// Folds one chunk's samples into the running per-channel maxima.
    ///
    /// **Independent of chunk size, bit for bit** — not merely to a tolerance. Each output position is
    /// computed from the same 48 taps and the same 48 samples however the file was cut, and a maximum
    /// has no accumulation for a different grouping to round differently. That is a stronger guarantee
    /// than `SignalLevelMetricsAccumulator` can make for its RMS, and the difference is the arithmetic,
    /// not the care taken.
    ///
    /// A chunk whose channel count disagrees with this accumulator's is ignored, mirroring the guard
    /// both sibling accumulators already use.
    public mutating func accumulate(_ chunk: PCMChunk) {
        guard chunk.channelCount == channelCount else { return }
        for channel in 0 ..< channelCount {
            accumulate(chunk.channels[channel], intoChannel: channel)
        }
    }

    /// The finished measurement, or `nil` when a reconstruction was not finite.
    ///
    /// Optional for the reason `SpectrogramAccumulator.finish()` is: the domain model refuses states it
    /// cannot describe honestly, and a producer that could not satisfy it must say so rather than hand
    /// back something partial. Every guard the model applies is met by construction here **except**
    /// finiteness, which a pathological input could in principle break by overflowing the convolution —
    /// so that one case, and only that one, becomes a `nil` the caller turns into a failure.
    ///
    /// The tail is flushed through `lookahead` zeros first: the file is surrounded by silence, which is
    /// what a decoder handing it to anything else also produces.
    public mutating func finish() -> TruePeakMeasurement? {
        for channel in 0 ..< channelCount {
            flush(channel)
        }
        guard let method = TruePeakMethod(
            oversamplingFactor: Self.oversamplingFactor, filter: .polyphaseFIRv1
        ) else { return nil }

        var channels: [TruePeakMeasurement.Channel] = []
        channels.reserveCapacity(channelCount)
        for channel in 0 ..< channelCount {
            // The `nil`-iff-empty rule is produced here rather than checked afterwards: a channel that
            // folded no frames has no maximum to report, and one that folded frames has exactly the
            // running maximum below.
            let value: Float? = sampleCount[channel] > 0 ? peak[channel] : nil
            guard let made = TruePeakMeasurement.Channel(
                sampleCount: sampleCount[channel], truePeak: value
            ) else { return nil }
            channels.append(made)
        }
        return TruePeakMeasurement(channels: channels, method: method)
    }
}

// MARK: - The streaming convolution

private extension TruePeakAccumulator {
    /// Folds one channel's run of samples, emitting every position whose whole tap window has arrived.
    mutating func accumulate(_ samples: [Float], intoChannel channel: Int) {
        guard !samples.isEmpty else { return }
        sampleCount[channel] += samples.count
        emit(samples, intoChannel: channel)
    }

    /// Runs the tail through the trailing zero-extension, so the last frames are measured too.
    mutating func flush(_ channel: Int) {
        guard sampleCount[channel] > 0 else { return }
        emit([Float](repeating: 0, count: Self.lookahead), intoChannel: channel)
    }

    /// Appends `incoming` to the channel's pending window, emits everything now covered, and keeps
    /// exactly `carriedSamples` behind.
    ///
    /// **No `removeFirst` on a growing buffer.** `pending` never exceeds `carriedSamples` between calls,
    /// and the copy that maintains it moves 47 floats — a fixed cost per chunk, independent of both the
    /// chunk's size and the file's length.
    mutating func emit(_ incoming: [Float], intoChannel channel: Int) {
        let taps = Self.tapsPerPhase
        let carried = pending[channel]
        let total = carried.count + incoming.count
        let outputCount = total - (taps - 1)

        if outputCount > 0 {
            if window.count < total { window = [Float](repeating: 0, count: total) }
            if convolved.count < outputCount { convolved = [Float](repeating: 0, count: outputCount) }
            window.withUnsafeMutableBufferPointer { destination in
                guard let target = destination.baseAddress else { return }
                carried.withUnsafeBufferPointer { source in
                    if let base = source.baseAddress { target.update(from: base, count: carried.count) }
                }
                incoming.withUnsafeBufferPointer { source in
                    if let base = source.baseAddress {
                        (target + carried.count).update(from: base, count: incoming.count)
                    }
                }
            }
            convolve(channel: channel, outputCount: outputCount)
        }

        // Keep the last `carriedSamples` — or everything, when the file is shorter than that.
        let keep = min(Self.carriedSamples, total)
        var next = [Float](repeating: 0, count: keep)
        let fromIncoming = min(keep, incoming.count)
        let fromCarried = keep - fromIncoming
        if fromCarried > 0 {
            next.replaceSubrange(0 ..< fromCarried, with: carried.suffix(fromCarried))
        }
        if fromIncoming > 0 {
            next.replaceSubrange(fromCarried ..< keep, with: incoming.suffix(fromIncoming))
        }
        pending[channel] = next
    }

    /// One `vDSP_conv` and one `vDSP_maxmgv` per phase, over the samples already staged in `window`.
    ///
    /// **The zero-stuffed 8× signal is never materialised.** By the polyphase identity, interpolating by
    /// `L` is `L` separate FIRs run at the *input* rate, so this touches `outputCount` values per phase
    /// rather than `8 × outputCount` in one buffer — the memory stays a function of the chunk, and the
    /// arithmetic is the same either way.
    ///
    /// `vDSP_conv` with a positive filter stride computes `C[n] = Σₚ A[n+p]·F[p]`, which is exactly
    /// `Σⱼ h[j]·x[n+j]` with the taps in increasing `j`. It reads `outputCount + tapsPerPhase - 1`
    /// elements of `A`, which is precisely what `window` holds.
    mutating func convolve(channel: Int, outputCount: Int) {
        var best = peak[channel]
        let taps = Self.tapsPerPhase
        window.withUnsafeBufferPointer { input in
            filter.coefficients.withUnsafeBufferPointer { kernel in
                convolved.withUnsafeMutableBufferPointer { output in
                    guard let inputBase = input.baseAddress,
                          let kernelBase = kernel.baseAddress,
                          let outputBase = output.baseAddress else { return }
                    for phase in 0 ..< Self.oversamplingFactor {
                        vDSP_conv(
                            inputBase, 1,
                            kernelBase + phase * taps, 1,
                            outputBase, 1,
                            vDSP_Length(outputCount), vDSP_Length(taps)
                        )
                        var phasePeak: Float = 0
                        vDSP_maxmgv(outputBase, 1, &phasePeak, vDSP_Length(outputCount))
                        best = max(best, phasePeak)
                    }
                }
            }
        }
        peak[channel] = best
    }
}

// MARK: - The filter, generated from the parameters rather than pasted

/// The polyphase windowed-sinc interpolation filter, built from its four parameters.
///
/// ## The coefficients are computed, never quoted
///
/// There is no table of 384 numbers in this repository. The design is `sinc` × Kaiser, evaluated per
/// phase, and generating it from the parameters is what keeps the constants above the single source of
/// truth — a pasted table would be a second one, free to drift.
///
/// **It is not ITU-R BS.1770 Annex 2's own filter**, and nothing in this project may describe it as one:
/// those coefficients were unavailable when the methodology was validated, so this is a filter of the
/// same family, designed to recorded parameters and checked against analytic ground truth and an
/// independent R128 implementation (ADR-0019 §6).
///
/// ## Why phase 0 is exactly the identity
///
/// `sinc(u)` is **zero at every non-zero integer and one at zero** — a definition, not an approximation.
/// Evaluating it as `sin(πu)/(πu)` returns about 1e-16 at integer arguments instead of 0, so it is
/// evaluated as the definition here. At phase 0 every tap argument is an integer, which makes its taps
/// exactly `0, …, 1, …, 0`: the reconstruction reproduces the stored samples bit for bit, and the
/// maximum is therefore taken over a set that already contains them.
///
/// **That is the whole proof of `truePeak >= samplePeak`**, and it is why no clamp exists anywhere in
/// this file. A clamp would hide a broken filter; this fails on one instead.
///
/// It holds only while `cutoff == 1.0`: below it, `cutoff · sinc(cutoff · u)` is not zero at integers,
/// phase 0 stops being the identity, and the invariant stops being structural.
struct PolyphaseInterpolationFilter {
    let factor: Int
    let tapsPerPhase: Int
    /// All phases end to end: phase `p`'s taps are `coefficients[p * tapsPerPhase ..< (p+1) * tapsPerPhase]`,
    /// in increasing tap offset `j`, ready for `vDSP_conv` to read directly.
    let coefficients: [Float]
    /// The lowest tap offset. `tapsPerPhase` taps run from here upwards.
    let jMin: Int

    init(factor: Int, tapsPerPhase: Int, beta: Double, cutoff: Double) {
        self.factor = factor
        self.tapsPerPhase = tapsPerPhase
        jMin = 1 - tapsPerPhase / 2
        let halfWidth = Double(tapsPerPhase) / 2

        var built = [Float]()
        built.reserveCapacity(factor * tapsPerPhase)
        for phase in 0 ..< factor {
            // The point being reconstructed sits `delta` of a sample after the position's own sample.
            let delta = Double(phase) / Double(factor)
            var taps = (0 ..< tapsPerPhase).map { index -> Double in
                let j = Double(index + 1 - tapsPerPhase / 2)
                let u = delta - j
                return cutoff * Self.sinc(cutoff * u) * Self.kaiser(u / halfWidth, beta: beta)
            }
            // Unit sum per phase: preserves DC gain and removes the window's own residual ripple.
            // Phase 0's taps already sum to exactly 1 (they are a delta), so this leaves the identity
            // untouched — the invariant above survives normalisation rather than depending on skipping it.
            let sum = taps.reduce(0, +)
            if sum != 0 { taps = taps.map { $0 / sum } }
            built.append(contentsOf: taps.map { Float($0) })
        }
        coefficients = built
    }

    /// One phase's taps, in increasing tap offset. For tests and for reading; the hot path indexes
    /// `coefficients` directly.
    func phase(_ index: Int) -> [Float] {
        guard index >= 0, index < factor else { return [] }
        return Array(coefficients[index * tapsPerPhase ..< (index + 1) * tapsPerPhase])
    }

    /// `sin(πu)/(πu)`, with its **exact** values at integer arguments used as such rather than
    /// approximated. See the type's own note: the identity of phase 0 depends on this branch.
    static func sinc(_ u: Double) -> Double {
        if u == u.rounded() { return u == 0 ? 1 : 0 }
        return sin(.pi * u) / (.pi * u)
    }

    /// Kaiser window over `r ∈ [-1, 1]`, zero outside.
    static func kaiser(_ r: Double, beta: Double) -> Double {
        guard abs(r) <= 1 else { return 0 }
        return besselI0(beta * (1 - r * r).squareRoot()) / besselI0(beta)
    }

    /// Zeroth-order modified Bessel function by its series. Converges well inside 60 terms for the β
    /// this filter uses, and stops early once a term cannot move the sum.
    static func besselI0(_ x: Double) -> Double {
        var sum = 1.0
        var term = 1.0
        let half = x / 2
        for k in 1 ... 60 {
            term *= (half / Double(k)) * (half / Double(k))
            sum += term
            if term < sum * 1e-18 { break }
        }
        return sum
    }
}
