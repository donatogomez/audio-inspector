/// A stable, machine-processable identity for the reconstruction filter a true peak was produced with.
///
/// The `rawValue` **is** the identity — not the Swift type name, not a function name, not a hash, and
/// nothing derived from the machine or the OS the measurement ran on. It is written down so it survives
/// a refactor: renaming the static member below, moving this file, or restructuring the accumulator
/// leaves the recorded identity untouched.
///
/// The shape is the one `WarningCode` already established in this module for exactly this problem: a
/// `RawRepresentable` over `String`, values added as named static members, never spelled free-form at a
/// call site. The `snake_case` spelling follows the same precedent.
///
/// ## What the version in the identity means
///
/// It names a **whole methodology**, not a family. The `v1` below is the design measured in
/// `docs/spikes/2026-08-11-true-peak-methodology-validation.md`: a polyphase FIR of 48 taps per phase,
/// Kaiser β 6.0, cutoff at exactly the original Nyquist, each phase normalised to unit sum, with the
/// signal zero-extended past its first and last sample. **Changing any one of those produces a
/// different measurement and therefore requires a new identity** (`v2`), because two files measured
/// under different designs would otherwise export the same identifier while disagreeing — which is the
/// confusion recording a methodology exists to prevent (ADR-0006, ADR-0019).
///
/// The oversampling factor is deliberately **not** folded in here: ADR-0006 requires the factor and the
/// filter to be recorded as two named things, and unlike this opaque token the factor is a number a
/// reader can actually act on.
public struct TruePeakFilterIdentifier: RawRepresentable, Sendable, Equatable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

public extension TruePeakFilterIdentifier {
    /// The polyphase windowed-sinc design this project measured and adopted.
    ///
    /// **It is not ITU-R BS.1770 Annex 2's own filter** and must never be described as one: those
    /// coefficients were unavailable when the methodology was validated, so this is a filter of the same
    /// family, designed to recorded parameters and checked against analytic ground truth and an
    /// independent R128 implementation (ADR-0019 §6). The identity says which filter ran; it does not
    /// claim conformance to a standard's table.
    static let polyphaseFIRv1 = TruePeakFilterIdentifier(rawValue: "polyphase_fir_v1")
}

/// How a true peak was produced — the methodology that travels with the value.
///
/// ADR-0006 requires the oversampling factor and the filter to be *recorded with the result*, and
/// ADR-0019 decides they live inside the measurement rather than in a report-wide or export-wide
/// location. This is that pair, and no more.
///
/// ## Why it carries an identity rather than the design
///
/// It records **which** methodology ran, never **how to configure one**. The 48 taps per phase, the
/// Kaiser β, the cutoff and the 384 coefficients they generate are the accumulator's own business; a
/// result type that carried them would be a DSP configuration wearing a result's name, and the first
/// consumer to write one back would be inventing a measurement that never happened. The identity above
/// pins all of it, and the spike report is where a reader finds what it stands for.
public struct TruePeakMethod: Sendable, Equatable {
    /// How many points per input sample the reconstruction was evaluated at. `8` for
    /// `polyphaseFIRv1`; a reader can reason about it directly, which is why it is a number here and
    /// not folded into the identifier.
    public let oversamplingFactor: Int
    /// Which reconstruction filter produced the value.
    public let filter: TruePeakFilterIdentifier

    /// Fails only on a factor that is not a positive multiplier.
    ///
    /// **`>= 1`, deliberately not `>= 4`.** A factor of zero or less describes no reconstruction at all
    /// and is arithmetic nonsense, which this type can refuse on its own. ADR-0006's *methodological*
    /// floor of 4× is a different kind of rule: it belongs to whoever chooses the constant — the
    /// accumulator — because a domain value type that policed it would be enforcing a standard it
    /// cannot see the evidence for.
    public init?(oversamplingFactor: Int, filter: TruePeakFilterIdentifier) {
        guard oversamplingFactor >= 1 else { return nil }
        self.oversamplingFactor = oversamplingFactor
        self.filter = filter
    }
}

