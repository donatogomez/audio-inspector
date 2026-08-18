/// A stable, machine-processable identity for the loudness algorithm a value was produced with.
///
/// The `rawValue` **is** the identity — not the Swift type name, not a hash, and nothing derived from
/// the machine the measurement ran on. The shape is the one `WarningCode` established in this module and
/// `TruePeakFilterIdentifier` reused: a `RawRepresentable` over `String`, values added as named static
/// members, never spelled free-form at a call site, `snake_case`.
///
/// ## What the version in the identity means
///
/// It names a **whole methodology**, so that **the same identifier implies the same number**. `v1` below
/// is ITU-R BS.1770-5 Annex 1 as this project implements it: 400 ms gating blocks overlapping by 75 %,
/// a 100 ms hop, an absolute gate at −70 LKFS applied to the channel-weighted block loudness with a
/// strict inequality, a relative gate 10 LU below the absolutely-gated loudness with both conditions
/// surviving into the final set, means taken over **energies** and converted afterwards, the −0.691
/// conversion offset, channel weights of 1.0, and an incomplete trailing block discarded rather than
/// padded.
///
/// **Changing any one of those requires `v2`**, because two files measured under different rules would
/// otherwise carry the same identifier while disagreeing — which is the confusion recording a
/// methodology exists to prevent (ADR-0006, ADR-0022).
///
/// The **filter's provenance is deliberately not folded in here**: it varies per file with the sample
/// rate while everything above stays fixed, and a reader can act on it. It is a separate identity for
/// the same reason `TruePeakMethod` keeps its oversampling factor out of its filter's identifier.
public struct LoudnessAlgorithmIdentifier: RawRepresentable, Sendable, Equatable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

public extension LoudnessAlgorithmIdentifier {
    /// Integrated loudness as ITU-R BS.1770-5 Annex 1 defines it.
    ///
    /// The revision is part of the identity rather than a field beside it. Separating them would make a
    /// state representable that this project would never intend — an algorithm identifier naming one
    /// revision's rules while a neighbouring field named a different revision — and the revision is not
    /// something a consumer can vary independently of the rules it defines.
    static let integratedBS1770v1 = LoudnessAlgorithmIdentifier(
        rawValue: "itu_r_bs1770_5_integrated_v1"
    )
}

/// Where the K-weighting filter's coefficients came from.
///
/// This exists because **BS.1770-5 publishes coefficients for 48 kHz alone** and asks every other rate
/// merely to *match that frequency response*, without publishing a prototype, a per-rate table, a
/// discretisation method or a tolerance (ADR-0022 §3). So a measurement at the published rate and one at
/// any other rate are produced by filters of different provenance, and that difference travels with the
/// value rather than being inferred from a sample rate this type does not carry.
///
/// It is a separate identity from the algorithm's, not a second version of it: the blocks, the gates and
/// the conversion are the same either way, and collapsing the two would leave a reader unable to see
/// that everything except the filter's origin was identical.
///
/// **It is not a conformance level and must never be read as one.** It records where numbers came from,
/// which is a fact; whether that amounts to conformance is a judgement, and no value type is in a
/// position to make it.
public struct LoudnessWeightingIdentifier: RawRepresentable, Sendable, Equatable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

public extension LoudnessWeightingIdentifier {
    /// The coefficients printed in ITU-R BS.1770-5 Annex 1, Tables 1 and 2, used at the 48 kHz they are
    /// published for. Transcribed, never re-derived or refitted.
    static let publishedAt48kHz = LoudnessWeightingIdentifier(
        rawValue: "itu_r_bs1770_5_tables_1_2_48k"
    )
}

/// How a loudness value was produced — the methodology that travels with it.
///
/// ADR-0006 requires the constants a measurement depends on to be recorded *with the result*, and
/// ADR-0019 decided for true peak that they live inside the measurement rather than in a report-wide
/// location. This is the loudness pair, and no more.
///
/// ## Why it carries identities rather than the constants
///
/// It records **which** methodology ran, never **how to configure one**. The block length, the hop, both
/// gate thresholds and the conversion offset are fixed by `algorithm`; carrying them as fields would put
/// contradictory states within reach — a block length that disagreed with the identifier naming it —
/// which this type could not police, because it cannot see the evidence the constants came from. The
/// identifiers pin all of it, and `docs/spikes/2026-08-18-loudness-measurement-validation.md` Part A is
/// where a reader finds what they stand for.
///
/// ## What is deliberately absent
///
/// **No conformance, compliance, certification or "EBU Mode" field, and no target level.** A measurement
/// cannot certify itself: conformance is a claim about a process, asserted by whoever holds the evidence,
/// and agreement with an independent meter is *test-time* evidence about an implementation rather than a
/// property of a file. Recording "compliant" here would also be the one thing this project's reports
/// never do — turn a measurement into a verdict (ADR-0022 §12). What is recorded is what ran; what that
/// is worth is the reader's to decide.
public struct LoudnessMethod: Sendable, Equatable {
    /// Which algorithm produced the value.
    public let algorithm: LoudnessAlgorithmIdentifier
    /// Where the K-weighting filter's coefficients came from.
    public let weighting: LoudnessWeightingIdentifier

