/// Why two measurements could not be compared, stripped of the values — for the one place that has
/// none to carry.
///
/// `MeasurementGap` carries this plus whatever survived. They are two types rather than one because
/// `ChannelComparison` genuinely has nothing to keep: when no index was compared there are no
/// per-channel figures to show, and a generic parameter existing only to be empty would be a worse
/// answer than a second name.
public enum MeasurementGapReason: Sendable, Equatable {
    /// The first side had a value; the second had none.
    case secondMissing
    /// The second side had a value; the first had none.
    case firstMissing
    /// Neither side had a value.
    case neitherPresent
    /// Both sides were measured by methods whose numbers do not mean the same thing.
    case methodsDiffer
}

/// Why two measurements could not be compared — **and whatever value survived it.**
///
/// It is `ComparisonGap`'s sibling and deliberately **not** the same type. That one splits five
/// property states so that "both available" has no spelling; this one has a reason that occurs *while*
/// both sides are available — the methods that produced them do not mean the same thing — so the same
/// trick does not apply and pretending it did would be worse than a second type.
///
/// **It carries a reason and values, never a message.** The words a surface uses live in presentation,
/// as they do for `ComparisonGap`.
///
/// ## Why it carries the values at all
///
/// The first shape of this type carried the reason alone, and that lost something real. A pair where the
/// first file measured −24.9 LUFS and the second measured nothing reached the surface with **no number
/// on either side** — so a row about a file that has a loudness printed *"No value"* under it. The
/// sentence was true of the second file and false of the first, and the surface had no honest way to fix
/// it: the value it needed had already been dropped here.
///
/// The alternative was to send both `ReportMeasurements` along beside the comparison so a formatter
/// could look the number up. That reintroduces exactly the defect group 3 was written against — two
/// values and one outcome arriving on screen from two different places, free to belong to two different
/// operations. **The comparison has to be self-sufficient**, so the value travels inside it.
///
/// ## Why each case carries exactly what it does
///
/// A gap that named a missing side while carrying a value for it would be a contradiction, so no case
/// has a field one could go in: `secondMissing` has a first and nothing else, `firstMissing` has a
/// second and nothing else, and `neitherPresent` has none. The state is unrepresentable rather than
/// merely untested.
///
/// `methodsDiffer` is the exception, and it is the only one whose payloads are optional. It is a
/// statement about the two **methodologies** and says nothing about presence — it is equally true when
/// both sides measured and when one of them could not — so whatever it carries cannot contradict it.
public enum MeasurementGap<Value>: Sendable, Equatable where Value: Sendable & Equatable {
    /// The first side had a value; the second had none. The first side's value travels with it.
    case secondMissing(first: Value)
    /// The second side had a value; the first had none.
    case firstMissing(second: Value)
    /// Neither side had a value. **Nothing is carried, and nothing is invented** — a zero here would
    /// manufacture a measurement out of an absence.
    case neitherPresent
    /// Both sides were measured by methods whose numbers do not mean the same thing.
    ///
    /// **This is not a defect of either file**, and a surface must not present it as one. It says the
    /// two numbers are not on the same scale, which is a fact about how they were measured — and both
    /// numbers travel with it, because a reader can still be shown what each file measured.
    case methodsDiffer(first: Value?, second: Value?)

    /// The reason alone, for a caller that only needs to say *why*.
    public var reason: MeasurementGapReason {
        switch self {
        case .secondMissing: .secondMissing
        case .firstMissing: .firstMissing
        case .neitherPresent: .neitherPresent
        case .methodsDiffer: .methodsDiffer
        }
    }

    /// What the first file measured, where it measured anything.
    public var first: Value? {
        switch self {
        case let .secondMissing(value): value
        case .firstMissing, .neitherPresent: nil
        case let .methodsDiffer(value, _): value
        }
    }

    /// What the second file measured, where it measured anything.
    public var second: Value? {
        switch self {
        case .secondMissing, .neitherPresent: nil
        case let .firstMissing(value): value
        case let .methodsDiffer(_, value): value
        }
    }
}

