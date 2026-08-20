import AudioInspectorDomain

/// What comparing one measured figure established, **in the reader's terms**.
///
/// A closed presentation enum decoupled from the domain's, exactly as `ComparisonOutcomeDisplay` is
/// decoupled from `PropertyComparison`: renaming a domain case can never silently change what a person
/// reads. It carries no value, because both values are already on the row.
///
/// **Bandwidth gets two cases of its own rather than borrowing `same`/`different`,** and that is the
/// whole point of the type. Two bandwidth readings are never *the same file's edge* — they are two
/// cells on two grids, and the only thing the analysis can say is whether it separated them. Calling
/// that `Same` would turn a statement about the instrument into a statement about the files.
enum MeasurementOutcomeDisplay: Equatable {
    case same
    case different
    /// The two readings' cells overlap: the analysis did not tell them apart at its own resolutions.
    case indistinguishable
    /// The two readings' cells do not overlap.
    case separated
    /// Carries the reason, which always names what was missing or why the numbers are not on one scale.
    case notComparable(reason: String)

    /// Plain words, and deliberately flat ones.
    ///
    /// **No direction anywhere** — not higher, lower, louder, quieter, hotter, cleaner, better or worse.
    /// Two measurements differing is an observation; the moment a word implies a direction the surface
    /// has started ranking two files (ADR-0017 §3, inherited by ADR-0024 §1).
    ///
    /// **And bandwidth's two words are about the grid.** *"Indistinguishable at these resolutions"*
    /// says the analysis could not separate them, never that the files are alike; *"Separated at these
    /// resolutions"* says it did, never that one is filtered, upsampled or from a different source.
    var text: String {
        switch self {
        case .same: "Same"
        case .different: "Different"
        case .indistinguishable: "Indistinguishable at these resolutions"
        case .separated: "Separated at these resolutions"
        case let .notComparable(reason): reason
        }
    }

    /// Whether the outcome is worth a quieter treatment. **Never a colour that means good or bad** —
    /// the text carries the whole meaning, and this only keeps an explanation from shouting. It is
    /// deliberately independent of `same`/`different` and of any difference's sign.
    var isSecondary: Bool {
        if case .notComparable = self { return true }
        return false
    }
}

/// One file's side of one measurement row: the value it carried, and the per-channel or per-grid detail
/// worth saying beneath it.
///
/// `value` is `nil` exactly when the comparison carried no value for this side — which is every
/// `incomparable` case, because the domain's gap says *what happened* and never smuggles a surviving
/// number out with it. **A `nil` is rendered as an absence and never as a zero**: absence and a
/// measured zero are different answers, and digital silence really does measure 0.0 dBTP.
struct MeasurementSideDisplay: Equatable {
    let value: String?
    let detail: String?

    static let noValue = MeasurementSideDisplay(value: nil, detail: nil)

    /// One side as a phrase, for an assistive reader.
    var spoken: String {
        guard let value else { return MeasurementComparisonCopy.noValue }
        return [value, detail].compactMap { $0 }.joined(separator: ", ")
    }
}

/// One measurement, as both files reported it, plus what comparing them established — and, on exactly
/// one row, the difference.
///
/// **`difference` exists on integrated loudness and nowhere else** (ADR-0024 §6, task 6.3). LUFS is
/// already logarithmic, so subtracting two of them is a plain subtraction whose result is a named unit.
/// True peak and the signal levels store linear amplitudes, so theirs would be a *ratio*; bandwidth's
/// would print a hertz distinction its grid cannot make. The field is `nil` for all of them, and the
/// formatter never populates it.
struct MeasurementRowDisplay: Equatable, Identifiable {
    let name: String
    let first: MeasurementSideDisplay
    let second: MeasurementSideDisplay
    let outcome: MeasurementOutcomeDisplay
    /// `second − first`, in LU. Loudness only, and absent when the two are equal — the domain does not
    /// carry a zero difference, because there is nothing to state.
    let difference: String?
    /// Why the two columns can read identically while the outcome says the two were told apart — or the
    /// other way round. `nil` whenever the display and the outcome agree, which is most of the time.
    ///
    /// **It exists because the honest formatters make it possible.** A DC offset of 1·10⁻¹⁴ and one of
    /// −3·10⁻¹⁴ both print as `0.0000`, and two bandwidth readings one bin apart both print as
    /// `16.1 kHz` because no digit finer than a bin may be shown (ADR-0023). Without this line the row
    /// would read as a contradiction and a reader would rightly suspect a defect. The fix is **never**
    /// to print another digit: that would claim a precision the measurement does not have.
    let precisionNote: String?