    /// Not failable, unlike `TruePeakMethod`'s: that one validates a numeric factor, and there is no
    /// number here to be nonsense. Two opaque identities have no contradictory combination this type
    /// could detect, and an initialiser that can never fail should not pretend otherwise.
    public init(algorithm: LoudnessAlgorithmIdentifier, weighting: LoudnessWeightingIdentifier) {
        self.algorithm = algorithm
        self.weighting = weighting
    }
}

/// A whole programme's **integrated loudness**, in LUFS.
///
/// ## What the value is, and what it is not
///
/// `integratedLoudness` is the gated mean loudness of the programme as ITU-R BS.1770-5 Annex 1 defines
/// it, in **LUFS** — the unit EBU R 128 names and declares equivalent to BS.1770's LKFS. It is
/// specifically **not**:
///
/// - **linear energy.** True peak stores linear because dBTP is a *presentation* of a linear peak; here
///   the normative quantity **is** the logarithmic one, and converting at the surface would invent a
///   unit the standard does not use and move the conversion offset somewhere it cannot be tested
///   (ADR-0022 §5). This is deliberately not the rule ADR-0019 set, and the difference is the point.
/// - **RMS**, which weights 40 Hz and 4 kHz alike; this is frequency-weighted and gated.
/// - **dBFS**, which describes stored sample amplitude rather than perceived programme level.
/// - **momentary or short-term loudness**, which are ungated sliding-window *meter* readings. Their
///   absence here is not a missing field: they are different quantities that would each need a stated
///   reduction — a maximum, a series — before they meant anything in a static report.
///
/// ## One value, and no per-channel breakdown
///
/// There is no per-channel integrated loudness, because the channels are combined before the quantity
/// exists — which is why this type has nothing like `TruePeakMeasurement.Channel`. For the same reason
/// it carries **neither a channel count nor a sample rate**: both describe the *file*, are already
/// reported by the technical properties, and would be a second description this type could not keep
/// consistent with the first. The only methodological consequence a sample rate has is which
/// coefficients were used, and `method.weighting` says that directly.
///
/// ## Finite, and otherwise unbounded
///
/// The only invariant is that the value is finite. **No range is imposed**, deliberately: BS.1770-5
/// states none, a programme above full scale legitimately reads above zero, and the −70 LKFS gate is a
/// threshold on *blocks*, never a floor on the result. That the gated mean necessarily exceeds −70 is a
/// property of the algorithm, demonstrated where it is true — in the accumulator — rather than enforced
/// here, exactly as `TruePeakMethod` declines to police ADR-0006's 4× oversampling floor.
///
/// ## Absence is not a value
///
/// A programme shorter than one gating block forms no block, and one whose every block falls below the
/// absolute gate leaves the gated set empty; BS.1770-5 eq. (7) divides by the size of that set, so both
/// are **undefined**. Neither is representable here, and that is the design: the absence lives in the
/// optional a producer returns, and the *cause* lives with whoever knows it. **−70 is the gate, never a
/// result**, and the reference implementation's −70.000 floor is a display convention this project does
/// not copy.
///
/// ## Not `Codable`
///
/// Like `SignalLevelMetrics`, `TruePeakMeasurement` and `Spectrogram`, the wire form is built by the
/// export mapper and this module never learns that JSON exists (ADR-0009).
public struct LoudnessMeasurement: Sendable, Equatable {
    /// The programme's integrated loudness, in LUFS. Finite; may be negative, zero or positive.
    public let integratedLoudness: Double
    /// The methodology that produced it.
    public let method: LoudnessMethod

    /// Fails on a value that could not describe a measurement.
    ///
    /// Failable rather than throwing, for the reason `WaveformBucket` and `TruePeakMeasurement.Channel`
    /// already state: this type knows nothing about which file produced it, so it cannot say *why* the
    /// value was wrong. Whoever does know turns the `nil` into an outcome carrying that context.
    ///
    /// `isFinite` refuses `NaN` — signalling included — and both infinities in one condition. It is the
    /// guard `SignalLevelMetrics` had to be repaired to include, kept here from the start.
    public init?(integratedLoudness: Double, method: LoudnessMethod) {
        guard integratedLoudness.isFinite else { return nil }
        self.integratedLoudness = integratedLoudness
        self.method = method
    }
}

public extension LoudnessWeightingIdentifier {
    /// Coefficients this project derived, to reproduce at another sample rate the response the published
    /// 48 kHz section provides.
    ///
    /// The construction: recover the analogue section each published one is the bilinear transform of,
    /// then re-discretise it at the target rate, prewarping each section at its own natural frequency.
    /// **BS.1770-5 publishes none of that** — not the prototype, not the transform, not a tolerance — so
    /// this identity names *our* method, and the name says the method rather than the goal, because two
    /// different constructions could both claim to match a response.
    ///
    /// **Changing the construction requires `v2`**, on the same rule the algorithm identity follows: the
    /// same identity must imply the same number.
    static let derivedFrom48kHz = LoudnessWeightingIdentifier(
        rawValue: "itu_r_bs1770_5_48k_prototype_rediscretised_v1"
    )
}
