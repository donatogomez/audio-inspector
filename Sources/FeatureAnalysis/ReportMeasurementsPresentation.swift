import AudioInspectorDomain

/// The four sample-derived measurements, arranged for one reading surface.
///
/// ## It arranges; it decides nothing
///
/// Every name, value, unit, per-channel breakdown, absence sentence, failure sentence and method
/// sentence below is the one `SignalLevelMetricsCopy`, `TruePeakCopy`, `LoudnessCopy` or
/// `ProgrammeBandwidthCopy` already produces. This type switches on the four presentation enums and
/// hands each one to the copy owner that owns it. It reads no domain value, formats nothing, rounds
/// nothing, converts no unit and holds no state — which is why it is tested with no view at all.
///
/// ## Why it exists
///
/// Without it the view carries four parallel switches, and the section's one promise — that every label
/// sits in one column and every measurement reads the same way — would be four independent
/// implementations of the same layout, free to drift. The four copy owners stay exactly where they are;
/// this only puts what they return into one shape.
enum MeasurementsDisplay {

    /// The two groups, in the report's own order.
    ///
    /// **The grouping is the report's, not this type's.** `ReportView` already orders these four by the
    /// distinction the group names state: the signal levels, the true peak and the loudness are its
    /// "level sections", and the programme bandwidth is "the first measurement in the report about
    /// frequency rather than level". `design.md` §3 records why that distinction is written down here
    /// rather than derived — there is no `groups(for:)` for measurements the way there is for
    /// properties.
    static func groups(
        signalLevelMetrics: SignalLevelMetricsPresentation,
        truePeak: TruePeakPresentation,
        loudness: LoudnessPresentation,
        programmeBandwidth: SignificantBandwidthPresentation
    ) -> [MeasurementGroupDisplay] {
        [
            MeasurementGroupDisplay(
                name: MeasurementsCopy.levelGroup,
                measurements: [
                    display(for: signalLevelMetrics),
                    display(for: truePeak),
                    display(for: loudness),
                ]
            ),
            MeasurementGroupDisplay(
                name: MeasurementsCopy.frequencyGroup,
                measurements: [display(for: programmeBandwidth)]
            ),
        ]
    }

    // MARK: - One measurement at a time

    /// Signal levels: four rows when measured, one sentence otherwise. No method is recorded for it, so
    /// it has none to disclose — the field is `nil` rather than a sentence invented to fill it.
    static func display(for presentation: SignalLevelMetricsPresentation) -> MeasurementDisplay {
        MeasurementDisplay(
            title: SignalLevelMetricsCopy.title,
            rows: {
                guard case let .metrics(metrics) = presentation else { return [] }
                return SignalLevelMetricsCopy.rows(for: metrics).map {
                    MeasurementFactRow(
                        name: $0.name, value: $0.value, detail: $0.detail,
                        accessibilityLabel: $0.accessibilityLabel
                    )
                }
            }(),
            state: SignalLevelMetricsCopy.text(for: presentation).map(MeasurementStateDisplay.init),
            isReadFailure: presentation.isReadFailure,
            method: nil
        )
    }

    /// True peak: one row and a method, or one sentence.
    static func display(for presentation: TruePeakPresentation) -> MeasurementDisplay {
        var rows: [MeasurementFactRow] = []
        var method: MeasurementMethodDisplay?
        if case let .measurement(measurement) = presentation {
            rows = TruePeakCopy.rows(for: measurement).map {
                MeasurementFactRow(
                    name: $0.name, value: $0.value, detail: $0.detail,
                    accessibilityLabel: $0.accessibilityLabel
                )
            }
            method = MeasurementMethodDisplay(
                text: TruePeakCopy.method(for: measurement),
                accessibilityLabel: TruePeakCopy.methodAccessibilityLabel(for: measurement)
            )
        }
        return MeasurementDisplay(
            title: TruePeakCopy.title,
            rows: rows,
            state: TruePeakCopy.text(for: presentation).map(MeasurementStateDisplay.init),
            isReadFailure: presentation.isReadFailure,
            method: method
        )
    }