/// What comparing one measured figure across two files establishes.
///
/// `PropertyComparison`'s three cases, for the same reasons (ADR-0017 §2), over a different kind of
/// fact. It is a separate type because its `incomparable` carries `MeasurementGap`, which can express
/// a reason `ComparisonGap` cannot.
///
/// **No ordering, no delta, no ratio, no preferred side** — ADR-0017 §3, inherited unchanged. The one
/// measurement that publishes a difference has its own type, and this is not it.
public enum MeasurementValueComparison<Value>: Sendable, Equatable where Value: Sendable & Equatable {
    /// Both sides carried a value and the values are equal. Carried once, because both sides hold it.
    case same(Value)
    /// Both sides carried a value and the values are not equal.
    case different(first: Value, second: Value)
    /// Nothing was compared — and whichever value existed travels with the reason.
    case incomparable(MeasurementGap<Value>)

    /// The single rule, written once. Two optionals compare only when both are present, and a side that
    /// **is** present keeps its value even when the other is not: the caller has already decided method
    /// compatibility and passes a `methodsDiffer` gap rather than two values.
    init(first: Value?, second: Value?) {
        switch (first, second) {
        case let (.some(a), .some(b)): self = a == b ? .same(a) : .different(first: a, second: b)
        case let (.some(a), .none): self = .incomparable(.secondMissing(first: a))
        case let (.none, .some(b)): self = .incomparable(.firstMissing(second: b))
        case (.none, .none): self = .incomparable(.neitherPresent)
        }
    }
}

/// One comparison per channel, or the reason there is none.
///
/// **Channels are indices and nothing else.** The pipeline reads channel counts and never labels, so
/// nothing here is left, right or centre, and no layout is inferred (ADR-0019, ADR-0023).
public enum ChannelComparison<Comparison>: Sendable, Equatable where Comparison: Sendable & Equatable {
    /// One entry per channel index, the two files carrying the same number of channels.
    case byIndex([Comparison])
    /// The two files carry different channel counts, so **no index was compared**.
    ///
    /// Deliberately not the intersection. Comparing the first two channels of a stereo file against the
    /// first two of a 5.1 file would assert that index 0 means the same thing in both, which is exactly
    /// the layout claim the pipeline refuses to make. The overall figures still compare.
    case countsDiffer(first: Int, second: Int)
    /// Nothing was compared at all — a side was missing, or the methods differ.
    ///
    /// **The reason alone**, because there are no per-channel figures to keep: this case says no index
    /// was compared, and the overall figures beside it carry whatever survived.
    case incomparable(MeasurementGapReason)
}

/// What comparing two integrated loudness measurements establishes.
///
/// **The one measurement that publishes a difference**, and the only one whose unit permits it: the
/// domain already stores a logarithmic quantity, so `second − first` is a plain subtraction whose
/// result is **LU** — a named unit that *is* a difference. True peak and signal levels store linear
/// amplitudes, so theirs would be a *ratio*, which ADR-0017 §3 excludes by name (ADR-0024 §6).
///
/// The difference is `second − first`, in the order the user supplied the two files. That order exists
/// so a surface can label two columns; it carries no rank, and nothing here derives one. **Nothing
/// interprets the sign** — there is no "louder", no "hotter", no "more compressed", and no member that
/// reduces the pair to one of its members.
public enum LoudnessComparison: Sendable, Equatable {
    /// Both sides measured, compatibly, and the values are equal. The difference would be zero and is
    /// not carried: there is nothing to state.
    case same(Double)
    /// Both sides measured, compatibly, and the values differ.
    case different(first: Double, second: Double, differenceLU: Double)
    /// Nothing was compared — and whichever side measured keeps its value. **No difference is carried
    /// here**: a difference needs two numbers on one scale, and that is exactly what this case says
    /// there are not.
    case incomparable(MeasurementGap<Double>)
}

