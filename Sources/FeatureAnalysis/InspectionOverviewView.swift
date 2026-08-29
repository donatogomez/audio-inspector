import AudioInspectorDomain
import SwiftUI

/// **Overview — where a reader lands, and the last section to get content of its own.**
///
/// ADR-0026 §1 makes the window's subject one file and §6 fixes exactly what this section may hold: the
/// file's identity, the core technical facts, the key measurements, a compact drawing of the envelope,
/// and what became of the reading. It is the entry point, so it is the shortest answer the application
/// can give — not a smaller copy of every other section.
///
/// ## It arranges facts; it derives none
///
/// Every name, value, unit, certainty state, absence sentence, failure sentence and outcome sentence
/// here is the one some other owner already produced — `ReportPropertyFormatter` for the facts, the
/// identity and the result, `MeasurementsDisplay` for the figures, `WaveformCopy` for the drawing's
/// words. Nothing below reads a domain property by name, formats a number, converts a unit, rounds
/// anything, or reads a sample. That is what stops this surface and Details disagreeing about the same
/// file: they are not two renderings of one fact, they are one fact rendered twice.
///
/// ## What "key measurements" means, and what it does not
///
/// Each measurement contributes the **first** row its own copy owner produces, or the sentence that
/// owner produces in place of rows. The order is the copy owner's and the words are the copy owner's;
/// this section takes a prefix rather than choosing a favourite. Per-channel breakdowns and method
/// sentences stay in Measurements, where R4 put them — not because they are unimportant, but because a
/// glance that carries everything is not a glance.
///
/// ## The count that is not here
///
/// ADR-0026 §6 permits a count of the report's warnings, *"as a way in to Details"*, and §7 argues it
/// under three conditions. It is **refused**: `audio-file-inspection`'s *Keep notes and the result apart
/// from the facts* says, without qualification, that *a note MUST NOT be counted, scored, ranked by
/// severity, or summarised into a total* — a cardinality is a total, this surface calls warnings
/// **Notes**, and that requirement shipped after ADR-0026 was written. §7 provides for exactly this
/// outcome: *"the count goes and the section title carries the reader instead."* See
/// `design.md` §2.
///
/// ## What it is not
///
/// No summary of what the file *is*, no score, grade, rating or quality claim, no statement about
/// origin, master, remaster, transcode, upsampling or bitrate, no threshold, no target, and no aggregate
/// over anything. No colour varies with a value; only a failure of the **reading** is read at full
/// weight, and it says so in words. **Nothing here navigates**: the section control R1 built is the only
/// way between sections, and every block on this surface is informative.
public struct InspectionOverviewView: View {
    private let report: InspectionReport
    private let waveform: WaveformPresentation
    private let measurements: [MeasurementDisplay]

