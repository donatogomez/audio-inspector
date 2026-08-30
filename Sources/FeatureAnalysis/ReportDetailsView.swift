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
    /// The comparison this section is being read inside, if any. **`.none` is the whole of inspection
    /// mode**, and every other case is a fact about the *second* file rather than about this one — which
    /// is why the first file's own content is presented unchanged in all four.
    private let comparison: ComparisonPresentation

    public init(report: InspectionReport, comparison: ComparisonPresentation = .none) {
        self.report = report
        self.comparison = comparison
    }

    /// Whether this section is presenting two files. It changes the measure and nothing else.
    private var isComparing: Bool {
        if case .ready = comparison { return true }
        return false
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if case let .ready(files, _) = comparison {
                    comparedTechnicalSection(files)
                    comparedFileSection(files)
                    comparedNotesSection(files)
                    comparedResultStatement(files)
                } else {
                    technicalSection
                    fileSection
                    notesSection
                    resultStatement
                    secondFileState
                }
            }
            // **A reading measure for prose, the window's width for a table.**
            //
            // 640 pt is right for one file: a column of short values beside their names, and a wider
            // window should give it more space around rather than longer lines. It is wrong for two. A
            // compared row carries both files' values *and* the sentence saying what comparing them
            // established — *"Not comparable — the second file's format does not define it"* — and
            // capping that at a reading measure clipped the reason instead of wrapping it. **A reason a
            // reader cannot finish is not a stated reason**, which is the whole of what that column is
            // for. Found by rendering it, not by a test.
            .frame(maxWidth: isComparing ? .infinity : 640, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(24)
        }
    }

    // MARK: - Technical — the report's own two groups, in one area

    /// One area, two named groups. The groups and their membership are `ReportPropertyFormatter`'s;
    /// nothing here picks, reorders or omits a property.
    private var technicalSection: some View {
        ReportSection("Technical") {
            let groups = ReportPropertyFormatter.groups(for: report.properties)
            ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
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


// MARK: - Comparison mode — the same four bodies, for two files

extension ReportDetailsView {

    /// **The report's own comparison, rendered.** `ComparisonFormatter.rows(for:)` decides which
    /// properties are compared, in which order, and what comparing each one established; nothing here
    /// re-decides any of it, applies a threshold, or compares a pair the domain reported as not
    /// comparable.
    ///
    /// The outcome column is a fact per row, not a scoreboard: **nothing totals it.** There is no count
    /// of how many agree, no count of how many differ, and no row is filtered out for either reason —
    /// every property the comparison covers is present whatever its outcome, which is what stops the
    /// absence of a row from meaning anything.
    fileprivate func comparedTechnicalSection(_ files: FileComparison) -> some View {
        ReportSection("Technical") {
            ComparedGrid(
                columns: [ComparisonCopy.firstFile, ComparisonCopy.secondFile, ComparisonCopy.outcomeColumn],
                leadingColumn: "Property"
            ) {
                ForEach(ComparisonFormatter.rows(for: files)) { row in
                    GridRow {
                        Text(row.name).font(.callout)
                        ComparedSide(display: row.first)
                        ComparedSide(display: row.second)
                        Text(row.outcome.text)
                            .font(.callout)
                            .foregroundStyle(row.outcome.isSecondary ? .secondary : .primary)
                            // The reasons are sentences, not labels: they wrap rather than truncate.
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: 320, alignment: .leading)
                    }
                    // One element per row, so a reader hears a coherent sentence — the property, each
                    // file's value, then what comparing them established — rather than correlating two
                    // columns by position.
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(row.accessibilityLabel)
                }
            }
        }
    }

    /// Both identities, under the labels naming their **positions**. No outcome: there is no column for
    /// one, so none can appear — a file's name, size and date are facts about the file rather than about
    /// its audio, and two copies of the same audio routinely differ in all three.
    fileprivate func comparedFileSection(_ files: FileComparison) -> some View {
        ReportSection("File") {
            ComparedGrid(
                columns: [ComparisonCopy.firstFile, ComparisonCopy.secondFile],
                leadingColumn: ""
            ) {
                comparedIdentityRow("Name", files.first.file.displayName, files.second.file.displayName)
                comparedIdentityRow("Extension", files.first.file.fileExtension, files.second.file.fileExtension)
                comparedIdentityRow(
                    "Size",
                    files.first.file.sizeBytes.map(HumanFormat.byteCount),
                    files.second.file.sizeBytes.map(HumanFormat.byteCount)
                )
                comparedIdentityRow(
                    "Modified",
                    files.first.file.modifiedAt.map(HumanFormat.dateTime),
                    files.second.file.modifiedAt.map(HumanFormat.dateTime)
                )
                comparedIdentityRow(
                    "Source",
                    Self.sourceDescription(files.first.file),
                    Self.sourceDescription(files.second.file)
                )
            }
        }
    }

    fileprivate func comparedIdentityRow(_ name: String, _ first: String?, _ second: String?) -> some View {
        GridRow {
            Text(name).font(.callout).foregroundStyle(.secondary)
            Text(first ?? "Not available").font(.callout)
            Text(second ?? "Not available").font(.callout)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(name). \(ComparisonCopy.firstFile): \(first ?? "not available"). "
                + "\(ComparisonCopy.secondFile): \(second ?? "not available")."
        )
    }

    /// Each file's notes, **for that file alone and never counted.**
    ///
    /// The surface this replaces rendered *"1 warning on this file"* for each side — a cardinality over
    /// notes, written before `audio-file-inspection` made *"A note MUST NOT be counted, scored, ranked by
    /// severity, or summarised into a total"* canonical. That count is gone rather than moved, and
    /// nothing stands in for it: no badge, no icon, no pluralised phrase, no severity. **A file with
    /// nothing to note simply has no notes area**, exactly as in inspection mode, and the two sides are
    /// never set against each other.
    fileprivate func comparedNotesSection(_ files: FileComparison) -> some View {
        let first = ReportPropertyFormatter.displays(for: files.first.warnings)
        let second = ReportPropertyFormatter.displays(for: files.second.warnings)
        return Group {
            if !first.isEmpty || !second.isEmpty {
                ReportSection("Notes") {
                    if !first.isEmpty {
                        ComparedNotes(position: ComparisonCopy.firstFile, notes: first)
                    }
                    if !second.isEmpty {
                        ComparedNotes(position: ComparisonCopy.secondFile, notes: second)
                    }
                }
            }
        }
    }

    /// Each reading's own result, side by side and **not compared**.
    ///
    /// There is no outcome column here and none is possible: a result says what became of *a reading*,
    /// and an outcome over two readings would be a verdict about them rather than a fact about either
    /// file. The two sentences are `InspectionOutcomeDisplay`'s own, unchanged.
    fileprivate func comparedResultStatement(_ files: FileComparison) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Result")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)
            ForEach([
                (ComparisonCopy.firstFile, ComparisonCopy.statusLine(for: files.first)),
                (ComparisonCopy.secondFile, ComparisonCopy.statusLine(for: files.second)),
            ], id: \.0) { position, sentence in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(position)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(width: 150, alignment: .leading)
                    Text(sentence).font(.callout)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(position). \(sentence)")
            }
        }
    }

    /// What is happening to the second file, stated once, beneath this file's own content — which is
    /// untouched, because a comparison that has not settled or has failed says nothing about it.
    @ViewBuilder
    fileprivate var secondFileState: some View {
        switch comparison {
        case .none, .ready:
            EmptyView()
        case .loading:
            ComparedState(headline: ComparisonCopy.loading, detail: nil, isFailure: false)
        case let .failed(message):
            ComparedState(headline: ComparisonCopy.failedHeadline, detail: message, isFailure: true)
        }
    }

    static func sourceDescription(_ file: AudioFileReference) -> String {
        switch file.source {
        case .userSelectedLocalFile:
            "User-selected local file (location omitted)"
        }
    }
}

