import AudioInspectorDomain
import SwiftUI

/// **Details — what the other four sections do not hold** (ADR-0026 §10): the technical properties, the
/// file's own identity, the notes, and what became of the reading.
///
/// ## It moves content; it decides none of it
///
/// Every value, unit, absence, certainty state, note and outcome sentence here is the one
/// `ReportPropertyFormatter` already produces, and the two groups are the ones `groups(for:)` already
/// assigns. This view renders that decision — it does not re-make it, and it cannot: nothing below reads
/// a domain property directly.
///
/// ## Why it looks the way it does
///
/// The same four bodies of content sit today at the bottom of one long page, as five identical boxes.
/// Three things went wrong there and are fixed here (`design.md` §3):
///
/// - **the grouping was invisible.** *Format* and *Encoding* are two halves of one idea — what the file
///   *is*, and how it is *encoded* — and as two boxes among five the split read as arbitrary. They are
///   now two named groups inside **one** technical area, so the distinction is legible as a distinction.
/// - **the result looked like more data.** The one statement that is about *the reading* rather than
///   about the file was styled exactly like the nine property rows above it. It now sits outside the
///   card rhythm entirely.
/// - **nothing aligned.** Each box laid its labels out independently, so the eye re-anchored at every
///   one. One label column now runs the length of the section.
///
/// ## Nothing is collapsed
///
/// ADR-0026 §11 permits collapsing an explanation and forbids collapsing a value, an absence, a failure
/// or a certainty state. The only candidate here is `PropertyDisplay.detail`, and it is two things behind
/// one field: the exact figure behind a rounded value, and the reason an unreliable reading carries.
/// Collapsing it collapses both, and the second is the half a reader most needs beside the value it
/// explains. Splitting the field is a change to a type R4's surfaces will share, so it is a follow-up
/// rather than something done badly here.
public struct ReportDetailsView: View {
    private let report: InspectionReport

    public init(report: InspectionReport) {
        self.report = report
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                technicalSection
                fileSection
                notesSection
                resultStatement
            }
            // A reading measure rather than the window's width: a wider window gets more space around
            // the section, not longer lines. Below the measure it simply fills what there is.
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(24)
        }
    }

    // MARK: - Technical — the report's own two groups, in one area

    /// One area, two named groups. The groups and their membership are `ReportPropertyFormatter`'s;
    /// nothing here picks, reorders or omits a property.
    private var technicalSection: some View {
        ReportSection("Technical") {
            ForEach(Array(ReportPropertyFormatter.groups(for: report.properties).enumerated()),
                    id: \.element.id) { index, group in
                if index > 0 {
                    Divider().padding(.vertical, 2)
                }
                Text(group.name)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .accessibilityAddTraits(.isHeader)
                ForEach(group.properties) { property in
                    DetailPropertyRow(property: property)
                }
            }
        }
    }

    // MARK: - File — identity, and never a location

    /// Whichever of these the report carries. **No path, URL, parent directory or bookmark exists to
    /// show**: the domain does not carry one (ADR-0010), and the source keeps the sentence it already
    /// had.
    private var fileSection: some View {
        ReportSection("File") {
            DetailRow(name: "Name", value: report.file.displayName, selectable: true)
            if let ext = report.file.fileExtension {
                DetailRow(name: "Extension", value: ext)
            }
            if let size = report.file.sizeBytes {
                DetailRow(
                    name: "Size",
                    value: HumanFormat.byteCount(size),
                    detail: HumanFormat.byteCountExact(size)
                )
            }
            if let modifiedAt = report.file.modifiedAt {
                DetailRow(name: "Modified", value: HumanFormat.dateTime(modifiedAt))
            }
            DetailRow(name: "Source", value: sourceDescription)
        }
    }

    /// Only the safe kind plus its disclosure — never the path, which the domain does not carry.
    private var sourceDescription: String {
        switch report.file.source {
        case .userSelectedLocalFile:
            "User-selected local file (location omitted)"
        }
    }

    // MARK: - Notes — absent when there are none

    /// A report with nothing to note shows no notes area, rather than an empty one saying so: an empty
    /// region is a statement, and there is nothing here to state.
    @ViewBuilder
    private var notesSection: some View {
        let notes = ReportPropertyFormatter.displays(for: report.warnings)
        if !notes.isEmpty {
            ReportSection("Notes") {
                ForEach(notes) { note in
                    VStack(alignment: .leading, spacing: 2) {
                        if let subject = note.subject {
                            Text(subject).font(.callout.weight(.medium))
                        }
                        Text(note.message)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(note.accessibilityLabel)
                }
            }
        }
    }

    // MARK: - Result — about the reading, and set apart from the facts

    /// **Outside the card rhythm on purpose.** It is a statement about what became of the *reading*, not
    /// a tenth property of the file, and giving it the same box as the facts is exactly what made it read
    /// as one. It characterises neither the file nor its quality — `InspectionOutcomeDisplay` owns those
    /// words, and this renders them.
    private var resultStatement: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Result")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)
            Text(ReportPropertyFormatter.outcome(
                for: report.status,
                properties: ReportPropertyFormatter.displays(for: report.properties)
            ).text)
            .font(.callout)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// One property, laid out against the section's shared label column.
///
/// The same four parts `PropertyRow` shows and in the same order, because they are the same four facts:
/// the name, the value, the certainty when there is one to state, and the detail. **The state is always
/// words** — a symbol only ever accompanies a label, never replaces one — and only a failure of the
/// *reading* is coloured, because colouring an absent or undefined property would tell the reader their
/// file is worse, which presentation may not say.
private struct DetailPropertyRow: View {
    let property: PropertyDisplay

    var body: some View {
        DetailRow(
            name: property.name,
            value: property.value ?? "—",
            detail: property.detail,
            state: property.state,
            accessibilityLabel: property.accessibilityLabel
        )
    }
}

/// The section's one row shape, so every label sits in one column and the eye anchors once.
private struct DetailRow: View {
    let name: String
    let value: String
    var detail: String?
    var state: PropertyPresentationState?
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
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // One element, one sentence — not four fragments read in sequence.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel ?? "\(name): \(value)")
    }

    @ViewBuilder
    private var valueText: some View {
        let text = Text(value).font(.callout).fontWeight(.medium)
        if selectable {
            text.textSelection(.enabled)
        } else {
            text
        }
    }
}