    /// Integrated loudness: one row and a method, or one sentence. The row has no detail, because the
    /// channels are combined before the quantity exists — a field that could only ever be empty is not
    /// invented here either.
    static func display(for presentation: LoudnessPresentation) -> MeasurementDisplay {
        var rows: [MeasurementFactRow] = []
        var method: MeasurementMethodDisplay?
        if case let .measurement(measurement) = presentation {
            let row = LoudnessCopy.row(for: measurement)
            rows = [
                MeasurementFactRow(
                    name: row.name, value: row.value, detail: nil,
                    accessibilityLabel: row.accessibilityLabel
                ),
            ]
            method = MeasurementMethodDisplay(
                text: LoudnessCopy.method(for: measurement),
                accessibilityLabel: LoudnessCopy.methodAccessibilityLabel(for: measurement)
            )
        }
        return MeasurementDisplay(
            title: LoudnessCopy.title,
            rows: rows,
            state: LoudnessCopy.text(for: presentation).map(MeasurementStateDisplay.init),
            isReadFailure: presentation.isReadFailure,
            method: method
        )
    }

    /// Programme bandwidth: the reading **and the resolution it sits on**, as two rows, plus a method.
    ///
    /// **A measurement can be `.measurement` and still carry no reading**, and that case reads to a
    /// person exactly as an absence. `ProgrammeBandwidthCopy.row(for:)` returns `nil` for it and
    /// `text(for:)` supplies the absence sentence, so the two are read together here rather than
    /// switching on the enum alone — which would render an empty measurement with a method line under
    /// it.
    static func display(for presentation: SignificantBandwidthPresentation) -> MeasurementDisplay {
        var rows: [MeasurementFactRow] = []
        var method: MeasurementMethodDisplay?
        if case let .measurement(measurement) = presentation,
           let value = ProgrammeBandwidthCopy.row(for: measurement),
           let resolution = ProgrammeBandwidthCopy.resolutionRow(for: measurement) {
            rows = [value, resolution].map {
                MeasurementFactRow(
                    name: $0.name, value: $0.value, detail: nil,
                    accessibilityLabel: $0.accessibilityLabel
                )
            }
            method = MeasurementMethodDisplay(
                text: ProgrammeBandwidthCopy.method(for: measurement),
                accessibilityLabel: ProgrammeBandwidthCopy.methodAccessibilityLabel(for: measurement)
            )
        }
        return MeasurementDisplay(
            title: ProgrammeBandwidthCopy.title,
            rows: rows,
            state: ProgrammeBandwidthCopy.text(for: presentation).map(MeasurementStateDisplay.init),
            isReadFailure: presentation.isReadFailure,
            method: method
        )
    }
}

/// One named group of measurements — a physical quantity, never a ranking.
struct MeasurementGroupDisplay: Equatable, Identifiable {
    let name: String
    let measurements: [MeasurementDisplay]

    var id: String { name }
}

/// One measurement: its name, whatever rows it has, the sentence that stands in for them when it has
/// none, and the method that produced it.
///
/// **`rows` and `state` are not exclusive by type, and deliberately so.** The copy owners already decide
/// which of the two carries the content — `text(for:)` returns `nil` exactly where the rows are the
/// whole answer — and re-deciding it here as an enum would be a second implementation of that rule,
/// free to disagree with the first.
struct MeasurementDisplay: Equatable, Identifiable {
    let title: String
    let rows: [MeasurementFactRow]
    /// Loading, absent or failed — or a bandwidth measurement that produced no reading.
    let state: MeasurementStateDisplay?
    /// Whether the sentence above is a failure of the **reading**. It is the only thing on this surface
    /// that may be read at full weight; a value is never emphasised by what it contains.
    let isReadFailure: Bool
    /// `nil` where the measurement records no method — signal levels — rather than a sentence invented
    /// to fill the field.
    let method: MeasurementMethodDisplay?

    var id: String { title }
}