    var id: String { name }

    /// One sentence in the order the row reads: the measurement, each file's value, the outcome, and
    /// the difference where there is one. **Nothing here characterises either file**, and the sign of
    /// the difference is spoken exactly as it is printed.
    var accessibilityLabel: String {
        var sentence = "\(name). \(MeasurementComparisonCopy.firstFile), \(first.spoken). "
            + "\(MeasurementComparisonCopy.secondFile), \(second.spoken). \(outcome.text)"
        if !sentence.hasSuffix(".") { sentence += "." }
        if let difference {
            sentence += " \(MeasurementComparisonCopy.differenceLabel), \(difference)."
        }
        if let precisionNote {
            sentence += " \(precisionNote)"
        }
        return sentence
    }
}

/// One metric's rows, and the one structural note that belongs to the metric rather than to a row.
struct MeasurementBlockDisplay: Equatable, Identifiable {
    let title: String
    let rows: [MeasurementRowDisplay]
    /// Why the per-channel figures were not compared, when they were not. `nil` when they were, or when
    /// the metric has no channels at all.
    let channelNote: String?

    var id: String { title }
}

/// Turns a `MeasurementComparison` into presentable blocks. Pure and deterministic, so it is unit-tested
/// with no view at all — the rule `ComparisonFormatter` already follows.
///
/// **It never decides comparability.** Every outcome below is a translation of a case the domain already
/// chose: no threshold is applied here, no tolerance invented, no method re-read. The one thing this
/// file owns is words.
enum MeasurementComparisonFormatter {

    /// The four metrics, in **the report's own order** — signal levels, true peak, integrated loudness,
    /// programme bandwidth (task 6.1). Not reordered by importance, and specifically not with loudness
    /// first because it is the one carrying a difference.
    ///
    /// Each title is taken from the section's own `Copy.title`, so a row here and a section above can
    /// never drift into two names for one measurement.
    static func blocks(for comparison: MeasurementComparison) -> [MeasurementBlockDisplay] {
        [
            signalLevels(comparison.signalLevels),
            truePeak(comparison.truePeak),
            loudness(comparison.loudness),
            bandwidth(comparison.programmeBandwidth),
        ]
    }

    // MARK: - Signal levels

    /// Four rows, never one outcome over them: peak, RMS, DC offset and a clipped-sample count are
    /// different quantities in different units. **RMS is a level and nothing more** — a differing RMS is
    /// not "more compressed", which is an inference with a threshold and is Findings' work.
    private static func signalLevels(_ comparison: SignalLevelsComparison) -> MeasurementBlockDisplay {
        let channels = channelValues(comparison.channels)
        return MeasurementBlockDisplay(
            title: SignalLevelMetricsCopy.title,
            rows: [
                row(
                    name: MeasurementComparisonCopy.peakSample,
                    comparison.overall.peakSample,
                    format: HumanFormat.decibelsFullScale,
                    detail: channels.map { perChannel($0.map(\.peakSample), HumanFormat.decibelsFullScale) }
                ),
                row(
                    name: MeasurementComparisonCopy.rms,
                    comparison.overall.rms,
                    format: HumanFormat.decibelsFullScale,
                    detail: channels.map { perChannel($0.map(\.rms), HumanFormat.decibelsFullScale) }
                ),
                row(
                    name: MeasurementComparisonCopy.dcOffset,
                    comparison.overall.dcOffset,
                    format: HumanFormat.linearOffset,
                    detail: channels.map { perChannel($0.map(\.dcOffset), HumanFormat.linearOffset) }
                ),
                row(
                    name: MeasurementComparisonCopy.clippedSamples,
                    comparison.overall.clippedSampleCount,
                    format: count,
                    detail: channels.map { perChannel($0.map(\.clippedSampleCount), count) }
                ),
            ],
            channelNote: channelNote(comparison.channels)
        )
    }

