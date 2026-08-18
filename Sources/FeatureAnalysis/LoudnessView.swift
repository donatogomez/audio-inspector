import AudioInspectorDomain
import SwiftUI

/// The integrated loudness as it appears inside the report: one measured value with the method that
/// produced it, or the words that stand in for it while loading, absent or failed.
///
/// Built on `TruePeakSection`'s own shape rather than a new one, because it answers the same kind of
/// question — one number about this file, produced by a method that has to travel with it. **Nothing
/// here is coloured by what the value contains**, and that matters more here than anywhere else in the
/// report: a loudness figure is the one a reader most expects to be judged against a target, and a
/// colour would be that judgement without a word being written.
struct LoudnessSection: View {
    let presentation: LoudnessPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if case let .measurement(measurement) = presentation {
                LoudnessRowView(row: LoudnessCopy.row(for: measurement))
                methodLine(measurement)
            } else if let text = LoudnessCopy.text(for: presentation) {
                stateText(text)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The visible half of "the methodology is recorded with the result" (ADR-0006, ADR-0022): a reader
    /// can see how the number was produced without opening a spike report. It is announced to an
    /// assistive reader too — the method is part of the measurement, not decoration around it.
    private func methodLine(_ measurement: LoudnessMeasurement) -> some View {
        Text(LoudnessCopy.method(for: measurement))
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(LoudnessCopy.methodAccessibilityLabel(for: measurement))
    }

    /// Loading, absent or failed: one statement rather than a row, following the same colour rule every
    /// other analysis section follows — only a genuine failure to measure is read at full weight.
    private func stateText(_ text: LoudnessSectionText) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let headline = text.headline {
                Text(headline).font(.callout).foregroundStyle(headlineStyle)
            }
            if let detail = text.detail {
                Text(detail).font(.caption).foregroundStyle(.secondary)
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

/// The one loudness row: name and value, announced as a single sentence. Mirrors `TruePeakRowView`,
/// including its refusal to colour anything — and without a detail line, because there is no
/// per-channel breakdown for a quantity whose channels are combined before it exists.
private struct LoudnessRowView: View {
    let row: LoudnessRow

    var body: some View {
        LabeledContent(row.name) {
            Text(row.value).fontWeight(.medium)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.accessibilityLabel)
    }
}