/// A whole file's **true peak**: the maximum absolute value of the waveform the samples represent,
/// including what it does *between* them — per channel, and for the file as a whole.
///
/// ## Not a sample peak, and not beside one
///
/// `SignalLevelMetrics.peakSample` is the largest **stored sample**: exact, and already reported. This
/// is an **estimate of a reconstruction**, produced by a different method, and it is normally larger.
/// The two live in two types on purpose (ADR-0018's rule applied by ADR-0019): sample peak is a direct
/// reduction over stored values, true peak needs an interpolation filter and has to say which one.
///
/// **The sample peak is deliberately not duplicated here.** The relationship `truePeak >= samplePeak`
/// is a property of the algorithm — it holds because phase 0 of the interpolator is the exact identity,
/// so the stored samples are inside the set the maximum is taken over — and it is demonstrated where
/// that is true, in the accumulator. Storing both numbers in one type would invite a consumer to
/// compare two values this type cannot keep consistent.
///
/// ## Linear, not decibels
///
/// Every value here is the domain's own normalized linear amplitude, full scale `1.0` — the same scale
/// `PCMChunk`, `WaveformBucket` and `SignalLevelMetrics` already use. **dBTP is a presentation unit and
/// appears nowhere in this module.** A file measured at `1.05` reads `+0.42 dBTP` on screen, and the
/// conversion is the interface's job, exactly as `TechnicalProperties` stores hertz rather than
/// `"44.1 kHz"`.
///
/// ## Values beyond full scale are kept, never clamped
///
/// Inherited from `PCMChunk`'s own contract and stated by `SignalLevelMetrics` for the same reason: a
/// reconstruction that genuinely exceeds full scale is the fact this measurement exists to reveal, and
/// limiting it would delete the answer. Only *negative*, infinite and `NaN` values are refused — a
/// maximum of absolute values cannot be negative, and a non-finite one would mean something upstream
/// let a broken sample through.
///
/// ## Zero frames is not a measured zero
///
/// A channel that carried no samples has no maximum: the maximum of an empty set does not exist, and
/// reporting `0` for it would claim the file was measured and found silent. `truePeak` is `nil` for
/// exactly that case and **only** that case, which the initialiser enforces in both directions. A
/// channel that was measured and is genuinely silent reports a real, computed `0`.
///
/// ## The overall value is derived, never stored
///
/// `overallTruePeak` is a computed maximum over the channels, so it **cannot** drift out of step with
/// them — there is no second field for a producer to fill in wrongly, and no initialiser argument for a
/// caller to get wrong. That differs from `SignalLevelMetrics`, which stores its overall values, and the
/// difference is not an inconsistency: `overallRMS` and `overallDCOffset` genuinely are *not* functions
/// of the per-channel results (they come from sums over every sample of every channel), so that type has
/// to carry them. A maximum of maxima **is** the maximum, exactly, so this one does not.
///
/// ## Not `Codable`
///
/// Like `SignalLevelMetrics` and `Spectrogram`, the wire form is built by the export mapper, and this
/// module never learns that JSON exists (ADR-0009). Conforming it would advertise a contract that lives
/// somewhere else.
public struct TruePeakMeasurement: Sendable, Equatable {
    /// One channel's own true peak.
    ///
    /// There is no channel *name* here, and none is inferred: the domain reports a **count** of
    /// channels, never a layout, so nothing may assert a left and a right the file never declared. The
    /// index is the position in `channels`, in the stream's own order.
    public struct Channel: Sendable, Equatable {
        /// How many samples this channel's measurement covered. `0` is the **only** condition under
        /// which `truePeak` is `nil`.
        public let sampleCount: Int
        /// Maximum absolute value of the reconstructed waveform. `nil` **iff** `sampleCount == 0`.
        /// May be `0`, below full scale, exactly full scale, or above it — never clamped.
        public let truePeak: Float?

        /// Fails on any combination that could not describe a measured channel.
        ///
        /// Failable rather than throwing, and for the reason `WaveformBucket` already states: a channel
        /// knows nothing about which file or stream produced it, so it cannot say *why* the values were
        /// wrong. Whoever does know turns the `nil` into an error carrying that context.
        public init?(sampleCount: Int, truePeak: Float?) {
            guard sampleCount >= 0 else { return nil }
            // The rule in both directions. Either half alone would leave a contradictory channel
            // representable: measured-but-unreported, or unmeasured-yet-reported.
            guard (truePeak == nil) == (sampleCount == 0) else { return nil }
            if let truePeak {
                guard truePeak.isFinite, truePeak >= 0 else { return nil }
            }
            self.sampleCount = sampleCount
            self.truePeak = truePeak
        }
    }

    /// One entry per channel, in the stream's own channel order.
    public let channels: [Channel]
    /// The methodology that produced every value above.
    public let method: TruePeakMethod

    /// The maximum of the channels that have a value, or `nil` when none does.
    ///
    /// Derived rather than stored, so it cannot contradict `channels` (see the type's own note). A
    /// channel that carried no samples contributes nothing rather than contributing a zero, so one empty
    /// channel beside a measured one yields the measured one's value — not a maximum dragged down by an
    /// absence. **Never a mean, and never a mixdown**: averaging channels would report a level no
    /// channel reached, and mixing them would synthesise a waveform present in none.
    public var overallTruePeak: Float? {
        channels.compactMap(\.truePeak).max()
    }

    /// Fails when the parts do not describe a measured stream.
    ///
    /// A stream has at least one channel — every producer of one in this project refuses fewer — so an
    /// empty `channels` describes a measurement of nothing and is refused here rather than left to read
    /// as a file whose every channel was empty, which is a different and representable thing.
    public init?(channels: [Channel], method: TruePeakMethod) {
        guard !channels.isEmpty else { return nil }
        self.channels = channels
        self.method = method
    }
}