/// What comparing two programme bandwidth readings establishes.
///
/// **Never an equality of hertz.** A reading is the centre of the highest qualifying bin and
/// `resolution` is the bin width, so each reading names an observable cell `[f − r/2, f + r/2]`. Two
/// readings are *not distinguished by the analysis* exactly when those cells overlap:
///
///     | f₁ − f₂ |  <  ( r₁ + r₂ ) / 2
///
/// Strictly less than: two readings exactly one bin apart on one grid are **separated**, because the
/// method resolved them into different bins. The rule is symmetric, uses only published quantities,
/// invents no tolerance, and holds when the two files analysed on different grids — which they do
/// whenever their sample rates differ, the window being fixed in time.
///
/// **This is not an uncertainty interval and must never be presented as one.** ADR-0023 refuses to
/// publish a bound on where the true extent lies, and this publishes none either: a cell is what the
/// analysis could *resolve*, not where the answer might be. The reading is also biased one way —
/// upward, by the window's leakage — so a symmetric interval would be wrong in shape as well as in
/// kind. The two cases are named for the **instrument**, not for the files: `indistinguishable` says
/// the analysis did not separate them, never that the files are the same.
///
/// **No frequency difference is published.** Printing "+50 Hz" against a 94 Hz grid would assert a
/// precision the grid does not have. Two identical readings appear as `indistinguishable` carrying
/// equal payloads, which is where exact equality shows.
public enum BandwidthReadingComparison: Sendable, Equatable {
    /// The cells overlap: the analysis did not distinguish these two readings at their resolutions.
    case indistinguishable(first: SignificantBandwidth.Channel, second: SignificantBandwidth.Channel)
    /// The cells do not overlap.
    case separated(first: SignificantBandwidth.Channel, second: SignificantBandwidth.Channel)
    /// Nothing was compared — and whichever side produced a reading keeps it, resolution included.
    case incomparable(MeasurementGap<SignificantBandwidth.Channel>)

    /// The rule, applied to two readings already known to come from compatible methods.
    init(first: SignificantBandwidth.Channel, second: SignificantBandwidth.Channel) {
        let separation = abs(first.frequency - second.frequency)
        let halfCells = (first.resolution + second.resolution) / 2
        self = separation < halfCells
            ? .indistinguishable(first: first, second: second)
            : .separated(first: first, second: second)
    }
}

/// Whether two measurements' methods produce numbers that mean the same thing.
///
/// Read from the domain's own identities and **never from a displayed string** (ADR-0024 §4). Each rule
/// is written out rather than derived from a shared helper, because the four are not the same rule.
enum MethodCompatibility {
    /// Both fields must match. An oversampling factor is not a provenance detail — it materially
    /// changes the estimate — and no equivalence between two factors has been measured.
    static func compatible(_ first: TruePeakMethod, _ second: TruePeakMethod) -> Bool {
        first.oversamplingFactor == second.oversamplingFactor && first.filter == second.filter
    }

    /// The algorithm must match, and the pair of weightings must be one this project has **measured**
    /// to produce the same number.
    ///
    /// `LoudnessProductionMatrixTests` reads one signal at 44.1, 48, 88.2, 96 and 192 kHz through the
    /// whole production path and requires the spread to stay within 0.03 LU. 48 kHz runs the published
    /// tables and every other rate runs the rediscretised prototype, so that test crosses exactly this
    /// pair — which is what licenses comparing across it.
    ///
    /// **Written as an explicit pair check rather than "ignore the weighting".** A third weighting
    /// added later is incomparable until someone measures it, instead of being silently admitted.
    static func compatible(_ first: LoudnessMethod, _ second: LoudnessMethod) -> Bool {
        guard first.algorithm == second.algorithm else { return false }
        if first.weighting == second.weighting { return true }
        return demonstratedEquivalentWeightings.contains { pair in
            (pair.0 == first.weighting && pair.1 == second.weighting)
                || (pair.0 == second.weighting && pair.1 == first.weighting)
        }
    }

    /// Unordered pairs, checked in both directions. An array of tuples rather than a `Set`, because
    /// making the identifier `Hashable` for this slice's convenience would change a type this change
    /// has no business changing.
    private static let demonstratedEquivalentWeightings: [(LoudnessWeightingIdentifier, LoudnessWeightingIdentifier)] = [
        (.publishedAt48kHz, .derivedFrom48kHz),
    ]

