import AudioInspectorDomain
import SwiftUI

/// **Measurements — the four figures the inspection derives from the file's samples.**
///
/// Where Details holds what the file's *header* declares, this holds what its *audio* measures: the
/// signal levels, the true peak, the integrated loudness and the programme bandwidth.
///
/// ## It arranges measurements; it takes none
///
/// Every name, value, unit, per-channel breakdown, absence sentence, failure sentence and method
/// sentence is the one the four copy owners already produce, routed here by `MeasurementsDisplay`.
/// Nothing below reads a domain value, formats a number, converts a unit or rounds anything, and no
/// sample is read to draw it.
///
/// ## Why it looks the way it does
///
/// The same four measurements sit today near the bottom of one long page as four identical boxes among
/// nine. Three things went wrong there and are fixed here (`design.md` §3):
///
/// - **four boxes said "four unrelated things".** Three of these describe *level* and one describes
///   *frequency* — the distinction `ReportView`'s own comments already order them by — and as four
///   identical cards it was invisible. They are now two named groups.
/// - **nothing aligned.** Each box laid its labels out independently, so a reader comparing a peak
///   against a loudness re-anchored at every box. One label column now runs the length of the section.
/// - **the explanations were louder than the facts.** Four method sentences among eight rows of figures
///   read as the bulk of the section. Each now sits behind a disclosure that never removes it.
///
/// ## What may not be hidden, and is not
///
/// ADR-0026 §11 permits collapsing an explanation and forbids collapsing a value, its unit, an absence,
/// a failure or a certainty state. Only the method sentences are collapsed. Every figure, every unit,
/// every per-channel breakdown, every absence and failure sentence, and the programme bandwidth's
/// **analysis resolution** stay visible — that last one deliberately, though §11 would permit collapsing
/// it, because it is the one row keeping the bandwidth figure from reading as an exact frequency.
///
/// ## What it is not
///
/// No score, no grade, no threshold, no target, no colour that varies with a value. Only a failure of
/// the *reading* is read at full weight, and it says so in words. There is no comparison here and no
/// difference: the comparison stays whole, where it is, until R8 (`design.md` §6).
public struct ReportMeasurementsView: View {
    private let groups: [MeasurementGroupDisplay]
    /// The comparison this section is being read inside, if any. **`.none` is the whole of inspection
    /// mode.** Every other case is a fact about the *second* file, so this file's own measurements are
    /// presented unchanged in all four.
    private let comparison: ComparisonPresentation

    /// Every measurement is a **required** parameter with no default, for `ReportView`'s own reason: a
    /// default would let a caller forget one and ship a section that silently shows nothing where a
    /// state belongs.
    public init(
        signalLevelMetrics: SignalLevelMetricsPresentation,
        truePeak: TruePeakPresentation,
        loudness: LoudnessPresentation,
        programmeBandwidth: SignificantBandwidthPresentation,
        comparison: ComparisonPresentation = .none
    ) {
        self.comparison = comparison
        groups = MeasurementsDisplay.groups(
            signalLevelMetrics: signalLevelMetrics,
            truePeak: truePeak,
            loudness: loudness,
            programmeBandwidth: programmeBandwidth
        )
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if case let .ready(_, measurements) = comparison {
                    comparedMeasurements(measurements)
                } else {
                    ForEach(groups) { group in
                        MeasurementGroupSection(group: group)
                    }
                    secondFileState
                }
            }
            // A reading measure rather than the window's width, exactly as Details takes it: a wider
            // window gets more space around the section, not longer lines.
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(24)
        }
    }

    // MARK: - Comparison mode — the same four measurements, for two files

    /// **The comparison in place, not appended.** The four measurements sit in the two groups they sit in
    /// for one file — *Level* and *Frequency* — so a reader who was looking at the loudness finds the
    /// loudness of both files where the loudness was, rather than a second table underneath.
    ///
    /// The blocks come from `MeasurementComparisonFormatter`, which decides every outcome, every reason
    /// and the one difference; nothing here re-decides any of them, and no row gains a place for a
    /// difference the domain does not publish.
    /// **The comparison in place, not appended.** It sits where the four measurements sit for one
    /// file, rather than as a second table after them — which is the shape this slice exists to remove.
    ///
    /// **It reuses `MeasurementComparisonSection` rather than re-rendering the same displays.** That view
    /// already renders `MeasurementComparisonFormatter`'s four blocks, each under its own measurement's
    /// name, and two suites already hold it to properties worth keeping: that it is given the comparison
    /// and **nothing else** — so two values and one outcome can never come from two operations — and that
    /// it says what is happening rather than rendering an empty table before both files have settled. A
    /// second rendering of the same values here would be free to drift from the one those suites pin.
    ///
    /// Its own heading repeats this section's name, which is a wording overlap R9 owns; a drifting
    /// duplicate would not have been.
    private func comparedMeasurements(_ measurements: MeasurementComparison?) -> some View {
        MeasurementComparisonSection(comparison: measurements)
    }

    /// What is happening to the second file, beneath this file's own measurements — which are untouched,
    /// because a comparison that has not settled or has failed says nothing about them.
    @ViewBuilder
    private var secondFileState: some View {
        switch comparison {
        case .none, .ready:
            EmptyView()
        case .loading:
            ComparedState(headline: ComparisonCopy.loading, detail: nil, isFailure: false)
        case let .failed(message):
            ComparedState(headline: ComparisonCopy.failedHeadline, detail: message, isFailure: true)
        }
    }
}

