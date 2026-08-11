import AudioInspectorDomain
import SwiftUI

/// Signal levels as they appear inside the report: four rows of measured facts, or the words that stand
/// in for them while loading, absent or failed.
///
/// Unlike the waveform and the spectrogram, this section has no drawing to fall back to words for — the
/// content **is** words, so each metric is its own accessible row rather than one description standing
/// in for a picture.
struct SignalLevelMetricsSection: View {
    let presentation: SignalLevelMetricsPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if case let .metrics(metrics) = presentation {
                ForEach(SignalLevelMetricsCopy.rows(for: metrics)) { row in
                    SignalLevelMetricsRowView(row: row)
                }
            } else if let text = SignalLevelMetricsCopy.text(for: presentation) {
                stateText(text)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Loading, absent or failed: one statement rather than any rows, following the waveform's own
    /// colour rule — only a genuine failure to measure is read at full weight.
    private func stateText(_ text: SignalLevelMetricsSectionText) -> some View {
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
        case .loading, .metrics, .absent: .secondary
        case .failed: .primary
        }
    }
}

/// One signal-level row: name, overall value, and a detail carrying either the per-channel breakdown or
/// the reason the value is absent. Mirrors `PropertyRow`'s own shape — the value speaks for itself, and
/// nothing here is coloured, since none of these is a warning about the reading.
private struct SignalLevelMetricsRowView: View {
    let row: SignalLevelMetricsRow

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            LabeledContent(row.name) {
                Text(row.value ?? "—").fontWeight(.medium)
            }
            if let detail = row.detail {
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.accessibilityLabel)
    }
}
