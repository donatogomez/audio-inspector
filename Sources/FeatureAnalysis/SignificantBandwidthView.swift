import AudioInspectorDomain
import SwiftUI

/// The programme bandwidth as it appears inside the report: one measured value, the resolution it was
/// measured on, and the method that produced it — or the words that stand in for it while loading,
/// absent or failed.
///
/// Built on `LoudnessSection`'s own shape rather than a new one, because it answers the same kind of
/// question: one number about this file, produced by a method that has to travel with it. **Nothing
/// here is coloured, badged or weighted by what the value contains**, and that matters as much here as
/// it does for loudness: a top frequency is the figure a reader most expects to be read as a verdict
/// about the file's origin, and a colour would be that verdict without a word being written. A reading
/// near the top of the band is drawn exactly like one in the middle of it.
struct ProgrammeBandwidthSection: View {
    let presentation: SignificantBandwidthPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if case let .measurement(measurement) = presentation,
               let row = ProgrammeBandwidthCopy.row(for: measurement),
               let resolution = ProgrammeBandwidthCopy.resolutionRow(for: measurement) {
                ProgrammeBandwidthRowView(row: row)
                // A second row, not a suffix on the first: the resolution is the width of an analysis
                // bin, and putting it after a `±` would turn a grid into an error bar.
                ProgrammeBandwidthRowView(row: resolution)
                methodLine(measurement)
            } else if let text = ProgrammeBandwidthCopy.text(for: presentation) {
                stateText(text)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The visible half of "the methodology is recorded with the result" (ADR-0006, ADR-0023): a reader
    /// can see how the number was produced without opening a spike report. It is announced to an
    /// assistive reader too — the method is part of the measurement, not decoration around it.
    private func methodLine(_ measurement: SignificantBandwidth) -> some View {
        Text(ProgrammeBandwidthCopy.method(for: measurement))
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(ProgrammeBandwidthCopy.methodAccessibilityLabel(for: measurement))
    }

    /// Loading, absent or failed: one statement rather than a row, following the same colour rule every
    /// other analysis section follows — only a genuine failure to measure is read at full weight.
    private func stateText(_ text: ProgrammeBandwidthSectionText) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let headline = text.headline {
                Text(headline).font(.callout).foregroundStyle(headlineStyle)
            }
            if let detail = text.detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text.accessibilityLabel)
    }

    private var headlineStyle: HierarchicalShapeStyle {
        switch presentation {
        case .loading, .measurement, .absent: .secondary
        case .failed: .primary
        }
    }
}

/// One programme bandwidth row: name and value, announced as a single sentence. Mirrors
/// `LoudnessRowView`, including its refusal to colour anything.
private struct ProgrammeBandwidthRowView: View {
    let row: ProgrammeBandwidthRow

    var body: some View {
        LabeledContent(row.name) {
            Text(row.value).fontWeight(.medium)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.accessibilityLabel)
    }
}
