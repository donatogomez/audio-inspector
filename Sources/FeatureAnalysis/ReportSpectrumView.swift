import AudioInspectorDomain
import SwiftUI

/// **Spectrum — where the file's energy sits, given room.**
///
/// The densest artefact the inspection produces: two dimensions, an absolute colour scale, two axes and
/// a legend. ADR-0026 §9 fixes what a section buys it and what it does not — *"A section gives each
/// drawing room. It gives it nothing else."*
///
/// ## It gives a drawing room; it transforms nothing
///
/// The transform, its resolution, the absolute dBFS scale, the floor, the colour ramp, the frequency
/// and time geometry and every sentence are the ones production already produces. Nothing below reads a
/// file, decodes one, runs a transform, rebuilds a model or retains a sample.
///
/// **Resizing is free, and that is a property of the pipeline rather than a hope.**
/// `SpectrogramRaster.buffer(for:)` takes no dimensions at all and the image is built in
/// `.task(id: model)`, so a taller window redraws an existing image and cannot rebuild it.
///
/// ## Which drawing, decided once
///
/// It takes `ReportVisuals` — the **same value** the transitional report page is handed, built by the
/// same call in the same body — and asks it for `spectrogramSections`. So the workspace and that page
/// can never disagree about whether this is one file or two, and a settled pairing still stands **in
/// place of** the single drawing rather than beside it.
///
/// It reads the comparison for that one question and no other. There is no comparison surface here and
/// no second lifecycle: R8 owns both.
///
/// ## What room does not buy
///
/// No playback, zoom, pan, scrubbing, cursor, selection, hovered frequency or time readout, overlay,
/// difference or subtraction of two models, alignment, channel selector or image export. The cells keep
/// `allowsHitTesting(false)`, and **nothing is re-coloured**: no normalisation, no auto-range, no
/// auto-contrast and no per-file scale, because the one comparison two spectrograms can honestly
/// support is the one an absolute scale makes possible.
public struct ReportSpectrumView: View {
    private let sections: [ReportVisualSection]

    public init(visuals: ReportVisuals) {
        sections = visuals.spectrogramSections
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // **The free space is shared, not pooled below** — the behaviour R5 arrived at by rendering
            // its own workspace. The plot's growth is bounded by the model's band count, so on a tall
            // window there is room left over, and content jammed to the top with a void beneath reads as
            // truncated rather than as composed. Two zero-minimum spacers centre what is there and
            // collapse to nothing when there is no room to give.
            Spacer(minLength: 0)
            // **Exactly one**, whichever mode this is — `ReportVisuals`' own guarantee, kept as a
            // collection so *how many* stays something a test can read.
            ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
                switch section {
                case let .singleSpectrogram(presentation):
                    SpectrogramSection(presentation: presentation, sizing: .workspaceSingle)
                case let .pairedSpectrogram(presentation):
                    PairedSpectrogramSection(presentation: presentation, sizing: .workspaceLane)
                case .singleWaveform, .pairedWaveform:
                    // Not reachable through `spectrogramSections`, and named rather than defaulted so a
                    // new kind of section fails to compile here instead of vanishing. The amplitude
                    // drawings are R5's section, not this one's.
                    EmptyView()
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(24)
    }
}
