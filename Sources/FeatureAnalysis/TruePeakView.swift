import AudioInspectorDomain
import SwiftUI

/// The true peak as it appears inside the report: one measured value with its per-channel detail and
/// the method that produced it, or the words that stand in for them while loading, absent or failed.
///
/// It is built on `SignalLevelMetricsSection`'s own shape rather than a new one, because it answers the
/// same kind of question — a number about amplitude — and should read the same way. **Nothing here is
/// coloured by what the value contains**: a true peak above full scale is a fact, not a warning, and the
/// only text read at full weight is a genuine failure to measure.
struct TruePeakSection: View {
    let presentation: TruePeakPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if case let .measurement(measurement) = presentation {
                ForEach(TruePeakCopy.rows(for: measurement)) { row in
                    TruePeakRowView(row: row)
                }
                methodLine(measurement)
            } else if let text = TruePeakCopy.text(for: presentation) {
                stateText(text)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The visible half of "the factor and the filter are recorded with the result" (ADR-0006): a reader
    /// can see how the number was produced without opening a spike report. It is announced to an
    /// assistive reader too — the method is part of the measurement, not decoration around it.
    private func methodLine(_ measurement: TruePeakMeasurement) -> some View {
        Text(TruePeakCopy.method(for: measurement))
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(TruePeakCopy.methodAccessibilityLabel(for: measurement))
    }

    /// Loading, absent or failed: one statement rather than a row, following the same colour rule the
    /// waveform, the spectrogram and the signal levels already follow — only a genuine failure to
    /// measure is read at full weight.
    private func stateText(_ text: TruePeakSectionText) -> some View {
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

/// One true peak row: name, value, and a detail carrying either the per-channel breakdown or the reason
/// the value is absent. Mirrors `SignalLevelMetricsRowView` exactly, including its refusal to colour
/// anything: none of this is a warning about the audio.
private struct TruePeakRowView: View {
    let row: TruePeakRow

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