    // MARK: - True peak

    /// One row, and **no difference of any kind**. The stored value is a linear amplitude, so the
    /// decibel difference a reader might want is a *ratio* of the two — the thing ADR-0017 §3 names.
    /// Both values are shown in dBTP and the surface does not subtract them.
    private static func truePeak(_ comparison: TruePeakComparison) -> MeasurementBlockDisplay {
        let channels = channelValues(comparison.channels)
        return MeasurementBlockDisplay(
            title: TruePeakCopy.title,
            rows: [
                row(
                    name: TruePeakCopy.title,
                    comparison.overall,
                    format: HumanFormat.decibelsTruePeak,
                    detail: channels.map { perChannel($0, HumanFormat.decibelsTruePeak) }
                ),
            ],
            channelNote: channelNote(comparison.channels)
        )
    }

    // MARK: - Integrated loudness

    /// The one row that carries a difference, and the only metric whose unit permits one.
    ///
    /// There are **no channels here at all** — the channels are combined before the quantity exists — so
    /// there is no per-channel detail and no channel note, and no field either could occupy.
    private static func loudness(_ comparison: LoudnessComparison) -> MeasurementBlockDisplay {
        let row: MeasurementRowDisplay = switch comparison {
        case let .same(value):
            MeasurementRowDisplay(
                name: LoudnessCopy.title,
                first: side(HumanFormat.loudnessFullScale(value)),
                second: side(HumanFormat.loudnessFullScale(value)),
                outcome: .same,
                // Equal values carry no difference: the domain does not store a zero one, because
                // "0.0 LU" states nothing the word `Same` has not already said.
                difference: nil, precisionNote: nil
            )
        case let .different(first, second, differenceLU):
            MeasurementRowDisplay(
                name: LoudnessCopy.title,
                first: side(HumanFormat.loudnessFullScale(first)),
                second: side(HumanFormat.loudnessFullScale(second)),
                outcome: .different,
                difference: HumanFormat.loudnessDifference(differenceLU),
                precisionNote: precisionNote(
                    .different,
                    HumanFormat.loudnessFullScale(first), HumanFormat.loudnessFullScale(second)
                )
            )
        case let .incomparable(gap):
            MeasurementRowDisplay(
                name: LoudnessCopy.title,
                first: .noValue, second: .noValue,
                outcome: .notComparable(reason: reason(for: gap)),
                difference: nil, precisionNote: nil
            )
        }
        return MeasurementBlockDisplay(title: LoudnessCopy.title, rows: [row], channelNote: nil)
    }

    // MARK: - Programme bandwidth

    /// One row on the cell rule, with each side's **analysis resolution** beneath its value.
    ///
    /// The resolution is shown because the outcome refers to it: *"at these resolutions"* means nothing
    /// unless the reader can see what they are. It is the width of an analysis bin — the grid the answer
    /// is quantised onto — and never an uncertainty, so it is a labelled figure of its own and never a
    /// `±` beside the reading (ADR-0023, the rule `ProgrammeBandwidthCopy.resolutionRow` already states).
    ///
    /// **No frequency difference is published.** Printing "+50 Hz" against a 23 Hz grid would assert a
    /// distinction the grid cannot make.
    private static func bandwidth(_ comparison: ProgrammeBandwidthComparison) -> MeasurementBlockDisplay {
        let row: MeasurementRowDisplay = switch comparison.overall {
        case let .indistinguishable(first, second):
            reading(first, second, outcome: .indistinguishable)
        case let .separated(first, second):
            reading(first, second, outcome: .separated)
        case let .incomparable(gap):
            MeasurementRowDisplay(
                name: ProgrammeBandwidthCopy.title,
                first: .noValue, second: .noValue,
                outcome: .notComparable(reason: reason(for: gap)),
                difference: nil, precisionNote: nil
            )
        }
        return MeasurementBlockDisplay(
            title: ProgrammeBandwidthCopy.title,
            rows: [row],
            channelNote: channelNote(comparison.channels)
        )
    }

