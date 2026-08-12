/// A whole file's sample-level signal metrics: peak, RMS, DC offset and a clipped-sample count, per
/// channel and combined across the whole file.
///
/// **DSP-derived, and deliberately not a field of `TechnicalProperties`.** That type states its own
/// boundary — "no DSP" — and every metric here needs a decoded sample to exist. This is its own value
/// type, living beside the inspection report exactly as `WaveformEnvelope` and `Spectrogram` already do:
/// a peer, never a member (ADR-0018).
///
/// ## Linear, not decibels
///
/// Every amplitude here (`peakSample`, `rms`, `dcOffset`) is the domain's own normalized linear scale —
/// the same one `PCMChunk`'s samples already use — not dBFS. A presentation layer converts for display;
/// this type states the measured fact in the units it was measured in, exactly as `TechnicalProperties`
/// stores `sampleRate` in Hz rather than in whatever a UI later renders it as.
///
/// ## Samples beyond `-1...1` are kept, never clamped
///
/// Inherited directly from `PCMChunk`'s own contract: a sample the file genuinely carries beyond full
/// scale is a real fact, and `peakSample` can therefore exceed `1.0`. Limiting it would be a concern of
/// drawing, not of this data — exactly the same reasoning `Spectrogram` and `WaveformBucket` already
/// state for the same situation.
///
/// ## Zero samples is not the same as a computed zero
///
/// A channel that carried no samples at all (`sampleCount == 0`) has no maximum, no mean and no RMS to
/// report — those three are mathematically undefined over an empty set, not honestly zero. `nil`
/// represents exactly that "not computable" case, distinctly from a channel that carried real silence
/// (every sample exactly `0`), whose `peakSample`, `rms` and `dcOffset` are all a genuine, computed
/// `0`. `clippedSampleCount` has no such gap: counting is well-defined over an empty set too, so it is
/// always a plain `Int`, `0` for an empty channel exactly as it would be for a channel with no clipped
/// samples.
///
/// ## The overall values are not an average of the per-channel ones
///
/// `overallRMS` is **not** the mean of `channels.map(\.rms)`, and `overallDCOffset` is not the mean of
/// `channels.map(\.dcOffset)` either — both are computed from the sum and the sum-of-squares across
/// **every sample of every channel combined**, each individual sample weighted equally regardless of
/// which channel it came from. `overallPeakSample` (the maximum of the per-channel maxima) and
/// `overallClippedSampleCount` (the sum of the per-channel counts) are the two overall values that *do*
/// coincide with a simple per-channel combination, because maximum and count are the two operations for
/// which that is exact. See `SignalLevelMetricsAccumulator.finish()` for where these are actually
/// computed, from the accumulator's own running totals rather than by re-deriving them from the already
/// -rounded per-channel values above.
///
/// ## Not `Codable`
///
/// Like `Spectrogram`, it never enters the `schemaVersion` 1 export and is not persisted.
public struct SignalLevelMetrics: Sendable, Equatable {
    /// One channel's own peak, RMS, DC offset and clipped-sample count.
    public struct Channel: Sendable, Equatable {
        /// How many samples this channel's metrics were computed over. `0` is the **only** condition
        /// under which `peakSample`, `rms` and `dcOffset` are `nil`.
        public let sampleCount: Int
        /// Maximum absolute sample value. `nil` iff `sampleCount == 0`.
        public let peakSample: Float?
        /// `sqrt(mean(sample²))` over this channel's samples. `nil` iff `sampleCount == 0`.
        public let rms: Float?
        /// The arithmetic mean of this channel's signed samples. `nil` iff `sampleCount == 0`.
        public let dcOffset: Float?
        /// Count of samples with `|sample| ≥ SignalLevelMetricsAccumulator.clippingThreshold`. Always a
        /// plain count, defined even when `sampleCount == 0` (an empty count is `0`, not absent).
        public let clippedSampleCount: Int