/// The comparison sections' one grid shape, so both files' columns line up down the section and the eye
/// anchors once — the same reason the inspection sections share a label column.
struct ComparedGrid<Content: View>: View {
    let columns: [String]
    let leadingColumn: String
    @ViewBuilder let content: Content

    var body: some View {
        // **Scrolls rather than shrinks.** Two value columns and an outcome do not fit the 720 pt
        // window's reading measure, and squeezing them would make the values illegible — which is worse
        // than asking the reader to scroll a table they can read.
        ScrollView(.horizontal) {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                GridRow {
                    Text(leadingColumn).gridColumnAlignment(.leading)
                    ForEach(columns, id: \.self) { Text($0) }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true) // repeated inside each row's own sentence
                content
            }
            .padding(.bottom, 2)
        }
    }
}

/// One file's value for a property, with how it was read when that is worth saying.
///
/// **The value stays on screen even when nothing could be compared** — two uncertain estimates still show
/// their numbers; the surface simply declines to call them the same or different.
struct ComparedSide: View {
    let display: PropertyDisplay

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            if let value = display.value {
                Text(value).font(.callout)
            }
            if let label = display.state.label {
                Text(label).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

/// One file's notes, in the report's own words. **No count, and nothing that varies with how many.**
struct ComparedNotes: View {
    let position: String
    let notes: [WarningDisplay]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(position)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)
            ForEach(notes) { note in
                VStack(alignment: .leading, spacing: 2) {
                    if let subject = note.subject {
                        Text(subject).font(.callout.weight(.medium))
                    }
                    Text(note.message).font(.callout).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(position). \(note.accessibilityLabel)")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// What is happening to the second file, where its values would be. Only a failure of the *inspection*
/// is read at full weight, and it says so in words.
struct ComparedState: View {
    let headline: String
    let detail: String?
    let isFailure: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(headline)
                .font(.callout)
                .foregroundStyle(isFailure ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                .fixedSize(horizontal: false, vertical: true)
            if let detail {
                Text(detail).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([headline, detail].compactMap { $0 }.joined(separator: ". "))
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