    private static func reading(
        _ first: SignificantBandwidth.Channel, _ second: SignificantBandwidth.Channel,
        outcome: MeasurementOutcomeDisplay
    ) -> MeasurementRowDisplay {
        let firstValue = HumanFormat.programmeBandwidth(first.frequency, resolution: first.resolution)
        let secondValue = HumanFormat.programmeBandwidth(second.frequency, resolution: second.resolution)
        return MeasurementRowDisplay(
            name: ProgrammeBandwidthCopy.title,
            first: MeasurementSideDisplay(
                value: firstValue, detail: MeasurementComparisonCopy.resolution(first.resolution)
            ),
            second: MeasurementSideDisplay(
                value: secondValue, detail: MeasurementComparisonCopy.resolution(second.resolution)
            ),
            outcome: outcome,
            difference: nil,
            precisionNote: precisionNote(outcome, firstValue, secondValue)
        )
    }

    // MARK: - The shared shapes

    /// One row from one value comparison. **Total over the three cases with no `default`**: a case added
    /// to the domain fails to compile here rather than falling into a catch-all that says something
    /// vague.
    private static func row<Value>(
        name: String, _ comparison: MeasurementValueComparison<Value>,
        format: (Value) -> String, detail: (first: String, second: String)?
    ) -> MeasurementRowDisplay {
        switch comparison {
        case let .same(value):
            MeasurementRowDisplay(
                name: name,
                first: MeasurementSideDisplay(value: format(value), detail: detail?.first),
                second: MeasurementSideDisplay(value: format(value), detail: detail?.second),
                outcome: .same, difference: nil, precisionNote: nil
            )
        case let .different(first, second):
            MeasurementRowDisplay(
                name: name,
                first: MeasurementSideDisplay(value: format(first), detail: detail?.first),
                second: MeasurementSideDisplay(value: format(second), detail: detail?.second),
                outcome: .different, difference: nil,
                precisionNote: precisionNote(.different, format(first), format(second))
            )
        case let .incomparable(gap):
            MeasurementRowDisplay(
                name: name, first: .noValue, second: .noValue,
                outcome: .notComparable(reason: reason(for: gap)), difference: nil, precisionNote: nil
            )
        }
    }

    /// The line that reconciles an outcome with two columns that read the same — or that read
    /// differently while the analysis says it could not tell them apart.
    ///
    /// **The formatters are the reason this exists, and they are right.** `linearOffset` shows four
    /// decimals because `Float` does not honestly carry more at that magnitude, so two DC offsets of
    /// 10⁻¹⁴ both print as `0.0000`; `programmeBandwidth` rounds to the analysis grid because ADR-0023
    /// forbids a digit finer than a bin, so two readings one bin apart both print as `16.1 kHz`. Left
    /// alone, either row reads as a contradiction. **The answer is a sentence, never another digit.**
    ///
    /// It states the relationship between the display and the measurement and stops there: no magnitude
    /// of the difference, no direction, and nothing about what the difference might mean.
    private static func precisionNote(
        _ outcome: MeasurementOutcomeDisplay, _ first: String?, _ second: String?
    ) -> String? {
        let readAlike = first == second
        switch outcome {
        case .different where readAlike: return MeasurementComparisonCopy.differsBelowThisPrecision
        case .separated where readAlike: return MeasurementComparisonCopy.separatedButRoundsAlike
        case .indistinguishable where !readAlike: return MeasurementComparisonCopy.overlapsButRoundsApart
        default: return nil
        }
    }

