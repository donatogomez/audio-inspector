import AudioInspectorDomain
import SwiftUI

/// The technical comparison of the report on screen against a second file, or the words that stand in
/// for one.
///
/// It knows only a `ComparisonPresentation`. No `URL`, no framework, no selection, no operation — and
/// it never reads a verdict out of the two files it puts side by side.
struct ComparisonSection: View {
    let presentation: ComparisonPresentation

    var body: some View {
        switch presentation {
        case .none:
            // Nothing asked for: the report reads exactly as it does without this feature.
            EmptyView()
        case .loading:
            container { Text(ComparisonCopy.loading).font(.callout).foregroundStyle(.secondary) }
        case let .failed(message):
            container {
                VStack(alignment: .leading, spacing: 4) {
                    Text(ComparisonCopy.failedHeadline).font(.callout)
                    Text(message).font(.caption).foregroundStyle(.secondary)
                }
                // Said as one sentence: a failure to open the second file is not a fault of the first.
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(ComparisonCopy.failedHeadline) \(message)")
            }
        case let .ready(comparison):
            container { readyBody(comparison) }
        }
    }

    /// The section's frame: a title, the sentence saying what this is and is not, then the content.
    private func container(@ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(ComparisonCopy.title).font(.headline)
                Text(ComparisonCopy.subtitle).font(.caption).foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func readyBody(_ comparison: FileComparison) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            fileNames(comparison)
            comparedRows(comparison)
            contextBlock(comparison)
        }
    }

    /// Which file is which, by **name and position only**. Never *original* and *copy*, never *source*
    /// and *derived*: those name a relationship this comparison cannot establish.
    private func fileNames(_ comparison: FileComparison) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 2) {
            GridRow {
                Text(ComparisonCopy.firstFile).font(.caption).foregroundStyle(.secondary)
                Text(ComparisonCopy.secondFile).font(.caption).foregroundStyle(.secondary)
            }
            GridRow {
                Text(comparison.first.file.displayName).font(.callout)
                Text(comparison.second.file.displayName).font(.callout)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(ComparisonCopy.firstFile): \(comparison.first.file.displayName). "
                + "\(ComparisonCopy.secondFile): \(comparison.second.file.displayName)."
        )
    }

    /// The eight technical facts, each with both values and what comparing them established **in
    /// words**. No badge, no arrow, no ordering, no highlight — and no count of how many differ, which
    /// is an aggregate score with a friendlier name.
    private func comparedRows(_ comparison: FileComparison) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
            GridRow {
                Text("Property").gridColumnAlignment(.leading)
                Text(ComparisonCopy.firstFile)
                Text(ComparisonCopy.secondFile)
                Text(ComparisonCopy.outcomeColumn)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .accessibilityHidden(true) // the headings are repeated inside each row's own sentence

            ForEach(ComparisonFormatter.rows(for: comparison)) { row in
                GridRow {
                    Text(row.name).font(.callout)
                    side(row.first)
                    side(row.second)
                    Text(row.outcome.text)
                        .font(.callout)
                        .foregroundStyle(row.outcome.isSecondary ? .secondary : .primary)
                }
                // One element per row, so a reader hears a coherent sentence rather than four
                // fragments — and never has to correlate two columns by position.
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(row.accessibilityLabel)
            }
        }
    }

    /// One file's value for a property, with how it was read when that is worth saying. **The value
    /// stays on screen even when nothing could be compared** — two uncertain estimates still show their
    /// numbers; the surface simply declines to call them the same or different.
    private func side(_ display: PropertyDisplay) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            if let value = display.value {
                Text(value).font(.callout)
            }
            if let label = display.state.label {
                Text(label).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    /// Facts shown for each file and deliberately **not** compared, with the reason stated so their
    /// absence from the table above reads as a decision rather than an omission.
    private func contextBlock(_ comparison: FileComparison) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(ComparisonCopy.contextTitle).font(.subheadline)
            Text(ComparisonCopy.contextDetail).font(.caption).foregroundStyle(.secondary)

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                contextRow(
                    "Extension",
                    comparison.first.file.fileExtension,
                    comparison.second.file.fileExtension
                )
                contextRow(
                    "Size",
                    comparison.first.file.sizeBytes.map(HumanFormat.byteCount),
                    comparison.second.file.sizeBytes.map(HumanFormat.byteCount)
                )
                contextRow(
                    "Inspection",
                    ComparisonCopy.statusLine(for: comparison.first),
                    ComparisonCopy.statusLine(for: comparison.second)
                )
                contextRow(
                    "Warnings",
                    warningSummary(comparison.first),
                    warningSummary(comparison.second)
                )
            }
        }
    }

    /// A context row carries **no outcome at all** — there is no column for one, so none can appear.
    private func contextRow(_ name: String, _ first: String?, _ second: String?) -> some View {
        GridRow {
            Text(name).font(.caption).foregroundStyle(.secondary)
            Text(first ?? "Not available").font(.callout)
            Text(second ?? "Not available").font(.callout)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(name). \(ComparisonCopy.firstFile): \(first ?? "not available"). "
                + "\(ComparisonCopy.secondFile): \(second ?? "not available")."
        )
    }

    /// Each file's own warnings, counted for that file alone. **Not a comparison**: two files with the
    /// same number of warnings are not thereby alike, and the two counts are never set against each
    /// other.
    private func warningSummary(_ report: InspectionReport) -> String {
        switch report.warnings.count {
        case 0: "None"
        case 1: "1 warning on this file"
        case let count: "\(count) warnings on this file"
        }
    }
}
