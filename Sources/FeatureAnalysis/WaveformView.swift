import AudioInspectorDomain
import SwiftUI

/// The waveform as it appears inside the report: a still drawing, or the words that stand in for one.
///
/// It knows only `WaveformEnvelope`. No `URL`, no framework, no decoding, no bucket decision, no
/// normalisation — and no reading of the shape it draws.
struct WaveformSection: View {
    let presentation: WaveformPresentation

    var body: some View {
        let text = WaveformCopy.text(for: presentation)
        return VStack(alignment: .leading, spacing: 8) {
            if case let .envelope(envelope) = presentation, !envelope.buckets.isEmpty {
                WaveformDrawing(envelope: envelope)
            }
            if let headline = text.headline {
                Text(headline)
                    .font(.callout)
                    .foregroundStyle(headlineStyle)
            }
            if let detail = text.detail {
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // One element for the whole section, not one per bucket: a drawing cannot be read, and 2048
        // shapes announced in sequence would be worse than silence.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text.accessibilityLabel)
    }

    /// Colour follows the state of the **reading**, and never the audio: waiting and having nothing to
    /// draw are ordinary outcomes and recede, while a statement that producing the drawing did not
    /// succeed is read at full weight.
    ///
    /// No alerting colour, deliberately. The report reserves red for a property of the file that could
    /// not be read, as a caption beside the row it belongs to; a full-width red heading here would read
    /// as an alarm about the file, which is the one thing a failure to draw does not mean. Nothing
    /// depends on this either way — the label carries the whole meaning.
    private var headlineStyle: HierarchicalShapeStyle {
        switch presentation {
        case .loading, .envelope, .absent: .secondary
        case .failed: .primary
        }
    }
}

/// The drawing itself.
///
/// **One vertical bar per bucket, in a single filled `Path`, rather than a continuous outline.** Two
/// reasons, and the second is the deciding one:
///
/// - *Cost.* One path and one fill per redraw, linear in the buckets and capped at 2048, with no view
///   per bucket and nothing rebuilt when the width changes. A closed outline would carry twice the
///   points for a shape that is visually identical at this density, where a bucket is well under a
///   point wide.
/// - *Honesty.* A continuous outline interpolates between one bucket's extremes and the next's, which
///   draws a value that was never measured. Separate bars assert the extremes of each slice and
///   nothing between them, which is exactly what the envelope contains.
private struct WaveformDrawing: View {
    let envelope: WaveformEnvelope

    var body: some View {
        Canvas(opaque: false) { context, size in
            // Drawn first and always, including for an envelope of pure silence, so amplitude zero is
            // visible as a position rather than as an absence.
            context.stroke(centreLine(in: size), with: .color(.secondary), lineWidth: 1)

            guard let geometry = WaveformGeometry(size: size, bucketCount: envelope.buckets.count) else {
                return // laid out at zero size; nothing to draw yet and nothing to recompute later
            }
            var bars = Path()
            for bar in geometry.bars(for: envelope.buckets) {
                bars.addRect(bar)
            }
            // An interface colour, chosen for contrast against the section's background in both
            // appearances. It never varies with what the samples contain: a colour that moved with the
            // audio would be a verdict on it, and every meaning here is already carried by the label.
            context.fill(bars, with: .color(.accentColor))
        }
        .frame(height: 96)
        // Still, in the strongest sense available: no gesture, no hover, no cursor, nothing to hit.
        .allowsHitTesting(false)
    }

    private func centreLine(in size: CGSize) -> Path {
        Path { path in
            path.move(to: CGPoint(x: 0, y: size.height / 2))
            path.addLine(to: CGPoint(x: size.width, y: size.height / 2))
        }
    }
}