    private static func side(_ value: String) -> MeasurementSideDisplay {
        MeasurementSideDisplay(value: value, detail: nil)
    }

    /// The per-channel values of both sides, or `nil` when no index was compared.
    ///
    /// **The channel outcomes are deliberately not rendered.** For the signal levels each index carries
    /// four of them, and reducing those to one word per channel would be an aggregate — the one thing
    /// ADR-0024 refuses. What is shown instead is each side's own per-channel figures, exactly as the
    /// report shows them for a single file, so a reader compares the same way they would there.
    private static func channelValues<Comparison>(
        _ channels: ChannelComparison<Comparison>
    ) -> [Comparison]? {
        guard case let .byIndex(entries) = channels, entries.count > 1 else { return nil }
        return entries
    }

    /// `Channel 1: … · Channel 2: …` for each side — **never `Left`/`Right`**: the pipeline reads a
    /// channel *count* and never a layout, so nothing here may assert a stereo pair the file never
    /// declared (the rule `SignalLevelMetricsCopy` and `TruePeakCopy` already state).
    private static func perChannel<Value>(
        _ comparisons: [MeasurementValueComparison<Value>], _ format: (Value) -> String
    ) -> (first: String, second: String) {
        var firsts: [String] = []
        var seconds: [String] = []
        for (index, comparison) in comparisons.enumerated() {
            let label = "\(MeasurementComparisonCopy.channel) \(index + 1)"
            switch comparison {
            case let .same(value):
                firsts.append("\(label): \(format(value))")
                seconds.append("\(label): \(format(value))")
            case let .different(first, second):
                firsts.append("\(label): \(format(first))")
                seconds.append("\(label): \(format(second))")
            case .incomparable:
                firsts.append("\(label): \(MeasurementComparisonCopy.noValue)")
                seconds.append("\(label): \(MeasurementComparisonCopy.noValue)")
            }
        }
        return (firsts.joined(separator: " · "), seconds.joined(separator: " · "))
    }

    private static func perChannel(
        _ comparisons: [BandwidthReadingComparison]
    ) -> (first: String, second: String) {
        var firsts: [String] = []
        var seconds: [String] = []
        for (index, comparison) in comparisons.enumerated() {
            let label = "\(MeasurementComparisonCopy.channel) \(index + 1)"
            switch comparison {
            case let .indistinguishable(first, second), let .separated(first, second):
                firsts.append("\(label): \(HumanFormat.programmeBandwidth(first.frequency, resolution: first.resolution))")
                seconds.append("\(label): \(HumanFormat.programmeBandwidth(second.frequency, resolution: second.resolution))")
            case .incomparable:
                firsts.append("\(label): \(MeasurementComparisonCopy.noValue)")
                seconds.append("\(label): \(MeasurementComparisonCopy.noValue)")
            }
        }
        return (firsts.joined(separator: " · "), seconds.joined(separator: " · "))
    }

    /// Why the per-channel figures were not compared, when they were not.
    ///
    /// **The only case that gets a note is `countsDiffer`**, and it gets one because the alternative —
    /// silence — would read as an omission. `byIndex` needs none (the figures are there) and
    /// `incomparable` needs none (the row's own outcome already says why).
    static func channelNote<Comparison>(_ channels: ChannelComparison<Comparison>) -> String? {
        guard case let .countsDiffer(first, second) = channels else { return nil }
        return MeasurementComparisonCopy.channelCountsDiffer(first: first, second: second)
    }