    /// The identifier alone. It stands for the whole rule set — the prominence threshold, the
    /// persistence criterion and the programme budget — and the window geometry beside it varies **by
    /// design** across rates, the window being fixed in time. The differing grids are absorbed by the
    /// cell rule, not by refusing to compare.
    static func compatible(_ first: SignificantBandwidthMethod, _ second: SignificantBandwidthMethod) -> Bool {
        first.identifier == second.identifier
    }
}

/// The four signal-level figures, compared. **Four separate facts, never one outcome**: peak, RMS, DC
/// offset and a clipped-sample count are different quantities in different units, and a single verdict
/// over them would have to pick a rule for the worst-fitting of the four.
///
/// **RMS is compared as a level and nothing more.** "Different RMS" is not "more compressed"; that is an
/// inference with a threshold and belongs to Findings.
public struct SignalLevelFiguresComparison: Sendable, Equatable {
    public let peakSample: MeasurementValueComparison<Float>
    public let rms: MeasurementValueComparison<Float>
    public let dcOffset: MeasurementValueComparison<Float>
    public let clippedSampleCount: MeasurementValueComparison<Int>
}

/// Signal level metrics compared: the whole-file figures, and the same four per channel.
///
/// **No method gate.** These are a direct reduction over the stored samples, with no methodology to
/// disagree about, so two measurements compare whenever both exist.
public struct SignalLevelsComparison: Sendable, Equatable {
    public let overall: SignalLevelFiguresComparison
    public let channels: ChannelComparison<SignalLevelFiguresComparison>
}

/// True peak compared: the derived overall maximum, and the per-channel estimates.
///
/// **No difference and no ratio.** The stored value is a linear amplitude; the difference a reader
/// would want is a decibel one, which is a ratio of the stored values — the thing ADR-0017 §3 names.
/// Both values are shown in their own unit and the type does not subtract them.
public struct TruePeakComparison: Sendable, Equatable {
    public let overall: MeasurementValueComparison<Float>
    public let channels: ChannelComparison<MeasurementValueComparison<Float>>
}

/// Programme bandwidth compared: the overall reading, and the per-channel readings, each on the cell
/// rule rather than on equality of hertz.
public struct ProgrammeBandwidthComparison: Sendable, Equatable {
    public let overall: BandwidthReadingComparison
    public let channels: ChannelComparison<BandwidthReadingComparison>
}

/// What comparing the measurements of two inspected files establishes.
///
/// A **sibling** of `FileComparison`, never an extension of it. That type is derived from two reports
/// and cannot be assembled, which is its whole integrity argument; measurements do not live in a report
/// and never will (ADR-0018), so folding them in would mean widening its initialiser to accept values
/// it cannot derive. A surface may present the two together; the domain keeps them apart.
///
/// ## Derived, never assembled
///
/// The only way to build one is from **two settled measurement bundles**. Declaring this initialiser
/// suppresses the memberwise one that would otherwise accept arbitrary results — the same mechanism
/// `FileComparison` uses, for the same reason.
///
/// ## Its input carries no lifecycle
///
/// `ReportMeasurements` holds four optionals where `nil` means *nothing to compare*. Loading, absence,
/// failure and cancellation are collapsed to `nil` by the feature **before** this type sees them, as
/// the export path already does it. So there is no error case here, nothing to await, and no way to
/// confuse *"this measurement failed on this run"* with *"these two files differ"*.
///
/// ## What it cannot express
///
/// **No aggregate of any kind** — no score, no similarity, no confidence, no count of differences, no
/// `allSame`. ADR-0017's reasoning applies verbatim: *"every comparable measurement agreed"* and *"the
/// two files are the same"* are different statements, and one bit cannot hold both.
///
/// **No conclusion about the audio.** Nothing here says whether the two files hold the same master,
/// whether one is a remaster, transcode, upsample or lossy source, which has more dynamic range, or
/// which is worth keeping. Those need evidence, alternatives and a confidence level, and are the
/// Findings capability's; this type is a producer of facts for it and provides no field in which such
/// a conclusion could be written.
///
/// **No ordering and no preferred side.** `first` and `second` are the order the user supplied them.
public struct MeasurementComparison: Sendable, Equatable {
    public let signalLevels: SignalLevelsComparison
    public let truePeak: TruePeakComparison
    public let loudness: LoudnessComparison
    public let programmeBandwidth: ProgrammeBandwidthComparison