/// One named group — a physical quantity — and the measurements in it.
private struct MeasurementGroupSection: View {
    let group: MeasurementGroupDisplay

    var body: some View {
        ReportSection(group.name) {
            ForEach(Array(group.measurements.enumerated()), id: \.element.id) { index, measurement in
                if index > 0 {
                    Divider().padding(.vertical, 2)
                }
                MeasurementBody(measurement: measurement)
            }
        }
    }
}

/// One measurement: its name, its rows or the sentence standing in for them, and its method.
private struct MeasurementBody: View {
    let measurement: MeasurementDisplay

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(measurement.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .accessibilityAddTraits(.isHeader)

            ForEach(measurement.rows) { row in
                MeasurementFactRowView(row: row)
            }

            if let state = measurement.state {
                stateText(state)
            }

            if let method = measurement.method {
                MeasurementMethodDisclosure(method: method)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Loading, absent or failed — **one sentence in the measurement's own place**, never an empty area
    /// and never a dash standing in for a sentence. Only a genuine failure of the *reading* is read at
    /// full weight, the colour rule all four sections already follow.
    private func stateText(_ state: MeasurementStateDisplay) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let headline = state.headline {
                Text(headline)
                    .font(.callout)
                    .foregroundStyle(measurement.isReadFailure ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let detail = state.detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(state.accessibilityLabel)
    }
}

/// One row of measured fact, laid out against the section's shared label column.
///
/// **A value with none shows the words for it, never a substituted number**: `detail` carries the reason
/// it is not computable, and a bare dash would lose exactly the distinction the domain types exist to
/// preserve. Nothing here is coloured, weighted or badged by what the value contains — a true peak above
/// full scale is drawn exactly like one below it.
private struct MeasurementFactRowView: View {
    let row: MeasurementFactRow

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(row.name)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(width: 150, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.value ?? "—")
                    .font(.callout)
                    .fontWeight(.medium)
                if let detail = row.detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // One element, one sentence — not three fragments read in sequence.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.accessibilityLabel)
    }
}

/// The method sentence, behind a control that opens it.
///
/// **Collapsed is not hidden** (ADR-0026 §11): the sentence stays inside the measurement it belongs to,
/// one action away, in the same section, and reachable by an assistive reader — which is what
/// *"the method travels with the value"* asks for. It is the only thing on this surface that is
/// collapsed at all.
private struct MeasurementMethodDisclosure: View {
    let method: MeasurementMethodDisplay
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            Text(method.text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(method.accessibilityLabel)
        } label: {
            Text(MeasurementsCopy.methodDisclosure)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