        /// Fails on any combination that could not describe a measured channel.
        ///
        /// Failable rather than throwing, for the reason `WaveformBucket` and
        /// `TruePeakMeasurement.Channel` already state: a channel knows nothing about which file or
        /// stream produced it, so it cannot say *why* the values were wrong. Whoever does know turns the
        /// `nil` into an error carrying that context.
        ///
        /// **This type used to accept anything, and that is how a real defect reached the surface.** An
        /// accumulator whose partial sums overflowed produced `rms == +infinity` and
        /// `dcOffset == NaN` from samples that were individually finite, and nothing between there and
        /// the export refused them. The cause is fixed where it belongs — in the accumulator — and this
        /// guard exists so a future change cannot reintroduce it silently. It is the same guard its two
        /// sibling value types have had all along; the asymmetry was an oversight, not a decision.
        ///
        /// **Values beyond `1.0` are still accepted**, and deliberately: a file genuinely carrying a
        /// sample beyond full scale is a fact this type exists to report, exactly as its own
        /// documentation says. Only the *impossible* is refused — a non-finite value, a negative
        /// maximum-of-magnitudes, a negative root-mean-square, and the two directions of the
        /// `nil`-iff-empty rule.
        public init?(sampleCount: Int, peakSample: Float?, rms: Float?, dcOffset: Float?, clippedSampleCount: Int) {
            guard sampleCount >= 0, clippedSampleCount >= 0, clippedSampleCount <= max(sampleCount, 0) else {
                return nil
            }
            // The rule in both directions. Either half alone would leave a contradictory channel
            // representable: measured-but-unreported, or unmeasured-yet-reported.
            let measured = sampleCount > 0
            guard (peakSample == nil) != measured,
                  (rms == nil) != measured,
                  (dcOffset == nil) != measured else { return nil }
            // A `NaN` or an infinity here would mean something upstream let a broken computation
            // through; `dcOffset` may be negative (it is a signed mean), the other two may not.
            if let peakSample { guard peakSample.isFinite, peakSample >= 0 else { return nil } }
            if let rms { guard rms.isFinite, rms >= 0 else { return nil } }
            if let dcOffset { guard dcOffset.isFinite else { return nil } }

            self.sampleCount = sampleCount
            self.peakSample = peakSample
            self.rms = rms
            self.dcOffset = dcOffset
            self.clippedSampleCount = clippedSampleCount
        }
    }

    /// One entry per channel, in the stream's own channel order.
    public let channels: [Channel]

    /// The maximum of every channel's own `peakSample`. `nil` iff every channel has `sampleCount == 0`.
    public let overallPeakSample: Float?
    /// The RMS over every sample of every channel combined, not an average of the per-channel RMS
    /// values. `nil` iff every channel has `sampleCount == 0`.
    public let overallRMS: Float?
    /// The mean over every sample of every channel combined, not an average of the per-channel DC
    /// offsets. `nil` iff every channel has `sampleCount == 0`.
    public let overallDCOffset: Float?
    /// The sum of every channel's own `clippedSampleCount`.
    public let overallClippedSampleCount: Int

    /// Fails when the parts do not describe a measured stream.
    ///
    /// A stream has at least one channel, so an empty `channels` describes a measurement of nothing and
    /// is refused rather than left to read as a file whose every channel was empty — which is a
    /// different and representable thing. The overall values obey the same `nil`-iff-nothing-was-measured
    /// rule the channels do, and the same finiteness guard, for the same reason.
    public init?(
        channels: [Channel],
        overallPeakSample: Float?,
        overallRMS: Float?,
        overallDCOffset: Float?,
        overallClippedSampleCount: Int
    ) {
        guard !channels.isEmpty, overallClippedSampleCount >= 0 else { return nil }
        let measured = channels.contains { $0.sampleCount > 0 }
        guard (overallPeakSample == nil) != measured,
              (overallRMS == nil) != measured,
              (overallDCOffset == nil) != measured else { return nil }
        if let overallPeakSample { guard overallPeakSample.isFinite, overallPeakSample >= 0 else { return nil } }
        if let overallRMS { guard overallRMS.isFinite, overallRMS >= 0 else { return nil } }
        if let overallDCOffset { guard overallDCOffset.isFinite else { return nil } }

        self.channels = channels
        self.overallPeakSample = overallPeakSample
        self.overallRMS = overallRMS
        self.overallDCOffset = overallDCOffset
        self.overallClippedSampleCount = overallClippedSampleCount
    }
}