    /// Compares two settled measurement bundles. Pure, total and deterministic: no port, no I/O, no
    /// `URL`, no framework, nothing to await and nothing that can fail.
    public init(first: ReportMeasurements, second: ReportMeasurements) {
        signalLevels = Self.compareSignalLevels(first.signalLevelMetrics, second.signalLevelMetrics)
        truePeak = Self.compareTruePeak(first.truePeak, second.truePeak)
        loudness = Self.compareLoudness(first.loudness, second.loudness)
        programmeBandwidth = Self.compareBandwidth(first.programmeBandwidth, second.programmeBandwidth)
    }
}

// MARK: - The four rules, each written out because the four are not the same rule

private extension MeasurementComparison {
    /// Why no index was compared, from which side had a measurement at all.
    ///
    /// **The reason without the values**, because `ChannelComparison` has none to keep — the overall
    /// figures beside it carry whatever survived, each one already knowing its own.
    static func channelReason<A, B>(_ first: A?, _ second: B?) -> MeasurementGapReason {
        switch (first, second) {
        case (.some, .some): .neitherPresent // unreachable: the caller has already returned
        case (.some, .none): .secondMissing
        case (.none, .some): .firstMissing
        case (.none, .none): .neitherPresent
        }
    }

    static func figures(
        _ first: SignalLevelMetrics.Channel?, _ second: SignalLevelMetrics.Channel?
    ) -> SignalLevelFiguresComparison {
        SignalLevelFiguresComparison(
            peakSample: MeasurementValueComparison(first: first?.peakSample, second: second?.peakSample),
            rms: MeasurementValueComparison(first: first?.rms, second: second?.rms),
            dcOffset: MeasurementValueComparison(first: first?.dcOffset, second: second?.dcOffset),
            clippedSampleCount: MeasurementValueComparison(
                first: first?.clippedSampleCount, second: second?.clippedSampleCount
            )
        )
    }

    static func compareSignalLevels(
        _ first: SignalLevelMetrics?, _ second: SignalLevelMetrics?
    ) -> SignalLevelsComparison {
        // **Optional chaining spells all four states, so the whole-metric guard is gone.** It used to
        // stamp one reason across the four figures and drop every number with it; each figure now
        // decides for itself, and a file that measured keeps what it measured.
        let overall = SignalLevelFiguresComparison(
            peakSample: MeasurementValueComparison(
                first: first?.overallPeakSample, second: second?.overallPeakSample
            ),
            rms: MeasurementValueComparison(first: first?.overallRMS, second: second?.overallRMS),
            dcOffset: MeasurementValueComparison(
                first: first?.overallDCOffset, second: second?.overallDCOffset
            ),
            clippedSampleCount: MeasurementValueComparison(
                first: first?.overallClippedSampleCount, second: second?.overallClippedSampleCount
            )
        )
        guard let a = first, let b = second else {
            return SignalLevelsComparison(
                overall: overall, channels: .incomparable(channelReason(first, second))
            )
        }
        guard a.channels.count == b.channels.count else {
            return SignalLevelsComparison(
                overall: overall,
                channels: .countsDiffer(first: a.channels.count, second: b.channels.count)
            )
        }
        return SignalLevelsComparison(
            overall: overall,
            channels: .byIndex(zip(a.channels, b.channels).map { figures($0, $1) })
        )
    }