    /// **Why nothing could be compared, named from the gap itself** — task 6.4, on ADR-0017 §5's
    /// precedent. A reader must be able to tell *"the methods differ"* from *"this file had no value"*,
    /// and the domain already keeps them apart, so the surface says which.
    ///
    /// **None of these is a failure**, and none of them says so. A comparison that could not be made is
    /// not a comparison that broke: the flow ran, both files were inspected, and one of them simply has
    /// no value to put here.
    static func reason(for gap: MeasurementGap) -> String {
        switch gap {
        case .secondMissing: MeasurementComparisonCopy.secondHasNoValue
        case .firstMissing: MeasurementComparisonCopy.firstHasNoValue
        case .neitherPresent: MeasurementComparisonCopy.neitherHasAValue
        case .methodsDiffer: MeasurementComparisonCopy.methodsDiffer
        }
    }

    private static func count(_ value: Int) -> String {
        value.formatted(.number.locale(HumanFormat.locale))
    }
}

/// The words the measurement comparison uses for everything that is not a formatted number.
///
/// Every state is **said in text**; none is conveyed by a colour, an icon, a badge or an empty area —
/// and nothing at all varies with the sign of the loudness difference (task 6.6).
enum MeasurementComparisonCopy {
    static let title = "Measurements"

    /// What this sub-section is, and — because a table of four measurements is exactly what invites the
    /// assumption — what it is not.
    static let subtitle =
        "What each file's audio measures, side by side. These are measurements of the samples; they do "
            + "not establish where either file came from, how it was produced, or which one to keep."

    static let firstFile = "First file"
    static let secondFile = "Second file"
    static let outcomeColumn = "Comparison"
    static let measurementColumn = "Measurement"
    static let differenceLabel = "Difference"
    static let channel = "Channel"
    static let noValue = "No value"

    static let peakSample = "Peak sample"
    static let rms = "RMS level"
    static let dcOffset = "DC offset"
    static let clippedSamples = "Clipped samples"

    /// Shown while one of the two files is still measuring. The technical comparison is already on
    /// screen above it, complete, which is why this says *these* rather than *the comparison*.
    static let waiting = "Measuring both files…"

    static let firstHasNoValue = "Not comparable — the first file has no value for this."
    static let secondHasNoValue = "Not comparable — the second file has no value for this."
    static let neitherHasAValue = "Not comparable — neither file has a value for this."

    /// **The one reason that occurs while both sides have a value.** It is not a defect of either file
    /// and must never read as one: it says the two numbers are not on the same scale, which is a fact
    /// about how they were measured.
    static let methodsDiffer =
        "Not comparable — the two were measured by different methods, so the numbers are not on the "
            + "same scale."

    /// **Two values that differ by less than the row can show.** It says which of the two the reader is
    /// looking at — a display limit — and deliberately not how large the difference is, which would be
    /// the extra digit the limit exists to withhold.
    static let differsBelowThisPrecision =
        "Both files round to the same figure here; the measurements themselves are not equal."

    /// The bandwidth version: the grid, not the display, is what separated them.
    static let separatedButRoundsAlike =
        "Both readings round to the same figure on this grid; the analysis placed them in different bins."

    /// And the converse, which the same rounding can produce at a bin boundary.
    static let overlapsButRoundsApart =
        "The two readings round to different figures, but their cells overlap, so the analysis did not "
            + "separate them."

    /// Task 6.4's channel half, and the copy the surface needs for `countsDiffer`.
    ///
    /// It says three things and no fourth: the overall figures **were** compared, the per-channel ones
    /// were not, and why. **No layout is named** — not left, not right, not a stereo pair — and neither
    /// count is described as more, fewer, better or worse than the other. Comparing the first two
    /// channels of one file against the first two of another would assert that index 0 means the same
    /// thing in both, which is the one claim the pipeline refuses to make.
    static func channelCountsDiffer(first: Int, second: Int) -> String {
        "Not compared per channel — the files carry \(first) and \(second) channels, so an index does "
            + "not mean the same thing in both. The overall figures above still compare."
    }

    /// One side's analysis resolution, labelled with the report's own name for it so the two never drift.
    static func resolution(_ hertz: Double) -> String {
        "\(ProgrammeBandwidthCopy.resolutionTitle): \(HumanFormat.frequency(hertz))"
    }
}