/// One row of measured fact: the four parts every measurement row already has.
///
/// Named for what it carries rather than for its shape, because `MeasurementRowDisplay` is already the
/// comparison's own row — two files side by side — and these two must never be mistaken for each other.
struct MeasurementFactRow: Equatable, Identifiable {
    let name: String
    /// `nil` where the value is not computable. The view shows the words for it, never a substituted
    /// number — `detail` carries the reason.
    let value: String?
    let detail: String?
    /// One sentence, so a row is announced as a coherent whole rather than as three fragments. Taken
    /// from the copy owner's own row, never rebuilt here.
    let accessibilityLabel: String

    var id: String { name }
}

/// The sentence a measurement shows in place of rows, in the copy owner's own words.
struct MeasurementStateDisplay: Equatable {
    let headline: String?
    let detail: String?
    let accessibilityLabel: String

    init(headline: String?, detail: String?, accessibilityLabel: String) {
        self.headline = headline
        self.detail = detail
        self.accessibilityLabel = accessibilityLabel
    }

    init(_ text: SignalLevelMetricsSectionText) {
        self.init(headline: text.headline, detail: text.detail, accessibilityLabel: text.accessibilityLabel)
    }

    init(_ text: TruePeakSectionText) {
        self.init(headline: text.headline, detail: text.detail, accessibilityLabel: text.accessibilityLabel)
    }

    init(_ text: LoudnessSectionText) {
        self.init(headline: text.headline, detail: text.detail, accessibilityLabel: text.accessibilityLabel)
    }

    init(_ text: ProgrammeBandwidthSectionText) {
        self.init(headline: text.headline, detail: text.detail, accessibilityLabel: text.accessibilityLabel)
    }
}

/// How a measurement was produced, in the copy owner's own words — the one thing on this surface that
/// may be collapsed (ADR-0026 §11, `design.md` §4).
struct MeasurementMethodDisplay: Equatable {
    let text: String
    let accessibilityLabel: String
}

// MARK: - Which state is a failure of the reading

/// Only a genuine failure to measure is read at full weight — the rule all four sections already follow,
/// stated once here instead of four times in a view.
/// Total, with no `default`: a state added to any of the four has to be decided to be a failure of the
/// reading or not, rather than quietly becoming one or quietly ceasing to be.
private extension SignalLevelMetricsPresentation {
    var isReadFailure: Bool {
        switch self {
        case .loading, .metrics, .absent: false
        case .failed: true
        }
    }
}

private extension TruePeakPresentation {
    var isReadFailure: Bool {
        switch self {
        case .loading, .measurement, .absent: false
        case .failed: true
        }
    }
}

private extension LoudnessPresentation {
    var isReadFailure: Bool {
        switch self {
        case .loading, .measurement, .absent: false
        case .failed: true
        }
    }
}

private extension SignificantBandwidthPresentation {
    var isReadFailure: Bool {
        switch self {
        case .loading, .measurement, .absent: false
        case .failed: true
        }
    }
}

/// The only words this section adds — two group names and one control label.
///
/// **None of them names a magnitude, a quality or a quantity's size.** The group names state which
/// physical quantity a measurement is *of*; the disclosure label is the phrase the four copy owners'
/// accessibility labels already use, reused verbatim so the same idea never has two voices.
enum MeasurementsCopy {
    /// The signal levels, the true peak and the integrated loudness: three ways of describing level.
    static let levelGroup = "Level"

    /// The programme bandwidth. A group of one, because one of the four is about frequency.
    static let frequencyGroup = "Frequency"

    /// The disclosure's label. `TruePeakCopy`, `LoudnessCopy` and `ProgrammeBandwidthCopy` all already
    /// speak this sentence to an assistive reader; this puts the same words on the control.
    static let methodDisclosure = "How it was measured"

    /// **Every string this section adds**, collected so a vocabulary sweep covers the surface rather
    /// than the repository — the discipline `WorkspaceCopy` established.
    static var everyRenderableString: [String] {
        [levelGroup, frequencyGroup, methodDisclosure]
    }
}
