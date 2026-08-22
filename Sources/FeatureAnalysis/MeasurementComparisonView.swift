import AudioInspectorDomain
import SwiftUI

/// The measurements of both files, side by side, **beneath** the technical rows.
///
/// It is a sub-section of the comparison rather than a section of its own: the reader is looking at one
/// pair of files, and splitting the answer into two top-level headings would suggest two comparisons.
/// It is also deliberately not folded *into* the technical table — those eight rows describe what the
/// two headers declare, these four describe what the samples measure, they arrive later, and exactly
/// one of them carries a difference (task 6.1, ADR-0024 §6).
///
/// **Nothing here decides anything.** Every outcome is a case the domain already chose, translated into
/// words by `MeasurementComparisonFormatter`. No threshold, no tolerance, no re-reading of a method.
struct MeasurementComparisonSection: View {
    /// `nil` until **both** files have settled their measurements. The technical rows above are already
    /// complete, so this says what is still happening rather than rendering an empty table.
    let comparison: MeasurementComparison?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(MeasurementComparisonCopy.title).font(.subheadline)
                Text(MeasurementComparisonCopy.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)

            if let comparison {
                table(comparison)
            } else {
                Text(MeasurementComparisonCopy.waiting).font(.callout).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// **One grid, so every metric's columns line up**, with the metric titles and the channel notes
    /// spanning it rather than sitting in a column of their own.
    ///
    /// The fifth column exists for the loudness row alone and is empty on every other. That is why this
    /// is not the technical table: giving those eight rows a column they can never use would invite
    /// someone to fill it, which is exactly what task 6.3 forbids.
    private func table(_ comparison: MeasurementComparison) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
            GridRow {
                Text(MeasurementComparisonCopy.measurementColumn).gridColumnAlignment(.leading)
                Text(MeasurementComparisonCopy.firstFile)
                Text(MeasurementComparisonCopy.secondFile)
                Text(MeasurementComparisonCopy.outcomeColumn)
                // The difference column carries no heading: it belongs to one row, and a heading over
                // four empty cells would read as four missing values.
                Color.clear.frame(width: 0, height: 0)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .accessibilityHidden(true) // repeated inside each row's own sentence

            ForEach(MeasurementComparisonFormatter.blocks(for: comparison)) { block in
                GridRow {
                    Text(block.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .gridCellColumns(5)
                }
                .accessibilityHidden(true) // each row below names its own measurement

                ForEach(block.rows) { row in
                    GridRow {
                        Text(row.name).font(.callout)
                        side(row.first)
                        side(row.second)
                        Text(row.outcome.text)
                            .font(.callout)
                            .foregroundStyle(row.outcome.isSecondary ? .secondary : .primary)
                            .fixedSize(horizontal: false, vertical: true)
                        // **The sign changes nothing but the character.** No colour, no badge, no icon,
                        // no weight — a difference of +3.4 LU and one of −3.4 LU are rendered by the
                        // same expression in the same style (task 6.6).
                        Text(row.difference ?? "").font(.callout)
                    }
                    // One element per row, so a reader hears a coherent sentence rather than five
                    // fragments and never has to correlate columns by position.
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(row.accessibilityLabel)

                    // Why two identical-looking columns can carry an outcome that says otherwise. It
                    // belongs to the row above and is announced with it, so it gets no element of its
                    // own.
                    if let note = row.precisionNote {
                        GridRow {
                            Text(note)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .gridCellColumns(5)
                        }
                        .accessibilityHidden(true)
                    }
                }

                if let note = block.channelNote {
                    GridRow {
                        Text(note)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .gridCellColumns(5)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(block.title). \(note)")
                }
            }
        }
    }

    /// One file's value, with its per-channel or per-grid detail beneath it.
    ///
    /// **A side with no value shows the words for it**, never a zero and never a bare dash: absence and
    /// a measured zero are different answers, and digital silence genuinely measures 0.0 dBTP.
    private func side(_ display: MeasurementSideDisplay) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(display.value ?? MeasurementComparisonCopy.noValue)
                .font(.callout)
                .foregroundStyle(display.value == nil ? .secondary : .primary)
            if let detail = display.detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