    /// Every measurement is a **required** parameter with no default, for the reason `ReportView` and
    /// `ReportMeasurementsView` both give: a default lets a caller forget one and ship a surface that
    /// silently shows nothing where a state belongs.
    public init(
        report: InspectionReport,
        waveform: WaveformPresentation,
        signalLevelMetrics: SignalLevelMetricsPresentation,
        truePeak: TruePeakPresentation,
        loudness: LoudnessPresentation,
        programmeBandwidth: SignificantBandwidthPresentation
    ) {
        self.report = report
        self.waveform = waveform
        // The same four displays the Measurements section is built from, in the same order, through the
        // same call — so a figure cannot differ between the two surfaces.
        measurements = MeasurementsDisplay.groups(
            signalLevelMetrics: signalLevelMetrics,
            truePeak: truePeak,
            loudness: loudness,
            programmeBandwidth: programmeBandwidth
        ).flatMap(\.measurements)
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                fileSection
                factsSection
                measurementsSection
                waveformSection
                resultStatement
            }
            // A reading measure rather than the window's width, exactly as Details uses: a wider window
            // gets more space around the section, not longer lines.
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(24)
        }
    }

    // MARK: - File — identity, and never a location

    /// Whichever of these the report carries. **No path, URL, parent directory or bookmark exists to
    /// show**: the domain does not carry one (ADR-0010), and the source keeps the sentence the report
    /// already uses for it.
    private var fileSection: some View {
        ReportSection("File") {
            OverviewRow(name: "Name", value: report.file.displayName, selectable: true)
            if let ext = report.file.fileExtension {
                OverviewRow(name: "Extension", value: ext)
            }
            if let size = report.file.sizeBytes {
                OverviewRow(name: "Size", value: HumanFormat.byteCount(size))
            }
            if let modifiedAt = report.file.modifiedAt {
                OverviewRow(name: "Modified", value: HumanFormat.dateTime(modifiedAt))
            }
            OverviewRow(name: "Source", value: sourceDescription)
        }
    }

    /// Only the safe kind plus its disclosure — never the path, which the domain does not carry. The same
    /// sentence Details states, because it is the same fact.
    private var sourceDescription: String {
        switch report.file.source {
        case .userSelectedLocalFile:
            "User-selected local file (location omitted)"
        }
    }

    // MARK: - Technical — the six §6 permits, selected by the formatter

    /// `coreFacts(for:)` decides which; this renders them. A fact the file does not carry keeps its
    /// state, so it is **words** here rather than a gap the reader has to notice.
    private var factsSection: some View {
        ReportSection("Technical") {
            ForEach(ReportPropertyFormatter.coreFacts(for: report.properties)) { property in
                OverviewRow(
                    name: property.name,
                    value: property.value ?? "—",
                    state: property.state,
                    accessibilityLabel: property.accessibilityLabel
                )
            }
        }
    }

    // MARK: - Measurements — one fact each, in the copy owner's own words

    /// The first row a measurement produces, or the sentence it produces instead. Nothing is reordered,
    /// nothing is ranked, and no measurement is described as principal or notable.
    private var measurementsSection: some View {
        ReportSection("Measurements") {
            ForEach(measurements) { measurement in
                if let row = measurement.rows.first {
                    // **The fact's own name, not the measurement's.** *Signal levels: −3.00 dBFS* does
                    // not say which level that is; *Peak sample* does, and it is what the copy owner
                    // already calls it. Where the two coincide — the true peak's row is named for its
                    // measurement — nothing is repeated. The measurement still names the row aloud, so
                    // an assistive reader hears which one it belongs to.
                    OverviewRow(
                        name: row.name,
                        value: row.value ?? "—",
                        accessibilityLabel: "\(measurement.title). \(row.accessibilityLabel)"
                    )
                } else if let state = measurement.state {
                    OverviewRow(
                        name: measurement.title,
                        value: state.headline ?? "—",
                        // A sentence standing in for a figure, so it recedes — unless it says the
                        // *reading* did not succeed, which is the one thing on this surface read at full
                        // weight. It is the rule the Measurements section already applies.
                        valueIsSentence: true,
                        isReadFailure: measurement.isReadFailure,
                        accessibilityLabel: "\(measurement.title). \(state.accessibilityLabel)"
                    )
                }
            }
        }
    }

    // MARK: - Waveform — compact, and informative

    /// The **same** `WaveformPresentation` the Waveform section is handed, so the two cannot disagree
    /// about the file, and the same four states in `WaveformCopy`'s own words. Nothing is read, decoded,
    /// re-bucketed or normalised to draw it, and it is not a control: no gesture, no hit target, no way
    /// through to anywhere.
    private var waveformSection: some View {
        let text = WaveformCopy.text(for: waveform)
        return ReportSection(WaveformCopy.title) {
            VStack(alignment: .leading, spacing: 8) {
                if case let .envelope(envelope) = waveform, !envelope.buckets.isEmpty {
                    WaveformDrawing(envelope: envelope, sizing: .overviewCompact)
                }
                if let headline = text.headline {
                    Text(headline)
                        .font(.caption)
                        .foregroundStyle(headlineStyle)
                        .fixedSize(horizontal: false, vertical: true)
                }
                // **Both lines, because either may be the only one.** An envelope carries no headline
                // and states what the drawing is entirely in the detail, so dropping it would leave the
                // one state that has a drawing as the one state with no words.
                if let detail = text.detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // One element for the whole drawing, never one per bucket.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(text.accessibilityLabel)
        }
    }

    /// The report page's own rule, unchanged: waiting and having nothing to draw are ordinary outcomes
    /// and recede; only a statement that producing the drawing did not succeed is read at full weight.
    private var headlineStyle: HierarchicalShapeStyle {
        switch waveform {
        case .loading, .envelope, .absent: .secondary
        case .failed: .primary
        }
    }

    // MARK: - Result — about the reading, set apart from the facts

    /// **Outside the card rhythm on purpose**, exactly as Details sets it apart: it is a statement about
    /// what became of the *reading*, not another fact about the file. `InspectionOutcomeDisplay` owns
    /// those words, and it characterises neither the file nor its quality.
    ///
    /// It is derived from **all** the report's properties, not from the six above, because it is the
    /// report's own account of its own reading — narrowing it to this section's rows would invent a
    /// second, quieter outcome.
    private var resultStatement: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Result")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)
            let outcome = ReportPropertyFormatter.outcome(
                for: report.status,
                properties: ReportPropertyFormatter.displays(for: report.properties)
            )
            Text(outcome.text)
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// The section's one row shape, so every label sits in one column and the eye anchors once.
///
/// Its own type rather than Details' `DetailRow` for the reason R5 gave for not reusing `WaveformSection`
/// — that row carries a `detail` line and an exact-figure disclosure this section deliberately does not
/// have, and inheriting it would drag the detail back onto the glance.
private struct OverviewRow: View {
    let name: String
    let value: String
    var state: PropertyPresentationState?
    /// Whether `value` is a sentence standing in for a figure rather than a figure.
    var valueIsSentence = false
    var isReadFailure = false
    var selectable = false
    var accessibilityLabel: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(name)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(width: 150, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                valueText
                if let label = state?.label {
                    Label {
                        Text(label)
                    } icon: {
                        if let symbol = state?.symbolName {
                            Image(systemName: symbol)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(
                        state?.isReadFailure == true ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary)
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel ?? "\(name). \(value)")
    }

    /// **Never emphasised by what the value contains.** A figure is a figure, however large or small.
    /// A sentence standing in for one recedes, unless it says the *reading* did not succeed — the same
    /// rule the Measurements section applies, and the only emphasis this surface has.
    @ViewBuilder
    private var valueText: some View {
        let text = Text(value)
            .font(.callout)
            .foregroundStyle(valueIsSentence && !isReadFailure ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
        if selectable {
            text.textSelection(.enabled)
        } else {
            text
        }
    }
}
