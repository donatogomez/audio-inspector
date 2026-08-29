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
struct WaveformDrawing: View {
    let envelope: WaveformEnvelope
    /// How much vertical space this drawing takes. Defaults to the strip the report page has always
    /// given it, so every existing caller is unchanged.
    var sizing: WaveformPlotSizing = .reportPage

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
        .frame(minHeight: sizing.minimum, maxHeight: sizing.maximum)
        // Still, in the strongest sense available: no gesture, no hover, no cursor, nothing to hit.
        // **Room is not a power** (ADR-0026 §9): a taller drawing is the same still drawing.
        .allowsHitTesting(false)
    }

    private func centreLine(in size: CGSize) -> Path {
        Path { path in
            path.move(to: CGPoint(x: 0, y: size.height / 2))
            path.addLine(to: CGPoint(x: size.width, y: size.height / 2))
        }
    }
}

/// How much height a waveform drawing is given.
///
/// It exists so a height is a **value with a reason** rather than a literal inside a view. The report
/// page has always drawn into a fixed strip and still does; the workspace flexes between a minimum that
/// survives the window's smallest supported size and a maximum past which a taller envelope stops
/// telling the reader anything (`design.md` §4).
///
/// The numbers are budgeted from the window's own minimum of 720 × 480 — the section navigation, the two
/// dividers, the action bar and the workspace's padding leave about 334 pt for content — rather than
/// chosen by eye.
struct WaveformPlotSizing: Equatable {
    let minimum: CGFloat
    /// `nil` would mean unbounded, which no case here wants: an envelope's vertical information is
    /// bounded by the amplitude scale rather than by pixels.
    let maximum: CGFloat

    /// A fixed strip: the two bounds are the same, so the drawing neither grows nor shrinks.
    static func fixed(_ height: CGFloat) -> WaveformPlotSizing {
        WaveformPlotSizing(minimum: height, maximum: height)
    }

    /// What the report page has drawn into since the waveform existed. Unchanged by this slice, so the
    /// transitional page looks exactly as it did.
    static let reportPage = WaveformPlotSizing.fixed(96)

    /// One file, filling the workspace. The minimum is already half again the strip it replaces and
    /// fits inside the 480 pt window with the prose beside it.
    static let workspaceSingle = WaveformPlotSizing(minimum: 140, maximum: 420)

    /// The inspection overview's compact strip (ADR-0026 §6).
    ///
    /// **Fixed, and smaller than the report page's** — which is what makes it compact. The overview is a
    /// reading surface where the drawing is one block among five rather than the subject, so it does not
    /// compete for the height a workspace exists to give: the reader who wants the envelope with room
    /// around it selects Waveform, where R5 put it. 72 pt keeps the centre line, the amplitude scale and
    /// the shape legible while leaving the 720 × 480 window's ~334 pt of content height for the four
    /// blocks the overview carries besides it.
    static let overviewCompact = WaveformPlotSizing.fixed(72)

    /// One lane of a pair, which has to fit twice over with two sets of prose and the shared-extent
    /// line. The minimum is what survives the 480 pt window; the maximum keeps two lanes from drifting
    /// apart on a tall display.
    static let workspaceLane = WaveformPlotSizing(minimum: 90, maximum: 260)
}
