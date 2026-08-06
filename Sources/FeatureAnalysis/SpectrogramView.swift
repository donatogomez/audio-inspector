import AudioInspectorDomain
import SwiftUI

/// The spectrogram as it appears inside the report: a still drawing with its axes and legend, or the
/// words that stand in for one.
///
/// It knows only `Spectrogram`. No `URL`, no framework, no decoding, no transform, no resolution
/// decision — and it never reads a conclusion out of the shape it draws.
struct SpectrogramSection: View {
    let presentation: SpectrogramPresentation

    var body: some View {
        let text = SpectrogramCopy.text(for: presentation)
        return VStack(alignment: .leading, spacing: 8) {
            if case let .model(model) = presentation, model.columnCount > 0 {
                SpectrogramPlot(model: model)
                SpectrogramLegend()
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
        // One element for the whole section, not one per cell: a drawing cannot be read, and 524 288
        // shapes announced in sequence would be far worse than silence. The label's length does not
        // depend on the model's size.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text.accessibilityLabel)
    }

    /// Colour follows the state of the **reading**, never the audio — the waveform's rule, for the same
    /// reason: a failure to draw is not an alarm about the file.
    private var headlineStyle: HierarchicalShapeStyle {
        switch presentation {
        case .loading, .model, .absent: .secondary
        case .failed: .primary
        }
    }
}

/// The drawing and its two axes.
private struct SpectrogramPlot: View {
    let model: Spectrogram

    /// Room for the frequency labels on the left and the time labels underneath. Fixed rather than
    /// measured: the axis must not shrink until a mark is unreadable, and a wider window should show
    /// the same marks further apart rather than different ones.
    private static let frequencyGutter: CGFloat = 56
    private static let timeGutter: CGFloat = 18
    private static let plotHeight: CGFloat = 220

    var body: some View {
        HStack(alignment: .top, spacing: 4) {
            frequencyAxis
            VStack(alignment: .leading, spacing: 2) {
                cells
                timeAxis
            }
        }
        .frame(height: Self.plotHeight + Self.timeGutter)
    }

    /// **One `Canvas`, one fill per cell, and no view per cell.**
    ///
    /// The alternative — a `View` per cell — would be up to 524 288 SwiftUI views for a single drawing,
    /// which is not a performance nuance but a different program. Here the cost is linear in the cells
    /// actually present, the model is walked once per redraw, and a resize re-runs only this: no decode,
    /// no transform, no change to the model.
    ///
    /// **Each cell is filled flat, with no interpolation between neighbours.** A smoothed image would
    /// draw levels that were never measured, and for an instrument whose subject is *where energy
    /// stops* an invented gradient across a cutoff is exactly the wrong artefact. Flat cells assert what
    /// the model contains and nothing between.
    private var cells: some View {
        Canvas(opaque: true) { context, size in
            guard let geometry = SpectrogramGeometry(size: size, model: model) else { return }
            for column in 0 ..< model.columnCount {
                for band in 0 ..< model.bandCount {
                    guard let value = model.value(column: column, band: band),
                          let rect = geometry.cell(column: column, band: band)
                    else { continue }
                    context.fill(Path(rect), with: .color(SpectrogramColourRamp.colour(for: value)))
                }
            }
        }
        .frame(height: Self.plotHeight)
        .frame(maxWidth: .infinity)
        // Not interactive by design: no zoom, no scrubbing, no cursor, no selection, no tooltip.
        // Pointer and scroll activity leave the drawing and its data untouched.
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// 0 Hz at the bottom, the file's own Nyquist at the top, linear throughout and never cropped.
    private var frequencyAxis: some View {
        GeometryReader { proxy in
            let marks = SpectrogramAxes.frequencyMarks(nyquist: model.nyquist)
            ForEach(marks, id: \.self) { frequency in
                if let y = SpectrogramGeometry(
                    size: CGSize(width: 1, height: proxy.size.height),
                    columnCount: 1, bandCount: 1
                )?.y(forFrequency: frequency, nyquist: model.nyquist) {
                    Text(HumanFormat.frequency(frequency))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(width: Self.frequencyGutter, alignment: .trailing)
                        .position(x: Self.frequencyGutter / 2, y: min(max(y, 6), proxy.size.height - 6))
                }
            }
        }
        .frame(width: Self.frequencyGutter, height: Self.plotHeight)
        .accessibilityHidden(true)
    }

    private var timeAxis: some View {
        let duration = SpectrogramAxes.duration(of: model)
        return GeometryReader { proxy in
            let marks = SpectrogramAxes.timeMarks(duration: duration)
            ForEach(marks, id: \.self) { seconds in
                if let x = SpectrogramGeometry(
                    size: CGSize(width: proxy.size.width, height: 1),
                    columnCount: 1, bandCount: 1
                )?.x(forTime: seconds, duration: duration),
                    let label = HumanFormat.duration(seconds) {
                    Text(label)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize()
                        .position(x: min(max(x, 16), proxy.size.width - 16), y: Self.timeGutter / 2)
                }
            }
        }
        .frame(height: Self.timeGutter)
        .accessibilityHidden(true)
    }
}

/// The numeric scale beneath the drawing.
///
/// **A gradient without numbers states nothing**, so the range is printed rather than implied. The
/// swatches are the same ramp the cells use, sampled evenly, so the legend cannot drift from the
/// drawing it explains.
private struct SpectrogramLegend: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 0) {
                ForEach(Array(SpectrogramColourRamp.legendStops().enumerated()), id: \.offset) { _, colour in
                    Rectangle().fill(colour)
                }
            }
            .frame(height: 8)
            HStack {
                ForEach(SpectrogramColourRamp.legendTicks, id: \.self) { level in
                    Text("\(Int(level))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    if level != SpectrogramColourRamp.legendTicks.last { Spacer() }
                }
            }
            Text("Energy in dBFS. Darker is quieter; lighter is louder.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .accessibilityHidden(true)
    }
}