    static func compareTruePeak(
        _ first: TruePeakMeasurement?, _ second: TruePeakMeasurement?
    ) -> TruePeakComparison {
        guard let a = first, let b = second else {
            return TruePeakComparison(
                overall: MeasurementValueComparison(
                    first: first?.overallTruePeak, second: second?.overallTruePeak
                ),
                channels: .incomparable(channelReason(first, second))
            )
        }
        guard MethodCompatibility.compatible(a.method, b.method) else {
            // Both files measured; the two numbers are simply not on one scale. They travel with the
            // gap, because a reader can still be shown what each file measured.
            return TruePeakComparison(
                overall: .incomparable(
                    .methodsDiffer(first: a.overallTruePeak, second: b.overallTruePeak)
                ),
                channels: .incomparable(.methodsDiffer)
            )
        }
        let overall = MeasurementValueComparison(first: a.overallTruePeak, second: b.overallTruePeak)
        guard a.channels.count == b.channels.count else {
            return TruePeakComparison(
                overall: overall, channels: .countsDiffer(first: a.channels.count, second: b.channels.count)
            )
        }
        return TruePeakComparison(
            overall: overall,
            channels: .byIndex(zip(a.channels, b.channels).map {
                MeasurementValueComparison(first: $0.truePeak, second: $1.truePeak)
            })
        )
    }

    static func compareLoudness(
        _ first: LoudnessMeasurement?, _ second: LoudnessMeasurement?
    ) -> LoudnessComparison {
        guard let a = first, let b = second else {
            switch (first, second) {
            case let (.some(x), .none): return .incomparable(.secondMissing(first: x.integratedLoudness))
            case let (.none, .some(y)): return .incomparable(.firstMissing(second: y.integratedLoudness))
            default: return .incomparable(.neitherPresent)
            }
        }
        guard MethodCompatibility.compatible(a.method, b.method) else {
            return .incomparable(
                .methodsDiffer(first: a.integratedLoudness, second: b.integratedLoudness)
            )
        }
        guard a.integratedLoudness != b.integratedLoudness else { return .same(a.integratedLoudness) }
        // `second − first`, in the order the user supplied the files. LUFS is already logarithmic, so
        // this is a plain subtraction and the result is LU. Nothing is converted and nothing is rounded.
        return .different(
            first: a.integratedLoudness,
            second: b.integratedLoudness,
            differenceLU: b.integratedLoudness - a.integratedLoudness
        )
    }

    static func compareBandwidth(
        _ first: SignificantBandwidth?, _ second: SignificantBandwidth?
    ) -> ProgrammeBandwidthComparison {
        guard let a = first, let b = second else {
            return ProgrammeBandwidthComparison(
                overall: reading(first?.overall, second?.overall),
                channels: .incomparable(channelReason(first, second))
            )
        }
        guard MethodCompatibility.compatible(a.method, b.method) else {
            return ProgrammeBandwidthComparison(
                overall: .incomparable(.methodsDiffer(first: a.overall, second: b.overall)),
                channels: .incomparable(.methodsDiffer)
            )
        }
        let overall = reading(a.overall, b.overall)
        guard a.channels.count == b.channels.count else {
            return ProgrammeBandwidthComparison(
                overall: overall, channels: .countsDiffer(first: a.channels.count, second: b.channels.count)
            )
        }
        return ProgrammeBandwidthComparison(
            overall: overall, channels: .byIndex(zip(a.channels, b.channels).map { reading($0, $1) })
        )
    }

    /// A channel that carried no reading stays absent. **It is never a reading of 0 Hz** — zero is not a
    /// bandwidth, and substituting one would manufacture a fact out of an absence.
    static func reading(
        _ first: SignificantBandwidth.Channel?, _ second: SignificantBandwidth.Channel?
    ) -> BandwidthReadingComparison {
        switch (first, second) {
        case let (.some(a), .some(b)): return BandwidthReadingComparison(first: a, second: b)
        case let (.some(a), .none): return .incomparable(.secondMissing(first: a))
        case let (.none, .some(b)): return .incomparable(.firstMissing(second: b))
        case (.none, .none): return .incomparable(.neitherPresent)
        }
    }
}
