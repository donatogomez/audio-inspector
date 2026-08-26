import AudioInspectorDomain
import SwiftUI

/// Two files' envelopes on one time axis.
///
/// Thin on purpose: every decision it renders was made as arithmetic somewhere a test can read.
/// `PairedWaveformAxis` decides how much of the width each file's audio spans; this puts the existing
/// single-file drawing inside that width and stops.
struct PairedWaveformSection: View {
    let presentation: PairedWaveformPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            lane(ComparisonCopy.firstFile, presentation.first, fraction: presentation.axis?.first?.fraction)
            lane(ComparisonCopy.secondFile, presentation.second, fraction: presentation.axis?.second?.fraction)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// One file's lane: its name, and its drawing across the share of the axis its own audio spans.
    ///
    /// The remainder carries nothing. Not a baseline, not a silent bucket — past a file's last frame
    /// nothing was measured, and drawing anything there would invent audio.
    private func lane(
        _ name: String, _ lane: PairedWaveformLane, fraction: Double?
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(name).font(.caption).foregroundStyle(.secondary)
            GeometryReader { proxy in
                WaveformSection(presentation: lane.asSingle)
                    .frame(width: proxy.size.width * CGFloat(fraction ?? 0), alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 96)
        }
    }
}

/// Two files' spectral models on one time axis and one frequency axis.
///
/// Each grid occupies the share of the width its audio spans and the share of the height its own Nyquist
/// reaches, from 0 Hz up. The strip above it is the range that file **cannot represent** — drawn in the
/// treatment `PairedSpectrogramAxes` fixes, which is not a level on the ramp.
struct PairedSpectrogramSection: View {
    let presentation: PairedSpectrogramPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            lane(ComparisonCopy.firstFile, presentation.first, geometry: presentation.axes?.first)
            lane(ComparisonCopy.secondFile, presentation.second, geometry: presentation.axes?.second)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func lane(
        _ name: String, _ lane: PairedSpectrogramLane, geometry: PairedSpectrogramAxes.Lane?
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(name).font(.caption).foregroundStyle(.secondary)
            GeometryReader { proxy in
                plot(lane, geometry: geometry, in: proxy.size)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 140)
        }
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
            // Nothing is drawn: the words for it are the section's, not a rectangle's.
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
    /// Achromatic, and no colour the ramp produces ever is.
    static var outOfRangeColour: Color {
        let treatment = PairedSpectrogramAxes.outOfRangeTreatment
        return Color(red: treatment.red, green: treatment.green, blue: treatment.blue)
    }
}
