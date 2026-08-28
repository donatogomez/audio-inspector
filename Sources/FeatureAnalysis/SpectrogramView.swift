import AudioInspectorDomain
import SwiftUI

/// The spectrogram as it appears inside the report: a still drawing with its axes and legend, or the
/// words that stand in for one.
///
/// It knows only `Spectrogram`. No `URL`, no framework, no decoding, no transform, no resolution
/// decision — and it never reads a conclusion out of the shape it draws.
struct SpectrogramSection: View {
    let presentation: SpectrogramPresentation
    /// How tall the cells are drawn. The report page keeps the strip it has always had; the spectrum
    /// workspace hands in a flexible one.
    var sizing: SpectrumPlotSizing = .reportPage

    var body: some View {
        let text = SpectrogramCopy.text(for: presentation)
        return VStack(alignment: .leading, spacing: 8) {
            if case let .model(model) = presentation, model.columnCount > 0 {
                SpectrogramPlot(model: model, sizing: sizing)
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
struct SpectrogramPlot: View {
    let model: Spectrogram
    /// How much vertical space the cells take. Defaults to the strip the report page has always given
    /// them, so every existing caller is unchanged.
    var sizing: SpectrumPlotSizing = .reportPage

    /// The model's cells, rasterised once. Held in state rather than recomputed in `body`, because
    /// `body` runs on every layout pass and the cells do not change when the window does.
    @State private var raster: CGImage?

    /// Room for the frequency labels on the left and the time labels underneath. Fixed rather than
    /// measured: the axis must not shrink until a mark is unreadable, and a wider window should show
    /// the same marks further apart rather than different ones.
    static let frequencyGutter: CGFloat = 56
    static let timeGutter: CGFloat = 18

    var body: some View {
        HStack(alignment: .top, spacing: 4) {
            frequencyAxis
            VStack(alignment: .leading, spacing: 2) {
                cells
                timeAxis
            }
        }
        .frame(minHeight: sizing.minimum + Self.timeGutter, maxHeight: sizing.maximum + Self.timeGutter)
        // **The raster is a function of the model, never of the size.** `SpectrogramRaster.buffer(for:)`
        // takes no dimensions at all, so a resize *cannot* rebuild it — and this only re-runs when the
        // model itself changes, which happens once per inspection.
        .task(id: model) {
            raster = await Self.rasterise(model)
        }
    }

    /// **One image, one draw per redraw — not one fill per cell.**
    ///
    /// The first version filled a rectangle per cell inside a `Canvas`: up to 524 288 fills, measured at
    /// **213 ms in Release and 611 ms in Debug**, and paid again on every size change because a `Canvas`
    /// re-runs when its area does. Building this image costs **6.5 ms** and drawing it **0.1 ms** at any
    /// width (`docs/spikes/2026-08-07-spectrogram-performance-presentation-diagnosis.md`, §D). The
    /// change is structural rather than clever: the work now follows the model, which is fixed once
    /// produced, instead of the window, which is not.
    ///
    /// **Interpolation is off, and that is load-bearing.** The image carries exactly one pixel per model
    /// cell, and scaling it must not invent a level between two that were measured. For an instrument
    /// whose subject is *where energy stops*, a smoothed edge would be precisely the wrong artefact —
    /// the same reason the previous version filled each cell flat.
    ///
    /// Before the raster exists the area is briefly empty. The section's own words are already on
    /// screen by then, so nothing is left unexplained.
    private var cells: some View {
        Group {
            if let raster {
                Image(decorative: raster, scale: 1, orientation: .up)
                    .resizable()
                    .interpolation(.none)
                    .antialiased(false)
            } else {
                Color.clear
            }
        }
        .frame(minHeight: sizing.minimum, maxHeight: sizing.maximum)
        .frame(maxWidth: .infinity)
        // Not interactive by design: no zoom, no scrubbing, no cursor, no selection, no tooltip.
        // Pointer and scroll activity leave the drawing and its data untouched.
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Builds the pixels **off the main actor**, then wraps them on it.
    ///
    /// `nonisolated` and `async`, so it runs on the generic executor rather than inheriting the view's
    /// isolation: the per-pixel loop is the expensive half and has no business blocking a layout pass.
    /// The split falls exactly here because `SpectrogramRaster.Buffer` is `Sendable` and `CGImage` is
    /// not — and wrapping bytes in one costs nothing worth moving.
    private nonisolated static func rasterise(_ model: Spectrogram) async -> CGImage? {
        guard let buffer = SpectrogramRaster.buffer(for: model) else { return nil }
        return SpectrogramRaster.image(from: buffer)
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
        .frame(width: Self.frequencyGutter)
        .frame(minHeight: sizing.minimum, maxHeight: sizing.maximum)
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
struct SpectrogramLegend: View {
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

/// How much height a spectral drawing's cells are given.
///
/// It exists for `WaveformPlotSizing`'s reason — a height should be a **value with a reason** rather
/// than a literal inside a view — and it is a separate type because the two drawings are bounded by
/// different things.
///
/// **The maximum is the model, not taste.** A `Spectrogram` carries at most
/// `SpectrogramGridMapping.defaultMaximumBandCount` bands, and the raster is drawn with
/// `interpolation(.none)` and `antialiased(false)` on purpose: past one pixel per band a taller image is
/// upscaled rather than more detailed, and upscaling adds blocks, not information. So the bound is a
/// property of the data.
///
/// The minima are budgeted from the window's own 720 × 480 minimum — the navigation, the dividers, the
/// action bar and the padding leave about 334 pt for content — against the axes, the legend and the
/// prose each case actually carries (`design.md` §4).
struct SpectrumPlotSizing: Equatable {
    let minimum: CGFloat
    let maximum: CGFloat

    /// A fixed strip: the two bounds are the same, so the drawing neither grows nor shrinks.
    static func fixed(_ height: CGFloat) -> SpectrumPlotSizing {
        SpectrumPlotSizing(minimum: height, maximum: height)
    }

    /// The height a spectral drawing is bounded by: one pixel per band, and no more.
    static let bandCount = CGFloat(SpectrogramGridMapping.defaultMaximumBandCount)

    /// What the report page has drawn a single file's cells into. Unchanged by this slice, so the
    /// transitional page looks exactly as it did.
    static let reportPage = SpectrumPlotSizing.fixed(220)

    /// What the report page has drawn a paired lane into. Also unchanged.
    static let reportPageLane = SpectrumPlotSizing.fixed(140)

    /// One file, filling the workspace. The minimum is exactly what the report page already gives it,
    /// so nothing is lost at the smallest window; the maximum is the band count.
    static let workspaceSingle = SpectrumPlotSizing(minimum: 220, maximum: bandCount)

    /// One lane of a pair, which has to fit twice over with two sets of prose, two shared-extent
    /// sentences and the legend. The maximum is half the band count, so two lanes together never exceed
    /// one full-resolution image's worth of height.
    static let workspaceLane = SpectrumPlotSizing(minimum: 90, maximum: bandCount / 2)
}
