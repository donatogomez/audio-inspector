import AudioInspectorDomain
import SwiftUI

/// Two files' envelopes on one time axis.
///
/// Thin on purpose: every decision it renders was made as arithmetic or as copy somewhere a test can
/// read. `PairedWaveformAxis` decides how much of the width each file's audio spans; `PairedVisualsCopy`
/// decides what the rest of it means; this puts the existing single-file drawing inside that width and
/// says so.
struct PairedWaveformSection: View {
    let presentation: PairedWaveformPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            lane(.first, presentation.first, geometry: presentation.axis?.first)
            lane(.second, presentation.second, geometry: presentation.axis?.second)
            if let shared = presentation.axis?.sharedSeconds {
                Text(PairedVisualsCopy.timeAxis(shared))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// One file's lane: which file it is, its drawing across the share of the axis its own audio spans,
    /// and — where its audio ends first — what the rest of the lane means.
    ///
    /// The remainder carries nothing. Not a baseline, not a silent bucket: past a file's last frame
    /// nothing was measured, and the sentence beside it says exactly that rather than *silence*.
    ///
    /// **One accessibility element for the whole lane**, labelled with the file and the artefact. The
    /// drawing's own element is folded into it, so a reader hears one sentence per drawing rather than
    /// one per bucket.
    private func lane(
        _ side: PairedWaveformAxis.Side, _ lane: PairedWaveformLane, geometry: PairedWaveformAxis.Lane?
    ) -> some View {
        let text = PairedVisualsCopy.waveform(
            lane, for: side, beyondItsAudio: (geometry?.remainderFraction ?? 0) > 0
        )
        return VStack(alignment: .leading, spacing: 4) {
            Text(text.attribution).font(.caption).foregroundStyle(.secondary)
            GeometryReader { proxy in
                WaveformSection(presentation: lane.asSingle)
                    .frame(width: proxy.size.width * CGFloat(geometry?.fraction ?? 0), alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 96)
            if let outOfRange = text.outOfRange {
                Text(outOfRange).font(.caption).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text.accessibilityLabel)
    }
}

/// Two files' spectral models on one time axis and one frequency axis.
///
/// Each grid occupies the share of the width its audio spans and the share of the height its own Nyquist
/// reaches, from 0 Hz up. The strip above it is the range that file **cannot represent** — drawn in the
/// treatment `PairedSpectrogramAxes` fixes, which is not a level on the ramp, **and said in words**, so
/// the distinction from the ramp's floor never rests on colour alone.
struct PairedSpectrogramSection: View {
    let presentation: PairedSpectrogramPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            lane(.first, presentation.first, geometry: presentation.axes?.first)
            lane(.second, presentation.second, geometry: presentation.axes?.second)
            if let axes = presentation.axes {
                Text(PairedVisualsCopy.timeAxis(axes.sharedSeconds))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(PairedVisualsCopy.frequencyAxis(axes.sharedNyquist))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func lane(
        _ side: PairedWaveformAxis.Side, _ lane: PairedSpectrogramLane, geometry: PairedSpectrogramAxes.Lane?
    ) -> some View {
        let text = PairedVisualsCopy.spectrogram(
            lane, for: side, aboveItsNyquist: (geometry?.outOfRangeFraction ?? 0) > 0
        )
        return VStack(alignment: .leading, spacing: 4) {
            Text(text.attribution).font(.caption).foregroundStyle(.secondary)
            GeometryReader { proxy in
                plot(lane, geometry: geometry, in: proxy.size)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 140)
            if let headline = text.headline {
                Text(headline).font(.callout).foregroundStyle(.secondary)
            }
            if let detail = text.detail {
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            if let outOfRange = text.outOfRange {
                Text(outOfRange).font(.caption).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text.accessibilityLabel)
    }

    /// The grid inside its own share of both axes, with the range above its Nyquist marked as one it
    /// cannot represent rather than one it measured silence in.
    @ViewBuilder
    private func plot(
        _ lane: PairedSpectrogramLane, geometry: PairedSpectrogramAxes.Lane?, in size: CGSize
    ) -> some View {
        switch lane {
        case let .model(model) where model.columnCount > 0 && geometry != nil:
            let laneGeometry = geometry!
            let width = size.width * CGFloat(laneGeometry.timeFraction)
            ZStack(alignment: .bottom) {
                Rectangle()
                    .fill(Self.outOfRangeColour)
                    .frame(width: width, height: size.height)
                image(for: model)
                    .frame(width: width, height: size.height * CGFloat(laneGeometry.frequencyFraction))
            }
            .frame(width: width, height: size.height, alignment: .bottom)
        case .model, .absent, .failed:
            // Nothing is drawn: the words for it are the lane's, not a rectangle's.
            Color.clear
        }
    }

    /// The model's own cells, at the model's own size, drawn without interpolation — the same rule the
    /// single-file drawing follows, and the reason a smoothed edge is never invented between two levels.
    private func image(for model: Spectrogram) -> some View {
        Group {
            if let raster = SpectrogramRaster.image(for: model) {
                Image(decorative: raster, scale: 1)
                    .resizable()
                    .interpolation(.none)
            } else {
                Color.clear
            }
        }
    }

    /// The treatment `PairedSpectrogramAxes` fixes for the range a file cannot represent, as a colour.
    /// Achromatic, and no colour the ramp produces ever is — and it is never the only way that region is
    /// distinguishable, because the lane says what it is.
    static var outOfRangeColour: Color {
        let treatment = PairedSpectrogramAxes.outOfRangeTreatment
        return Color(red: treatment.red, green: treatment.green, blue: treatment.blue)
    }
}
